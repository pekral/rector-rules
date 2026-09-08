#!/usr/bin/env bash
# assert-current-repo.sh — refuse to act on a GitHub issue/PR that belongs to a
# different repository than the current checkout.
#
# Why this exists
#   Every skill that loads a GitHub reference and then *acts* on it (implements
#   it, reviews it, comments on it, merges it) must first prove the reference
#   belongs to the repository the caller is standing in. Without the check, a
#   pasted URL from a neighbouring project silently redirects the whole run: the
#   skill reads a foreign assignment, edits the local tree, and opens a PR
#   against the wrong backlog. Nothing in the flow contradicts the URL.
#
# Usage
#   assert-current-repo.sh <URL|owner/repo>
#   assert-current-repo.sh --self-test
#
#   URL         any github.com URL whose path starts with <owner>/<repo>
#               (issue, PR, or the bare repo URL); a `www.` prefix, a trailing
#               `.git`, and a trailing slash are tolerated
#   owner/repo  a bare nameWithOwner
#
# On success the resolved nameWithOwner is echoed on stdout and the exit code is
# 0. Every non-zero exit is a HARD STOP.
#
#   IMPORTANT — these codes are this script's own. Do NOT apply the deterministic
#   loader convention ("exit 2/3 -> fall back to the MCP server") to them. There
#   is no fallback for an ownership verdict: a guard that cannot prove ownership
#   must stop the flow, never route around itself.
#
# What counts as "the current repository"
#   Every remote is considered, not just `origin`, and both its fetch and push
#   URLs are read through `git remote get-url`, which applies `insteadOf` /
#   `pushInsteadOf` rewrites and returns the *effective* URL. This matters for
#   two real workflows the naive `git config --get remote.origin.url` breaks:
#     - fork workflow: `origin` is your fork, `upstream` is the canonical repo
#       the PR actually lives in. Both are legitimately "this project".
#     - `pushurl` / `insteadOf`: the configured URL is not the effective one, so
#       reading raw config compares against a repository git would never touch.
#   A reference matching ANY of the checkout's remotes is accepted; a reference
#   matching none of them is the foreign case this guard exists to stop.
#
# Exit codes:
#   0  the reference belongs to the current repository
#   1  usage error (missing, malformed, or unparseable argument)
#   2  missing required tool (git)
#   4  MISMATCH — the reference belongs to a different repository
#   5  the current repository could not be resolved (not a git checkout, no
#      github.com remote, and `gh` could not answer either)
#
#   Code 3 is intentionally unused: it is the loader convention's "fetch failed
#   -> fall back to MCP" code, and reusing it here invited callers to treat an
#   unresolvable ownership check as a soft failure.
set -euo pipefail

PROG="${0##*/}"

usage() {
  cat >&2 <<'EOF'
Usage: assert-current-repo.sh <URL|owner/repo>
       assert-current-repo.sh --self-test

  URL         a github.com URL whose path starts with <owner>/<repo>
              e.g. https://github.com/pekral/ai-olympus/issues/75
  owner/repo  a bare nameWithOwner
              e.g. pekral/ai-olympus

Exits 4 when the reference belongs to a different repository than the checkout.
Every non-zero exit is a hard stop — there is no MCP fallback for ownership.
EOF
}

# Render untrusted text safely. The reference is attacker-influenced (a JIRA
# `pullRequests[]` entry or a Bugsnag `linkedIssues[]` entry is writable by
# anyone with tracker access), and it is printed in the very message meant to
# stop the operator. ANSI escapes could erase or rewrite that message and bidi
# overrides could reverse it, so display is restricted to printable ASCII and
# truncated. C locale makes `[:print:]` byte-wise, which drops every multibyte
# sequence including U+202E and friends.
safe_display() {
  printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]' | cut -c1-200
}

# A GitHub owner or repository name. Deliberately strict: it excludes `.` and
# `..` as whole segments, which is what makes path traversal unrepresentable
# rather than merely filtered.
NAME_RE='^[A-Za-z0-9_.-]+$'

is_valid_name() {
  local name="$1"
  [[ "$name" =~ $NAME_RE ]] || return 1
  # `.` and `..` are syntactically valid under the charset but are path
  # segments, never repository names.
  [[ "$name" != "." && "$name" != ".." ]] || return 1
  return 0
}

