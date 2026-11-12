// Generates 100 realistic test images: real web pages rendered in Chrome, cropped around the pointer
// exactly like the app does (pointer drawn in, Retina 2x, sips -Z 2000). Question content is Danish test data.
// Run: node benchmark/make-images.mjs   (macOS, needs Google Chrome and ./benchmark/crop)

import { nemme, svaere } from "./questions.mjs";
import { spawn, execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync, rmSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, "images");
const SCREEN = { w: 1440, h: 900 };            // skærm i punkter (MacBook)
const CAPTURE = { w: 1100, h: 800 };           // samme som captureSize i appen
const LETTERS = "ABCDE";

// ---------- deterministisk tilfældighed ----------
let seed = 20261105;
const rnd = () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const shuffle = (a) => { a = [...a]; for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };
const between = (a, b) => a + rnd() * (b - a);
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// ---------- spørgsmål ----------
const bank = [...nemme.map((q) => ({ lvl: "nem", q })), ...svaere.map((q) => ({ lvl: "svaer", q }))];
function prepare(entry) {
  const [text, right, wrong] = entry.q;
  const options = shuffle([right, ...wrong]);
  return { text, options, correct: options.indexOf(right), lvl: entry.lvl };
}

// ---------- stilarter (13 forskellige quiz-sider) ----------
// Hver stil: css + funktion der laver HTML for ét spørgsmål. Alle bruger .q (blok), .qt (spørgsmålstekst), .opt (mulighed).
const radio = (on) => `<span class="rb${on ? " on" : ""}"></span>`;
const styles = {
  "google-forms": {
    single: false,
    css: (fs) => `body{background:#f0ebf8;font-family:Arial,Helvetica,sans-serif;margin:0}
      .wrap{max-width:720px;margin:24px auto}.head{background:#fff;border-top:10px solid #673ab7;border-radius:8px;padding:22px 24px;margin-bottom:12px;font-size:28px}
      .q{background:#fff;border-radius:8px;padding:24px;margin-bottom:12px;border:1px solid #dadce0}.qt{font-size:${fs}px;color:#202124;margin-bottom:16px}
      .opt{display:flex;align-items:center;gap:12px;font-size:${fs - 2}px;color:#202124;padding:9px 0}
      .rb{width:18px;height:18px;border:2px solid #5f6368;border-radius:50%;display:inline-block;flex:none}.rb.on{border-color:#673ab7;box-shadow:inset 0 0 0 4px #fff,inset 0 0 0 10px #673ab7}`,
    head: (n) => `<div class="head">Scrum-quiz – Runde ${n}<div style="font-size:14px;color:#5f6368;margin-top:8px">* Angiver et obligatorisk spørgsmål</div></div>`,
    q: (q, i, sel) => `<div class="q"><div class="qt">${esc(q.text)} <span style="color:#d93025">*</span></div>${q.options.map((o, k) => `<div class="opt">${radio(sel === k)}${esc(o)}</div>`).join("")}</div>`,
  },
  "moodle": {
    single: false,
    css: (fs) => `body{background:#fff;font-family:"Helvetica Neue",Helvetica,sans-serif;margin:0;color:#1d2125}
      .wrap{max-width:980px;margin:20px auto}.q{display:flex;gap:16px;margin-bottom:26px}
      .info{width:130px;flex:none;background:#f8f9fa;border:1px solid #dee2e6;padding:10px;font-size:13px;line-height:1.5}.info b{font-size:15px}
      .content{flex:1;background:#e7f3f5;padding:16px;border-radius:4px}.qt{font-size:${fs}px;margin-bottom:12px}.sub{font-size:14px;margin-bottom:6px}
      .opt{display:flex;align-items:center;gap:8px;font-size:${fs - 1}px;padding:5px 0}.rb{width:14px;height:14px;border:1px solid #666;border-radius:50%;flex:none}.rb.on{background:radial-gradient(#0f6cbf 45%,#fff 50%)}`,
    head: () => "",
    q: (q, i, sel) => `<div class="q"><div class="info"><b>Spørgsmål ${i + 1}</b><br>${sel != null ? "Besvaret" : "Endnu ikke besvaret"}<br>Point ud af 1,00<br>⚑ Markér spørgsmål</div><div class="content"><div class="qt">${esc(q.text)}</div><div class="sub">Vælg en:</div>${q.options.map((o, k) => `<div class="opt">${radio(sel === k)}${"abcde"[k]}. ${esc(o)}</div>`).join("")}</div></div>`,
  },
  "kahoot": {
    single: true,
    css: (fs) => `body{background:#46178f;font-family:Montserrat,"Avenir Next",Arial,sans-serif;margin:0}
      .wrap{padding:30px 40px}.q{}.qt{background:#fff;font-size:${fs + 10}px;font-weight:700;text-align:center;padding:22px;border-radius:6px;margin:0 auto 200px;max-width:1100px}
      .grid{display:grid;grid-template-columns:1fr 1fr;gap:12px}.opt{color:#fff;font-weight:700;font-size:${fs + 4}px;padding:26px 20px;border-radius:5px;display:flex;align-items:center;gap:18px;min-height:70px}
      .opt:nth-child(1){background:#e21b3c}.opt:nth-child(2){background:#1368ce}.opt:nth-child(3){background:#d89e00}.opt:nth-child(4){background:#26890c}.opt:nth-child(5){background:#864cbf}
      .sh{font-size:34px}`,
    head: () => "",
    q: (q) => `<div class="q"><div class="qt">${esc(q.text)}</div><div class="grid">${q.options.map((o, k) => `<div class="opt"><span class="sh">${"▲◆●■★"[k]}</span>${esc(o)}</div>`).join("")}</div></div>`,
  },
  "moerk": {
    single: false,
    css: (fs) => `body{background:#121212;color:#e8e8e8;font-family:"Avenir Next",Avenir,sans-serif;margin:0}
      .wrap{max-width:800px;margin:30px auto}.q{margin-bottom:40px}.qt{font-size:${fs + 2}px;font-weight:600;margin-bottom:14px}
      .opt{display:flex;align-items:center;gap:14px;background:#1f1f1f;border:1px solid #333;border-radius:12px;padding:12px 16px;margin:8px 0;font-size:${fs}px}
      .opt.on{border-color:#7c4dff;background:#2a2140}.lt{width:30px;height:30px;border-radius:50%;background:#333;display:grid;place-items:center;font-weight:700;flex:none}`,
    head: (n) => `<div style="font-size:13px;color:#888;margin-bottom:24px">QUIZ · SCRUM · DEL ${n}</div>`,
    q: (q, i, sel) => `<div class="q"><div class="qt">${i + 1}. ${esc(q.text)}</div>${q.options.map((o, k) => `<div class="opt${sel === k ? " on" : ""}"><span class="lt">${LETTERS[k]}</span>${esc(o)}</div>`).join("")}</div>`,
  },
  "word-dokument": {
    single: false,
    css: (fs) => `body{background:#e5e5e5;font-family:"Times New Roman",Times,serif;margin:0}
      .wrap{background:#fff;max-width:800px;margin:20px auto;padding:60px 70px;box-shadow:0 0 8px #aaa;min-height:1400px}.q{margin-bottom:26px}
      .qt{font-size:${fs}px;margin-bottom:8px}.opts{display:flex;flex-wrap:wrap;gap:6px 34px}.opt{font-size:${fs}px}`,
    head: (n) => `<h2 style="text-align:center;font-weight:normal">Eksamensopgave i Scrum – sæt ${n}</h2><p style="font-size:15px">Sæt ring om det rigtige svar.</p>`,
    q: (q, i, sel) => `<div class="q"><div class="qt">${i + 1}. ${esc(q.text)}</div><div class="opts">${q.options.map((o, k) => `<span class="opt">${"abcde"[k]}) ${esc(o)}</span>`).join("")}</div></div>`,
  },
  "tabel-venstre": {
    single: false,
    css: (fs) => `body{background:#fff;font-family:Verdana,sans-serif;margin:0}.wrap{max-width:1150px;margin:20px auto}
      table{border-collapse:collapse;width:100%}td{border:1px solid #999;padding:12px;vertical-align:top}.q td:first-child{width:42%;background:#f3f6fa}
      .qt{font-size:${fs}px}.opt{font-size:${fs - 1}px;padding:4px 0}`,
    head: () => "",
    wrapStart: "<table>", wrapEnd: "</table>",
    q: (q, i, sel) => `<tr class="q"><td><div class="qt"><b>${i + 1}.</b> ${esc(q.text)}</div></td><td>${q.options.map((o, k) => `<div class="opt">${LETTERS[k]}. ${esc(o)}${sel === k ? " ✔" : ""}</div>`).join("")}</td></tr>`,
  },
  "tabel-hoejre": {
    single: false,
    css: (fs) => `body{background:#fffdf5;font-family:Georgia,serif;margin:0}.wrap{max-width:1150px;margin:20px auto}
      table{border-collapse:collapse;width:100%}td{border-bottom:2px solid #c9b98a;padding:14px;vertical-align:middle}.q td:last-child{width:45%;font-style:italic}
      .qt{font-size:${fs}px}.opt{font-size:${fs - 1}px;padding:3px 0}`,
    head: () => "",
    wrapStart: "<table>", wrapEnd: "</table>",
    q: (q, i, sel) => `<tr class="q"><td>${q.options.map((o, k) => `<div class="opt">(${LETTERS[k]}) ${esc(o)}</div>`).join("")}</td><td><div class="qt">Spørgsmål ${i + 1}: ${esc(q.text)}</div></td></tr>`,
  },
  "spoergsmaal-under": {
    single: false,
    css: (fs) => `body{background:#f7f7f7;font-family:"Trebuchet MS",sans-serif;margin:0}.wrap{max-width:760px;margin:20px auto}
      .q{background:#fff;border-left:5px solid #00897b;padding:16px 20px;margin-bottom:22px}.opt{font-size:${fs}px;padding:4px 0}
      .qt{font-size:${fs + 1}px;font-weight:bold;margin-top:12px;color:#00695c}`,
    head: () => "",
    q: (q, i, sel) => `<div class="q">${q.options.map((o, k) => `<div class="opt">${LETTERS[k]} – ${esc(o)}</div>`).join("")}<div class="qt">▲ ${i + 1}) ${esc(q.text)}</div></div>`,
  },
  "to-kolonner": {
    single: false,
    css: (fs) => `body{background:#eef2f7;font-family:-apple-system,"SF Pro Text",Helvetica,sans-serif;margin:0}.wrap{max-width:1300px;margin:20px auto;display:grid;grid-template-columns:1fr 1fr;gap:18px}
      .q{background:#fff;border-radius:14px;padding:20px;box-shadow:0 2px 6px rgba(0,0,0,.08)}.qt{font-size:${fs}px;font-weight:600;margin-bottom:12px}
      .opt{font-size:${fs - 2}px;padding:6px 10px;border-radius:8px;margin:4px 0;background:#f5f7fa}.opt.on{background:#dbeafe;outline:2px solid #3b82f6}`,
    head: () => "",
    q: (q, i, sel) => `<div class="q"><div class="qt">${esc(q.text)}</div>${q.options.map((o, k) => `<div class="opt${sel === k ? " on" : ""}">(${LETTERS[k]}) ${esc(o)}</div>`).join("")}</div>`,
  },
  "runde-quiz": { // ligner brugerens egen quiz
    single: false,
    css: (fs) => `body{background:#fff;font-family:-apple-system,Helvetica,sans-serif;margin:0;color:#222}.wrap{max-width:820px;margin:20px auto}
      .q{margin-bottom:30px}.qt{font-size:${fs}px;font-weight:700;margin-bottom:10px}.opt{font-size:${fs - 1}px;padding:7px 0}`,
    head: (n) => `<h1 style="font-size:24px">SCRUM – Runde ${n}</h1><p style="color:#666">0/5 besvaret</p>`,
    q: (q, i, sel) => `<div class="q"><div class="qt">${i + 1}. ${esc(q.text)}</div>${q.options.map((o, k) => `<div class="opt">${LETTERS[k]}. ${esc(o)}${sel === k ? " (Valgt)" : ""}</div>`).join("")}</div>`,
  },
  "lille-mono": {
    single: false,
    css: (fs) => `body{background:#fafafa;color:#555;font-family:"Courier New",monospace;margin:0}.wrap{max-width:900px;margin:10px 30px}
      .q{margin-bottom:12px}.qt{font-size:12px;margin-bottom:2px}.opt{font-size:12px;padding:1px 0}`,
    head: () => `<div style="font-size:12px">=== scrum_test.txt ===</div>`,
    q: (q, i, sel) => `<div class="q"><div class="qt">Q${i + 1}: ${esc(q.text)}</div>${q.options.map((o, k) => `<div class="opt">[${sel === k ? "x" : " "}] ${LETTERS[k]}) ${esc(o)}</div>`).join("")}</div>`,
  },
  "stor-lav-kontrast": {
    single: false,
    css: (fs) => `body{background:#ececec;color:#8a8a8a;font-family:Georgia,serif;margin:0}.wrap{max-width:1000px;margin:20px auto}
      .q{margin-bottom:40px}.qt{font-size:26px;margin-bottom:12px}.opt{font-size:24px;padding:6px 0;display:flex;gap:14px;align-items:center}
      .lt{width:34px;height:34px;border:2px solid #aaa;border-radius:50%;display:grid;place-items:center;font-size:18px;flex:none}`,
    head: () => "",
    q: (q, i, sel) => `<div class="q"><div class="qt">${esc(q.text)}</div>${q.options.map((o, k) => `<div class="opt"><span class="lt">${LETTERS[k]}</span>${esc(o)}</div>`).join("")}</div>`,
  },
  "comic-nummer": { // svarmuligheder nummereret 1-4 i stedet for bogstaver
    single: false,
    css: (fs) => `body{background:#fff8dc;font-family:"Comic Sans MS",cursive;margin:0}.wrap{max-width:780px;margin:20px auto}
      .q{border:3px dashed #ff6f61;border-radius:18px;padding:16px 22px;margin-bottom:20px;background:#fff}.q:nth-child(even){background:#e8f7ff;border-color:#2d9cdb}
      .qt{font-size:${fs + 1}px;color:#b03a2e;margin-bottom:8px}.opt{font-size:${fs}px;padding:3px 0}`,
    head: () => `<h2 style="color:#e67e22">🌟 Scrum-quiz for 2. semester 🌟</h2>`,
    q: (q, i, sel) => `<div class="q"><div class="qt">${esc(q.text)}</div>${q.options.map((o, k) => `<div class="opt">${k + 1}) ${esc(o)}</div>`).join("")}</div>`,
  },
};
const styleNames = Object.keys(styles);
const cursorKinds = ["spoergsmaal", "rigtig-mulighed", "forkert-mulighed", "midt-i-mulighederne", "margin-venstre", "til-hoejre", "lige-under-blokken"];

