#!/usr/bin/env bash
# render-previews.sh — render every HTML mockup in a directory to a PNG preview.
#
# Why this exists
#   `@skills/page-redesign/SKILL.md` owes a rendered preview of every state the
#   main view hides, because a reviewer cannot check a collapsed section against
#   a screenshot they do not have. Producing those by hand is where the coverage
#   quietly drops to "the states I remembered", so the render is a script: point
#   it at the mockups, get one PNG per mockup, and compare the two counts.
#
#   It adds no dependency to the project under test. The Playwright runtime is
#   resolved by `skills/_shared/browser-drive.sh`, which is also what `raphael`
#   uses to drive a real browser without installing anything.
#
# Usage
#   render-previews.sh <mockups-dir> <output-dir> [--viewport <WIDTHxHEIGHT>]
#   render-previews.sh --self-test
#
#   --viewport  the viewport the application is actually used at
#               (default 1440x900). A preview rendered at the wrong width
#               proves nothing about the layout it is meant to show.
#
# Output
#   <output-dir>/<mockup basename>.png, one per `*.html` in <mockups-dir>,
#   full-page, and a line per file on stdout so the caller can count them.
#
# Exit codes
#   0  every mockup rendered
#   2  usage error (missing argument, unreadable directory, bad viewport)
#   3  the mockups directory contains no `*.html` file
#   4  the renderer is unavailable (propagated from browser-drive.sh)
#   5  a mockup failed to render

set -euo pipefail

PROG="${0##*/}"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
readonly PROG SELF

readonly EXIT_USAGE=2
readonly EXIT_NO_MOCKUPS=3
readonly EXIT_NO_RENDERER=4
readonly EXIT_RENDER_FAILED=5

usage() {
    cat >&2 <<'EOF'
Usage: render-previews.sh <mockups-dir> <output-dir> [--viewport <WIDTHxHEIGHT>]
       render-previews.sh --self-test

Renders every *.html in <mockups-dir> to <output-dir>/<name>.png.
EOF
}

# The scenario is generated rather than shipped as a file: it carries the input
# list, and a scenario that read a directory itself would duplicate the globbing
# and the "no mockups" verdict this script already owns.
write_scenario() {
    local scenario="$1" width="$2" height="$3" output_dir="$4"
    shift 4

    {
        printf 'const { chromium } = require("playwright");\n'
        printf 'const path = require("path");\n\n'
        printf 'const files = [\n'
        local file
        for file in "$@"; do
            printf '  %s,\n' "$(printf '%s' "$file" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')"
        done
        printf '];\n\n'
        printf 'const outputDir = %s;\n' "$(printf '%s' "$output_dir" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/')"
        printf 'const viewport = { width: %s, height: %s };\n\n' "$width" "$height"
        cat <<'EOF'
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport, deviceScaleFactor: 2 });

  try {
    for (const file of files) {
      const name = path.basename(file, path.extname(file));
      const target = path.join(outputDir, name + ".png");

      await page.goto("file://" + file, { waitUntil: "load" });
      await page.screenshot({ path: target, fullPage: true });

      process.stdout.write(target + "\n");
    }
  } finally {
    await browser.close();
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack ? error.stack : error) + "\n");
  process.exit(1);
});
EOF
    } >"$scenario"
}

