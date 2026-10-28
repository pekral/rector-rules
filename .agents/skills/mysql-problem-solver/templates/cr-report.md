## MySQL report — critical optimizations (advisory)

Advisory only: this report does not block the merge and is not part of the code review.
Engine: <mysql | mariadb | unresolved — the review's `Not verified:` entry> · Head: <short SHA> · DB access: <EXPLAIN run | static analysis only — <reason>>

### 1. <one-sentence problem> — `<file>:<line>`
- **Evidence:** <reconstructed SQL, EXPLAIN baseline or the stated limitation, table size when known>
- **Why it is critical:** <the concrete production consequence>
- **Proposed optimization:** <the rewrite, batch, index, or online DDL>
- **Non-regression:** <baseline vs proposal, or why it is slower and what justifies it>

<!-- When no item qualifies, keep the heading, the advisory line, and the engine line, and replace the items with: No critical MySQL item in this diff. -->
