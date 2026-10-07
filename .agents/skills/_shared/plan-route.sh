#!/usr/bin/env bash
# plan-route.sh — turn a risk tier and a few flags into the run's execution plan.
#
# Why this exists
#   The tier was already decided by a script (`classify-risk.sh`), but the
#   sequence it implies — which specialist runs, in which mode, at which model
#   tier, and where the deterministic steps sit — was left to the orchestrator
#   to reconstruct from prose on every run. That reasoning is the same every
#   time for the same inputs, so it is code: a plan the orchestrator reads and
#   executes rather than a workflow it re-derives.
#
#   It also makes the routing contract testable. A prose sequence can only be
#   checked by reading it; this one is asserted.
#
# Usage
#   plan-route.sh --tier <FAST|STANDARD|CRITICAL> [options]
#   plan-route.sh --self-test
#
#   --tier <t>                 the classifier's verdict (required)
#   --thorough                 run the complete pipeline regardless of the tier
#   --hotfix                   the caller declared a production emergency: the
#                              review stage runs in its narrowed `review_hotfix`
#                              mode and the plan records `"hotfix": true`. It
#                              never changes the tier, so a sensitive-area force
#                              still buys every stage it would otherwise buy.
#   --security-analysis        the task carries a cyber-security question, so the
#                              pre-implementation analysis stage applies
#   --redesign                 the task asks for a page redesign, so `michelangelo`
#                              produces the layout specification the implementer
#                              then builds. Tier-independent by design: a
#                              redesign is a kind of work, not a level of risk.
#   --runtime-acceptance       the change alters behaviour a user can observe, so
#                              `raphael` exercises the running application.
#                              Tier-independent by design: a user-visible change
#                              is checked in the UI at every level of risk.
#   --escalated-from <tier>    a post-implementation re-classification raised the
#                              tier from this one; emits the stages the earlier
#                              plan had already skipped
#   --tracker <yes|no>         whether a source tracker item exists (default yes);
#                              `no` drops the reporting stage, which has no
#                              destination
#
# Output (stdout, JSON)
#   {
#     "tier": "STANDARD",
#     "thorough": false,
#     "escalated_from": null,
#     "stages": [
#       { "type": "agent", "role": "donatello", "mode": "implementation", "model_tier": "default" },
#       { "type": "deterministic_classification", "mode": "post_implementation" },
#       { "type": "agent", "role": "leonardo", "mode": "review", "model_tier": "default" },
#       { "type": "deterministic_validation", "mode": "scoped" },
#       { "type": "deterministic_reporting", "mode": "completion" }
#     ]
#   }
#
#   Three stage types, and the split between them is the whole point:
#     - `agent`                        — an LLM dispatch, the expensive thing
#     - `deterministic_validation`     — `run-validation.sh` over a manifest
#     - `deterministic_classification` — `classify-risk.sh` over the real diff
#     - `deterministic_reporting`      — the templated completion report
#
# Exit codes
#   0  a plan was produced
#   1  usage error (missing or unknown tier, unknown flag)
set -euo pipefail

PROG="${0##*/}"

usage() {
  cat >&2 <<'EOF'
Usage: plan-route.sh --tier <FAST|STANDARD|CRITICAL> [--thorough] [--hotfix]
                     [--security-analysis] [--redesign] [--runtime-acceptance]
                     [--escalated-from <tier>] [--tracker <yes|no>]
       plan-route.sh --self-test

Prints the run's execution plan as JSON.
EOF
}

safe_display() {
  printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]' | cut -c1-120
}

normalise_tier() {
  local value
  value="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  case "$value" in
  FAST | STANDARD | CRITICAL) printf '%s' "$value" ;;
  THOROUGH) printf 'CRITICAL' ;;
  *) return 1 ;;
  esac
}

tier_rank() {
  case "$1" in
  FAST) printf '0' ;;
  STANDARD) printf '1' ;;
  *) printf '2' ;;
  esac
}

STAGES=()

stage_agent() {
  STAGES+=("{ \"type\": \"agent\", \"role\": \"$1\", \"mode\": \"$2\", \"model_tier\": \"$3\" }")
}

stage_deterministic() {
  STAGES+=("{ \"type\": \"$1\", \"mode\": \"$2\" }")
}

