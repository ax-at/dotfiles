// Build-time generator for the GitHub Pages OpenGraph card (../../og.png).
//
// GitHub Pages is static hosting — there is no server to render a social image on
// the fly — so we pre-render a 1200x630 PNG here with Takumi (a Rust image engine
// with Node bindings; no headless browser) and commit the result. The Pages deploy
// workflow just copies og.png alongside index.html.
//
//   Regenerate:  cd scripts/og && npm install && npm run gen
//
// The card mirrors the homepage: Catppuccin Mocha, the ❯ mark, the one-command
// pitch, and the install line. Keep it in sync with index.html by eye.

import { Renderer } from "@takumi-rs/core";
import { container, text, image } from "@takumi-rs/helpers";
import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const here = (p) => fileURLToPath(new URL(p, import.meta.url));

// Catppuccin Mocha — the same palette index.html ships.
const C = {
  bg: "#181825",
  panel: "#1e1e2e",
  deep: "#11111b",
  line: "#313244",
  line2: "#45475a",
  text: "#cdd6f4",
  muted: "#9399b2",
  faint: "#6c7086",
  blue: "#89b4fa",
  green: "#a6e3a1",
  mauve: "#cba6f7",
  peach: "#fab387",
};
const SANS = "Space Grotesk";
const MONO = "JetBrains Mono";

// Fonts must be supplied as bytes — Takumi never reads system fonts. We fetch them
// from Google Fonts at generation time (network is available here; the committed PNG
// is what ships, so the build stays offline-safe).
//
// Why hand-roll this instead of @takumi-rs/helpers' googleFont()? That helper sends a
// modern-Chrome User-Agent, for which Google serves a SINGLE variable woff2 shared by
// every requested weight — then its parser dedupes by URL and keeps only the first
// (weight 400). So 500/600/700 are silently dropped: headings fall back to the
// variable font's light default instance and the card's weights never match the site
// (the very mismatch this card exists to avoid). Requesting with an old User-Agent
// makes Google emit a distinct STATIC .ttf per weight, so every weight is the real one.
const OLD_UA = "Mozilla/4.0";

async function loadFont(family, weights) {
  const cssUrl =
    `https://fonts.googleapis.com/css2?family=${encodeURIComponent(family)}` +
    `:wght@${weights.join(";")}`;
  const css = await fetch(cssUrl, { headers: { "User-Agent": OLD_UA } }).then((r) => {
    if (!r.ok) throw new Error(`HTTP ${r.status} fetching ${family} CSS`);
    return r.text();
  });

  // One @font-face block per weight, each pointing at its own static .ttf.
  const faces = [];
  for (const [, body] of css.matchAll(/@font-face\s*\{([^}]*)\}/g)) {
    const weight = Number(body.match(/font-weight:\s*(\d+)/)?.[1]);
    const src = body.match(/src:\s*url\(([^)]+)\)/)?.[1];
    if (!weight || !src) continue;
    const data = new Uint8Array(await fetch(src).then((r) => r.arrayBuffer()));
    faces.push({ name: family, data, weight, style: "normal" });
  }
  if (!faces.length) throw new Error(`No @font-face found for ${family}`);
  return faces;
}

const [sans, mono] = await Promise.all([
  loadFont(SANS, [400, 500, 600, 700]),
  loadFont(MONO, [400, 500, 700]),
]);

const markPng = await readFile(here("./mark.png"));

const renderer = new Renderer({ fonts: [...sans, ...mono], loadDefaultFonts: true });

// A non-breaking space keeps a visible gap between two adjacent text nodes.
const NB = " ";

const dot = (color, size = 10) =>
  container({ style: { width: size, height: size, borderRadius: 999, backgroundColor: color } });

