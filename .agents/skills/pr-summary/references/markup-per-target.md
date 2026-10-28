# Markup per target

Loaded by `@skills/pr-summary/SKILL.md` *Constraints* before the body is published to JIRA or Bugsnag.

## No leaked markup on JIRA

When the target is JIRA, the template body uses only the helper's supported Wiki Markup subset. It is never sent to JIRA directly. Before publishing, scan the source and convert or reject each leaked Markdown construct per `@rules/jira/general.md`:

| Markdown | JIRA Wiki Markup |
|---|---|
| `**bold**` / `__bold__` | `*bold*` |
| `#` / `##` / `###` headings | `h1.` / `h2.` / `h3.` |
| `` `code` `` | `{{code}}` |
| fenced ```` ``` ```` blocks | `{code}…{code}` |
| `- ` / `+ ` bullets | `*` |
| `[label]` + `(url)` | `[label\|url]` |

The reader must never see a raw `**` or `#`.

## No markup at all on Bugsnag

Bugsnag renders a comment as plain text, so every markup character reaches the reader literally. Write the body with no headings, no bold, no inline code, no links in bracket form: section names on their own line, field labels followed by a colon, list items opened with a plain `-`, and URLs written out in full. There is no per-actor marker either — the API token identifies the author.
