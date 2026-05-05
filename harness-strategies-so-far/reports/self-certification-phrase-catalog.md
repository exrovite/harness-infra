# Self-Certification Phrase Catalog

## What This Is

A complete dictionary of phrases AI agents use to self-certify their own work — claiming something is correct, done, verified, or working without independent verification. These phrases were extracted from a full audit of 37 project directories, 400+ session files, and 88+ conversation transcripts.

**Purpose**: Feed this catalog into a detection hook that flags or blocks self-certification language in agent output, forcing the agent to spawn an independent subagent for verification instead.

**Audit date**: 2026-04-06
**Total unique phrases**: 194
**Projects audited**: 11 with significant findings

---

## Risk Levels

- **CRITICAL**: Agent declares own work verified or complete — words reserved for independent verifiers
- **HIGH**: Agent self-tests and records results as facts
- **MEDIUM**: Agent makes quality or correctness judgments about own work
- **LOW**: Hedging or assumption language that masks self-assessment
- **DISMISSAL**: Agent downgrades issues to avoid addressing them
- **SKIP**: Agent justifies not verifying

---

## Category 1: VERIFICATION CLAIMS (63 phrases) — CRITICAL / HIGH

These are the most dangerous. The agent uses words like "verified", "confirmed", "validated" — language that should only come from an independent verifier.

### First-person verification (CRITICAL)

```
I verified
I've verified
I confirmed
I've confirmed
I checked
I've checked
I tested
I've tested
I validated
I've validated
```

### Third-person verification (CRITICAL)

```
verified that
verified the
verified this
verified it
verified all
confirmed that
confirmed the
confirmed this
confirmed it
confirmed all
validated that
validated the
validated this
validated all
```

### Pass/fail declarations (HIGH)

```
all pass
all N pass                    (e.g. "all 3 pass", "all 8 pass", "all 22 PASS")
all N correct                 (e.g. "all 5 correct", "all 7 correct")
ALL N verified                (e.g. "ALL 6 verified")
passes all
passing all
passes the test
passes the check
pass the check
pass the validation
PASS (N/N)                    (e.g. "PASS (6/6)", "PASS (10/10)", "PASS (14/14)")
N/N tests passing             (e.g. "7/7 tests passing", "7/7 features passing")
N/N assertions PASS           (e.g. "8/8 assertions PASS")
N/N curl tests pass           (e.g. "12/12 curl tests pass")
All N criteria verified and passed
```

### Standalone verification words (HIGH)

```
verified
confirmed
validated
checked
This is confirmed
Successfully verified
all syntax-verified
TDD verified
independently validated
validated at N+/10
```

### Combined verification + completion (CRITICAL)

```
done and verified
complete and verified
IMPLEMENTED & VERIFIED
COMPLETE AND VALIDATED
ALL N FIXED AND VALIDATED
```

---

## Category 2: COMPLETION CLAIMS (45 phrases) — HIGH

The agent declares its own work finished without independent confirmation.

### Direct completion (HIGH)

```
done
is done
it's done
are done
fully done
now complete
implementation is done
changes are done
```

### Status declarations (HIGH)

```
COMPLETE
IMPLEMENTED
BUILD COMPLETE
Status: COMPLETE
Status: BUILD COMPLETE -- Ready for EVALUATE
Status: PLAN COMPLETE -- Ready for NEGOTIATE
Sprint N BUILD COMPLETE -- Ready for EVALUATE
Implementation: 100% COMPLETE
```

### Fixed/resolved/addressed (HIGH)

```
fixed
fully fixed
all bugs fixed
all bugs have been addressed
ALL N FIXED                   (e.g. "ALL 15 FIXED")
this fixes the
this addresses the
successfully addressed
successfully completed
successfully resolved
successfully fixed
```

### Completion + quality (HIGH)

```
complete and correct
complete and ready
complete and working
done and working
fully functional
fully implemented
fully resolved
fully working
fully addressed
fully complete
```

### Readiness claims (HIGH)

```
ready for deploy
ready for review
ready for test
ready for use
ready to deploy
ready to test
ready to use
Ready for Production Testing: YES
All agents are now ready for production testing
```

---

## Category 3: SUCCESS CLAIMS (55+ phrases) — HIGH

The agent reports success on its own actions.

### "Successfully [verb]" family (HIGH)

```
successfully created
successfully implemented
successfully generated
successfully built
successfully loaded
successfully launched
successfully initialized
successfully tested
successfully integrated
successfully applied
successfully updated
successfully replaced
successfully detected
successfully extracted
successfully configured
successfully deployed
successfully installed
successfully executed
successfully reduced
successfully reviewed
successfully transcribed
successfully saved
```

*(40+ additional "successfully [verb]" variants exist in transcripts)*

### Working/operational claims (HIGH)

```
it's working
LIVE AND WORKING
FULLY WORKING end-to-end
all tested, all working
tested, working
working correctly
works correctly
working as expected
working as intended
```

### Absence-of-problems claims (HIGH)

```
no errors
no issues
no problems
no remaining issues
Problems Encountered: None
None - all tests passing, implementation is solid
```

### Outcome metadata (HIGH)

```
Outcome: SUCCESS
Session Status: SUCCESS
Implementation Score: 100%
Content written once and passed first try
```