# Does this ssh host name resolve to github.com?
#
# `ssh -G <host>` prints the effective configuration after applying Host /
# Match rules and echoes the real `hostname`. An unconfigured name resolves to
# itself, so `github-work` without a matching Host block correctly fails to
# match, while `github.com-evil.example` is only ever accepted if the
# operator's own ssh config says it is github.com. That soundness is why this
# replaced a `github.com-*` prefix rule, which could not tell a local alias
# from a registrable look-alike domain.
#
# It makes no network connection and performs no authentication, but it is NOT
# side-effect free: a `Match exec` block in the operator's ssh config runs an
# arbitrary shell command during evaluation (verified). The config is the
# operator's own, so this is not an escalation — but this guard runs first in
# nine skills, so the cost is stated rather than glossed over. The call is
# narrow by construction: it fires only for a non-github.com host on an
# ssh/scp remote, so the common `git@github.com:…` checkout never invokes it.
# The caller de-duplicates remote URLs before resolving them, so a Host that
# appears as both a fetch and a push URL is looked up once, not twice.
ssh_host_is_github() {
  local host="$1" resolved

  command -v ssh >/dev/null 2>&1 || return 1

  # `--` terminates option parsing: the host comes from a git remote, and this
  # script calls `ssh` unqualified from PATH, so it must not depend on a
  # particular ssh build refusing a leading dash.
  resolved="$(ssh -G -- "$host" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }' | tr '[:upper:]' '[:lower:]')"
  [[ "$resolved" == "github.com" ]]
}

# The single canonical parser, used for BOTH the caller's reference and every
# remote URL. Two separate parsers is how the first version of this script
# ended up accepting inputs on one side that it rejected on the other.
#
# Echoes "<owner>/<repo>" on success; returns 1 when the input is not a
# github.com reference this guard can vouch for.
github_nwo_from_url() {
  local url="$1" context="${2:-reference}"
  local scheme="" rest="" authority="" path="" host="" owner="" repo="" segment

  # Reject anything carrying a newline: only the first line would be validated
  # and the remainder would ride along unchecked.
  case "$url" in
  *$'\n'* | *$'\r'*) return 1 ;;
  esac

  # Percent-encoding and backslashes are never needed to name a GitHub
  # repository, and both are ways to smuggle a separator past the segment
  # checks below (`%2e%2e` -> `..`, `%2f` -> `/`, `..\` on lenient parsers).
  # Rejecting them outright is cheaper than trying to decode safely, and a
  # decode step would only reopen the question one layer down (`%252e`).
  case "$url" in
  *%* | *\\*) return 1 ;;
  esac

  # --- Separate scheme, authority, and path -----------------------------
  #
  # This split is the whole point of the function. Stripping userinfo with a
  # blind `${rest#*@}` cuts at the first `@` ANYWHERE — including one sitting
  # in the path — which lets `…/attacker/other-repo/issues/1@github.com/us/ours`
  # read as ours while the loader (and GitHub) resolve the other repository.
  # Userinfo only ever lives inside the authority, so the authority has to be
  # isolated before it is touched.
  if [[ "$url" == *"://"* ]]; then
    scheme="$(printf '%s' "${url%%://*}" | tr '[:upper:]' '[:lower:]')"
    scheme="${scheme#git+}" # git+ssh -> ssh
    rest="${url#*://}"
    authority="${rest%%[/?#]*}"
    path="${rest:${#authority}}"
  else
    # scp-style `[user@]host:path`. The colon must come before any slash,
    # otherwise this is not an scp URL at all.
    rest="$url"
    if [[ "$rest" == *:* && "${rest%%:*}" != */* ]]; then
      authority="${rest%%:*}"
      path="/${rest#*:}"
    else
      return 1
    fi
  fi

  path="${path%%\?*}" # drop query
  path="${path%%#*}"  # drop fragment

  # Userinfo is stripped only within the authority, and at the LAST `@` so a
  # username containing one cannot shift the host boundary.
  authority="${authority##*@}"
  host="$(printf '%s' "${authority%%:*}" | tr '[:upper:]' '[:lower:]')"
  host="${host#www.}"

  # --- Host policy, by context ------------------------------------------
  #
  # An SSH host alias (`github.com-work`, a Host entry in ~/.ssh/config) is a
  # purely local name. It can legitimately appear in a git remote over ssh, and
  # never in a URL a person pastes from a browser. Honouring it over http(s)
  # would accept `github.com-evil.example` — a registrable domain — as GitHub.
  case "$context" in
  remote)
    case "$scheme" in
    '' | ssh | git | https | http) ;;
    *) return 1 ;;
    esac
    if [[ "$host" == "github.com" ]]; then
      :
    elif [[ -z "$scheme" || "$scheme" == "ssh" ]] && ssh_host_is_github "$host"; then
      # An ssh Host alias can be named anything — `github-work`, `gh-personal`,
      # `github.com-client`. Resolving it locally is what `gh` does internally,
      # and it is the correct fix for the multi-account setups GitHub itself
      # documents. The earlier version instead widened the `gh` fallback, which
      # papered over parser gaps rather than closing them.
      :
    else
      return 1
    fi
    ;;
  *)
    # A caller-supplied reference is a browser URL: github.com over http(s).
    case "$scheme" in
    https | http) ;;
    *) return 1 ;;
    esac
    [[ "$host" == "github.com" ]] || return 1
    ;;
  esac

  # --- Path -> owner/repo -----------------------------------------------
  path="${path#/}"
  path="${path%/}"
  [[ "$path" == */* ]] || return 1

  # Split on `/` with `read -a` rather than an unquoted `set --`. An unquoted
  # expansion is also subject to pathname expansion, which `IFS` does not
  # disable: `https://github.com/*/*` then expanded against the caller's cwd
  # and the verdict depended on which files happened to sit there — a
  # fail-open bug (exit 0 on a glob that matched two entries).
  local segments=()
  IFS='/' read -r -a segments <<<"$path"

  # No segment may be a relative path element. Traversal is made
  # unrepresentable rather than filtered: `/o/r/../../other/repo` keeps the
  # first two segments looking like ours while resolving elsewhere.
  for segment in "${segments[@]}"; do
    [[ "$segment" == "." || "$segment" == ".." ]] && return 1
  done

  owner="${segments[0]}"
  repo="${segments[1]-}"
  repo="${repo%.git}"

  is_valid_name "$owner" || return 1
  is_valid_name "$repo" || return 1

  printf '%s/%s' "$owner" "$repo"
}

