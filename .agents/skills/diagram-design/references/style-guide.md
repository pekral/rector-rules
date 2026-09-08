# Style Guide

The single source of truth for every token a diagram uses. When a value here and a value in a diagram disagree, this file wins.

## Contents
- [Palette](#palette)
- [Dark mode](#dark-mode)
- [Type roles](#type-roles)
- [Spacing grid](#spacing-grid)
- [Strokes, radius, and depth](#strokes-radius-and-depth)
- [Node sizes](#node-sizes)
- [Contrast floor](#contrast-floor)
- [The token block](#the-token-block)

## Palette

Neutrals carry the structure. Exactly one accent carries the meaning. A second accent is allowed only for a genuine error/warning state, never for a second category.

| Token | Light value | Role |
|-------|-------------|------|
| `--canvas` | `#fbfbfa` | page and node fill behind edge labels |
| `--surface` | `#ffffff` | node fill |
| `--hairline` | `#c8c4bc` | every border and every edge |
| `--ink` | `#1c1b19` | titles and node labels |
| `--ink-muted` | `#6b6862` | captions, edge labels, secondary text |
| `--accent` | `#c2410c` | the one element the reader must see first |
| `--accent-soft` | `#fdf0e8` | fill behind an accented node |
| `--alert` | `#9f1239` | an error or failure path only |

The accent is deliberately warm and slightly desaturated. A saturated primary blue is the default of every diagram tool, which is exactly why a diagram using it reads as generated.

## Dark mode

Redefine only the tokens under `@media (prefers-color-scheme: dark)`. Never give a color its sole definition inside the dark block — a token missing from the light `:root` renders as nothing.

| Token | Dark value |
|-------|------------|
| `--canvas` | `#171614` |
| `--surface` | `#211f1c` |
| `--hairline` | `#3d3a35` |
| `--ink` | `#f2f0ec` |
| `--ink-muted` | `#a29d94` |
| `--accent` | `#f97316` |
| `--accent-soft` | `#2e1c10` |
| `--alert` | `#fb7185` |

## Type roles

Three roles, three faces, one job each. Every stack ends in a generic family so the file renders offline on a machine that has none of the named faces.

| Role | Used for | Stack |
|------|----------|-------|
| Display | the diagram title, and a pulled-out callout | `"Instrument Serif", "Iowan Old Style", Georgia, "Times New Roman", serif` |
| Label | node labels, edge labels, captions | `"Geist", "Inter", system-ui, -apple-system, "Segoe UI", sans-serif` |
| Mono | class names, table names, routes, commands | `"Geist Mono", ui-monospace, "SF Mono", "Cascadia Mono", Menlo, monospace` |

Sizes, all divisible by 4 except the two label sizes that need the odd step:

| Element | Size | Weight |
|---------|------|--------|
| Title | 24px | 400 (display face) |
| Node label | 14px | 500 |
| Node sublabel | 12px | 400, `--ink-muted` |
| Edge label | 11px | 500, `--ink-muted` |
| Caption | 12px | 400, `--ink-muted` |

Never set a label below 11px. Never letter-space a label to make it fit — shorten the label or widen the node.

## Spacing grid

**Every coordinate, size, gap, and offset is divisible by 4.** This is the rule that separates a laid-out diagram from a generated one, and it is checkable: divide every number in the SVG by 4 and none should leave a remainder.

| Gap | Value |
|-----|-------|
| Between sibling nodes | 32px |
| Between layers / rows | 64px |
| Node padding | 16px horizontal, 12px vertical |
| Canvas margin | 48px |
| Title band (reserved, top) | 64px |
| Caption band (reserved, bottom) | 48px |

## Strokes, radius, and depth

- Every stroke is `1` — nodes, edges, and frames alike. Weight never encodes importance; the accent does.
- `stroke-linecap="round"` and `stroke-linejoin="round"` on edges. Square joins read as a technical drawing, not an editorial one.
- Border radius is `8` for a node and `4` for a small chip. Never above `10`, never `0`.
- No `filter`, no `feDropShadow`, no gradient fill, no 3D transform. Hierarchy comes from spacing, size, and the accent.
- A dashed edge (`stroke-dasharray="4 4"`) means asynchronous or optional. Use it for that and nothing else.

## Node sizes

| Node | Width | Height |
|------|-------|--------|
| Standard box | 160 | 56 |
| Wide box (two-line label) | 200 | 72 |
| Chip / small state | 96 | 32 |
| Actor (sequence) | 128 | 40 |

A label that does not fit its box is shortened. Growing the box past the table above breaks the grid alignment of every sibling.

## Contrast floor

Every text/background pair meets **WCAG AA**: 4.5:1 for text at 14px and below, 3:1 at 24px. The pairs that need checking, since they are the ones that fail in practice:

- `--ink-muted` on `--surface` — the caption and edge-label pair.
- `--accent` on `--accent-soft` — accented node label on accented fill.
- `--hairline` against `--canvas` — not text, but an edge invisible on the canvas is a lost edge; keep it at 1.5:1 or better.

Check both color schemes. A pair that passes in light frequently fails in dark.

## The token block

```css
:root {
  --canvas: #fbfbfa;
  --surface: #ffffff;
  --hairline: #c8c4bc;
  --ink: #1c1b19;
  --ink-muted: #6b6862;
  --accent: #c2410c;
  --accent-soft: #fdf0e8;
  --alert: #9f1239;
  --font-display: "Instrument Serif", "Iowan Old Style", Georgia, "Times New Roman", serif;
  --font-label: "Geist", "Inter", system-ui, -apple-system, "Segoe UI", sans-serif;
  --font-mono: "Geist Mono", ui-monospace, "SF Mono", "Cascadia Mono", Menlo, monospace;
}

@media (prefers-color-scheme: dark) {
  :root {
    --canvas: #171614;
    --surface: #211f1c;
    --hairline: #3d3a35;
    --ink: #f2f0ec;
    --ink-muted: #a29d94;
    --accent: #f97316;
    --accent-soft: #2e1c10;
    --alert: #fb7185;
  }
}
```
