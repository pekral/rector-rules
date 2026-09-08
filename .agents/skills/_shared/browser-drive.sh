#!/usr/bin/env bash
# browser-drive.sh — run a Playwright scenario against a locally running application.
#
# Exists so an acceptance run can drive a real browser WITHOUT adding a dependency to the
# project under test. `@skills/e2e-testing` writes Playwright tests that live in a project
# which has adopted Playwright; this script is the other case — the project has not adopted
# it, and `agents/argus.md` still has to click through a UI to verify a criterion. It never
# writes into the project: the Playwright runtime is resolved from whatever is already
# installed (the project's own node_modules first, then the global npm root), and the
# scenario file is supplied by the caller from a temporary path.
#
# The scenario must be CommonJS (`require('playwright')`, a `.js` file). Playwright is made
# resolvable through NODE_PATH, which ESM resolution ignores entirely — an `import` in a
# scenario living outside a node project fails with ERR_MODULE_NOT_FOUND regardless of what
# is installed.
#
# Usage:
#   browser-drive.sh <scenario.js>      run the scenario with `playwright` resolvable
#   browser-drive.sh --self-test        verify the resolution and failure paths
#
# Exit codes:
#   0  the scenario ran (its own exit code is propagated)
#   2  usage error — no scenario given, or the file does not exist
#   3  no Playwright runtime is available anywhere; the message names the install command
#   4  Playwright is installed but its browser binaries are not

set -euo pipefail

# Resolved once, absolutely: the self-test re-invokes this script from other working
# directories, where a relative invocation path would no longer resolve and every case
# would fail 127 instead of exercising the branch it is meant to check.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
readonly SELF

readonly EXIT_USAGE=2
readonly EXIT_NO_RUNTIME=3
readonly EXIT_NO_BROWSER=4

# Prints the first directory that contains a `playwright` module, or nothing.
# The project's own copy wins: a project that HAS adopted Playwright must be driven by the
# version it pinned, never by whatever happens to be global.
resolve_playwright_root() {
    local candidate
    for candidate in "$PWD/node_modules" "$(npm root -g 2>/dev/null || true)"; do
        if [ -n "$candidate" ] && [ -d "$candidate/playwright" ]; then
            printf '%s\n' "$candidate"

            return 0
        fi
    done

    return 1
}

run_scenario() {
    local scenario="$1" root output status

    if ! root="$(resolve_playwright_root)"; then
        cat >&2 <<'MSG'
browser-drive.sh: no Playwright runtime found.
Install one without touching the project under test:
    npm install -g playwright && playwright install chromium
MSG

        return "$EXIT_NO_RUNTIME"
    fi

    # `node` is invoked directly rather than through `playwright test`, which would require a
    # config file inside the project — the one thing this script exists to avoid writing.
    set +e
    output="$(NODE_PATH="$root" node "$scenario" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output"

    if [ "$status" -ne 0 ] && printf '%s' "$output" | grep -q "Executable doesn't exist"; then
        echo "browser-drive.sh: Playwright is installed but its browsers are not. Run: playwright install chromium" >&2

        return "$EXIT_NO_BROWSER"
    fi

    return "$status"
}

self_test() {
    local tmp failures=0 out status
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    check() {
        local label="$1" expected="$2" actual="$3"
        if [ "$expected" = "$actual" ]; then
            printf 'ok    %-46s exit %s\n' "$label" "$actual"
        else
            printf 'FAIL  %-46s expected %s, got %s\n' "$label" "$expected" "$actual"
            failures=$((failures + 1))
        fi
    }

    set +e
    "$SELF" > /dev/null 2>&1
    check "no scenario argument" "$EXIT_USAGE" "$?"

    "$SELF" "$tmp/missing.js" > /dev/null 2>&1
    check "scenario file does not exist" "$EXIT_USAGE" "$?"
    set -e

    # No runtime anywhere: an empty cwd and an `npm` stub pointing at a directory with no
    # `playwright` module must produce the actionable install message, never a node crash.
    mkdir -p "$tmp/empty/bin" "$tmp/emptyroot"
    printf '#!/usr/bin/env bash\necho "%s"\n' "$tmp/emptyroot" > "$tmp/empty/bin/npm"
    chmod +x "$tmp/empty/bin/npm"
    echo 'console.log("never reached")' > "$tmp/empty/scenario.js"
    set +e
    out="$(cd "$tmp/empty" && PATH="$tmp/empty/bin:$PATH" "$SELF" "$tmp/empty/scenario.js" 2>&1)"
    status=$?
    set -e
    check "no playwright runtime anywhere" "$EXIT_NO_RUNTIME" "$status"
    if printf '%s' "$out" | grep -q 'npm install -g playwright'; then
        printf 'ok    %-46s names the install command\n' "no-runtime message"
    else
        printf 'FAIL  %-46s does not name the install command\n' "no-runtime message"
        failures=$((failures + 1))
    fi

    # A resolvable runtime: the scenario is executed and its own exit code is propagated, so a
    # failing assertion inside the scenario surfaces as a failure rather than a silent pass.
    mkdir -p "$tmp/proj/node_modules/playwright"
    echo '{"name":"playwright"}' > "$tmp/proj/node_modules/playwright/package.json"
    echo 'process.exit(7)' > "$tmp/proj/scenario.js"
    set +e
    (cd "$tmp/proj" && "$SELF" "$tmp/proj/scenario.js" > /dev/null 2>&1)
    check "scenario exit code is propagated" "7" "$?"
    set -e

    if [ "$failures" -eq 0 ]; then
        echo "browser-drive.sh: --self-test PASS"

        return 0
    fi

    echo "browser-drive.sh: --self-test FAIL ($failures)" >&2

    return 1
}

main() {
    if [ "${1:-}" = "--self-test" ]; then
        self_test

        return $?
    fi

    if [ -z "${1:-}" ]; then
        echo "usage: browser-drive.sh <scenario.js> | --self-test" >&2

        return "$EXIT_USAGE"
    fi

    if [ ! -f "$1" ]; then
        echo "browser-drive.sh: scenario file not found: $1" >&2

        return "$EXIT_USAGE"
    fi

    run_scenario "$1"
}

main "$@"