// ---------- CDP (Chrome DevTools Protocol) ----------
async function startChrome() {
  const port = 9300 + Math.floor(Math.random() * 500);
  const profile = mkdtempSync(path.join(tmpdir(), "sk-chrome-"));
  const proc = spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    ["--headless=new", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, "--hide-scrollbars", "--no-first-run", "--disable-gpu", "about:blank"],
    { stdio: "ignore" });
  let list;
  for (let t = 0; t < 50; t++) {
    try { list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); if (list.find((x) => x.type === "page")) break; } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  const page = list.find((x) => x.type === "page");
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener("open", r, { once: true }));
  let id = 0; const waiting = new Map(); const events = [];
  ws.addEventListener("message", (m) => {
    const d = JSON.parse(m.data);
    if (d.id && waiting.has(d.id)) { const { res, rej } = waiting.get(d.id); waiting.delete(d.id); d.error ? rej(new Error(d.error.message)) : res(d.result); }
    else if (d.method) events.push(d.method);
  });
  const send = (method, params = {}) => new Promise((res, rej) => { const i = ++id; waiting.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params })); });
  const close = () => { try { ws.close(); } catch {} proc.kill(); setTimeout(() => { try { rmSync(profile, { recursive: true, force: true }); } catch {} }, 1500); };
  return { send, close };
}