const card = container({
  style: {
    width: 1200,
    height: 630,
    display: "flex",
    flexDirection: "column",
    justifyContent: "space-between",
    padding: "54px 76px",
    background: "linear-gradient(135deg, #1c1c2c 0%, #181825 52%, #141420 100%)",
    color: C.text,
    fontFamily: SANS,
  },
  children: [
    // ── brand row ───────────────────────────────────────────────
    container({
      style: { display: "flex", flexDirection: "row", alignItems: "center", gap: 18 },
      children: [
        image({ src: markPng, width: 60, height: 60, style: { borderRadius: 14 } }),
        container({
          style: {
            display: "flex",
            flexDirection: "row",
            alignItems: "baseline",
            fontFamily: MONO,
            fontSize: 30,
          },
          children: [
            text("ax-at", { color: C.muted, fontWeight: 500 }),
            text(`${NB}/${NB}`, { color: C.faint }),
            text("dotfiles", { color: C.text, fontWeight: 500 }),
          ],
        }),
      ],
    }),

    // ── pitch ───────────────────────────────────────────────────
    // marginTop widens the brand→eyebrow gap beyond what space-between alone gives,
    // so the eyebrow breathes under the wordmark the way it does on the site.
    container({
      style: { display: "flex", flexDirection: "column", marginTop: 24 },
      children: [
        // Mirrors the site's .eyebrow: the label, then a 1px rule that dissolves to
        // the right (linear-gradient from --line-2 to transparent) filling the row.
        container({
          style: {
            display: "flex",
            flexDirection: "row",
            alignItems: "center",
            gap: 16,
            marginBottom: 26,
          },
          children: [
            text("REPRODUCIBLE  ·  DECLARATIVE  ·  OPINIONATED", {
              fontFamily: MONO,
              fontSize: 21,
              letterSpacing: 3,
              color: C.muted,
            }),
            container({
              style: {
                flexGrow: 1,
                height: 2,
                background: `linear-gradient(90deg, ${C.line2}, transparent)`,
              },
            }),
          ],
        }),
        container({
          style: {
            display: "flex",
            flexDirection: "column",
            fontWeight: 600,
            fontSize: 76,
            lineHeight: 1.05,
            letterSpacing: -1.5,
          },
          children: [
            container({
              style: { display: "flex", flexDirection: "row", alignItems: "baseline" },
              children: [
                text("One command", { color: C.blue }),
                text(`${NB}sets up`, { color: C.text }),
              ],
            }),
            text("your entire dev machine.", { color: C.text }),
          ],
        }),
        text("The same tools, runtimes, editors, and dotfiles every time —", {
          fontSize: 27,
          color: C.muted,
          marginTop: 28,
          lineHeight: 1.4,
        }),
        text("declarative, idempotent, safe to re-run.", {
          fontSize: 27,
          color: C.muted,
          lineHeight: 1.4,
        }),
      ],
    }),

    // ── install line + meta ─────────────────────────────────────
    container({
      style: { display: "flex", flexDirection: "column", gap: 24 },
      children: [
        // Mirrors the site's .command bar: full-width, crust fill, --radius corners,
        // the same lifted shadow, and a terminal cursor block after the command.
        container({
          style: {
            display: "flex",
            flexDirection: "row",
            alignItems: "center",
            backgroundColor: C.deep,
            border: `1px solid ${C.line}`,
            borderRadius: 14,
            padding: "18px 22px",
            fontFamily: MONO,
            fontSize: 25,
            boxShadow: "0 18px 50px -30px rgba(0,0,0,0.9), inset 0 1px 0 rgba(255,255,255,0.02)",
          },
          children: [
            text("$", { color: C.green }),
            text(`${NB}sh -c "$(curl -fsSL https://ax-at.github.io/dotfiles/install)"`, {
              color: C.text,
            }),
            container({
              style: {
                width: 9,
                height: 26,
                borderRadius: 2,
                marginLeft: 9,
                backgroundColor: C.blue,
              },
            }),
          ],
        }),
        container({
          style: {
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-between",
            alignItems: "center",
            fontFamily: MONO,
            fontSize: 22,
          },
          children: [
            container({
              style: { display: "flex", flexDirection: "row", alignItems: "center", gap: 12 },
              children: [
                dot(C.green),
                text("macOS  ·  Linux & sandboxes soon", { color: C.muted }),
              ],
            }),
            text("80 packages  ·  11 modules", { color: C.faint }),
          ],
        }),
      ],
    }),
  ],
});

const png = await renderer.render(card, { width: 1200, height: 630, format: "png" });
const out = here("../../og.png");
await writeFile(out, png);
console.log(`Wrote ${out} (${png.length} bytes)`);
