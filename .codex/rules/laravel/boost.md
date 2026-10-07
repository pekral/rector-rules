---
description: Laravel Boost — CLAUDE.md and AGENTS.md are generated from .ai/guidelines; edit the sources, regenerate in the same commit, and keep the output under the loader limit. Apply only when laravel/boost is installed.
paths:
  - ".ai/**"
  - "CLAUDE.md"
  - "AGENTS.md"
  - "config/boost.php"
  - "boost.json"
  - "composer.json"
---

## Scope
- Apply these rules only when the project installs `laravel/boost`.

## Generated Files — Edit the Sources, Never the Output
- **The guideline file is generated.** Boost composes it from the project's `.ai/guidelines/*.md` files plus the guideline blocks it extracts from installed packages. Edit the matching `.ai/guidelines/*.md` file. A hand edit to the output is overwritten by the next `boost:update`.
- **Know which file Boost writes for Claude Code.** It writes to `boost.agents.claude_code.guidelines_path` in `config/boost.php` — `AGENTS.md` by default. Claude Code loads a root `CLAUDE.md` in preference to `AGENTS.md`, so a committed `CLAUDE.md` that Boost no longer writes shadows the generated file and goes stale. Keep exactly one generated copy: either point `guidelines_path` at `CLAUDE.md`, or keep `CLAUDE.md` as the one-line import `@AGENTS.md`.
- **Regenerate in the same commit as the source change.** Run `php -d memory_limit=2G artisan boost:update --no-interaction`, or the project's own command. The default 128 MB limit can run out inside Boost's guideline discovery. A guideline commit without the regenerated output leaves the tracked file describing the previous rules.
- **Resolve a conflict in a generated file by regenerating, never by hand-merging.** Take either side, regenerate, and commit the result. The sources are what have to merge.
- **A dependency change can change the output.** Installing, upgrading, or removing a package that ships Boost guidelines changes the packaged blocks. Regenerate in the commit that changes `composer.json` or `composer.lock`.
- **`.ai/rules/boost/**` and `.ai/rules/index.md` are generated as well.** Boost rewrites them on every `boost:update`, so never hand-edit them. A rule file under `.ai/rules/` outside `boost/` — the output of Boost's `record-rule` tool — is hand-maintained.

## The 150 000-Character Limit
- **Claude Code refuses an instruction file over 150 000 characters and then loads none of it.** Every guideline in the file goes inactive at once, with no error in the session. The limit applies to the generated guideline file, whichever name it has.
- **Keep headroom with `@scoped([...])` blocks.** With `rules.scoped_guidelines` enabled in `config/boost.php`, Boost extracts each scoped block into `.ai/rules/boost/` and registers it in `.ai/rules/index.md`. The content moves from always-loaded to loaded-by-path; nothing is dropped.
- **Check the size after every guideline change** (`wc -c` on the generated file). Aim for headroom rather than the limit, because a packaged block can grow on the next `composer update`.
- **Scope by path, never by size.** A guideline is a candidate for `@scoped` only when an agent that never touches the covered paths does not need it. Cross-cutting guidance stays inline whatever it costs.

## Project Skills
- **A project skill lives in `.ai/skills/<name>/SKILL.md`** with `name` and `description` frontmatter. Boost links it into `.claude/skills/<name>` on every `boost:update`. Commit the source, the generated link, and `boost.json` together.
- **A project skill never shares a name with a skill a package installs.** A package installer writes through the link, so a same-named project skill is overwritten on the next update.

## Packaged Blocks Describe a Default Laravel Application
- **Boost's packaged blocks are written for a default Laravel application.** Where one does not match the project — the deployment target, the local URL, a command that does not exist — record the override in a project guideline. The project guideline wins (`@rules/general/general.md` *Project instructions take precedence*).
- **Keep that override file true.** When a package it names changes major version, or its block stops saying what the override quotes, correct or delete the override in the same change. A stale override is worse than none, because it is written to be trusted over the block it contradicts.
- **Pin `'enforce_tests' => true` in `config/boost.php`.** Boost decides whether to emit its test-enforcement block by counting tests in a child process that runs with the default memory limit. On a large suite the child can die part-way, Boost reads a truncated count, and the block appears and disappears between regenerations.

## Code Review Application
- Mark as **Moderate**:
  - a diff that hand-edits a generated file (the guideline file, `.ai/rules/boost/**`, `.ai/rules/index.md`) with no matching source change;
  - a committed `CLAUDE.md` that is neither the configured `guidelines_path` nor a one-line `@AGENTS.md` import — a second, stale copy of the guidelines;
  - a diff that changes `.ai/guidelines/**` or a Boost-shipping dependency without the regenerated output;
  - a project skill written into `.claude/skills/` instead of `.ai/skills/`.
