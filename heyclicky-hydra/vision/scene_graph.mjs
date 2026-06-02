#!/usr/bin/env node
/**
 * Screenshot -> scene-graph harness.
 *
 * Standalone test of the vision loop, independent of the Mac app. Sends a
 * screenshot to Gemini (directly, or via the Worker /vision route) and prints
 * the parsed scene-graph the orchestrator will consume.
 *
 * Usage:
 *   node scene_graph.mjs --image shot.png                 # direct to Gemini, needs GEMINI_API_KEY
 *   node scene_graph.mjs --image shot.png --worker URL    # via the Cloudflare Worker
 *   node scene_graph.mjs --mock                           # no keys, canned output
 *
 * Env: GEMINI_API_KEY, GEMINI_MODEL (default gemini-2.0-flash)
 */
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dir = dirname(fileURLToPath(import.meta.url));
const args = parseArgs(process.argv.slice(2));

const MODEL = process.env.GEMINI_MODEL || "gemini-2.0-flash";

async function loadPrompt() {
  // Extract the fenced ```text block from the prompt doc.
  const md = await readFile(join(__dir, "..", "prompts", "scene_graph_prompt.md"), "utf8");
  const m = md.match(/```text\n([\s\S]*?)```/);
  return (m ? m[1] : md).trim();
}

function mockScene() {
  return {
    summary: "DaVinci Resolve color page; user is grading a clip.",
    elements: [
      { label: "Color page tab", kind: "tab", box_2d: [20, 480, 55, 545], desc: "switches to the color grading workspace" },
      { label: "Primary wheels", kind: "panel", box_2d: [620, 30, 900, 360], desc: "lift/gamma/gain color wheels" },
      { label: "Export button", kind: "button", box_2d: [930, 880, 975, 980], desc: "renders the timeline to a file" },
      { label: "Node editor", kind: "panel", box_2d: [120, 640, 460, 980], desc: "grading node graph" },
    ],
  };
}

function mimeFor(path) {
  if (/\.png$/i.test(path)) return "image/png";
  if (/\.webp$/i.test(path)) return "image/webp";
  return "image/jpeg";
}

async function viaWorker(workerUrl, b64, mime, prompt) {
  const r = await fetch(workerUrl.replace(/\/$/, "") + "/vision", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ image: b64, mimeType: mime, prompt }),
  });
  if (!r.ok) throw new Error(`worker ${r.status}: ${await r.text()}`);
  const { scene } = await r.json();
  return scene;
}

async function viaGemini(b64, mime, prompt) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new Error("GEMINI_API_KEY not set (or use --mock / --worker)");
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${key}`;
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }, { inline_data: { mime_type: mime, data: b64 } }] }],
      generationConfig: { responseMimeType: "application/json", temperature: 0 },
    }),
  });
  if (!r.ok) throw new Error(`gemini ${r.status}: ${await r.text()}`);
  const data = await r.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
  return JSON.parse(text);
}

/**
 * The orchestrator-side bit: turn a scene-graph into the compact "ON SCREEN
 * NOW" block injected into Hydra, and a label->box lookup for point_at.
 */
function toContextBlock(scene) {
  const lines = (scene.elements || []).map((e) => `- "${e.label}" (${e.kind}) — ${e.desc}`);
  return `ON SCREEN NOW: ${scene.summary || ""}\n${lines.join("\n")}`;
}

async function main() {
  const prompt = await loadPrompt();
  let scene;

  if (args.mock) {
    scene = mockScene();
  } else {
    if (!args.image) throw new Error("--image <path> required (or --mock)");
    const buf = await readFile(args.image);
    const b64 = buf.toString("base64");
    const mime = mimeFor(args.image);
    scene = args.worker
      ? await viaWorker(args.worker, b64, mime, prompt)
      : await viaGemini(b64, mime, prompt);
  }

  console.log("=== scene-graph (raw) ===");
  console.log(JSON.stringify(scene, null, 2));
  console.log("\n=== context block injected into Hydra ===");
  console.log(toContextBlock(scene));
}

function parseArgs(argv) {
  const out = { mock: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--mock") out.mock = true;
    else if (argv[i] === "--image") out.image = argv[++i];
    else if (argv[i] === "--worker") out.worker = argv[++i];
  }
  return out;
}

main().catch((e) => { console.error("error:", e.message); process.exit(1); });
