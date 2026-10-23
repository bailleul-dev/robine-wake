// Copies the repository documentation (../docs) into the Starlight content
// tree, so the specifications stay the single source of truth. Generated
// folders are git-ignored. Camera / bed-exit specs (group 40) are retired
// from the product and are not published.
import { mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, posix, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const docs = join(root, "docs");
const out = join(root, "website/src/content/docs/docs");
const base = (process.env.SITE_BASE ?? "/").replace(/\/?$/, "/");
const repo = "https://github.com/bailleul-dev/robine-wake";

const RETIRED_GROUPS = new Set(["40"]);

/** @type {Map<string, {route: string, file: string, title: string, source: string}>} */
const pages = new Map();

function walk(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)],
  );
}

function register(source, section, slug) {
  const body = readFileSync(source, "utf8");
  const title = body.match(/^#\s+(.+)$/m)?.[1].trim() ?? slug;
  const rel = relative(root, source).split("\\").join("/");
  pages.set(rel, {
    route: `${base}docs/${section}/${slug}/`,
    file: join(out, section, `${slug}.md`),
    title,
    source: rel,
  });
}

for (const file of walk(join(docs, "specs"))) {
  const m = file.match(/specs\/(\d\d)\/(\d{3}-[\w-]+)\/spec\.md$/);
  if (m && !RETIRED_GROUPS.has(m[1])) register(file, "specs", `${m[1]}-${m[2]}`);
}
for (const f of readdirSync(join(docs, "knowledges")))
  if (f.endsWith(".md") && f !== "README.md")
    register(join(docs, "knowledges", f), "notes", f.replace(/\.md$/, ""));
register(join(docs, "bluetooth/v1.md"), "interfaces", "bluetooth-v1");

function rewriteLinks(text, fromRel) {
  return text.replace(/\]\(([^)\s]+)\)/g, (whole, href) => {
    if (/^([a-z]+:|#|\/)/i.test(href)) return whole;
    const [path, hash = ""] = href.split("#");
    if (!path) return whole;
    const target = posix.normalize(posix.join(posix.dirname(fromRel), path));
    const page = pages.get(target);
    if (page) return `](${page.route}${hash ? `#${hash}` : ""})`;
    // Anything else (code, retired specs, assets) points at the repository.
    return `](${repo}/blob/main/${target}${hash ? `#${hash}` : ""})`;
  });
}

for (const dir of ["specs", "notes", "interfaces"])
  rmSync(join(out, dir), { recursive: true, force: true });

for (const page of pages.values()) {
  let text = readFileSync(join(root, page.source), "utf8");
  text = text.replace(/^#\s+.+\n+/m, ""); // Starlight renders the title itself
  text = rewriteLinks(text, page.source);
  const front = [
    "---",
    `title: ${JSON.stringify(page.title)}`,
    `editUrl: ${JSON.stringify(`${repo}/edit/main/${page.source}`)}`,
    "---",
    "",
  ].join("\n");
  mkdirSync(dirname(page.file), { recursive: true });
  writeFileSync(page.file, front + text);
}
console.log(`sync-docs: ${pages.size} pages`);
