---
description: Simplified technical writing — every agent response and published report follows the ASD-STE100 style principles, in whatever language the assignment is written in.
---

## Simplified Technical Writing (ASD-STE100)

Every response an agent produces — a reply to the user, a handoff, a pull request description, a commit body, a code-review finding, a tracker comment — **is written in simplified technical style**, modelled on **ASD-STE100 (Simplified Technical English)**. The reader of an agent's output is deciding something: whether to merge, whether the bug is understood, what to do next. Prose that hides the decision behind long sentences, passive constructions, or synonym variation costs the reader a re-read, and a re-read is the failure this rule prevents.

### The rules

- **One idea per sentence.** A sentence states one fact, one instruction, or one consequence. When a sentence carries a second idea behind *and*, *but*, *while*, or a semicolon, split it.
- **Short sentences.** Keep an instruction to roughly **20 words** and a descriptive sentence to roughly **25**. These are working limits, not a character count to game — a 30-word sentence that cannot be split without losing meaning stays.
- **Active voice, named actor.** Write *`hephaestus` opens the pull request*, never *the pull request is opened*. The passive hides who acts, and in an agent pipeline the actor is the load-bearing part.
- **Present tense for what is true; past tense only for what happened.** A rule, an invariant, and a description of current behaviour are present tense. A report of a completed action is past tense.
- **One term per concept, always the same term.** Pick one word for each thing and repeat it, however repetitive it reads. *Brief*, *task brief*, *assignment*, and *zadání* used for one artifact in one report force the reader to decide whether they are four things. Synonym variation is a style virtue in prose and a defect in technical writing.
- **No telegraphic compression.** Simplifying means removing ideas per sentence, never removing words a sentence needs. Keep articles, prepositions, and relative pronouns. *Run gate after fix* is not simpler than *Run the gate after the fix*, it is only shorter.
- **Short paragraphs.** Roughly **six sentences** maximum. A longer block of reasoning becomes a list, a table, or several paragraphs.
- **Sequences are numbered lists.** Two or more steps that happen in order are a numbered list, never a sentence chaining them with *then*.
- **No marketing register.** Drop superlatives, intensifiers, and self-congratulation — *comprehensive*, *robust*, *seamlessly*, *significantly improved*, *carefully verified*. State what was done and what it produces. A verdict is a fact (*build green, 618 tests*), never an adjective (*excellent coverage*).
- **No hedging where a fact is available.** Write *the test fails on line 42*, not *there may possibly be an issue around line 42*. When the fact is genuinely unknown, say what is unknown and what would settle it.
- **Nested conditions get unnested.** A sentence carrying two or more conditions becomes a list of cases, one case per line.

### Language neutrality (this rule never forces English)

ASD-STE100 is written for English, but everything above is a **structural** property of the sentence, not a property of English. The **principles apply to whatever language the output is in** — a Czech report follows the same one-idea-per-sentence, active-voice, one-term-per-concept discipline.

Two parts of the published standard are explicitly **not** imported: its **approved-word dictionary** and its **English-only word forms**. An agent writing in Czech does not restrict itself to an English vocabulary list, and does not calque English syntax to imitate the standard. It writes plain, correct Czech that obeys the structural rules above.

Code identifiers, file paths, command names, and label strings stay **verbatim** in every language — they are names, not prose, and translating or inflecting them breaks the reader's ability to grep for them.

> **Scope boundary — style, not language choice.** This rule owns **how** a sentence is written. `@rules/reports/general.md` owns **which language** a tracker-published report is written in (the assignment's language, never mixed) and the narrow English exception for technical CR findings on a GitHub PR. The two never overlap and never override each other: a report first takes its language from `@rules/reports/general.md`, then obeys this rule inside that language. Raise one finding per violation — a Czech report written in bloated prose is a violation of this rule only, and an English report dropped into a Czech tracker comment is a violation of `@rules/reports/general.md` only.
