# ScreenPulse website

Static site built with [Astro](https://astro.build). No client framework; two small scripts drive the keyboard demos.

```bash
npm install
```

```bash
npm run dev      # http://localhost:4321
```

```bash
npm run build    # output in dist/
```

## Hosting

The site is a Vercel project (`screenpulse`, root directory `website`) connected to this repository.
Production address: <https://screenpulse.vercel.app> (the project also answers on its generated
Vercel addresses, which point search engines to this one). Vercel Authentication protects every
deployment, including production, so only members of the Vercel team can see it until protection is
turned off (Project Settings → Deployment Protection). The repository URL, licence name, Mac requirement
and the download switches live in `src/site.ts`.

## Structure

- `src/pages/index.astro` – all sections and their content (features, steps, FAQ)
- `src/components/` – `Header`, `Hero`, `Keyboard`, `AnswerWindow`, `SignalLab`, `Logo`
- `src/scripts/signal.ts` – the blink pattern, mirroring the app's timings
- `src/styles/global.css` – design tokens (see `docs/BRAND.md`)

Only describe features the app actually has. The feature list and FAQ are written against
the implementation in `app/`; update them together.
