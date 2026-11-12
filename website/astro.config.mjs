import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import vercel from "@astrojs/vercel";

// The production address on Vercel (also used for canonical links, the share image and the sitemap).
const SITE_URL = process.env.SITE_URL || "https://screenpulse.vercel.app";

export default defineConfig({
  site: SITE_URL,
  integrations: [sitemap()],
  adapter: vercel({
    webAnalytics: { enabled: true },
  }),
  build: { inlineStylesheets: "auto" },
});
