# Diagram Types

Every type carries the reader question it answers, its layout grammar, and its density ceiling. Pick by the question, never by what the data happens to look like.

## Contents
- [Structure](#structure) — architecture, layers, nested, tree, org chart
- [Behavior](#behavior) — flowchart, sequence, state machine, swimlane, data flow
- [Relation](#relation) — ER, Venn, quadrant
- [Change over time](#change-over-time) — timeline, Gantt
- [Quantity](#quantity) — bar, treemap

Density ceilings below are hard. Over the ceiling, split into two diagrams or raise the abstraction level of the nodes.

## Structure

### architecture
**Question:** what talks to what?
**Grammar:** boxes laid out left to right in the direction the calls travel; the entry point on the left, the store on the right. Group co-deployed boxes in a frame with a 1px dashed border and a 11px label at its top-left. Edges are orthogonal and carry the protocol or the payload as a label.
**Ceiling:** 12 boxes, 3 frames.
**Trap:** drawing the deployment topology and the call graph in one picture. Pick one.

### layers
**Question:** what sits on top of what?
**Grammar:** full-width horizontal bands stacked bottom-up, 64px apart, each band 56px tall with its name left-aligned inside. A dependency that skips a layer is the one thing worth drawing as an explicit edge — that is usually the point of the diagram.
**Ceiling:** 6 bands.

### nested
**Question:** what is contained in what?
**Grammar:** concentric rounded rectangles, 32px inset per level, label at the top-left of each. Reserve the innermost shape for the thing the reader is meant to find.
**Ceiling:** 4 levels.

### tree
**Question:** how does this hierarchy branch?
**Grammar:** root at the top, children below on fixed rows 64px apart, orthogonal connectors that leave the parent at bottom-center and enter the child at top-center. Siblings share a row and a vertical center line.
**Ceiling:** 4 levels, 12 nodes.

### org chart
**Question:** who reports to whom?
**Grammar:** the tree grammar, with a role sublabel under every name. A dotted connector means a dotted-line report and nothing else.
**Ceiling:** 12 nodes.

## Behavior

### flowchart
**Question:** what happens next, and where does it branch?
**Grammar:** top to bottom. A decision is a 96×96 diamond with its two exits labeled on the edge, `yes` leaving right and `no` leaving bottom — keep that convention across every flowchart or the reader re-learns it each time. Terminals are fully rounded chips.
**Ceiling:** 12 nodes, 4 decisions.
**Trap:** a flowchart with no decision is a numbered list. Do not draw it.

### sequence
**Question:** in what order do these participants exchange messages?
**Grammar:** actors as 128×40 boxes on a single top row, a 1px vertical lifeline dropping from each center, messages as horizontal arrows between lifelines ordered top to bottom on a 32px step. A synchronous call gets a solid arrow with a filled head; a return gets a dashed arrow with an open head. An activation is a 8px-wide bar on the lifeline. A conditional block is a frame around the messages with the condition in its top-left corner.
**Ceiling:** 6 actors, 16 messages.
**Trap:** more than 6 lifelines and the arrows are longer than the labels. Collapse the participants that always act together.

### state machine
**Question:** what states exist and what moves between them?
**Grammar:** states as 96×32 chips, transitions as labeled curved edges, the label naming the **event**, not the outcome. The initial state gets a filled 8px dot with an edge into it; a terminal state gets a double border. Lay states out so the happy path reads left to right and the error transitions drop below it.
**Ceiling:** 8 states, 12 transitions.

### swimlane
**Question:** who owns which step?
**Grammar:** one horizontal lane per actor, lanes separated by a hairline, the actor name in a 128px left gutter. Steps sit in their owner's lane and progress left to right. A handoff is a vertical edge crossing a lane boundary — those crossings are the content of the diagram, so keep them few and make them visible.
**Ceiling:** 5 lanes, 12 steps.

### data flow
**Question:** where does this data go, and what transforms it?
**Grammar:** sources on the left, sinks on the right, transforms as boxes between them. An edge label names the payload and its shape (`OrderData[]`), never just an arrow. A store is a box with a doubled top border.
**Ceiling:** 12 nodes.

## Relation

### ER
**Question:** how do these tables relate?
**Grammar:** each entity a box with the table name in mono in a 32px header band and its key columns listed below, 20px per row — only the keys and the columns the relation uses, never every column. Crow's-foot notation at the relation ends. Place related entities adjacent; a long edge across the canvas means the layout is wrong.
**Ceiling:** 7 entities, 6 columns each.

### Venn
**Question:** what do these sets share?
**Grammar:** 2 or 3 circles at 30% opacity fill, labels outside the circles, the intersection label inside. Three circles is the maximum a reader can decode.
**Ceiling:** 3 sets.

### quadrant
**Question:** how do these options score on two axes?
**Grammar:** a square plot, both axes labeled at their ends with the direction the value grows, quadrant names in the corners at 11px muted, items as 8px dots with labels placed to avoid overlap. Position must be defensible — a quadrant chart with made-up coordinates is the fastest way to lose a reader's trust.
**Ceiling:** 12 items.

## Change over time

### timeline
**Question:** what happened when?
**Grammar:** one horizontal axis, events as 8px dots on it with alternating labels above and below to avoid collision, dates in mono at 11px. Space events by real elapsed time when the intervals matter, evenly when only the order matters — and say which in the caption.
**Ceiling:** 10 events.

### Gantt
**Question:** what runs when, and what overlaps?
**Grammar:** one row per task, 24px tall on a 32px pitch, bars positioned against a shared top axis with gridlines at the period boundaries. A dependency is a right-angle connector from the end of one bar to the start of the next.
**Ceiling:** 10 tasks.

## Quantity

### bar
**Question:** how do these values compare?
**Grammar:** horizontal bars sorted by value descending, labels left-aligned in a fixed gutter, values at the bar end in mono. The axis starts at zero, always. One accented bar marks the value the reader should notice.
**Ceiling:** 10 bars.

### treemap
**Question:** how does this total break down proportionally?
**Grammar:** rectangles whose **area** is proportional to value — verify the arithmetic, since an area that lies is worse than no chart. Two levels maximum, the outer level labeled inside its top-left corner.
**Ceiling:** 12 leaves, 2 levels.
