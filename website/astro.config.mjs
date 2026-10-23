import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

const repo = "https://github.com/bailleul-dev/robine-wake";

export default defineConfig({
  site: process.env.SITE_URL ?? "https://robine-wake.bailleul.dev",
  base: process.env.SITE_BASE ?? "/",
  integrations: [
    starlight({
      title: "Robine Wake",
      description:
        "A privacy-first smart alarm clock for Raspberry Pi: sunrise light, gentle sound, guided breathing.",
      favicon: "/favicon.svg",
      social: [{ icon: "github", label: "GitHub", href: repo }],
      editLink: { baseUrl: `${repo}/edit/main/website/` },
      customCss: ["./src/styles/docs.css"],
      sidebar: [
        { label: "Guides", items: [{ autogenerate: { directory: "docs/guides" } }] },
        { label: "Specifications", items: [{ autogenerate: { directory: "docs/specs" } }] },
        { label: "Design notes", items: [{ autogenerate: { directory: "docs/notes" } }] },
        { label: "Interfaces", items: [{ autogenerate: { directory: "docs/interfaces" } }] },
      ],
    }),
  ],
});
