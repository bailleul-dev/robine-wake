# Robine Wake website

Marketing page and technical documentation, built with
[Astro](https://astro.build) and [Starlight](https://starlight.astro.build).

```sh
cd website
npm install
npm run dev      # http://localhost:4321
npm run build    # static site in dist/
```

- `src/pages/index.astro` — the landing page (`/`).
- `src/content/docs/docs/guides/` — hand-written guides (`/docs/guides/...`).
- `src/content/docs/docs/{specs,notes,interfaces}/` — **generated** from
  `../docs` by `scripts/sync-docs.mjs` on every `dev` / `build`; do not edit
  them, edit the source in `docs/`. The retired camera / bed-exit specs
  (group 40) are not published.

`SITE_URL` and `SITE_BASE` set the public URL and sub-path for a build
(for example `SITE_BASE=/robine-wake/` on GitHub Pages).
