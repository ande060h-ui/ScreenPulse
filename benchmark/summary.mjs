// Collects all results in one table. Run: node benchmark/summary.mjs
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), "results");
console.log("configuration".padEnd(44), "correct  easy  hard  avg.time >15s  thinking-tokens");
for (const f of readdirSync(dir).filter((f) => f.endsWith(".json")).sort()) {
  const r = JSON.parse(readFileSync(path.join(dir, f), "utf8")).results;
  const p = (xs) => `${Math.round((100 * xs.filter((x) => x.rigtigt).length) / xs.length)} %`.padStart(5);
  const avg = (k) => Math.round(r.reduce((s, x) => s + x[k], 0) / r.length);
  console.log(f.replace(".json", "").padEnd(44), p(r).padStart(7), p(r.filter((x) => x.niveau === "nem")), p(r.filter((x) => x.niveau === "svaer")),
    `${(avg("ms") / 1000).toFixed(1)} s`.padStart(8), String(r.filter((x) => x.ms > 15000).length).padStart(5), String(avg("taenk")).padStart(8));
}
