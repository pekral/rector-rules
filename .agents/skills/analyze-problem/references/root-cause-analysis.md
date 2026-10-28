# Root Cause Analysis

## Symptom vs Root Cause
- Symptom = what you see
- Root cause = why

## Valid Root Cause
Must:
- explain behavior
- be testable
- be reproducible

## When to Stop
- explains all verified facts
- is verified: reproduced, or traced on the real code path
- every other candidate is ruled out by evidence, or listed as not verified with the check that settles it

## Cause vs Damage
- Cause = the code path that produces the wrong result
- Damage = the records that path already wrote and that are still wrong
- Both are part of the resolution; the cause is fixed first, the damage repaired after
- Verify the damage against the storage: a count plus a predicate, never a guess

## Pitfalls
- stopping too early
- ignoring evidence
- naming the cause and never asking what it already wrote
- repairing the data while the cause is still live