// ---------- byg én test ----------
function buildPage(styleName, qs, selected, fs, runde) {
  const st = styles[styleName];
  const blocks = qs.map((q, i) => st.q(q, i, selected[i])).join("");
  return `<!doctype html><html lang="da"><head><meta charset="utf-8"><style>*{box-sizing:border-box}${st.css(fs)}
    .rb{display:inline-block}#musemarkoer{position:fixed;z-index:99999;pointer-events:none}</style></head>
    <body>${browserChrome(runde)}<div style="height:112px"></div><div class="wrap">${st.head(runde)}${st.wrapStart || ""}${blocks}${st.wrapEnd || ""}</div></body></html>`;
}

// macOS-menulinje + Chrome-faneblade og adresselinje (fast øverst, ligesom på en rigtig skærm)
function browserChrome(runde) {
  const host = ["moodle.ucl.dk/mod/quiz", "docs.google.com/forms", "kahoot.it", "quizlet.com/scrum", "itslearning.com/test"][runde % 5];
  return `<div style="position:fixed;top:0;left:0;right:0;z-index:9999;font-family:-apple-system,'SF Pro Text',Helvetica,sans-serif">
    <div style="height:25px;background:#ececec;display:flex;align-items:center;gap:18px;padding:0 14px;font-size:13px;color:#111">
      <b></b><b>Chrome</b><span>Arkiv</span><span>Rediger</span><span>Vis</span><span>Historik</span><span>Bogmærker</span><span>Profiler</span><span>Fane</span><span>Vindue</span><span>Hjælp</span>
      <span style="margin-left:auto">⇪ 🔋 Wi‑Fi  tor. 5. nov. 10.4${runde}</span></div>
    <div style="height:46px;background:#dfe3e8;display:flex;align-items:flex-end;padding-left:80px;gap:2px">
      <div style="background:#fff;border-radius:8px 8px 0 0;padding:8px 14px;font-size:12px;width:230px">Scrum-quiz – Runde ${runde}</div>
      <div style="padding:8px 14px;font-size:12px;width:200px;color:#444">Gmail – Indbakke (3)</div>
      <div style="padding:8px 14px;font-size:12px;width:200px;color:#444">Scrum Guide 2020.pdf</div></div>
    <div style="height:41px;background:#fff;display:flex;align-items:center;gap:12px;padding:0 12px;border-bottom:1px solid #d0d0d0;font-size:14px;color:#555">
      ← → ⟳<div style="flex:1;background:#f1f3f4;border-radius:16px;padding:6px 14px;color:#222">🔒 ${host}/runde-${runde}</div>☆ ⋮</div></div>`;
}

