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

    // CORS preflight for the browser demo.
    if (req.method === "OPTIONS") return cors(new Response(null, { status: 204 }), env);

    if (url.pathname === "/hydra") return proxyHydra(req, env);
    if (url.pathname === "/vision" && req.method === "POST") return cors(await vision(req, env), env);
    if (url.pathname === "/tutor" && req.method === "POST") return cors(await tutor(req, env), env);
    if (url.pathname === "/health") return cors(json({ ok: true }), env);

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
  // Hydra auths via the `api_key` query parameter (see docs/HYDRA_CONTRACT.md §1).
  const upUrl = new URL(env.HYDRA_WS_URL);
  upUrl.searchParams.set("api_key", env.HYDRA_API_KEY);
  if (!upUrl.searchParams.get("model")) upUrl.searchParams.set("model", "hydra");
  const upstream = new WebSocket(upUrl.toString());

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

  const scene = await callGemini(env, body.image, body.mimeType || "image/jpeg", body.prompt);
  return json({ scene });
}

/* ------------------------------------------------------------------ */
/* 3. Tutor brain (browser demo stand-in for Hydra)                    */
/*    image + spoken question -> { say, point_label }                  */
/* ------------------------------------------------------------------ */

interface TutorRequest {
  image: string;
  mimeType?: string;
  question: string;
}

const TUTOR_PROMPT = `You are Clicky, a warm, quick on-screen tutor. The user asks
a question about what's on their screen (the image). Answer in ONE or TWO short
spoken sentences — friendly, like a friend leaning over their shoulder. If there
is a specific on-screen element they should look at, name it exactly as it reads
on screen so a pointer can be drawn to it.

Return STRICT JSON:
{
  "say": "what you'd say out loud, short",
  "point_label": "exact label of the element to point at, or null",
  "box_2d": [ymin, xmin, ymax, xmax]  // 0-1000 normalized for that element, or null
}`;

async function tutor(req: Request, env: Env): Promise<Response> {
  let body: TutorRequest;
  try { body = (await req.json()) as TutorRequest; }
  catch { return json({ error: "invalid JSON body" }, 400); }
  if (!body.image || !body.question) return json({ error: "image and question required" }, 400);

  const scene = await callGemini(env, body.image, body.mimeType || "image/jpeg",
    `${TUTOR_PROMPT}\n\nUser asked: "${body.question}"`);
  return json(scene);
}

/** Shared Gemini JSON call. */
async function callGemini(env: Env, image: string, mimeType: string, prompt: string): Promise<unknown> {
  const model = env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL;
  const endpoint =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${env.GEMINI_API_KEY}`;
  const r = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }, { inline_data: { mime_type: mimeType, data: image } }] }],
      generationConfig: { responseMimeType: "application/json", temperature: 0 },
    }),
  });
  if (!r.ok) return { error: "gemini error", status: r.status, detail: await r.text() };
  const data = (await r.json()) as any;
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
  try { return JSON.parse(text); } catch { return { raw: text }; }
}

/* ------------------------------------------------------------------ */

function cors(res: Response, env: Env): Response {
  const h = new Headers(res.headers);
  h.set("Access-Control-Allow-Origin", env.ALLOWED_ORIGIN || "*");
  h.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  h.set("Access-Control-Allow-Headers", "Content-Type");
  return new Response(res.body, { status: res.status, headers: h });
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
