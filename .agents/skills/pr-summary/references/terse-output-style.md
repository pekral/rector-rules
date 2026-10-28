# Terse output style (issue #51)

Loaded by `@skills/pr-summary/SKILL.md` *Constraints*. Section names in italics refer to that skill.

Every sentence this skill authors into the rendered comment — the `What changed` fields, the `Review findings` bullets, and the `How to test` steps — carries a fact and nothing else.

- **Drop** filler words (just / really / basically / actually / simply and their assignment-language equivalents), pleasantries, hedging, and self-congratulation.
- **Keep** all technical substance — only fluff goes. Prefer short synonyms ("fix", not "implement a solution for").
- **Sentence shape is `@rules/writing/general.md`'s, not this section's.** Terseness removes ideas per sentence and removes filler; it never removes a word the sentence needs. Keep articles, prepositions, and relative pronouns — telegraphic fragments are not terse, only shorter.
- **Abbreviations:** standard well-known acronyms are fine (DB, API, HTTP); never invent new abbreviations (cfg / impl / req) — they save nothing and cost clarity.
- **No decoration:** no decorative tables, no decorative emoji, no causal arrows (→) in authored prose.
- **Verbatim always:** technical terms, code identifiers, toggle names, values, URLs, and commands.
- **Compress the style, never the language** — the assignment-language rule (`@rules/reports/general.md`) is unchanged.
- **Never name or announce the style** in the rendered comment — no "terse mode". The JIRA template's footer, which states that the comment is generated, is traceability rather than a style announcement, and stays.
- **Auto-clarity carve-outs** — write normal, fully explicit sentences for: the `Cause` and `Result` fields (a reader who misreads the mechanism draws the wrong conclusion), security warnings and destructive or irreversible actions inside `How to test` steps, and every must-hold outcome. Never drop a word whose absence changes or blurs a tester's action.
- **Never compressed at all:** the `{embedded_blocks}` slot (rendered verbatim per *Embedded blocks* in `@skills/pr-summary/SKILL.md`), pre-authored test steps passed by the caller (used as passed), the closing links line, and the templates' fixed footers.
