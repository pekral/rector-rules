What changed

Problem: [Who hit it, on what, and what they saw instead. Name the scale when it is known — how many attempts, over how long, how many accounts. Terse, but every number stays.]

Cause: [One mechanism, stated so a non-developer follows it. A missing or partially met acceptance criterion is named here in prose — never as a verdict field.]

Result: [What the cause actually cost: the number, the runtime, the failure it produced. When the failure was silent, say why it was silent.]

What I fixed:

- [One change the reader can observe. State the new behaviour and, where a number exists, the before-and-after.]
- [Next observable change.]

Side benefit: [Optional — an improvement the fix produces that the assignment never asked for. Omit this field entirely when there is none.]

Filed separately: [Optional — a genuinely unrelated defect found during the work and filed on its own ticket. Name the ticket and state that it is linked. Omit this field entirely when there is none.]

How to test

1. [The scenario's starting point, with concrete inputs — account, URL, entity name, value typed in. When the change is reachable only behind a test parameter, this step enables it, naming the exact toggle and value. Then the must-hold outcome: what the tester must see for the step to pass.]
2. [Next scenario step — concrete input, then its must-hold outcome. Say so in the step when this is the important one.]
3. [Regression: the neighbouring flows the tester exercises to confirm nothing else moved, and the outcome that must stay unchanged.]

{embedded_blocks}

PR #123: PR_URL · ISSUE-KEY: ISSUE_URL

=== END OF COMMENT BODY — NOTHING BELOW THIS LINE IS EVER PUBLISHED ===

TEMPLATE GUIDANCE. The published comment ends at the line above. Bugsnag renders
a comment as plain text and has no comment syntax, so this guidance cannot be
hidden the way the GitHub template hides its own in an HTML comment — the
boundary is this marker line, and it is structural, not decorative.

No markup at all
  Bugsnag shows every markup character literally, so this template carries none:
  no hash headings, no double-asterisk bold, no backtick code, no bracket links.
  Section names sit on their own line, field labels end with a colon, list items
  open with a plain "-", and every URL is written out in full. There is no
  per-actor marker either — the API token identifies the author.

Headings and field labels
  Translate them into the assignment language per @rules/reports/general.md — a
  Czech assignment renders "Co se změnilo", "Problém:", "Příčina:", "Výsledek:",
  "Co jsem opravil:", "Vedlejší přínos:", "Na jiný ticket:", "Jak otestovat".
  Never mix an English heading with assignment-language prose.

Length
  There is no word budget. The report is as long as the facts it carries and no
  longer — see @skills/pr-summary/SKILL.md (Length follows the facts).

{embedded_blocks}
  Render this slot only when the calling CR wrapper passes one or more blocks —
  the Clarifying questions block and/or the Assignment Compliance block returned
  by @skills/assignment-compliance-check/SKILL.md. Each block is already
  converted to plain text by the wrapper; append it verbatim, in the order
  received, separated by a single blank line. When no blocks are passed,
  omit this slot entirely — including the surrounding blank lines — so the
  comment runs straight from the test steps to the closing links line; that is the
  shape of a non-CR invocation, never of a clean CR result. This is the only route
  the assignment verdict takes into this comment, and
  a CR run with a linked tracker always passes it — met, not met, or no criteria
  stated (@rules/code-review/general.md, Two-Part CR Output,
  "The tracker comment carries the same verdict — in all three cases"). The template itself still renders no
  verdict, no banner, and no "satisfies the assignment" line of its own; it
  appends the passed block verbatim.

  Do not add an Authors line, an Available behind line, a Summary of changes
  section, severity counts, file paths, line numbers, or code snippets — none of
  those belongs on any target this skill publishes to.

Closing links line
  One line, the pull request and the source tracker item, separated by " · ",
  each written as a label, a colon, and the full URL. Render whichever of the two
  links exists; omit the line when neither does.

The canonical statement of every rule above lives in
@skills/pr-summary/SKILL.md. This block restates the slot mechanics for whoever
is filling the template in; the skill is the source of truth if the two ever
disagree.
