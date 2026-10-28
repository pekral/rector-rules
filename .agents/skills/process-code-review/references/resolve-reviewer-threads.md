# Resolve addressed reviewer threads (GitHub)

Referenced from `skills/process-code-review/SKILL.md` *PR update*. Extracted to keep the skill body under the skill-check token limit; the procedure is the skill's, stated once here.

After the fixes are committed and pushed (the skill's *Finalization*), mark every reviewer review thread whose finding was **actually fixed** as resolved, using the thread `id` captured during intake:

```
gh api graphql -f query='mutation($threadId:ID!){ resolveReviewThread(input:{threadId:$threadId}){ thread{ isResolved } } }' -F threadId=<thread-id>
```

- Resolve **only** threads that were fixed. Leave a thread unresolved when its point was rejected or deferred, and record the rejection reason in the CR comment instead of resolving it. A **deferred** (not rejected) point must additionally be filed as a follow-up issue in the originating tracker per `@rules/compound-engineering/tracker.md` *File deferred points as follow-up tracker issues* (mechanics in `@skills/resolve-issue/SKILL.md` *Deferred-item follow-up issues*); the comment entry carries the created issue URL — rejection is a decision, deferral is a promise.
- If `gh api graphql` is unavailable, fall back to the GitHub MCP server's resolve-review-thread operation.
- Resolving a thread is a GitHub PR state change, not a code change — it stays within the read-fixes-push-resolve flow this skill already owns and never touches the protected main branch.
