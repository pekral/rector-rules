# Redesign — {page name}

> Fill every section. Write in the language of the assignment (`@rules/reports/general.md`); keep every on-screen label verbatim in the language the application uses. Delete a section only when it does not apply, and say why in *Assumptions and gaps*.

**Page:** {route} · {view file} · {component or controller class}
**Viewport:** {width × height the application is actually used at}
**Main layout shell:** unchanged · {or: changed on the caller's explicit order, quoted below}

## What does not work today

One line per problem, each one observed on the real page and tied to the operator's task.

- {problem} — {what it costs the operator}

## The operator's task

The sequence the redesign is built around.

1. {step}
2. {step}

{Where the current layout interrupts this sequence.}

## The redesigned content region

{One paragraph on the new structure: the regions top to bottom, the primary action, and what drives the order.}

![Main view](previews/main.png)

## State map

| State | Trigger | Region affected | Hidden in main view | Mockup | Preview |
| --- | --- | --- | --- | --- | --- |
| Main view | page load | whole content region | no | `mockups/main.html` | `previews/main.png` |
| {state} | {trigger} | {region} | yes | `mockups/{state}.html` | `previews/{state}.png` |

**Coverage:** {n} states · {n} mockups · {n} previews rendered.

{One subsection per hidden state, each with its preview image and one paragraph on what changed and why.}

## Element specification

One row per element. This is what the developer builds from, so no cell is left to interpretation.

| # | Element | Label (verbatim) | Type / component | Data source | States | Behaviour | Position |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | {name} | `{text}` | {existing component to reuse} | {field, relation, or computed value} | {enabled, disabled, empty, error} | {what happens on use} | {region, row, column span} |

**New components:** {none · or the component, why no existing one fits, and what it is composed of.}

## Density and extensibility

- **Fill:** {how the region uses the available width and height, and what was removed to achieve it.}
- **Guards:** {the grouping, target sizes, and line lengths that keep it readable.}
- **Growth slots:** {per region — the slot a new field, column, or action lands in, and what it can absorb without a re-layout.}

## Do not change

- The main layout shell: {header, sidebar, navigation, footer} stay exactly as they are.
- {behaviour, contract, or element the redesign deliberately leaves alone, and why}

## Assumptions and gaps

- {material that was missing, the assumption made in its place, and what would confirm it}
- {state left out of scope, with the reason}
