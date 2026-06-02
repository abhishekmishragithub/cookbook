/* HeyClicky × Hydra — browser demo.
 *
 * Proves the screen-aware + pointing experience today. Two sources:
 *   • Demo:  bundled SVG screenshot + canned brain  → runs with ZERO setup.
 *   • Live:  real getDisplayMedia capture + Gemini  → needs a deployed Worker.
 *
 * The browser voice (speechSynthesis) is a stand-in for Hydra. We fake the one
 * thing that matters most for the wow — BARGE-IN — by cancelling speech the
 * instant a new question arrives. Swap in the real HydraClient for true
 * full-duplex.
 */
const $ = (id) => document.getElementById(id);
const stage = $("stage"), img = $("demoImg"), video = $("screen"), overlay = $("overlay");
const clicky = $("clicky"), bubble = $("bubble"), statusEl = $("status");

let mode = null;            // 'demo' | 'live'
let stream = null;
let lastBox = null;         // [ymin,xmin,ymax,xmax] 0-1000 of current target
const DEMO_IMG = "demo-screen.svg";

/* ---- canned brain for demo mode (matches demo-screen.svg) ---- */
const DEMO_SCENE = [
  { label: "Color tab",            box: [30, 437, 62, 500] },
  { label: "Primary color wheels", box: [587, 31, 950, 328] },
  { label: "Node editor",          box: [587, 508, 900, 844] },
  { label: "Export button",        box: [925, 875, 975, 969] },
];
function demoBrain(q) {
  const t = q.toLowerCase();
  if (/export|render|save|deliver/.test(t))
    return { say: "Easy — see that Export button bottom-right? Click it and pick your format.", label: "Export button" };
  if (/color|grade|wheel|lift|gamma|gain/.test(t))
    return { say: "For grading, you're on the Color tab — now nudge these primary wheels right here.", label: "Primary color wheels" };
  if (/node/.test(t))
    return { say: "Each effect is a node here. Right-click in the node editor to add one.", label: "Node editor" };
  return { say: "Try asking how to export, or about the color wheels — I'll point you there.", label: "Color tab" };
}
const findBox = (label) => (DEMO_SCENE.find((e) => e.label === label) || {}).box || null;

/* ---- sources ---- */
function workerUrl() {
  const u = $("worker").value.trim().replace(/\/$/, "");
  if (u) localStorage.setItem("workerUrl", u);
  return u;
}
async function startDemo() {
  mode = "demo"; stopStream();
  video.style.display = "none";
  img.src = DEMO_IMG; img.style.display = "block";
  img.onload = () => { sizeOverlay(); greet(); };
}
async function startLive() {
  try {
    stream = await navigator.mediaDevices.getDisplayMedia({ video: { frameRate: 5 }, audio: false });
  } catch (e) { setStatus("screen share denied"); return; }
  mode = "live"; img.style.display = "none";
  video.srcObject = stream; video.style.display = "block";
  video.onloadedmetadata = () => { sizeOverlay(); greet(); };
  stream.getVideoTracks()[0].onended = () => setStatus("screen share ended");
}
function stopStream() { if (stream) { stream.getTracks().forEach((t) => t.stop()); stream = null; } }

/* capture current frame as base64 jpeg (live mode) */
function captureFrame() {
  const c = document.createElement("canvas");
  c.width = video.videoWidth; c.height = video.videoHeight;
  c.getContext("2d").drawImage(video, 0, 0);
  return c.toDataURL("image/jpeg", 0.6).split(",")[1];
}

/* ---- ask flow ---- */
async function ask(q) {
  if (!mode) { setStatus("pick a source first"); return; }
  if (!q) return;
  bargeIn();                       // interrupt whatever Clicky was saying
  setStatus("thinking…");

  let say, label, box;
  if (mode === "demo") {
    const r = demoBrain(q); say = r.say; label = r.label; box = findBox(label);
  } else {
    const u = workerUrl(); if (!u) { setStatus("set the Worker URL"); return; }
    try {
      const res = await fetch(u + "/tutor", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ image: captureFrame(), mimeType: "image/jpeg", question: q }),
      });
      const data = await res.json();
      say = data.say || "Hmm, I'm not sure — try rephrasing?";
      label = data.point_label; box = data.box_2d || null;
    } catch (e) { setStatus("worker error"); return; }
  }
  setStatus("idle");
  speak(say);
  if (box) pointAt(box, say);
}

