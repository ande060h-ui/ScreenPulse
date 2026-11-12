// Runs the benchmark: sends every test image to Gemini exactly like the app does and checks
// which letter the keyboard signal would blink.
// Usage: node benchmark/run-benchmark.mjs <crop: centreret|skub|hel> <prompt: app|da> [repetitions=2] [model=gemini-3.8-flash] [thinking: standard|low|minimal]
//   prompt "app" = the current English Focus Mode prompt in app/Sources/Core/Prompts.swift
//   prompt "da"  = the original Danish prompt (benchmark/prompt-da.txt) the stored results were produced with
// Field names in the manifest and result files are Danish (historic test data).

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.dirname(HERE);
const [crop = "centreret", promptName = "app", repsArg = "2", model = "gemini-3.8-flash", thinking = "standard"] = process.argv.slice(2);
const REPS = Number(repsArg);
const CONCURRENCY = 8;

const env = Object.fromEntries(readFileSync(path.join(ROOT, ".env"), "utf8").split("\n").map((l) => l.match(/^([A-Z_]+)=(.*)$/)).filter(Boolean).map((m) => [m[1], m[2].replace(/^["']|["']$/g, "")]));
const KEY = env.GEMINI_API_KEY;
// The Focus Mode prompt is assembled in Prompts.swift from three string literals.
const promptsSrc = readFileSync(path.join(ROOT, "app/Sources/Core/Prompts.swift"), "utf8");
const lit = (name) => promptsSrc.match(new RegExp(`static let ${name} = (?:pointerIntro \\+ "\\\\n" \\+ )?"""\\n([\\s\\S]*?)\\n\\s*"""`))[1].replace(/^    /gm, "");
const appPrompt = [lit("pointerIntro"), lit("focus"), lit("ownWindow")].join("\n");
const systemPrompt = promptName === "app" ? appPrompt : readFileSync(path.join(HERE, `prompt-${promptName}.txt`), "utf8");
const manifest = JSON.parse(readFileSync(path.join(HERE, "images/manifest.json"), "utf8"));

// Same logic as cleanAnswerForLED() in the app
function cleanAnswerForLED(raw) {
  const t = raw.trim();
  const m = t.match(/(?:answer|svar):\s*([a-zæøåA-ZÆØÅ\s,]+)/i);
  if (m) { const e = m[0].replace(/(?:answer|svar):\s*/i, "").replace(/,/g, " ").trim(); if (e) return e; }
  const s = t.match(/^\s*[(\[]?([A-Za-zÆØÅæøå])[.)\]:\s]*$/);
  if (s) return s[1];
  return t;
}
const norm = (s) => s.toUpperCase().replace(/\s+/g, " ").trim();

async function ask(imageB64) {
  const body = JSON.stringify({
    systemInstruction: { parts: [{ text: systemPrompt }] },
    contents: [{ role: "user", parts: [{ inlineData: { mimeType: "image/png", data: imageB64 } }, { text: promptName === "app" ? "Answer the question at the mouse pointer." : "Besvar spørgsmålet ved musemarkøren." }] }],
    ...(thinking === "standard" ? {} : { generationConfig: { thinkingConfig: { thinkingLevel: thinking } } }),
  });
  for (let attempt = 0; attempt < 6; attempt++) {
    const t0 = Date.now();
    try {
      const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
        method: "POST", headers: { "Content-Type": "application/json", "x-goog-api-key": KEY }, body });
      const j = await r.json();
      if (r.status === 429 || r.status >= 500) { await new Promise((s) => setTimeout(s, 2000 * (attempt + 1))); continue; }
      const text = (j.candidates?.[0]?.content?.parts ?? []).filter((p) => !p.thought).map((p) => p.text ?? "").join("").trim();
      const u = j.usageMetadata ?? {};
      return { text: text || `[no answer: ${JSON.stringify(j).slice(0, 120)}]`, ms: Date.now() - t0,
        ind: u.promptTokenCount ?? 0, ud: u.candidatesTokenCount ?? 0, taenk: u.thoughtsTokenCount ?? 0 };
    } catch (e) { await new Promise((s) => setTimeout(s, 2000 * (attempt + 1))); }
  }
  return { text: "[error: no connection]", ms: 0, ind: 0, ud: 0, taenk: 0 };
}

const jobs = [];
for (const t of manifest) for (let r = 0; r < REPS; r++) jobs.push({ t, r });
const results = [];
let done = 0;
async function worker() {
  while (jobs.length) {
    const { t, r } = jobs.shift();
    const img = readFileSync(path.join(HERE, "images", crop, t.fil)).toString("base64");
    const a = await ask(img);
    const led = cleanAnswerForLED(a.text);
    results.push({ ...t, gentagelse: r + 1, raat: a.text, blinket: norm(led), rigtigt: norm(led) === t.forventet, ms: a.ms, ind: a.ind, ud: a.ud, taenk: a.taenk });
    process.stdout.write(`\r${++done}/${manifest.length * REPS}`);
  }
}
await Promise.all(Array.from({ length: CONCURRENCY }, worker));
results.sort((a, b) => a.nr - b.nr || a.gentagelse - b.gentagelse);

mkdirSync(path.join(HERE, "results"), { recursive: true });
const id = `${crop}-${promptName}-${model}${thinking === "standard" ? "" : "-taenk-" + thinking}`;
writeFileSync(path.join(HERE, "results", `${id}.json`), JSON.stringify({ crop, prompt: promptName, model, reps: REPS, results }, null, 2));

const pct = (xs) => `${xs.filter((x) => x.rigtigt).length}/${xs.length} (${Math.round((100 * xs.filter((x) => x.rigtigt).length) / xs.length)} %)`;
const group = (k) => Object.entries(results.reduce((a, x) => ((a[x[k]] ??= []).push(x), a), {})).map(([g, xs]) => `  ${String(g).padEnd(22)} ${pct(xs)}`).join("\n");
const avg = (k) => Math.round(results.reduce((s, x) => s + x[k], 0) / results.length);
console.log(`\n\n=== ${id} ===\nTotal: ${pct(results)}\nLevel:\n${group("niveau")}\nStyle:\n${group("stil")}\nPointer:\n${group("mus")}`);
console.log(`Avg. time: ${avg("ms")} ms · tokens in ${avg("ind")} · out ${avg("ud")} · thinking ${avg("taenk")} · over 15 s: ${results.filter((x) => x.ms > 15000).length}`);