const arrowSVG = `<svg xmlns="http://www.w3.org/2000/svg" width="17" height="25" viewBox="0 0 17 25"><path d="M1 1 L1 19.5 L5.6 15.4 L8.6 22.6 L11.6 21.3 L8.7 14.3 L14.7 14.3 Z" fill="#000" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/></svg>`;

async function main() {
  rmSync(OUT, { recursive: true, force: true });
  mkdirSync(OUT, { recursive: true });
  const chrome = await startChrome();
  const { send } = chrome;
  await send("Page.enable");
  const manifest = [];
  const kindsOrder = shuffle(Array.from({ length: 100 }, (_, i) => cursorKinds[i % cursorKinds.length]));
  const stylesOrder = shuffle(Array.from({ length: 100 }, (_, i) => styleNames[i % styleNames.length]));

  for (let n = 0; n < 100; n++) {
    const entry = bank[n];
    const styleName = stylesOrder[n];
    const st = styles[styleName];
    const target = prepare(entry);
    // naboer: andre spørgsmål på samme side
    const others = shuffle(bank.filter((_, k) => k !== n)).slice(0, st.single ? 0 : 2 + Math.floor(rnd() * 3)).map(prepare);
    const tIndex = st.single ? 0 : Math.floor(rnd() * (others.length + 1));
    const qs = [...others]; qs.splice(tIndex, 0, target);
    // nogle sider har allerede et (forkert) valgt svar markeret
    const selected = qs.map((q, i) => (rnd() < 0.3 ? (i === tIndex ? (q.correct + 1 + Math.floor(rnd() * (q.options.length - 1))) % q.options.length : Math.floor(rnd() * q.options.length)) : null));
    const fs = Math.round(between(14, 20));
    const scale = rnd() < 0.75 ? 2 : 1;          // 75 % Retina, 25 % almindelig skærm
    const kind = kindsOrder[n];
    const html = buildPage(styleName, qs, selected, fs, 1 + Math.floor(rnd() * 9));
    const htmlPath = path.join(OUT, `side-${String(n + 1).padStart(3, "0")}.html`);
    writeFileSync(htmlPath, html);

    await send("Emulation.setDeviceMetricsOverride", { width: SCREEN.w, height: SCREEN.h, deviceScaleFactor: scale, mobile: false });
    await send("Page.navigate", { url: "file://" + htmlPath });
    for (let t = 0; t < 50; t++) {
      const r = await send("Runtime.evaluate", { expression: "document.readyState", returnByValue: true });
      if (r.result.value === "complete") break;
      await new Promise((r) => setTimeout(r, 50));
    }
    await send("Runtime.evaluate", { expression: "document.fonts.ready", awaitPromise: true });

    // rul så målspørgsmålet står et realistisk sted på skærmen
    const wantY = Math.round(between(170, 560));
    const geo = (await send("Runtime.evaluate", {
      returnByValue: true,
      expression: `(() => {
        const b = document.querySelectorAll('.q')[${tIndex}];
        const top = b.getBoundingClientRect().top + scrollY;
        scrollTo(0, Math.max(0, top - ${wantY}));
        const r = (e) => { const x = e.getBoundingClientRect(); return { x: x.left, y: x.top, w: x.width, h: x.height }; };
        const textRect = (e) => { const g = document.createRange(); g.selectNodeContents(e); const x = g.getBoundingClientRect(); return { x: x.left, y: x.top, w: x.width, h: x.height }; };
        const opts = [...b.querySelectorAll('.opt')];
        return { block: r(b), qt: textRect(b.querySelector('.qt')), opts: opts.map(textRect), optBoxes: opts.map(r) };
      })()`,
    })).result.value;

    // vælg musens position
    const { block, qt, opts } = geo;
    const optsTop = Math.min(...opts.map((o) => o.y)), optsBottom = Math.max(...opts.map((o) => o.y + o.h));
    const optsLeft = Math.min(...opts.map((o) => o.x)), optsRight = Math.max(...opts.map((o) => o.x + o.w));
    const inRect = (o) => [o.x + between(0.15, 0.85) * o.w, o.y + between(0.3, 0.7) * o.h];
    let [mx, my] = {
      "spoergsmaal": () => inRect(qt),
      "rigtig-mulighed": () => inRect(opts[target.correct]),
      "forkert-mulighed": () => inRect(opts[pick(opts.map((_, k) => k).filter((k) => k !== target.correct))]),
      "midt-i-mulighederne": () => [(optsLeft + optsRight) / 2 + between(-20, 20), (optsTop + optsBottom) / 2 + between(-8, 8)],
      "margin-venstre": () => [Math.max(8, Math.min(qt.x, optsLeft) - between(25, 70)), (optsTop + optsBottom) / 2],
      "til-hoejre": () => [Math.min(SCREEN.w - 8, optsRight + between(40, 160)), between(optsTop, optsBottom)],
      "lige-under-blokken": () => [between(optsLeft, (optsLeft + optsRight) / 2), Math.min(block.y + block.h, optsBottom + 30) + between(-4, 6)],
    }[kind]();
    mx = Math.round(Math.min(SCREEN.w - 2, Math.max(2, mx)));
    my = Math.round(Math.min(SCREEN.h - 2, Math.max(2, my)));

    // markør (macOS-pil, spidsen præcis på musens punkt)
    await send("Runtime.evaluate", { expression: `(() => { const d = document.createElement('div'); d.id = 'musemarkoer'; d.innerHTML = ${JSON.stringify(arrowSVG)}; d.style.left = '${mx - 1}px'; d.style.top = '${my - 1}px'; document.body.appendChild(d); })()` });

    // hele skærmen som "screencapture" ville se den, derefter beskæring i pixels
    const shot = await send("Page.captureScreenshot", { format: "png" });
    const full = path.join(OUT, "_skaerm.png");
    writeFileSync(full, Buffer.from(shot.data, "base64"));
    const name = `${String(n + 1).padStart(3, "0")}-${target.lvl}-${styleName}-${kind}.png`;
    const crops = {
      // appens nuværende metode: musen i midten, mindre område tæt på kanten
      centreret: (() => {
        const hw = Math.max(150, Math.min(CAPTURE.w / 2, mx, SCREEN.w - mx));
        const hh = Math.max(150, Math.min(CAPTURE.h / 2, my, SCREEN.h - my));
        const x0 = Math.max(0, mx - hw), y0 = Math.max(0, my - hh);
        return { x: x0, y: y0, w: Math.min(SCREEN.w, mx + hw) - x0, h: Math.min(SCREEN.h, my + hh) - y0 };
      })(),
      // alternativ: fuld størrelse, skubbet ind på skærmen (musen står så ikke altid i midten)
      // alternativ: hele skærmen (markøren er tegnet med, så modellen kan finde den)
      hel: { x: 0, y: 0, w: SCREEN.w, h: SCREEN.h },
      skub: { x: Math.min(Math.max(0, mx - CAPTURE.w / 2), SCREEN.w - CAPTURE.w), y: Math.min(Math.max(0, my - CAPTURE.h / 2), SCREEN.h - CAPTURE.h), w: CAPTURE.w, h: CAPTURE.h },
    };
    for (const [mode, c] of Object.entries(crops)) {
      mkdirSync(path.join(OUT, mode), { recursive: true });
      const file = path.join(OUT, mode, name);
      execFileSync(path.join(HERE, "crop"), [full, file, String(Math.round(c.x * scale)), String(Math.round(c.y * scale)),
        String(Math.round(c.w * scale)), String(Math.round(c.h * scale))], { stdio: "ignore" });
      execFileSync("/usr/bin/sips", ["-Z", "2000", file], { stdio: "ignore" }); // som appen
    }

    const expected = LETTERS[target.correct];
    manifest.push({ nr: n + 1, fil: name, niveau: target.lvl, stil: styleName, mus: kind, skala: scale, skrift: fs, musX: mx, musY: my,
      forvalgtSvar: selected[tIndex] != null ? LETTERS[selected[tIndex]] : null, antalSpoergsmaalPaaSiden: qs.length,
      spoergsmaal: target.text, muligheder: target.options, forventet: expected });
    process.stdout.write(`\r${n + 1}/100 ${name.padEnd(70)}`);
  }
  writeFileSync(path.join(OUT, "manifest.json"), JSON.stringify(manifest, null, 2));
  rmSync(path.join(OUT, "_skaerm.png"), { force: true });
  chrome.close();
  console.log(`\nDone: ${manifest.length} images in ${OUT}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