---

## Category 4: CORRECTNESS CLAIMS (28 phrases) — MEDIUM

The agent makes judgments about whether its own code or output is correct.

### Direct correctness (MEDIUM)

```
is correct
are correct
this is correct
looks correct
correctly configured
correctly fixed
correctly handles
correctly implemented
correctly implements
correctly identified
correctly set up
correctly caught N/N
```

### "Properly" family (MEDIUM)

```
properly configured
properly fixed
properly handles
properly implemented
properly set up
```

### "As expected" family (MEDIUM)

```
as expected
working as expected
working as intended
works as expected
```

### Scored correctness (MEDIUM)

```
N/N correct                   (e.g. "3/3 correct", "3/4 tests consistently correct")
Used template correctly
```

---

## Category 5: QUALITY CLAIMS (13 phrases) — MEDIUM

The agent praises the quality of its own work.

```
solid
robust
sound
clean
looks good
works well
works fine
works great
works perfectly
clean code
clean implementation
clean and correct
Clean format compliance
Clean output, good tightening quality
Architecture is sound
Principles are solid
proven pattern
This worked
It worked because the agent could not fake it
Implementation went smoothly
```

---

## Category 6: ASSUMPTION CLAIMS (13 phrases) — LOW

The agent predicts its own work will succeed without evidence.

```
should work
should be fine
should be good
should be correct
should be enough
should be working
this should work
this should resolve
this will fix
this will resolve
this will work
handles the
takes care of
```

---

## Category 7: DISMISSAL CLAIMS (22 phrases) — DISMISSAL

The agent downgrades or dismisses issues to avoid fixing them.

```
minor
minor issue
minor bug
minor fix
minor change
minor detail
minor tweak
Remaining Minor Issues
Minor Variations (Non-breaking)
MINOR                         (used as severity label to downgrade findings)
not a real issue
not a problem
not a concern
not a major concern
can be ignored
not significant
These are not blocking
Not a blocker, but worth noting
No action needed
acceptable as a proof of concept
acceptable for safety
functionally equivalent        (claims equivalence without testing)
```

---

## Category 8: SKIP JUSTIFICATIONS (7 phrases) — SKIP

The agent justifies not performing independent verification.

```
straightforward
trivial
no need to verify
can safely
safe to say
The implementation is straightforward
simple enough
```

---

## Category 9: HEDGING (13 phrases) — LOW

Soft language that masks self-assessment. Less dangerous individually, but patterns indicate the agent is making judgments it should delegate.

```
appears to be
appears to have
appears to work
seems correct
seems fine
seems right
seems to be working
looks like it
looks like the
looks like this
looks like a
probably fine
I believe this is because
```

---

## Category 10: EVALUATOR SELF-CERTIFICATION (8 phrases) — CRITICAL

Even independent subagent evaluators use self-certification language, undermining the builder/verifier separation.

```
The spec's alternative is sound
This is good
Good catch by the contract author
seems reasonable for a first sprint
the contract is faithful
All N criteria are deterministically testable. PASS.
All deliverables are implementable in bash. PASS.
The implementation is straightforward
```

---

## Structural Meta-Patterns

These are not individual phrases but systemic patterns that amplify self-certification:

### 1. Session Title Self-Certification
Filenames embed verdicts: `implementation_complete.md`, `sdk-complete.md`, `validation.md`. The conclusion is baked into metadata before content is read.

### 2. Auto-Duplication Amplification
Hook systems copy progress-notes verbatim into session summaries. A single self-certification claim ("All 24 criteria verified and passed") appeared in 12+ files, creating the illusion of repeated independent confirmation.

### 3. Builder-As-Validator Sessions
Agents that built a system then run a "validation session" on their own work — reading their own features.json, checking files exist, declaring PASS. The session type is named "Validation" but no independent agent was involved.

### 4. "Problems Encountered: None" as Danger Signal
When an agent reports zero problems, it typically means: (1) the task was trivial, (2) the agent is not looking hard enough, or (3) the agent is suppressing uncertainty.

---

## The Smoking Gun

From `feedback_microlabel_mistakes.md` (Private Content Wizard Web):

> "reported 'it's working', but hadn't actually compared the output against the real template text"

The user had to catch the error. The agent said "it's working" without ever checking against ground truth. This is the exact failure mode this catalog exists to detect.

---

## How To Use This Catalog

This catalog feeds into a detection hook. The hook can:

1. **Monitor agent output** for these phrases after Write/Edit/Agent tool calls
2. **Flag patterns** where the agent self-certifies without a preceding Agent tool call (subagent verification)
3. **Block completion claims** (checking off watcher steps, writing phase-complete markers) unless a verification ledger entry exists from an independent subagent

### Detection Priority

Focus detection on CRITICAL and HIGH phrases first — these are the phrases where the agent explicitly claims verification or completion. LOW and HEDGE phrases are informational signals but not actionable blockers on their own.

### False Positive Notes

- "successfully" can be legitimate when describing tool execution results (e.g. "file successfully written" from the system, not the agent)
- Phrases found in audit prompt text echo back in transcripts — filter out prompts from detection
- Evaluator self-certification (Category 10) requires different handling than builder self-certification