plan() {
  local tier="" thorough=0 hotfix=0 security=0 redesign=0 runtime=0 escalated_from="" tracker="yes"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --tier)
      [[ $# -ge 2 ]] || { usage; return 1; }
      if ! tier="$(normalise_tier "$2")"; then
        echo "$PROG: unknown tier: $(safe_display "$2")" >&2
        return 1
      fi
      shift 2
      ;;
    --thorough)
      thorough=1
      shift
      ;;
    --hotfix)
      hotfix=1
      shift
      ;;
    --security-analysis)
      security=1
      shift
      ;;
    --redesign)
      redesign=1
      shift
      ;;
    --runtime-acceptance)
      runtime=1
      shift
      ;;
    --escalated-from)
      [[ $# -ge 2 ]] || { usage; return 1; }
      if ! escalated_from="$(normalise_tier "$2")"; then
        echo "$PROG: unknown tier: $(safe_display "$2")" >&2
        return 1
      fi
      shift 2
      ;;
    --tracker)
      [[ $# -ge 2 ]] || { usage; return 1; }
      case "$2" in
      yes | no) tracker="$2" ;;
      *)
        echo "$PROG: --tracker takes yes or no" >&2
        return 1
        ;;
      esac
      shift 2
      ;;
    *)
      echo "$PROG: unknown argument: $(safe_display "$1")" >&2
      usage
      return 1
      ;;
    esac
  done

  [[ -n "$tier" ]] || { usage; return 1; }

  # `--thorough` is an escalation, never a de-escalation: it runs the complete
  # pipeline, so it resolves to CRITICAL whatever the classifier said.
  if [[ "$thorough" -eq 1 ]]; then
    tier=CRITICAL
  fi

  local model_tier="default"
  [[ "$tier" == "CRITICAL" ]] && model_tier="escalated"

  # A declared hotfix narrows what the reviewer reports; it never removes the
  # reviewer, and it never moves the tier. The mode travels in the plan so the
  # dispatch cannot forget it and cannot invent it.
  local review_mode="review"
  [[ "$hotfix" -eq 1 ]] && review_mode="review_hotfix"

  STAGES=()

  # --- Re-entry after a post-implementation escalation -----------------------
  #
  # The earlier plan already ran implementation, so replaying it would redo the
  # work. What the raised tier owes is the stages the lower tier skipped, and
  # nothing else.
  if [[ -n "$escalated_from" ]]; then
    if [[ "$(tier_rank "$escalated_from")" -ge "$(tier_rank "$tier")" ]]; then
      # Not an escalation. Emitting the full plan here would re-run the whole
      # run; emitting nothing says plainly that there is nothing owed.
      STAGES=()
    else
      [[ "$tier" == "CRITICAL" ]] && stage_deterministic deterministic_validation pre_review
      stage_agent leonardo "$review_mode" "$model_tier"
      stage_deterministic deterministic_validation scoped
    fi
    emit "$tier" "$thorough" "$escalated_from" "$hotfix"
    return 0
  fi

  # --- The normal plan -------------------------------------------------------
  if [[ "$security" -eq 1 && "$tier" == "CRITICAL" ]]; then
    stage_agent leonardo security_analysis "$model_tier"
  fi

  # The redesign produces the specification the implementation builds from, so it
  # sits before `donatello` for the same reason the security analysis does. It is
  # not gated on the tier: a page can need a redesign at any level of risk.
  if [[ "$redesign" -eq 1 ]]; then
    stage_agent michelangelo redesign default
  fi

  stage_agent donatello implementation "$model_tier"

  # The diff only exists once the implementation lands, so the re-classification
  # that can raise the tier sits here and nowhere earlier.
  stage_deterministic deterministic_classification post_implementation

  if [[ "$tier" == "CRITICAL" ]]; then
    stage_deterministic deterministic_validation pre_review
  fi

  if [[ "$tier" != "FAST" ]]; then
    stage_agent leonardo "$review_mode" "$model_tier"
  fi

  # Every tier validates, FAST included: it is the tier's only gate, so it is
  # the one stage that is never conditional.
  stage_deterministic deterministic_validation scoped

  # The acceptance pass is not gated on the tier: a change a user can observe is
  # checked in the running application at every level of risk. The re-entry plan
  # above never adds it, because the lower tier's plan already carried it.
  if [[ "$runtime" -eq 1 ]]; then
    stage_agent raphael acceptance default
  fi

  if [[ "$tracker" == "yes" ]]; then
    stage_deterministic deterministic_reporting completion
  fi

  emit "$tier" "$thorough" "" "$hotfix"
  return 0
}

emit() {
  local tier="$1" thorough="$2" escalated_from="$3" hotfix="${4:-0}" first=1 stage

  printf '{\n'
  printf '  "tier": "%s",\n' "$tier"
  printf '  "thorough": %s,\n' "$([[ "$thorough" -eq 1 ]] && printf 'true' || printf 'false')"
  printf '  "hotfix": %s,\n' "$([[ "$hotfix" -eq 1 ]] && printf 'true' || printf 'false')"
  if [[ -n "$escalated_from" ]]; then
    printf '  "escalated_from": "%s",\n' "$escalated_from"
  else
    printf '  "escalated_from": null,\n'
  fi
  printf '  "stages": ['
  for stage in ${STAGES[@]+"${STAGES[@]}"}; do
    [[ "$first" -eq 1 ]] || printf ','
    first=0
    printf '\n    %s' "$stage"
  done
  [[ "$first" -eq 1 ]] || printf '\n  '
  printf ']\n'
  printf '}\n'
}

