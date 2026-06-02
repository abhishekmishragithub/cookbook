/**
 * HeyClicky × Hydra — edge proxy.
 *
 * Two jobs, so the macOS app never holds an API key:
 *   1.  GET  /hydra   — upgrade to WebSocket, open a socket to Hydra with the
 *                       server-side key, and pipe frames both ways untouched.
 *   2.  POST /vision  — take a screenshot (base64 PNG/JPEG) + a prompt, call
 *                       Gemini, and return the scene-graph JSON.
 *
 * Mirrors the original Clicky `worker/` pattern (keys in env, thin routes).
 */

export interface Env {
  HYDRA_WS_URL: string;   // e.g. wss://api.smallest.ai/hydra/v1/stream
  HYDRA_API_KEY: string;  // secret
  GEMINI_API_KEY: string; // secret
  GEMINI_MODEL?: string;  // default below
  ALLOWED_ORIGIN?: string; // optional CORS lock-down
}

const DEFAULT_GEMINI_MODEL = "gemini-2.0-flash";

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);

    if (url.pathname === "/hydra") return proxyHydra(req, env);
    if (url.pathname === "/vision" && req.method === "POST") return vision(req, env);
    if (url.pathname === "/health") return json({ ok: true });

    return new Response("not found", { status: 404 });
  },
};

/* ------------------------------------------------------------------ */
/* 1. Hydra WebSocket passthrough                                      */
/* ------------------------------------------------------------------ */

async function proxyHydra(req: Request, env: Env): Promise<Response> {
  if (req.headers.get("Upgrade") !== "websocket") {
    return new Response("expected websocket", { status: 426 });
  }

  // Socket pair: `client` is returned to the caller, `server` is ours to drive.
  const pair = new WebSocketPair();
  const client = pair[0];
  const server = pair[1];
  server.accept();

  // Open the upstream socket to Hydra with the key the app never sees.
  // (Auth header on the upgrade; if Hydra wants the key in the first JSON
  // message instead, do that in the `server.message` handler before relaying.)
  const upstream = new WebSocket(env.HYDRA_WS_URL, {
    headers: { Authorization: `Bearer ${env.HYDRA_API_KEY}` },
  } as unknown as string); // CF accepts an init object at runtime

  const upReady = new Promise<void>((resolve) => {
    upstream.addEventListener("open", () => resolve(), { once: true });
  });
  const pending: (string | ArrayBuffer)[] = [];

  // client → upstream (buffer until upstream is open)
  server.addEventListener("message", (e: MessageEvent) => {
    const data = e.data as string | ArrayBuffer;
    if (upstream.readyState === WebSocket.OPEN) upstream.send(data);
    else pending.push(data);
  });
  upReady.then(() => {
    for (const m of pending) upstream.send(m);
    pending.length = 0;
  });

  // upstream → client
  upstream.addEventListener("message", (e: MessageEvent) => {
    if (server.readyState === WebSocket.OPEN) server.send(e.data);
  });

  // tear-down in both directions
  const closeBoth = (code = 1000, reason = "") => {
    try { server.close(code, reason); } catch {}
    try { upstream.close(code, reason); } catch {}
  };
  server.addEventListener("close", (e: CloseEvent) => closeBoth(e.code, e.reason));
  upstream.addEventListener("close", (e: CloseEvent) => closeBoth(e.code, e.reason));
  server.addEventListener("error", () => closeBoth(1011, "client error"));
  upstream.addEventListener("error", () => closeBoth(1011, "upstream error"));

  return new Response(null, { status: 101, webSocket: client });
}

/* ------------------------------------------------------------------ */
/* 2. Gemini vision → scene-graph                                      */
/* ------------------------------------------------------------------ */

interface VisionRequest {
  image: string;        // base64, no data: prefix
  mimeType?: string;    // default image/jpeg
  prompt: string;       // the scene-graph instruction (see prompts/)
}

async function vision(req: Request, env: Env): Promise<Response> {
  let body: VisionRequest;
  try {
    body = (await req.json()) as VisionRequest;
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!body.image || !body.prompt) {
    return json({ error: "image and prompt are required" }, 400);
  }

  const model = env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL;
  const endpoint =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent` +
    `?key=${env.GEMINI_API_KEY}`;

  const geminiBody = {
    contents: [{
      role: "user",
      parts: [
        { text: body.prompt },
        { inline_data: { mime_type: body.mimeType || "image/jpeg", data: body.image } },
      ],
    }],
    // Force strict JSON back so the orchestrator can parse without scraping.
    generationConfig: { responseMimeType: "application/json", temperature: 0 },
  };

  const r = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(geminiBody),
  });

  if (!r.ok) return json({ error: "gemini error", status: r.status, detail: await r.text() }, 502);

  const data = (await r.json()) as any;
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
  // Already JSON (responseMimeType), but parse defensively.
  let scene: unknown;
  try { scene = JSON.parse(text); } catch { scene = { raw: text }; }
  return json({ scene });
}

/* ------------------------------------------------------------------ */

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
