[One status sentence: the state the work is in and what happens next. Example: "Done. Ready for merge; nothing was merged."]

h2. Acceptance criteria

[One sentence carrying the verdict: "All N criteria are met." or "N of M met." or, when the assignment states no explicit criteria, the basis the state was judged on.]

* [Only a criterion that is NOT met, is partially met, or needs a human to confirm it. What is missing, and who must confirm it. Plain prose.]

h2. How to test

# [The concrete input — account, value, screen — followed by the outcome that must hold.]
# [Next step, same shape.]
# [Regression: what else the tester exercises, and what must stay unchanged.]

h2. What changed

* [One observable change in behaviour. Where a before exists: before -> after.]
* [Next. Three to five bullets in total.]

{embedded_blocks}

[PR #123|PR_URL] · [ISSUE-KEY|ISSUE_URL]

----

_This comment is generated automatically. It is written for the person who owns this ticket, not for a developer._

=== END OF COMMENT BODY — NOTHING BELOW THIS LINE IS EVER PUBLISHED ===

TEMPLATE GUIDANCE. The published comment ends at the line above. The intermediate
source format has no comment syntax, so this guidance cannot be hidden the way the GitHub
template hides its own in an HTML comment — the boundary is this marker line, and
it is structural, not decorative. Written as plain text on purpose: the Wiki
Markup quote macro this guidance used to sit inside is functional markup, so
guidance wrapped in one renders as a real, official-looking quotation if it ever
reaches the published body - which is exactly how meta-instructions leak
unnoticed. That macro's name is deliberately not written out anywhere in this
file: a single unpaired opening token would swallow everything after it.

Who reads this comment
  A product manager, not a developer. @rules/reports/general.md ("A JIRA comment
  is written for a non-technical reader") is binding on every line above the
  marker: it lists the content that never appears here, its two exceptions, and
  the 3 000-character cap. Read it before filling this template in. The
  technical evidence a reviewer or a merge gate needs is not lost — it lives on
  the GitHub pull-request comment, which is where @skills/merge-github-pr reads
  it.

Section order is binding
  Status sentence, then Acceptance criteria, then How to test, then What
  changed, then the closing links line. The verdict comes first because it is
  the one thing the reader opens the ticket for. This order is JIRA's own; the
  GitHub and Bugsnag templates keep their What changed / How to test shape.

Status sentence
  One sentence, above the first heading. It states the state of the work and
  what happens next — whether anything was merged, deployed, or is waiting on a
  person. Never a heading of its own.

Acceptance criteria
  One verdict sentence, then a bullet only for a criterion that is unmet,
  partially met, or awaiting a human's confirmation. Satisfied criteria are
  never enumerated one by one — the verdict is the whole report for them. When
  the assignment states no explicit criteria, say so and name the basis judged
  instead (the described expected behaviour, the reporter's example, the
  reproduction steps), so "no criteria" never reads as "nobody checked".
  This section is the only route the assignment verdict takes into this comment,
  and a CR run with a linked tracker always carries it — met, not met, or no
  criteria stated (@rules/code-review/general.md, Two-Part CR Output, "The
  tracker comment carries the same verdict — in all three cases"). The
  @skills/assignment-compliance-check/SKILL.md result is what fills it; on JIRA
  that result is rendered into this section rather than appended as an embedded
  block.

How to test
  Numbered steps a non-developer follows. Each step names a concrete input —
  the account, the value, the screen — and then the outcome that must hold. The
  last step is the regression: what else the tester exercises, and what must
  stay unchanged. When the change is reachable only behind a test parameter, the
  first step enables it, naming the exact toggle and value: admin switch label
  _New pricing preview_, ENV {{BETA_PRICING=1}}, query {{?preview=1}}, feature
  key {{feature.new_pricing}}. A toggle name and a value the tester types are
  strings the reader sees, so they are quoted verbatim.

What changed
  Three to five bullets, observable behaviour only, in before -> after form
  where a before exists. It states impact, never mechanism — a bullet that
  explains how the code now works belongs on the pull request instead. This
  section replaces the Problem / Cause / Result fields the JIRA template used to
  open with: Cause asked for a mechanism, and a mechanism is what invited method
  names into a product manager's ticket.

Headings and field labels
  Translate them into the assignment language per @rules/reports/general.md — a
  Czech assignment renders "h2. Akceptační kritéria", "h2. Jak otestovat",
  "h2. Co se změnilo". Never mix an English heading with assignment-language
  prose.

Length
  3 000 characters, counted over the published body. When the comment overflows,
  shorten What changed — never How to test, whose steps a tester has to follow
  literally. @rules/reports/general.md owns this cap, and
  @skills/pr-summary/SKILL.md *Length follows the facts* names JIRA as the
  one target it applies to.

{embedded_blocks}
  Render this slot only when the calling CR wrapper passes the
  "h2. Clarifying questions" block — the open questions the reviewer needs
  answered before the work can be accepted. The block already uses the
  intermediate format; append it verbatim. When no block is passed,
  omit this slot entirely — including the surrounding blank lines — so the
  comment runs straight from What changed to the closing links line.
  The Assignment Compliance block does not travel through this slot on JIRA. Its
  verdict is the Acceptance criteria section above, which is why that section is
  first and no longer optional.

  Do not add an Authors line, an Available behind line, a Summary of changes
  section, severity counts, file paths, line numbers, or code snippets — none of
  those belongs on any target this skill publishes to.

Closing links line
  One line, the pull request and the source tracker item, separated by " · ", in
  intermediate link form ([label|url]). Render whichever of the two links exists;
  omit the line when neither does. It sits above the footer separator. This is
  the one link the comment carries, and it is navigation rather than a technical
  note.

The canonical statement of every rule above lives in
@skills/pr-summary/SKILL.md. This block restates the slot mechanics for whoever
is filling the template in; the skill is the source of truth if the two ever
disagree.
