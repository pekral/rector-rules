#!/usr/bin/env bash
# The globals this library sets are read by the script that sources it.
# shellcheck disable=SC2034
# domain-vocabulary.sh — shared word lists for the sensitive domains.
#
# Sourced, not executed, by `classify-risk.sh` (which tier a change gets) and
# `gate-context.sh` (which project knowledge a task needs). Both must agree on
# what an auth, a data-loss, or a concurrency signal is, so the word lists
# exist here once. A word added here changes both verdicts.
#
# Every pattern is lower case. The caller lower-cases its input and matches it
# one line at a time, so `(^|/)` and `$` anchor to one path or one line.
# Words only one caller needs stay in that caller.

AUTH_RE='auth|login|logout|password|credential|secret|token|jwt|oauth|saml|session|crypt|cipher|(^|/)policies/|policy|(^|/)gates?/|permission|privilege|(^|/)acl|(^|/)roles?/|admin|guard|csrf|cors|sanctum|passport|2fa|mfa'
DATA_RE='(^|/)migrations?/|migration|\.sql$|(^|/)schema[./]|truncate|drop_'
QUEUE_RE='(^|/)jobs?/|(^|/)queues?/|queue|worker|(^|/)listeners?/|(^|/)events?/|lock|mutex|semaphore|concurren|cache|redis|schedul|cron|broadcast'
