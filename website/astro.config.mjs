import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

// The production address on Vercel (also used for canonical links, the share image and the sitemap).
const SITE_URL = process.env.SITE_URL || "https://screenpulse.vercel.app";

export default defineConfig({
  site: SITE_URL,
  integrations: [sitemap()],
  build: { inlineStylesheets: "auto" },
});
