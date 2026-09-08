#!/usr/bin/env bash
# seed-labels.sh — create or update the triage label taxonomy on the current
# GitHub repository: 4 priority labels and 10 type labels.
#
# Usage:
#   seed-labels.sh
#
# Behavior:
#   Every label is written with `gh label create --force`, which creates the
#   label when it is missing and updates its color and description when it
#   already exists. The script therefore converges the repository on the
#   taxonomy below no matter how many times it runs, and it never deletes a
#   label — labels outside the taxonomy are left untouched.
#
# Target repository:
#   The repository `gh` resolves from the current working directory. Run it
#   from inside the checkout you want to seed. It is resolved and PRINTED as
#   the first line of output, before the first write, so the transcript names
#   the repository the labels were written to instead of leaving it implicit.
#
# Exit codes:
#   0  every label in the taxonomy exists with the taxonomy color/description
#   1  wrong usage
#   2  required tool not found (gh)
#   3  a `gh` call failed — resolving the repository, or creating a label
#      (auth, permissions, API error)

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: seed-labels.sh

  Creates or updates the 4 priority labels and the 10 type labels of the
  triage taxonomy on the repository resolved from the current directory.
  Takes no arguments and deletes nothing.
EOF
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "seed-labels.sh: unexpected argument: $1" >&2
      usage
      exit 1
      ;;
  esac
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "seed-labels.sh: required tool not found: gh" >&2
  exit 2
fi

# name|color|description — the taxonomy, in triage order (priority first).
# Descriptions are the ones the repository already uses; they are data, not
# prose, so they stay verbatim in their original language.
LABELS=(
  "priority: critical|b60205|Blokuje jádro produktu nebo bezpečnostní incident — řeší se první"
  "priority: high|d93f0b|Bug s reálným dopadem — řeší se po critical"
  "priority: medium|fbca04|Nová funkcionalita / enhancement"
  "priority: low|0e8a16|Nice-to-have, testy, chore, docs, marketing, refactor, plány"
  "bug|d73a4a|Something isn't working"
  "enhancement|a2eeef|New feature or request"
  "documentation|0075ca|Improvements or additions to documentation"
  "question|d876e3|Further information is requested"
  "test|bfd4f2|Doplnění nebo oprava testů"
  "refactor|c5def5|Změna struktury bez změny chování"
  "chore|cfd3d7|Údržba repozitáře, release, konfigurace"
  "security|ee0701|Bezpečnostní téma (hardening, zranitelnost, capability model)"
  "marketing|f9d0c4|Launch, komunikace, obsah"
  "plan|5319e7|Plánovací meta-issue rozpadající větší záměr"
)

# Name the target before touching it: `gh` resolves the repository implicitly
# from the working directory, and this script writes 14 labels unconditionally.
if ! repo_nwo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>&1)"; then
  echo "seed-labels.sh: failed to resolve the target repository: $repo_nwo" >&2
  exit 3
fi

echo "seed-labels.sh: target repository: $repo_nwo"

for entry in "${LABELS[@]}"; do
  name="${entry%%|*}"
  rest="${entry#*|}"
  color="${rest%%|*}"
  description="${rest#*|}"

  if ! gh_error="$(gh label create "$name" --color "$color" --description "$description" --force 2>&1 >/dev/null)"; then
    echo "seed-labels.sh: failed to create or update label '$name': $gh_error" >&2
    exit 3
  fi

  echo "ok  $name (#$color)"
done

echo "seed-labels.sh: ${#LABELS[@]} labels are in sync with the taxonomy"