# Accepts the caller's reference in either supported form.
extract_reference_nwo() {
  local ref="$1"

  case "$ref" in
  *$'\n'* | *$'\r'*) return 1 ;;
  esac

  # A bare nameWithOwner: exactly one slash and nothing else.
  if [[ "$ref" != *://* && "$ref" != *github.com* && "$ref" != *@* ]]; then
    local owner="${ref%%/*}" repo="${ref#*/}"
    [[ "$ref" == */* && "$repo" != */* ]] || return 1
    is_valid_name "$owner" || return 1
    is_valid_name "$repo" || return 1
    printf '%s/%s' "$owner" "$repo"
    return 0
  fi

  github_nwo_from_url "$ref" reference
}

# Echoes every nameWithOwner the current checkout is attached to, one per line.
# Errors from git are surfaced, never swallowed: a `dubious ownership` refusal
# or a broken config must not masquerade as "no remote configured", which would
# send the caller chasing a remote that is in fact present.
current_repo_nwos() {
  local git_err remotes remote url nwo found=0

  if ! git_err="$(git rev-parse --is-inside-work-tree 2>&1 >/dev/null)"; then
    if [[ -n "$git_err" ]]; then
      echo "$PROG: git could not read this directory: $(safe_display "$git_err")" >&2
    fi
    return 1
  fi

  if ! remotes="$(git remote 2>&1)"; then
    echo "$PROG: git could not list remotes: $(safe_display "$remotes")" >&2
    return 1
  fi

  # Collect every effective URL across all remotes first, then de-duplicate,
  # then resolve. A remote's fetch and push URLs are usually identical, so
  # without the dedup an ssh Host would be resolved once per URL — and because
  # each resolution runs `github_nwo_from_url` in a `$()` subshell, a memo on
  # the resolver cannot persist between calls (the subshell-state trap). Dedup
  # at the URL level sidesteps that entirely: one lookup per distinct URL.
  #
  # --all covers multi-valued url entries; the push variant covers pushurl.
  # get-url (unlike `git config`) applies insteadOf / pushInsteadOf, so this is
  # the URL git would actually contact. The `2>/dev/null` is deliberate and
  # narrow: `--push --all` exits non-zero on a remote with no pushurl, the
  # common case and not an error; a genuine git failure was already surfaced by
  # the `rev-parse` / `git remote` calls above, which suppress nothing.
  local all_urls=""
  while IFS= read -r remote; do
    [[ -n "$remote" ]] || continue
    all_urls+="$(git remote get-url --all "$remote" 2>/dev/null || true)"$'\n'
    all_urls+="$(git remote get-url --push --all "$remote" 2>/dev/null || true)"$'\n'
  done <<<"$remotes"

  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    if nwo="$(github_nwo_from_url "$url" remote)"; then
      printf '%s\n' "$nwo"
      found=1
    fi
  done < <(printf '%s' "$all_urls" | awk 'NF && !seen[$0]++')

  [[ "$found" -eq 1 ]] || return 1
  return 0
}

# Global, not local: the EXIT trap fires after the function's locals are gone,
# and reading an unset local under `set -u` would abort the cleanup.
SELF_TEST_TMP=""
# Reached only through `trap cleanup_self_test EXIT` below. ShellCheck's reachability pass does
# not credit a trap as an invocation, which is the case SC2317 itself names ("or ignore if
# invoked indirectly"); there is nothing to fix at the source. ShellCheck 0.11 split that
# reachability case out into SC2329, so both codes are suppressed or the newer version of the
# same false positive re-breaks the gate.
# shellcheck disable=SC2317,SC2329
cleanup_self_test() {
  [[ -n "$SELF_TEST_TMP" ]] && rm -rf "$SELF_TEST_TMP"
  return 0
}

self_test() {
  local tmp failures=0 script
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$PROG"
  SELF_TEST_TMP="$(mktemp -d)"
  tmp="$SELF_TEST_TMP"
  trap cleanup_self_test EXIT

  # Build a scratch checkout. Each argument is one `git` invocation; the tests
  # below use no arguments containing whitespace, so word splitting is intended.
  mkrepo() {
    local dir cmd
    dir="$tmp/repo-$RANDOM$RANDOM"
    mkdir -p "$dir"
    if ! git -C "$dir" init -q; then
      echo "mkrepo: could not init $dir" >&2
      return 1
    fi
    for cmd in "$@"; do
      # Intentional word splitting: each argument is a literal git argv line
      # with no glob characters. A failure here must abort — a fixture that
      # silently did not get built made two `exit 5` assertions pass for the
      # wrong reason, which is the same class of bug as an unrun self-test.
      # shellcheck disable=SC2086
      if ! git -C "$dir" $cmd; then
        echo "mkrepo: git $cmd failed in $dir" >&2
        return 1
      fi
    done
    printf '%s' "$dir"
  }

  # Assert BOTH the exit code and, when given, the resolved nameWithOwner on
  # stdout. Comparing exit codes alone would let a wrong-but-zero verdict pass
  # silently — the guard's whole output is the repository it vouched for.
  verdict() {
    local label="$1" dir="$2" reference="$3" expected="$4" expected_out="${5:-}"
    local actual out
    if [[ -z "$dir" || ! -d "$dir" ]]; then
      printf 'FAIL  %-50s fixture was not built\n' "$label" >&2
      failures=$((failures + 1))
      return 0
    fi
    set +e
    out="$(cd "$dir" && "$script" "$reference" 2>/dev/null)"
    actual=$?
    set -e
    if [[ "$actual" -ne "$expected" ]]; then
      printf 'FAIL  %-50s expected exit %s, got %s\n' "$label" "$expected" "$actual" >&2
      failures=$((failures + 1))
      return 0
    fi
    if [[ -n "$expected_out" && "$out" != "$expected_out" ]]; then
      printf 'FAIL  %-50s expected stdout %s, got %s\n' "$label" "$expected_out" "$out" >&2
      failures=$((failures + 1))
      return 0
    fi
    printf 'ok    %-50s exit %s\n' "$label" "$actual"
  }

  check() {
    verdict "$1" "$(mkrepo "remote add origin $2")" "$3" "$4" "${5:-}"
  }

  local ours='https://github.com/pekral/ai-olympus/issues/75'
  local theirs='https://github.com/attacker/other-repo/issues/2017'
  local OURS_NWO='pekral/ai-olympus'

  # Every remote spelling git accepts must recognise its own repository.
  check 'https remote'              'https://github.com/pekral/ai-olympus.git' "$ours" 0 "$OURS_NWO"
  check 'scp-style remote'          'git@github.com:pekral/ai-olympus.git'     "$ours" 0 "$OURS_NWO"
  check 'ssh:// remote'             'ssh://git@github.com/pekral/ai-olympus'   "$ours" 0 "$OURS_NWO"
  check 'git+ssh:// remote'         'git+ssh://git@github.com/pekral/ai-olympus' "$ours" 0 "$OURS_NWO"
  check 'git:// remote'             'git://github.com/pekral/ai-olympus'       "$ours" 0 "$OURS_NWO"
  check 'credentials in remote'     'https://user:tok@github.com/pekral/ai-olympus' "$ours" 0 "$OURS_NWO"
  # An email address as the username puts an `@` inside the userinfo itself, so
  # the host boundary is the LAST `@` in the authority, never the first.
  check 'email-style userinfo'      'https://user@corp.example:tok@github.com/pekral/ai-olympus' "$ours" 0 "$OURS_NWO"
  check 'trailing slash remote'     'https://github.com/pekral/ai-olympus.git/' "$ours" 0 "$OURS_NWO"
  check 'bare nwo reference'        'https://github.com/pekral/ai-olympus'     'pekral/ai-olympus' 0 "$OURS_NWO"
  check 'mixed-case reference'      'https://github.com/pekral/ai-olympus'     'Pekral/Ai-Olympus' 0 "$OURS_NWO"

  # The foreign cases this guard exists to stop.
  check 'foreign repo'              'https://github.com/pekral/ai-olympus'     "$theirs" 4
  check 'foreign owner'             'https://github.com/pekral/ai-olympus'     'other-owner/ai-olympus' 4
  check 'foreign repo name'         'https://github.com/pekral/ai-olympus'     'pekral/something-else' 4

  # --- Regressions -------------------------------------------------------
  #
  # An `@` in the PATH must not be mistaken for userinfo. Stripping at the
  # first `@` made the guard vouch for the trailing segment while the loader
  # read `attacker/other-repo` from the front. The verdict must follow the
  # first two path segments, exactly as every other GitHub parser reads them.
  check 'userinfo lookalike in path' 'https://github.com/pekral/ai-olympus' \
    'https://github.com/attacker/other-repo/issues/1@github.com/pekral/ai-olympus' 4

  # An SSH host alias is a local ~/.ssh/config name. Honouring it over https
  # accepted `github.com-evil.example`, which anyone can register.
  check 'dash-alias host over https' 'https://github.com/pekral/ai-olympus' \
    'https://github.com-evil.example/pekral/ai-olympus/issues/1' 1

  # The same policy applies to the remote side, which has its own, looser host
  # branch. Without this case the reference-side check alone keeps passing while
  # the remote branch silently accepts a registrable look-alike domain.
  check 'dash-alias remote over https' 'https://github.com-evil.example/pekral/ai-olympus' "$ours" 5

  # Traversal, in every spelling that reaches a different repository.
  check 'traversal in reference'    'https://github.com/pekral/ai-olympus' \
    'https://github.com/pekral/ai-olympus/../../attacker/other-repo/issues/1' 1
  check 'encoded traversal'         'https://github.com/pekral/ai-olympus' \
    'https://github.com/pekral/ai-olympus/%2e%2e/%2e%2e/attacker/other-repo' 1
  check 'double-encoded traversal'  'https://github.com/pekral/ai-olympus' \
    'https://github.com/pekral/ai-olympus/%252e%252e/attacker/other-repo' 1
  check 'encoded separator in path' 'https://github.com/pekral/ai-olympus' \
    'https://github.com/pekral/ai-olympus%2f..%2fattacker%2fother-repo' 1
  check 'backslash separator'       'https://github.com/pekral/ai-olympus' \
    'https://github.com/pekral/ai-olympus\..\attacker\other-repo' 1

  # Look-alike hosts and malformed input.
  check 'host suffix attack'        'https://github.com/pekral/ai-olympus'     'https://github.com.evil.example/pekral/ai-olympus' 1
  check 'non-github URL'            'https://github.com/pekral/ai-olympus'     'https://gitlab.com/foo/bar/issues/1' 1
  check 'garbage reference'         'https://github.com/pekral/ai-olympus'     'not-a-repo' 1
  check 'percent-encoded separator' 'https://github.com/pekral/ai-olympus'     'pekral%2Fx/ai-olympus' 1
  # A pasted reference is a browser URL. Tracker `url` fields are https too, so
  # an ssh-transport reference is malformed input rather than a repository.
  # An unquoted split also globs, so these expanded against the caller's cwd
  # and the verdict depended on which files happened to be sitting there.
  check 'glob wildcards in reference'  'https://github.com/pekral/ai-olympus' 'https://github.com/*/*' 1
  check 'bracket glob in reference'    'https://github.com/pekral/ai-olympus' \
    'https://github.com/[a]gentic-vibes/[l]aravel-ai-olympus' 1

  check 'ssh reference rejected'    'https://github.com/pekral/ai-olympus'     'ssh://git@github.com/pekral/ai-olympus' 1

  # --- Effective remote URLs --------------------------------------------
  #
  # These three are why the guard stopped reading `remote.origin.url`: in each
  # case the configured value and the URL git actually contacts differ.
  verdict 'insteadOf rewrite' "$(mkrepo \
    'config url.https://github.com/.insteadOf gh:' \
    'remote add origin gh:pekral/ai-olympus')" "$ours" 0 "$OURS_NWO"

  verdict 'pushurl points at this repo' "$(mkrepo \
    'remote add origin https://github.com/someone/unrelated.git' \
    'remote set-url --push origin https://github.com/pekral/ai-olympus.git')" "$ours" 0 "$OURS_NWO"

  verdict 'multi-valued remote url' "$(mkrepo \
    'remote add origin https://github.com/someone/unrelated.git' \
    'remote set-url --add origin https://github.com/pekral/ai-olympus.git')" "$ours" 0 "$OURS_NWO"

  # A fork workflow is legitimately "this project": origin is the fork, the PR
  # lives on upstream. Both must be accepted, and a third repo still blocked.
  local forkdir
  forkdir="$(mkrepo \
    'remote add origin git@github.com:me/ai-olympus.git' \
    'remote add upstream https://github.com/pekral/ai-olympus.git')"
  verdict 'fork workflow accepts upstream'    "$forkdir" "$ours" 0 "$OURS_NWO"
  verdict 'fork workflow still blocks foreign' "$forkdir" "$theirs" 4

  # An ssh Host alias resolves through the operator's own ssh config. `ssh -G`
  # locates it via getpwuid, so overriding $HOME does not redirect it; `-F`
  # would, but the guard deliberately reads the operator's default config
  # rather than taking a config path, so there is nothing to point at a
  # fixture. What is tested is therefore the contract this script actually
  # owns — consult ssh, parse its answer, honour it — with a stub supplying
  # the answer. Whether real ssh prints `hostname <value>` is ssh's contract,
  # not this script's.
  local stubbin="$tmp/stubbin"
  mkdir -p "$stubbin"
  cat >"$stubbin/ssh" <<'STUB'
#!/usr/bin/env bash
# Stand-in for `ssh -G <host>`: `github-work` is configured to be github.com,
# everything else resolves to itself, exactly as real ssh behaves.
for arg in "$@"; do :; done
host="${!#}"
if [[ "$host" == "github-work" ]]; then
  echo "hostname github.com"
else
  echo "hostname $host"
fi
STUB
  chmod +x "$stubbin/ssh"

  local aliasdir alias_rc alias_out
  aliasdir="$(mkrepo 'remote add origin git@github-work:pekral/ai-olympus.git')"
  set +e
  alias_out="$(cd "$aliasdir" && PATH="$stubbin:$PATH" "$script" "$ours" 2>/dev/null)"
  alias_rc=$?
  set -e
  if [[ "$alias_rc" -eq 0 && "$alias_out" == "$OURS_NWO" ]]; then
    printf 'ok    %-50s exit 0\n' 'configured ssh alias resolves to github.com'
  else
    printf 'FAIL  %-50s expected 0/%s, got %s/%s\n' 'configured ssh alias resolves to github.com' "$OURS_NWO" "$alias_rc" "$alias_out" >&2
    failures=$((failures + 1))
  fi

  # An unconfigured alias resolves to itself and must not pass as github.com —
  # this is what makes the check sound where the old `github.com-*` prefix rule
  # was not: `github.com-evil.example` is a registrable domain.
  local unconfigured
  unconfigured="$(mkrepo 'remote add origin git@github.com-evil.example:pekral/ai-olympus.git')"
  set +e
  (cd "$unconfigured" && PATH="$stubbin:$PATH" "$script" "$ours" >/dev/null 2>&1)
  alias_rc=$?
  set -e
  if [[ "$alias_rc" -eq 5 ]]; then
    printf 'ok    %-50s exit 5\n' 'unconfigured alias is not github.com'
  else
    printf 'FAIL  %-50s expected 5, got %s\n' 'unconfigured alias is not github.com' "$alias_rc" >&2
    failures=$((failures + 1))
  fi

  # A non-github checkout cannot vouch for ownership and must say so (5), not
  # guess (0) and not report a mismatch (4).
  check 'non-github remote only'    'https://gitlab.com/foo/bar.git'                            "$ours" 5

  # Known limit: reverting the `REMOTES_PRESENT` restriction on the `gh`
  # fallback is not observable here. Exercising it needs a remote that git
  # accepts, this parser rejects, and `gh` can still resolve — which cannot be
  # constructed without also reintroducing a parser bug. The restriction is
  # defence in depth against exactly that pairing, so it is stated here rather
  # than asserted.

  if [[ "$failures" -gt 0 ]]; then
    echo "assert-current-repo self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'assert-current-repo self-test: PASS'
  return 0
}

if [[ "${1:-}" == "--self-test" ]]; then
  if ! command -v git >/dev/null 2>&1; then
    echo "$PROG: required tool not found: git" >&2
    exit 2
  fi
  self_test
  exit $?
fi

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  usage
  exit 1
fi

INPUT="$1"

if ! command -v git >/dev/null 2>&1; then
  echo "$PROG: required tool not found: git" >&2
  exit 2
fi

REF_NWO="$(extract_reference_nwo "$INPUT" || true)"
if [[ -z "$REF_NWO" ]]; then
  echo "$PROG: could not extract <owner>/<repo> from: $(safe_display "$INPUT")" >&2
  usage
  exit 1
fi

CURRENT_NWOS="$(current_repo_nwos || true)"

# Whether the checkout has ANY remote, independent of whether one parsed.
# This has to be read here, in the main shell: `current_repo_nwos` runs inside a
# command substitution, so a flag it sets would never reach this point.
#
# There is deliberately no `gh repo view` fallback. It would only be reachable
# when the checkout has no remote at all — and `gh` derives the repository FROM
# the remotes, so it answers `no git remotes found` in exactly that case. Worse,
# when remotes DO exist but none parse, asking gh would let its parser silently
# repair a verdict this script could not reach on its own, hiding the gap. An
# unprovable ownership check must stay unprovable.
REMOTES_PRESENT=0
if git remote 2>/dev/null | grep -q .; then
  REMOTES_PRESENT=1
fi

# `gh repo view` is a fallback for a checkout with NO remotes at all, never a
# second opinion on remotes this script failed to parse. gh runs its own URL
# parser, so consulting it after a parse failure silently repairs the verdict
# and hides the gap — which is how an incomplete parser stayed invisible
# through a full review round. When remotes exist but none of them resolved,
# that is an unprovable state and must be reported as one.
if [[ -z "$CURRENT_NWOS" ]]; then
  cat >&2 <<EOF
$PROG: cannot resolve the current repository.

No remote on this checkout resolves to a github.com repository$( [[ "$REMOTES_PRESENT" -eq 1 ]] && printf '%s' " (remotes are configured, but none of them parsed as GitHub — \`gh\` is deliberately not consulted here, so a parser gap cannot be silently repaired)" || printf '%s' " and \`gh repo view\` did not answer" ).
Ownership cannot be proven, so the operation must not proceed: run from inside
the target checkout, or add the remote, before acting on $(safe_display "$REF_NWO").
EOF
  exit 5
fi

REF_LOWER="$(printf '%s' "$REF_NWO" | tr '[:upper:]' '[:lower:]')"

while IFS= read -r candidate; do
  [[ -n "$candidate" ]] || continue
  if [[ "$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')" == "$REF_LOWER" ]]; then
    printf '%s\n' "$candidate"
    exit 0
  fi
done <<<"$CURRENT_NWOS"

{
  echo "$PROG: REPOSITORY MISMATCH — refusing to act."
  echo
  echo "  reference points at : $(safe_display "$REF_NWO")"
  echo "  this checkout is    : $(safe_display "$(printf '%s' "$CURRENT_NWOS" | paste -sd ', ' -)")"
  echo
  echo "The assignment belongs to a different repository than the one you are"
  echo "standing in. Acting on it here would read a foreign backlog and push"
  echo "changes to the wrong project. Switch to the correct checkout, or load the"
  echo "assignment from this repository instead."
} >&2
exit 4