render() {
    local mockups_dir="" output_dir="" viewport="1440x900"

    while [ $# -gt 0 ]; do
        case "$1" in
        --viewport)
            [ $# -ge 2 ] || { usage; return "$EXIT_USAGE"; }
            viewport="$2"
            shift 2
            ;;
        -*)
            echo "$PROG: unknown option: $1" >&2
            usage
            return "$EXIT_USAGE"
            ;;
        *)
            if [ -z "$mockups_dir" ]; then
                mockups_dir="$1"
            elif [ -z "$output_dir" ]; then
                output_dir="$1"
            else
                echo "$PROG: unexpected argument: $1" >&2
                usage
                return "$EXIT_USAGE"
            fi
            shift
            ;;
        esac
    done

    if [ -z "$mockups_dir" ] || [ -z "$output_dir" ]; then
        usage
        return "$EXIT_USAGE"
    fi

    if [ ! -d "$mockups_dir" ]; then
        echo "$PROG: not a directory: $mockups_dir" >&2
        return "$EXIT_USAGE"
    fi

    local width height
    width="${viewport%%x*}"
    height="${viewport##*x}"

    case "$viewport" in
    *x*) ;;
    *)
        echo "$PROG: --viewport takes WIDTHxHEIGHT, e.g. 1440x900" >&2
        return "$EXIT_USAGE"
        ;;
    esac

    case "$width$height" in
    *[!0-9]* | '')
        echo "$PROG: --viewport takes WIDTHxHEIGHT, e.g. 1440x900" >&2
        return "$EXIT_USAGE"
        ;;
    esac

    local mockups=()
    local candidate
    for candidate in "$mockups_dir"/*.html; do
        [ -f "$candidate" ] || continue
        mockups+=("$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")")
    done

    if [ "${#mockups[@]}" -eq 0 ]; then
        echo "$PROG: no *.html mockup in $mockups_dir — write the mockups first" >&2
        return "$EXIT_NO_MOCKUPS"
    fi

    mkdir -p "$output_dir"
    output_dir="$(cd "$output_dir" && pwd)"

    local scenario
    scenario="$(mktemp -t page-redesign-previews.XXXXXX)"
    mv "$scenario" "$scenario.js"
    scenario="$scenario.js"
    # shellcheck disable=SC2064 # expand the path now: the variable is reassigned below.
    trap "rm -f '$scenario'" EXIT

    write_scenario "$scenario" "$width" "$height" "$output_dir" "${mockups[@]}"

    local driver status=0
    driver="$(cd "$(dirname "$SELF")/../../_shared" && pwd)/browser-drive.sh"

    if [ ! -x "$driver" ]; then
        echo "$PROG: browser-drive.sh not found next to this skill: $driver" >&2
        return "$EXIT_NO_RENDERER"
    fi

    "$driver" "$scenario" || status=$?

    case "$status" in
    0) return 0 ;;
    3 | 4) return "$EXIT_NO_RENDERER" ;;
    *) return "$EXIT_RENDER_FAILED" ;;
    esac
}

self_test() {
    local failures=0

    expect_exit() {
        local label="$1" expected="$2"
        shift 2
        local actual=0
        set +e
        "$SELF" "$@" >/dev/null 2>&1
        actual=$?
        set -e
        if [ "$actual" -eq "$expected" ]; then
            printf 'ok    %-52s exit %s\n' "$label" "$actual"
        else
            printf 'FAIL  %-52s expected exit %s, got %s\n' "$label" "$expected" "$actual" >&2
            failures=$((failures + 1))
        fi
    }

    local workspace
    workspace="$(mktemp -d -t page-redesign-self-test.XXXXXX)"
    # shellcheck disable=SC2064 # expand the path now: the trap must survive the local going out of scope.
    trap "rm -rf '$workspace'" EXIT
    mkdir -p "$workspace/empty" "$workspace/out"

    expect_exit 'no argument is a usage error' 2
    expect_exit 'a missing output directory is a usage error' 2 "$workspace/empty"
    expect_exit 'an unknown option is a usage error' 2 "$workspace/empty" "$workspace/out" --nonsense
    expect_exit 'a non-directory input is a usage error' 2 "$workspace/nope" "$workspace/out"
    expect_exit 'a malformed viewport is a usage error' 2 \
        "$workspace/empty" "$workspace/out" --viewport huge
    # The coverage guarantee rests on this one: an empty directory renders nothing, and reporting
    # that as success would let a proposal claim previews it never produced.
    expect_exit 'a directory with no mockup refuses to report success' 3 \
        "$workspace/empty" "$workspace/out"

    if [ "$failures" -gt 0 ]; then
        echo "$PROG: $failures failure(s)" >&2
        return 4
    fi

    echo "$PROG: --self-test PASS"
    return 0
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

render "$@"
