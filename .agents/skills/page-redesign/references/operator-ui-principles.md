# Designing for an operator who is not an IT person

Referenced from `skills/page-redesign/SKILL.md` steps 3, 4, and 5.

## Contents

- [Who the user is](#who-the-user-is)
- [Layout principles](#layout-principles)
- [Labels and words](#labels-and-words)
- [Density and extensibility](#density-and-extensibility)
- [What this is not](#what-this-is-not)

## Who the user is

The person using this page is not a developer, an analyst, or a power user. They are a worker — in a warehouse, a workshop, or on a shop floor — and the software is a tool they need in order to finish their actual job: processing orders, as fast as the work allows.

Four consequences follow, and every rule below comes from one of them:

- **They did not choose this software and they will not explore it.** A feature they cannot see does not exist for them. Discoverability is not a nicety here; it is the whole interface.
- **They are interrupted constantly.** A page has to be re-readable in two seconds after the operator looks away, so the current state must be visible rather than remembered.
- **They repeat the same task all day.** A saving of two clicks per order is not a micro-optimisation — it is the point of the redesign.
- **They are often not at a desk.** Standing, gloves, a touch screen, poor lighting, a scanner instead of a keyboard. Small targets and low contrast fail in exactly those conditions.

## Layout principles

- **One primary action per screen, and it is obvious.** The thing the operator is here to do is the largest, highest-contrast control on the page, positioned where the task sequence ends. Everything else is visibly secondary.
- **Order the page by the task, not by the data model.** The sequence the operator actually follows drives the order of the regions. A field group that exists because the database has a table is not a reason to put it first.
- **Put the decision and its inputs on the same screen.** When an operator must choose, everything the choice depends on is visible at that moment. A decision that needs a scroll, a tab switch, or an opened section is where mistakes come from.
- **Never hide a fact behind a closed section.** A collapsed region's header carries the summary that makes opening it unnecessary — a count, a status, a total, a warning. Collapse detail, never meaning.
- **Group what is used together, separate what is not.** Grouping is done with position and whitespace between groups, not with borders around everything.
- **Keep the eye on one path.** One primary scan direction per region. A layout that makes the eye jump left, right, and back again is slower even when everything fits.
- **Large targets, high contrast.** Buttons are big enough for a gloved finger, and text is readable under bad light on a cheap screen.
- **Minimise keystrokes and clicks per order.** Sensible defaults, the cursor already in the first field, keyboard and scanner entry where the work is repetitive, no confirmation step that confirms nothing.
- **Every state says what it is.** Empty, loading, error, and no-permission states each say what happened and what to do next — never a blank region and never a technical message.

## Labels and words

- **Use the operator's vocabulary.** The words on screen are the words used on the floor, not the names of columns, classes, or statuses in the code.
- **Say what the control does.** A button is labelled with the action it performs (`Vyskladnit`), never with a generic verb (`Odeslat`) or an abbreviation only the author understands.
- **An error says what to do.** Name the field, say what is wrong, and say what a correct value looks like. Never expose an exception, a field name from the schema, or a stack trace.
- **No jargon, no icon-only controls.** An icon may accompany a label; it never replaces one, because an icon's meaning is learned and this user has not been trained.

## Density and extensibility

The page is a tool, and empty space that carries no grouping meaning is screen the operator pays for by scrolling. Fill the available area — and stop before it becomes a wall.

**Fill it:**

- Use the full width of the content region. A form in a narrow column down the middle of a wide screen wastes most of the display.
- Put related short fields on one row rather than one per line.
- Show the rows, items, or lines the operator needs to see without scrolling, at the real viewport the application runs at.

**Do not overdo it:**

- Keep the whitespace **between groups**; remove only the space that separates nothing. Grouping is what makes a dense page readable.
- Never shrink a control below a comfortable touch target, and never shrink body text to fit one more column.
- Keep a readable line length for anything the operator has to read as a sentence.
- A region that cannot be scanned in one pass is too dense, whatever the fill ratio says.

**Extensible by structure, not by blank space:**

- Every region is a grid, a list, or a table that accepts one more field, column, or action **in an existing slot**. Growth must not force a re-layout.
- Reserving an empty block for a future feature is the failure this rule exists to prevent — it wastes space now and is rarely the shape the future feature needs.
- Where a region is expected to grow, the proposal names the slot and what it can absorb.

## What this is not

This file owns **how the page serves the operator**. It does not own the visual direction, the design tokens, or the component implementation — `skills/page-redesign/SKILL.md` *Scope* names the skill that owns each. When a principle here and a project's existing design system disagree, the design system wins and the proposal records the conflict.
