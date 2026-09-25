# State coverage — find every state the main view hides, and prove each one is covered

Referenced from `skills/page-redesign/SKILL.md` steps 2 and 7.

## Contents

- [Why this is the first step](#why-this-is-the-first-step)
- [Enumerating the states](#enumerating-the-states)
- [The state map](#the-state-map)
- [Proving coverage](#proving-coverage)

## Why this is the first step

A reviewer can check the main view against the screenshot they already have. They cannot check anything that is closed, collapsed, or behind a tab — and that is exactly where a redesign silently breaks a page, because a hidden region is where a design decision is easiest to skip.

So the states are enumerated **before** the layout work starts. A state discovered while writing the previews is a state the redesign was never actually designed for.

## Enumerating the states

Read the view source and walk each source below. Each one hides content that the main screenshot does not show.

- **Disclosure** — accordions, collapsible panels, expandable table rows, "show more" toggles, and anything rendered with a collapsed default.
- **Navigation inside the page** — tabs, steps of a wizard, inner pagination, switchable views (list and grid, table and cards).
- **Overlays** — modals, drawers, popovers, dropdown menus, date pickers, autocomplete panels, context menus, tooltips that carry information rather than decoration.
- **Interaction states of a control** — focus, hover, active, disabled, busy, and the state after a control has been used.
- **Data states** — empty, one item, the realistic many, and the extreme (a very long name, a large number, a full table). The long and empty cases are what break a layout.
- **Outcome states** — validation errors per field and per form, a failed save, a successful save, and a partial result.
- **Async states** — loading, saving, and a slow or failed background action.
- **Authorisation states** — every role or permission that changes what is rendered, including the read-only variant.
- **Viewport states** — each viewport the application is actually used at. Ask which devices the operators use; a shop-floor tablet is not an assumption to skip.

Two states collapse into one only when the region renders identically in both. Say so in the map rather than dropping one silently.

## The state map

Record the map in the proposal as a table, one row per state:

| State | Trigger | Region affected | Hidden in main view | Mockup | Preview |
| --- | --- | --- | --- | --- | --- |
| Main view | page load | whole content region | no | `main.html` | `main.png` |
| Items expanded | click on the order row | items table | yes | `items-expanded.html` | `items-expanded.png` |
| Assign worker | `Přiřadit` button | modal over the content region | yes | `assign-worker.html` | `assign-worker.png` |

`Hidden in main view` is the column that matters: every `yes` row is a state whose design nobody can review without the preview.

## Proving coverage

- **Every row of the map has a mockup and a rendered preview.** No exceptions, and no "same as above".
- **A state that is deliberately left out of scope stays in the map**, with the reason in place of the mockup — so the reader sees the decision instead of a gap.
- **A preview that could not be rendered is reported as not rendered**, with the reason. Never describe a preview that does not exist, and never present a mockup as a rendered preview.
- **The summary names the counts**: states in the map, mockups written, previews rendered. Three equal numbers, or an explanation of why they differ.
