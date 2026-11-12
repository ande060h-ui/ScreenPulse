// Stress test: sends many question images to Gemini at once with the app's Focus Mode prompt,
// and measures how many answers are right and how long they take.
// Usage: node tests/stress.mjs <image folder> <variant: ""|"_wrong"> <concurrency> [repetitions] [out.json]
// Needs GEMINI_API_KEY (and optionally GEMINI_MODEL) in .env in the repository root.
// Images are generated with tests/render.swift from tests/questions.json.
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const env = Object.fromEntries(readFileSync(path.join(ROOT, ".env"), "utf8").split("\n").map((l) => l.match(/^([A-Z_]+)=(.*)$/)).filter(Boolean).map((m) => [m[1], m[2].replace(/^["']|["']$/g, "")]));
const KEY = env.GEMINI_API_KEY;
const MODEL = env.GEMINI_MODEL || "gemini-3.8-flash";
// The Focus Mode prompt, assembled from Prompts.swift exactly as the app does.
const promptsSrc = readFileSync(path.join(ROOT, "app/Sources/Core/Prompts.swift"), "utf8");
const lit = (name) => promptsSrc.match(new RegExp(`static let ${name} = (?:pointerIntro \\+ "\\\\n" \\+ )?"""\\n([\\s\\S]*?)\\n\\s*"""`))[1].replace(/^    /gm, "");
const SYSTEM = [lit("pointerIntro"), lit("focus"), lit("ownWindow")].join("\n");

const [dir, variant = "", conc = "1", reps = "1", outFile] = process.argv.slice(2);
const items = JSON.parse(readFileSync(new URL("./questions.json", import.meta.url)));
const URL_ = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

const jobs = [];
for (let r = 0; r < Number(reps); r++) for (const it of items) jobs.push(it);

const results = [];
let next = 0;
const t0 = Date.now();

async function one(it) {
  const file = `${dir}/${String(it.n).padStart(2, "0")}${variant}.png`;
  const data = readFileSync(file).toString("base64");
  const start = Date.now();
  let text = "", error = null;
  try {
    const res = await fetch(URL_, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": KEY },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: SYSTEM }] },
        contents: [{ role: "user", parts: [{ inlineData: { mimeType: "image/png", data } }, { text: "Answer the question at the mouse pointer." }] }],
        generationConfig: { thinkingConfig: { thinkingLevel: "low" } },
      }),
      signal: AbortSignal.timeout(120_000),
    });
    const j = await res.json();
    text = res.ok
      ? (j.candidates?.[0]?.content?.parts ?? []).filter((p) => !p.thought).map((p) => p.text ?? "").join("").trim()
      : `Error ${res.status}: ${j.error?.message ?? ""}`;
  } catch (e) {
    error = String(e);
  }
  const ms = Date.now() - start;
  const m = text.match(/(?:Answer|Svar):\s*([A-D](?:\s*,\s*[A-D])*)/i);
  const got = m ? m[1].replace(/\s/g, "").toUpperCase() : null;
  const apiErr = /^Error/.test(text) ? text.slice(0, 160) : null;
  results.push({ n: it.n, key: it.key, got, ok: got === it.key, ms, error: error || apiErr, raw: got ? "" : text.slice(0, 160) });
}

async function worker() {
  while (next < jobs.length) await one(jobs[next++]);
}
await Promise.all(Array.from({ length: Number(conc) }, worker));

const wall = (Date.now() - t0) / 1000;
const ok = results.filter((r) => r.ok).length;
const errs = results.filter((r) => r.error);
const answered = results.filter((r) => r.got);
const times = results.map((r) => r.ms).sort((a, b) => a - b);
const pct = (p) => times[Math.min(times.length - 1, Math.floor((p / 100) * times.length))];
const errKinds = {};
for (const e of errs) { const k = e.error.replace(/\d+/g, "#").slice(0, 90); errKinds[k] = (errKinds[k] || 0) + 1; }

const summary = {
  variant: variant || "normal", concurrency: Number(conc), requests: results.length,
  correct: ok, percent_correct: +(100 * ok / results.length).toFixed(1),
  answered: answered.length, api_or_network_errors: errs.length,
  time_ms: { min: times[0], median: pct(50), p90: pct(90), max: times.at(-1) },
  total_time_s: +wall.toFixed(1), error_kinds: errKinds,
  wrong: results.filter((r) => r.got && !r.ok).sort((a, b) => a.n - b.n).map((r) => `#${r.n}: expected ${r.key}, got ${r.got}`),
  unanswered: results.filter((r) => !r.got).map((r) => `#${r.n}: ${r.error || r.raw}`).slice(0, 8),
};
console.log(JSON.stringify(summary, null, 2));
if (outFile) writeFileSync(outFile, JSON.stringify({ summary, results }, null, 1));