/* ---- voice (Hydra stand-in) + barge-in ---- */
let speaking = false;
function speak(text) {
  if (!("speechSynthesis" in window)) return;
  speaking = true;
  const u = new SpeechSynthesisUtterance(text);
  u.rate = 1.05; u.pitch = 1.0;
  u.onend = () => { speaking = false; };
  speechSynthesis.speak(u);
}
function bargeIn() {
  if (speaking && "speechSynthesis" in window) {
    speechSynthesis.cancel(); speaking = false;
    setStatus("↩ interrupted");   // the Hydra magic, simulated
  }
}

/* ---- pointing overlay + Clicky character ---- */
function renderedRect() {
  // actual drawn rect of the contained image/video inside #stage (letterboxed)
  const el = mode === "live" ? video : img;
  const natW = mode === "live" ? video.videoWidth : img.naturalWidth;
  const natH = mode === "live" ? video.videoHeight : img.naturalHeight;
  const sw = stage.clientWidth, sh = stage.clientHeight;
  if (!natW || !natH) return { x: 0, y: 0, w: sw, h: sh };
  const scale = Math.min(sw / natW, sh / natH);
  const w = natW * scale, h = natH * scale;
  return { x: (sw - w) / 2, y: (sh - h) / 2, w, h };
}
function boxToPoint(box) {
  const [ymin, xmin, ymax, xmax] = box;
  const r = renderedRect();
  return {
    x: r.x + ((xmin + xmax) / 2 / 1000) * r.w,
    y: r.y + ((ymin + ymax) / 2 / 1000) * r.h,
  };
}
function pointAt(box, text) {
  lastBox = box;
  const p = boxToPoint(box);
  // move Clicky next to the target
  clicky.classList.remove("hidden");
  clicky.style.left = Math.min(p.x + 18, stage.clientWidth - 300) + "px";
  clicky.style.top = Math.max(p.y - 30, 8) + "px";
  bubble.textContent = text; bubble.classList.add("show");
}
function sizeOverlay() {
  overlay.width = stage.clientWidth; overlay.height = stage.clientHeight;
}
/* animated pulsing ring + cursor dot */
function drawLoop(t) {
  const ctx = overlay.getContext("2d");
  ctx.clearRect(0, 0, overlay.width, overlay.height);
  if (lastBox) {
    const p = boxToPoint(lastBox);
    const pulse = 14 + 6 * Math.sin(t / 250);
    ctx.beginPath(); ctx.arc(p.x, p.y, pulse + 14, 0, Math.PI * 2);
    ctx.strokeStyle = "rgba(27,110,243,.9)"; ctx.lineWidth = 3; ctx.stroke();
    ctx.beginPath(); ctx.arc(p.x, p.y, 6, 0, Math.PI * 2);
    ctx.fillStyle = "#1b6ef3"; ctx.fill();
  }
  requestAnimationFrame(drawLoop);
}
function greet() {
  speak("Hey! I can see your screen. Ask me anything — or just watch me point.");
  setStatus(mode === "demo" ? "demo mode — no keys needed" : "live — sharing screen");
}

/* ---- mic (push-to-talk) ---- */
function setupMic() {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SR) { $("btnMic").disabled = true; $("btnMic").title = "no speech recognition"; return; }
  const rec = new SR(); rec.lang = "en-US"; rec.interimResults = false;
  rec.onresult = (e) => { const q = e.results[0][0].transcript; $("q").value = q; ask(q); };
  const start = () => { try { rec.start(); setStatus("listening…"); } catch {} };
  const stop = () => rec.stop();
  $("btnMic").addEventListener("mousedown", start);
  $("btnMic").addEventListener("mouseup", stop);
  $("btnMic").addEventListener("touchstart", (e) => { e.preventDefault(); start(); });
  $("btnMic").addEventListener("touchend", (e) => { e.preventDefault(); stop(); });
}

/* ---- wire up ---- */
function setStatus(s) { statusEl.textContent = s; }
$("worker").value = localStorage.getItem("workerUrl") || "";
$("btnDemo").onclick = startDemo;
$("btnLive").onclick = startLive;
$("btnAsk").onclick = () => ask($("q").value.trim());
$("q").addEventListener("keydown", (e) => { if (e.key === "Enter") ask($("q").value.trim()); });
window.addEventListener("resize", sizeOverlay);
setupMic();
sizeOverlay();
requestAnimationFrame(drawLoop);
