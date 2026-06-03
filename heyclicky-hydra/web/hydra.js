/* Real Hydra speech-to-speech for the browser.
 *
 * Vanilla-JS port of smallest-inc/hydra_agents (lib/hydra-client.ts, lib/audio.ts,
 * hooks/useHydraSession.ts). Full-duplex: streams mic PCM16@16k up, plays PCM16@24k
 * down gaplessly, stops instantly on barge-in, and runs client-side tools.
 *
 * Usage:
 *   const h = new HydraSession({
 *     apiKey, instructions, voice, tools,
 *     onStatus(s){}, onUserSpeech(){}, onAssistantText(t){},
 *     onToolCall(name, args) { return resultString; }   // sync or async
 *   });
 *   await h.connect();
 *   h.appendContext("ON SCREEN NOW: ...");   // inject vision mid-session
 *   h.disconnect();
 */
const HYDRA_URL = "wss://api.smallest.ai/waves/v1/s2s?model=hydra";

const b64 = {
  enc(u8) {
    let s = "", CH = 0x8000;
    for (let i = 0; i < u8.length; i += CH) s += String.fromCharCode.apply(null, u8.subarray(i, i + CH));
    return btoa(s);
  },
  dec(str) {
    const bin = atob(str), u8 = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
    return u8.buffer;
  },
};

const MIC_WORKLET = `
class HydraMic extends AudioWorkletProcessor {
  constructor(){ super(); this.buf = new Float32Array(0); }
  process(inputs){
    const ch = inputs[0] && inputs[0][0]; if(!ch) return true;
    const nb = new Float32Array(this.buf.length + ch.length);
    nb.set(this.buf); nb.set(ch, this.buf.length); this.buf = nb;
    const N = 480; // 30ms @16k
    while(this.buf.length >= N){
      const seg = this.buf.slice(0, N); this.buf = this.buf.slice(N);
      const i16 = new Int16Array(N); let peak = 0;
      for(let i=0;i<N;i++){ const s=Math.max(-1,Math.min(1,seg[i])); i16[i]=s<0?s*32768:s*32767; const a=s<0?-s:s; if(a>peak)peak=a; }
      this.port.postMessage({pcm:i16.buffer, peak},[i16.buffer]);
    }
    return true;
  }
}
registerProcessor('hydra-mic', HydraMic);`;

class Playback {
  constructor(rate) { this.rate = rate; this.ctx = null; this.gain = null; this.next = 0; this.active = new Set(); }
  setRate(r) { if (r !== this.rate) { this.rate = r; this.stop(); } }
  _ensure() {
    if (this.ctx) return;
    this.ctx = new AudioContext({ sampleRate: this.rate });
    this.gain = this.ctx.createGain(); this.gain.gain.value = 1;
    this.gain.connect(this.ctx.destination); this.next = 0;
  }
  play(ab) {
    this._ensure();
    const i16 = new Int16Array(ab), f32 = new Float32Array(i16.length);
    for (let i = 0; i < i16.length; i++) f32[i] = i16[i] / 32768;
    const buf = this.ctx.createBuffer(1, f32.length, this.rate);
    buf.getChannelData(0).set(f32);
    const src = this.ctx.createBufferSource(); src.buffer = buf; src.connect(this.gain);
    const now = this.ctx.currentTime;
    if (this.next === 0) this.next = now + 0.12;
    if (this.next < now) this.next = now + 0.04;
    src.start(this.next); this.next += buf.duration;
    this.active.add(src); src.onended = () => this.active.delete(src);
  }
  stop() {
    if (this.gain) { try { this.gain.gain.setValueAtTime(0, this.gain.context.currentTime); } catch {} }
    for (const s of this.active) { try { s.onended = null; s.stop(); s.disconnect(); } catch {} }
    this.active.clear();
    if (this.ctx) { this.ctx.close().catch(() => {}); this.ctx = null; this.gain = null; }
    this.next = 0;
  }
  isPlaying() { return this.active.size > 0; }
}

class HydraSession {
  constructor(opts) {
    this.opts = opts;
    this.ws = null; this.mic = null; this.playback = new Playback(24000);
    this.fn = {};            // call_id -> {name, args}
    this.resumeTimer = null;
  }

