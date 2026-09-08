# Self-Check

Run every item before handoff. A failing item is fixed, never shipped with a caveat. Each item names how to check it, because "looks fine" is not a check.

## Contents
- [Truth](#truth)
- [Density](#density)
- [Geometry](#geometry)
- [Type and contrast](#type-and-contrast)
- [Self-containment](#self-containment)
- [Motion](#motion)
- [Accessibility](#accessibility)

## Truth

1. **Every node is anchored.** Each node maps to a `file:line`, a table in a migration, or a line of the assignment. List the anchors in the handoff. A node you cannot anchor is deleted.
2. **Every edge is real.** The call, the relation, or the transition the edge claims exists in the code. An edge drawn because the layout looked empty is a lie the reader cannot detect.
3. **Labels name real symbols.** `OrderPaymentAction`, not `Payment Service`. `orders.customer_id`, not `customer key`.
4. **The caption states the takeaway**, not the contents. "Payment confirmation crosses the queue boundary twice" beats "Payment flow".

## Density

5. At most **12 nodes**. Count them.
6. At most **2 focal elements** — accented nodes, or nodes at a larger size.
7. At most **one accent hue** carries meaning. `--alert` is allowed only on a genuine failure path.
8. Deleting the diagram costs the reader understanding. When it costs only decoration, delete it instead of shipping it.

## Geometry

9. **Every number in the SVG is divisible by 4** — `x`, `y`, `width`, `height`, `cx`, `cy`, `r`, and every path coordinate. Scan the markup and divide; a remainder is a defect.
10. **No two text elements overlap.** Compute the bounding box of each label from its font size and character count rather than trusting the rendered view at one zoom level.
11. **No label is struck through by an edge.** An edge label carries a background rectangle in `--canvas` behind it, sized 4px larger than the text on each side.
12. **Edge crossings are minimized.** More than two crossings means the layout should be reordered, not the crossings styled around.
13. **Nothing is clipped by the viewBox.** Every element sits at least 48px inside the canvas edge, the title band and caption band excluded.
14. **Sibling nodes share an axis.** Nodes on one row share a `y`; nodes in one column share an `x`. A 2px drift is visible and reads as carelessness.

## Type and contrast

15. **Every text/background pair meets WCAG AA** — 4.5:1 at 14px and below, 3:1 at 24px. Check `--ink-muted` on `--surface` and `--accent` on `--accent-soft` explicitly; those are the pairs that fail.
16. **Check both color schemes.** Toggle the OS to dark and re-read the diagram. A pair that passes in light frequently fails in dark.
17. **No label below 11px**, and no label letter-spaced to fit.
18. **Every `<text>` carries an explicit `text-anchor` and `dominant-baseline`.** Renderer defaults differ, so a label centered in one browser drifts in another.
19. **The three type roles are used for their own job** — display for the title, sans for labels, mono for identifiers — and every stack ends in a generic family.

## Self-containment

20. **No external request.** Grep the file for `http://`, `https://`, `@import`, `<link`, `<script src`, and `url(` — every hit is a data URI, the mandatory SVG namespace `http://www.w3.org/2000/svg`, or a defect. The namespace is an identifier the renderer never resolves over the network, so it is the one expected hit.
21. **The file renders with the network disabled.** Open it offline and confirm.
22. **The file renders with JavaScript disabled**, complete and readable. Motion is an enhancement, never the content.
23. **No Mermaid, no draw.io XML, no client-side renderer.** A markup language that needs a library to become a picture is an external dependency wearing a self-contained costume.

## Motion

Skip this block when the diagram is static, which is the default.

24. **Every animated element renders in its final state when animation is off.** Never animate `opacity` from `0` without a fallback that ends at `1`.
25. **`@media (prefers-reduced-motion: reduce)`** shows the complete final frame and hides the controls.
26. **The controls are keyboard-reachable** and carry a visible focus ring.

## Accessibility

27. **The root `<svg>` carries a `<title>` and a `<desc>`**, and `role="img"` with `aria-labelledby` pointing at their ids.
28. **The `<desc>` describes the structure in prose** — an assistive-technology reader gets the diagram's content from it, not from the node labels.
29. **Color is never the only channel.** A meaning carried by the accent is also carried by position, a label, or a border treatment.
