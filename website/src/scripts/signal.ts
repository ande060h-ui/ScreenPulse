// Plays ScreenPulse keyboard signals on a <Keyboard> illustration.
// The patterns mirror app/Sources/Core/Signal.swift: letters and digits are counted out,
// yes is one long light, no is two, "answer ready" is two short blinks, error is three quick ones.

export type Signal =
  | { kind: "letters" | "number"; value: string }
  | { kind: "yes" | "no" | "ready" | "error" };
export type Step = { on: boolean; ms: number };
export type SignalHandle = { cancel: () => void; done: Promise<boolean> };

const wait = (ms: number, signal: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    const t = setTimeout(resolve, ms);
    signal.addEventListener("abort", () => { clearTimeout(t); reject(new Error("cancelled")); }, { once: true });
  });

export function blinkCount(c: string): number {
  if (/^[a-z]$/i.test(c)) return c.toLowerCase().charCodeAt(0) - 96;
  if (/^\d$/.test(c)) return c === "0" ? 10 : Number(c);
  return 0;
}

export function stepsFor(signal: Signal, unit = 420): Step[] {
  const out: Step[] = [];
  const blink = (n: number, on: number, off: number) => { for (let i = 0; i < n; i++) out.push({ on: true, ms: on }, { on: false, ms: off }); };
  switch (signal.kind) {
    case "letters":
    case "number":
      for (const c of signal.value) {
        if (c === " ") { out.push({ on: false, ms: unit * 6 }); continue; }
        blink(blinkCount(c), unit, unit);
        out.push({ on: false, ms: unit * 3.5 });
      }
      break;
    case "yes": blink(1, unit * 3, unit); break;
    case "no": blink(2, unit * 3, unit); break;
    case "ready": blink(2, 200, 200); break;
    case "error": blink(3, 80, 80); break;
  }
  return out;
}

export const reducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/** The "thinking" flicker in the Caps Lock light only. With reduced motion the light stays on instead. */
async function think(kb: HTMLElement, ms: number, signal: AbortSignal) {
  const caps = (on: boolean) => { kb.dataset.led = on ? "on" : "off"; kb.dataset.backlight = "off"; };
  if (reducedMotion()) { caps(true); await wait(ms, signal); caps(false); return; }
  const end = performance.now() + ms;
  while (performance.now() < end) {
    caps(true); await wait(45, signal);
    caps(false); await wait(45, signal);
  }
}

/** Plays only the thinking flicker for `ms` milliseconds. */
export function playThinking(kb: HTMLElement, ms: number, onDone?: () => void): SignalHandle {
  const ctrl = new AbortController();
  const done = (async () => {
    try { await think(kb, ms, ctrl.signal); onDone?.(); return true; }
    catch { kb.dataset.led = "off"; return false; }
  })();
  return { cancel: () => ctrl.abort(), done };
}

export function playSignal(
  kb: HTMLElement,
  signal: Signal,
  opts: { unit?: number; thinkMs?: number; onPhase?: (phase: "thinking" | "pause" | "blink" | "done", n?: number) => void } = {},
): SignalHandle {
  const ctrl = new AbortController();
  const set = (on: boolean, backlight = on) => {
    kb.dataset.led = on ? "on" : "off";
    kb.dataset.backlight = backlight ? "on" : "off";
  };
  const done = (async () => {
    try {
      const thinkMs = opts.thinkMs ?? 1500;
      if (thinkMs > 0) {
        opts.onPhase?.("thinking");
        await think(kb, thinkMs, ctrl.signal);
        opts.onPhase?.("pause");
        await wait(signal.kind === "error" ? 150 : 900, ctrl.signal);
      }
      let n = 0;
      for (const step of stepsFor(signal, opts.unit)) {
        if (step.on) opts.onPhase?.("blink", ++n);
        set(step.on);
        await wait(step.ms, ctrl.signal);
      }
      opts.onPhase?.("done");
      return true;
    } catch {
      set(false);
      return false;
    }
  })();
  return { cancel: () => ctrl.abort(), done };
}

