# finding-defs.jq — the jq definitions that extract-findings.sh and review-state.sh share.
#
# A jq module, never run on its own. Each script loads it from its own directory with
# `jq -L "$HERE" 'include "finding-defs"; …'`. It is program text this package ships; no report, state, or
# other input contributes to it.

def isstr($v; $re): ($v | type) == "string" and ($v | test($re));
def severity_rank: {"low": 1, "medium": 2, "high": 3, "critical": 4}[.] // 0;
def status_rank: {"dismissed": 1, "resolved": 2, "needs-verification": 3, "new": 4, "confirmed": 5}[.] // 0;