  async connect() {
    const url = new URL(HYDRA_URL);
    url.searchParams.set("api_key", this.opts.apiKey);
    this._status("connecting");
    this.ws = new WebSocket(url.toString());
    this.ws.onopen = () => this._status("open");
    this.ws.onclose = () => { this._status("closed"); this._teardownAudio(); };
    this.ws.onerror = () => this._status("error");
    this.ws.onmessage = (e) => { try { this._onEvent(JSON.parse(e.data)); } catch {} };
  }

  disconnect() { try { this.ws?.close(); } catch {} this.ws = null; this._teardownAudio(); }

  _send(o) { if (this.ws && this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(o)); }
  _status(s) { this.opts.onStatus?.(s); }

  appendContext(text) {
    this._send({ type: "conversation.item.create",
      item: { type: "message", role: "system", content: [{ type: "input_text", text }] } });
  }

  async _onEvent(evt) {
    switch (evt.type) {
      case "session.created":
        this._send({ type: "session.configure", session: {
          instructions: this.opts.instructions,
          voice: this.opts.voice || "wren",
          tools: (this.opts.tools || []).map((t) => ({ ...t, type: "function" })),
          generate_initial_response: this.opts.speaksFirst !== false,
        } });
        break;
      case "session.configured":
        if (evt.session?.output_audio_sample_rate) this.playback.setRate(evt.session.output_audio_sample_rate);
        this._status("ready");
        await this._startMic();
        break;
      case "input_audio_buffer.speech_started":   // BARGE-IN
        this.playback.stop();
        this.opts.onUserSpeech?.();
        break;
      case "response.output_audio.delta":
        if (evt.delta) this.playback.play(b64.dec(evt.delta));
        break;
      case "conversation.item.done": {
        const t = evt.item?.content?.[0]?.text;
        if (t && evt.item?.role === "assistant") this.opts.onAssistantText?.(t);
        break;
      }
      case "response.function_call_arguments.delta": {
        const st = this.fn[evt.call_id] || (this.fn[evt.call_id] = { name: evt.name || "", args: "" });
        if (evt.name) st.name = evt.name;
        st.args += evt.delta || "";
        break;
      }
      case "response.function_call_arguments.done": {
        const st = this.fn[evt.call_id] || { name: evt.name || "", args: evt.arguments || "" };
        const name = evt.name || st.name;
        let args = {}; try { args = JSON.parse(evt.arguments || st.args || "{}"); } catch {}
        delete this.fn[evt.call_id];
        let out = "{}";
        try { out = await this.opts.onToolCall?.(name, args); } catch (e) { out = JSON.stringify({ error: String(e) }); }
        this._send({ type: "conversation.item.create",
          item: { type: "function_call_output", call_id: evt.call_id, output: String(out ?? "{}") } });
        // debounce so parallel calls land before we resume narration
        clearTimeout(this.resumeTimer);
        this.resumeTimer = setTimeout(() => this._send({ type: "response.create" }), 220);
        break;
      }
      case "error":
        this.opts.onStatus?.("error", evt.error?.message);
        break;
    }
  }

  async _startMic() {
    if (this.mic) return;
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: { noiseSuppression: true, echoCancellation: true, autoGainControl: true },
    });
    const ctx = new AudioContext({ sampleRate: 16000 });
    const url = URL.createObjectURL(new Blob([MIC_WORKLET], { type: "application/javascript" }));
    await ctx.audioWorklet.addModule(url); URL.revokeObjectURL(url);
    const src = ctx.createMediaStreamSource(stream);
    const node = new AudioWorkletNode(ctx, "hydra-mic");
    node.port.onmessage = (e) => {
      if (this.ws?.readyState === WebSocket.OPEN)
        this._send({ type: "input_audio_buffer.append", audio: b64.enc(new Uint8Array(e.data.pcm)) });
    };
    const sink = ctx.createGain(); sink.gain.value = 0;
    src.connect(node); node.connect(sink).connect(ctx.destination);
    this.mic = { stream, ctx };
  }

  _teardownAudio() {
    try { this.mic?.stream.getTracks().forEach((t) => t.stop()); this.mic?.ctx.close(); } catch {}
    this.mic = null; this.playback.stop();
  }
}

window.HydraSession = HydraSession;