self_test() {
  local failures=0 script
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$PROG"

  # Assert the exact role/type sequence — a plan that contains the right stages
  # in the wrong order routes a review before the code it reviews exists.
  expect_sequence() {
    local label="$1" expected="$2"
    shift 2
    local out actual
    if ! out="$("$script" "$@" 2>&1)"; then
      printf 'FAIL  %-52s script exited non-zero: %s\n' "$label" "$out" >&2
      failures=$((failures + 1))
      return 0
    fi
    actual="$(printf '%s' "$out" | jq -r '[.stages[] | if .type == "agent" then "\(.role):\(.mode):\(.model_tier)" else .type + ":" + .mode end] | join(" -> ")')"
    if [[ "$actual" != "$expected" ]]; then
      printf 'FAIL  %-52s\n  expected %s\n  got      %s\n' "$label" "$expected" "$actual" >&2
      failures=$((failures + 1))
      return 0
    fi
    printf 'ok    %-52s %s\n' "$label" "$actual"
  }

  expect_field() {
    local label="$1" expected="$2" filter="$3"
    shift 3
    local out actual
    if ! out="$("$script" "$@" 2>&1)"; then
      printf 'FAIL  %-52s script exited non-zero: %s\n' "$label" "$out" >&2
      failures=$((failures + 1))
      return 0
    fi
    actual="$(printf '%s' "$out" | jq -r "$filter")"
    if [[ "$actual" != "$expected" ]]; then
      printf 'FAIL  %-52s expected %s, got %s\n' "$label" "$expected" "$actual" >&2
      failures=$((failures + 1))
      return 0
    fi
    printf 'ok    %-52s %s\n' "$label" "$actual"
  }

  expect_exit() {
    local label="$1" expected="$2"
    shift 2
    local actual
    set +e
    "$script" "$@" >/dev/null 2>&1
    actual=$?
    set -e
    if [[ "$actual" -eq "$expected" ]]; then
      printf 'ok    %-52s exit %s\n' "$label" "$actual"
    else
      printf 'FAIL  %-52s expected exit %s, got %s\n' "$label" "$expected" "$actual" >&2
      failures=$((failures + 1))
    fi
  }

  local IMPL='donatello:implementation:default'
  local RECLASS='deterministic_classification:post_implementation'
  local VALIDATE='deterministic_validation:scoped'
  local REPORT='deterministic_reporting:completion'

  # FAST is the whole point of the mechanism: exactly one LLM dispatch.
  expect_sequence 'FAST runs one agent and validates deterministically' \
    "$IMPL -> $RECLASS -> $VALIDATE -> $REPORT" --tier FAST

  expect_sequence 'STANDARD adds the review at the default model tier' \
    "$IMPL -> $RECLASS -> leonardo:review:default -> $VALIDATE -> $REPORT" --tier STANDARD

  expect_sequence 'CRITICAL escalates the model and validates before review' \
    "donatello:implementation:escalated -> $RECLASS -> deterministic_validation:pre_review -> leonardo:review:escalated -> $VALIDATE -> $REPORT" \
    --tier CRITICAL

  expect_sequence 'CRITICAL with a security question analyses first' \
    "leonardo:security_analysis:escalated -> donatello:implementation:escalated -> $RECLASS -> deterministic_validation:pre_review -> leonardo:review:escalated -> $VALIDATE -> $REPORT" \
    --tier CRITICAL --security-analysis

  # The security analysis belongs to CRITICAL. A STANDARD task that mentions
  # security is routed by the classifier, which forces CRITICAL on a real
  # security surface — so a STANDARD plan never carries the stage.
  expect_sequence 'STANDARD never buys the upfront security analysis' \
    "$IMPL -> $RECLASS -> leonardo:review:default -> $VALIDATE -> $REPORT" --tier STANDARD --security-analysis

  expect_sequence 'runtime acceptance adds raphael on CRITICAL' \
    "donatello:implementation:escalated -> $RECLASS -> deterministic_validation:pre_review -> leonardo:review:escalated -> $VALIDATE -> raphael:acceptance:default -> $REPORT" \
    --tier CRITICAL --runtime-acceptance

  # A user-visible change is checked in the UI at every tier, not only CRITICAL.
  expect_sequence 'runtime acceptance adds raphael on FAST' \
    "$IMPL -> $RECLASS -> $VALIDATE -> raphael:acceptance:default -> $REPORT" --tier FAST --runtime-acceptance
  expect_sequence 'runtime acceptance adds raphael on STANDARD' \
    "$IMPL -> $RECLASS -> leonardo:review:default -> $VALIDATE -> raphael:acceptance:default -> $REPORT" --tier STANDARD --runtime-acceptance

  expect_sequence '--thorough runs the full pipeline over a FAST verdict' \
    "donatello:implementation:escalated -> $RECLASS -> deterministic_validation:pre_review -> leonardo:review:escalated -> $VALIDATE -> $REPORT" \
    --tier FAST --thorough

  expect_sequence 'no tracker means no reporting stage to run' \
    "$IMPL -> $RECLASS -> $VALIDATE" --tier FAST --tracker no

  # --- Post-implementation escalation ----------------------------------------
  #
  # The raised tier owes the stages the lower one skipped, never a replay of the
  # implementation it already has.
  expect_sequence 'FAST escalated to STANDARD owes the review' \
    "leonardo:review:default -> $VALIDATE" --tier STANDARD --escalated-from FAST
  expect_sequence 'FAST escalated to CRITICAL owes both validations and the review' \
    "deterministic_validation:pre_review -> leonardo:review:escalated -> $VALIDATE" \
    --tier CRITICAL --escalated-from FAST
  expect_sequence 'an unchanged tier owes nothing' '' --tier STANDARD --escalated-from STANDARD
  expect_sequence 'a tier cannot be lowered by re-classification' '' --tier FAST --escalated-from CRITICAL
  expect_sequence 'an escalation never replays the acceptance pass' \
    "deterministic_validation:pre_review -> leonardo:review:escalated -> $VALIDATE" \
    --tier CRITICAL --escalated-from FAST --runtime-acceptance

  # --- Redesign --------------------------------------------------------------
  #
  # The specification has to exist before the code that implements it, and the
  # need for one is a property of the task rather than of its risk — so the stage
  # appears at every tier, always ahead of the implementer.
  expect_sequence '--redesign designs before it implements' \
    "michelangelo:redesign:default -> $IMPL -> $RECLASS -> leonardo:review:default -> $VALIDATE -> $REPORT" \
    --tier STANDARD --redesign

  expect_sequence '--redesign applies on FAST too' \
    "michelangelo:redesign:default -> $IMPL -> $RECLASS -> $VALIDATE -> $REPORT" --tier FAST --redesign

  expect_sequence 'a CRITICAL redesign still analyses security first' \
    "leonardo:security_analysis:escalated -> michelangelo:redesign:default -> donatello:implementation:escalated -> $RECLASS -> deterministic_validation:pre_review -> leonardo:review:escalated -> $VALIDATE -> $REPORT" \
    --tier CRITICAL --security-analysis --redesign

  # A re-classification owes the stages the lower tier skipped. The redesign is not
  # one of them: it already ran, and replaying it would redo the work and hand the
  # implementer a second, competing specification.
  expect_sequence 'an escalation never replays the redesign' \
    "leonardo:review:default -> $VALIDATE" --tier STANDARD --escalated-from FAST --redesign

  # --- HOTFIX ----------------------------------------------------------------
  #
  # The mode narrows what the reviewer reports. A plan that dropped the reviewer
  # instead would ship an unreviewed emergency change, which is the opposite of
  # what the mode trades.
  expect_sequence '--hotfix narrows the review instead of removing it' \
    "$IMPL -> $RECLASS -> leonardo:review_hotfix:default -> $VALIDATE -> $REPORT" \
    --tier STANDARD --hotfix

  expect_sequence '--hotfix never lowers a CRITICAL tier' \
    "donatello:implementation:escalated -> $RECLASS -> deterministic_validation:pre_review -> leonardo:review_hotfix:escalated -> $VALIDATE -> $REPORT" \
    --tier CRITICAL --hotfix

  expect_sequence '--hotfix carries into a post-implementation escalation' \
    "leonardo:review_hotfix:default -> $VALIDATE" --tier STANDARD --escalated-from FAST --hotfix

  expect_field '--hotfix is recorded in the plan' 'true' '.hotfix' --tier STANDARD --hotfix
  expect_field 'an ordinary run records no hotfix' 'false' '.hotfix' --tier STANDARD

  # --- Usage -----------------------------------------------------------------
  expect_exit 'a missing tier is a usage error' 1
  expect_exit 'an unknown tier is a usage error' 1 --tier PARANOID
  expect_exit 'an unknown flag is a usage error' 1 --tier FAST --nonsense
  expect_exit 'a bad --tracker value is a usage error' 1 --tier FAST --tracker maybe

  if [[ "$failures" -gt 0 ]]; then
    echo "plan-route self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'plan-route self-test: PASS'
  return 0
}

if [[ "${1:-}" == "--self-test" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "$PROG: required tool not found: jq" >&2
    exit 2
  fi
  self_test
  exit $?
fi

plan "$@"
