#!/usr/bin/env bash
# jira-actor.sh — sourced by the JIRA comment helpers; defines functions only.
#
# One definition of the acli actor identity, so the helper that writes the
# `_cr-comment:actor=<actor-digest>_` marker and the helper that proves
# ownership before a delete can never derive two different digests.
#
#   jira_auth_status_field <auth-status-text> <label>
#       Print the value of one `Label: value` line of `acli jira auth status`
#       (e.g. `site`, `email`). Prints nothing when the line is absent.
#
#   jira_actor_digest <email>
#       Print the first 16 hex characters of the SHA-256 digest of the e-mail.
#       The marker publishes this digest, never the address itself. Prints
#       nothing when the e-mail is empty or php is unavailable.
#
#   jira_actor_account_id
#       Print the Jira account ID of the acli user. `acli` has no "current user"
#       command, so Jira resolves it through JQL `currentUser()`: the assignee of
#       an issue matching `assignee = currentUser()`, else the reporter of one
#       matching `reporter = currentUser()`. Prints nothing when the account
#       neither holds nor reported any issue, or when acli or jq fails.

jira_auth_status_field() {
  printf '%s' "$1" | awk -F': *' -v label="$2" 'tolower($0) ~ (label ":") { gsub(/[[:space:]]+$/, "", $2); print $2; exit }'
}

jira_actor_digest() {
  if [[ -z "${1:-}" ]]; then
    return 0
  fi

  printf '%s' "$1" | php -r 'echo substr(hash("sha256", (string) stream_get_contents(STDIN)), 0, 16);' 2>/dev/null || true
}

jira_actor_account_id() {
  local field account_id
  for field in assignee reporter; do
    account_id="$(acli jira workitem search --jql "${field} = currentUser() ORDER BY updated DESC" --fields "$field" --json --limit 1 2>/dev/null \
      | jq -r --arg field "$field" '[.. | objects | .fields?[$field]?.accountId? | select(type == "string" and . != "")] | first // empty' 2>/dev/null || true)"
    if [[ -n "$account_id" ]]; then
      printf '%s' "$account_id"
      return 0
    fi
  done
}
