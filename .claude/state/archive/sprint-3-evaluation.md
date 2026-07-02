# Sprint 3 Contract Evaluation: Pre-Flight Gate System

**Evaluator**: Independent sceptical sub-agent
**Default**: FAIL if in doubt
**Date**: 2026-04-06

---

## VERDICT: FAIL

The contract is close but has **5 issues that must be resolved before BUILD**. Three are design flaws that would undermine the system's purpose. Two are specification gaps that would cause ambiguity during implementation.

---

## 1. COMPLETENESS

### Spec vs. Contract Coverage

| Spec Requirement | Contract Deliverable | Status |
|---|---|---|
| Pre-flight gate hook on Write/Edit | D4 | Covered |
| MCQ with 4 questions | D2 | Covered |
| Distractor pool (4 files, 100+ entries) | D1 (50+ entries) | **MISMATCH** |
| Validation (exact match, consumed on use) | D3 | Covered |
| Watcher slot enhancements (SCOPE, OUT OF SCOPE, MISTAKES TO AVOID) | D5 | Covered |
| Question advancement on checklist tick / slot update | **NONE** | **MISSING** |
| Exemption for .claude/pre-flight/ | D4 | Covered |
| Registry updates | D6 | Covered |

**Issue 1 (MINOR): Distractor pool size mismatch.** The spec says "100+ entries each" (line 54). The contract says "50+ entries" (D1, line 8). The evaluation criteria also say "50+ entries" (line 26). This is a deliberate downscoping that seems reasonable for a first sprint, but it contradicts the spec. Either the spec should be amended or the contract should acknowledge the deviation explicitly.

**Issue 2 (INFO): Question advancement is unspecified.** The spec (lines 62-68) says questions regenerate when a checklist item is ticked, the challenge is consumed, or the watcher slot is updated. The contract's consumed-on-use pattern (D3: delete files after validation) naturally handles regeneration on each new write. The checklist-tick and slot-update triggers are not explicitly addressed, but since the generator re-reads the watcher slot fresh each time it runs, this is implicitly handled. Not a blocker, but worth noting.

### Evaluation Criteria vs. Contract Verification Criteria

| Eval Criterion | Contract V# | Status |
|---|---|---|
| Hook fires on Write/Edit | V9, V12 | Covered |
| .claude/pre-flight/ exempted | V10 | Covered |
| Blocks with exit 2 | V12 | Covered |
| Generates challenge.md with 4 MCQ | V3 | Covered |
| Validates response.md (exact match) | V6, V7 | Covered |
| Response deleted after validation | V6 | Covered |
| Re-derives answers from watcher (no stored key) | **NONE** | **CONTRADICTED** |
| Q1-Q4 correct answer sources | V5 | Partial |
| Q4 "none" case | Not in V# | **MISSING** |
| Correct answer position randomized | V5 (implicit) | Weak |
| Pool exists with 50+ entries | V1 | Covered |
| 3 distractors via shuf | V2 (no-dupes only) | Weak |
| Different distractors on consecutive challenges | Not in V# | **MISSING** |
| Watcher slot template sections | V14 | Covered |
| Coexists with pre-write-gate.sh | V13 | Covered |
| Coexists with post-write-check.sh | Not explicit | **MISSING** |
| Gate doesn't fire on Read/Bash/Grep/Glob | Implicit (matcher) | Covered by design |
| Cron unchanged | Not in V# | Covered by scope boundaries |
| SCRIPT_REGISTRY updated | V15 | Covered |

---

## 2. FEASIBILITY

### challenge-key.txt: CRITICAL DESIGN FLAW

**Issue 3 (CRITICAL): The challenge-key.txt approach directly contradicts the spec and creates a trivial cheating vector.**

The spec explicitly states (line 60): "No stored answer key -- correct answers re-derived from watcher slot at validation time."

The contract's D2 (line 19) introduces `challenge-key.txt` containing the 4 correct letters. D3 (line 25) then reads this key file for validation.

This is a **fundamental contradiction** with the spec's core security model. The spec intentionally avoids a stored key because:

1. **Cheating vector**: The agent can Read `.claude/pre-flight/challenge-key.txt`, see "B D A C", and write those letters to response.md without reading or understanding the questions. This completely defeats the purpose of the gate.
2. **The spec's alternative is sound**: Re-derive correct answers from the watcher slot at validation time. The validator can re-extract `**Task**:` line, first unchecked step, etc., and compare the agent's selected option text against the known-correct text. This is deterministic and does not require a key file.

**However**, there is a counter-argument: re-derivation at validation time is more complex and fragile. If the watcher slot changes between challenge generation and validation, the answers could become stale. The key file approach is simpler.

**Resolution required**: Either:
- (a) Follow the spec: no key file, re-derive at validation time. Accept the complexity.
- (b) Amend the spec: allow a key file BUT make it unreadable by the agent. Since all files are readable, this means storing it outside the project directory (e.g., `/tmp/pre-flight-key-$(date +%s).txt` with a randomized name) or encoding it in a way that requires the validator script to decode.
- (c) Accept the cheating vector as a known limitation for sprint 3, document it, and plan hardening for sprint 4.

Option (c) is pragmatic but must be explicitly acknowledged in the contract.

### Dependencies

- D4 depends on D2 and D3 (hook calls both scripts) -- **correct ordering, no circular dependency**.
- D2 depends on D1 (generator reads distractor pool) -- **correct**.
- D4 depends on D5 (hook reads watcher slot sections) -- the generator needs `## MISTAKES TO AVOID` and `## OUT OF SCOPE` sections. If these are empty or missing, the generator must handle it. The contract's D2 says "Extracts: ... mistakes to avoid / out of scope" but does not specify fallback behavior.

**Issue 4 (MODERATE): Generator fallback for missing watcher sections is unspecified.** What happens if an agent claims a watcher slot but does not fill in `## MISTAKES TO AVOID` or `## OUT OF SCOPE`? The spec (line 48) says: "If 'none': correct answer is 'None identified', distractors are fabricated constraints." The contract's D2 does not mention this fallback. This will cause ambiguity during BUILD.

### Bash feasibility

All deliverables are implementable in bash (Layer 2). The operations are: file reading, grep/sed extraction, shuf for randomization, file writing, exit codes. No LLM needed. **PASS.**

---

## 3. VERIFICATION

### Are the 16 criteria testable deterministically?

| V# | Deterministic? | Notes |
|---|---|---|
| 1 | YES | `wc -l` is deterministic |
| 2 | YES | `sort | uniq -d` is deterministic |
| 3 | YES | Run script, check output file exists with expected structure |
| 4 | YES | Check file format |
| 5 | YES | Cross-reference challenge content against watcher slot |
| 6 | YES | Run with correct answers, check exit code and file deletion |
| 7 | YES | Run with wrong answers, check exit code and stderr |
| 8 | YES | Run without response.md, check exit code |
| 9 | YES | `bash -n` is deterministic |
| 10 | YES | Testable with mock path |
| 11 | YES | Testable with mock watcher path |
| 12 | YES | Testable without response.md |
| 13 | YES | Inspect settings.json hook array ordering |
| 14 | YES | `grep` for section headers |
| 15 | YES | `jq` count |
| 16 | YES | `bash -n` on each script |

All 16 criteria are deterministically testable. **PASS.**

### Gaps in verification criteria

**Issue 5 (MODERATE): Several eval criteria have no corresponding verification criterion.**

- **Q4 "none" case**: The evaluation criteria (line 19) explicitly require handling the "none" case. No verification criterion tests this.
- **Correct answer position randomization**: The evaluation criteria (line 20) require randomized position. No verification criterion tests that the correct answer is not always in the same position across multiple runs.
- **Distractor rotation**: The evaluation criteria (line 27) require different distractors on consecutive challenges. No verification criterion tests this.
- **Post-write-check.sh coexistence**: The evaluation criteria (line 37) require coexistence with post-write-check.sh. No verification criterion tests this (V13 only checks pre-write-gate.sh ordering).

These are not blocking, but they mean the verification is incomplete -- things could pass all 16 criteria and still fail evaluation.

---

## 4. RISKS

### Hook conflict with pre-write-gate.sh

The contract (D4, line 39) says "Must run AFTER pre-write-gate.sh". Looking at settings.json, the existing PreToolUse entry matches `Write|Edit|Agent`. The new hook would need to be a second entry in the PreToolUse array. Claude Code hook execution order within the same event is array-order dependent -- the new hook entry must come AFTER the existing one.

**Risk**: The existing pre-write-gate.sh matches `Agent` too. The new pre-flight-gate.sh (D4 line 32) matches only `Write|Edit`. This is correct -- the Agent tool should not trigger the pre-flight gate. But the contract should explicitly state that the Agent tool is excluded from the pre-flight gate. Currently the contract says "PreToolUse on Write|Edit" which is correct but implicit.

**Risk level**: LOW. The implementation is straightforward if the builder puts the new entry second in the array.

### Hook exemption for .claude/pre-flight/

The contract (D4, line 33) exempts `.claude/pre-flight/`. The hook receives tool input via stdin or environment variables in Claude Code's hook protocol. The hook must parse the target file path from the tool call to determine if it's in the exempted directory.

**Risk**: How does the hook get the target file path? Claude Code PreToolUse hooks receive JSON on stdin with tool_input containing the file path. The contract does not specify how the hook extracts this. The existing pre-write-gate.sh does NOT parse the target file path -- it uses a simple counter. The new hook needs a different approach.

**Risk level**: MODERATE. This is implementable but the contract should specify the mechanism (e.g., `jq '.tool_input.file_path'` from stdin).

### Watcher slot writes

The contract (D4, line 34) adds an exemption for watcher slot writes (`$HOME/.openclaw/watchers/`). This is good -- it means the agent can update its watcher without being blocked by the pre-flight gate. This was NOT in the spec but is a necessary addition. **Good catch by the contract author.**

### No watcher claimed

If no watcher is claimed, the generator (D2) cannot extract task/steps/scope. The contract says the generator "finds slot via REGISTRY.json project match" (D2, line 13). If no slot matches, what happens?

The existing pre-write-gate.sh already blocks writes after 2 free writes if no watcher is claimed. So in practice, the pre-flight gate would never fire without a watcher (because pre-write-gate.sh blocks first). But if pre-write-gate.sh is somehow bypassed or the agent is within 2 free writes, the generator could fail.

**Risk level**: LOW. The ordering (pre-write-gate.sh runs first) provides implicit protection, but the generator should still fail gracefully with a clear error message rather than producing a broken challenge.

### Distractor pool files don't exist yet

The generator (D2) depends on the distractor pool (D1). If D1 is not created first, D2 will fail. The contract lists D1 before D2, implying build order, but does not explicitly state the dependency.

**Risk level**: LOW. Any competent builder will create D1 first, but the contract should state the build order.

---

## 5. SCOPE

### Over-engineering concerns

- The 4-question MCQ on every single write is aggressive. For a first sprint, this is acceptable as a proof of concept, but it will be extremely annoying in practice. The spec acknowledges this is the design, so the contract is faithful.
- The distractor pool with 50+ entries per file is reasonable for sprint 3.

### Under-specification concerns

- **Hook input parsing**: How does the hook extract the target file path from the tool call? Not specified.
- **Generator error handling**: What if watcher slot is claimed but empty/malformed? Not specified.
- **Q4 fallback**: "None identified" case is in the spec and eval criteria but not in the contract.
- **Response.md format**: What format should the agent write? The contract says "4 answers" but does not specify the expected format (e.g., "Q1: B\nQ2: D\nQ3: A\nQ4: C" or just "B D A C" or something else).

---

## SUMMARY OF ISSUES

| # | Severity | Issue | Resolution Required |
|---|----------|-------|-------------------|
| 1 | MINOR | Distractor pool size mismatch (spec says 100+, contract says 50+) | Acknowledge deviation or amend spec |
| 2 | INFO | Question advancement implicitly handled but not explicitly stated | No action needed |
| 3 | **CRITICAL** | challenge-key.txt contradicts spec's "no stored key" and creates trivial cheating vector | Must resolve: remove key file, secure it, or explicitly accept risk |
| 4 | MODERATE | Generator fallback for missing/empty MISTAKES TO AVOID and OUT OF SCOPE sections unspecified | Add fallback behavior to D2 |
| 5 | MODERATE | 4 evaluation criteria have no corresponding verification criterion (Q4 none case, position randomization, distractor rotation, post-write-check coexistence) | Add verification criteria or accept gaps |

### Additional risks noted (not blocking but should be documented):
- Hook input parsing mechanism unspecified (how to get target file path)
- Response.md format unspecified
- Build order dependency (D1 before D2) implicit but not stated

---

## VERDICT: FAIL

**Reason**: Issue #3 (challenge-key.txt) is a critical design flaw that directly contradicts the spec's security model and creates a trivial bypass. An agent can simply `Read .claude/pre-flight/challenge-key.txt` to get all correct answers without engaging with the questions. This defeats the entire purpose of the pre-flight gate system.

Issues #4 and #5 are moderate gaps that would cause ambiguity during BUILD and incomplete verification during EVALUATE.

**To proceed to BUILD**, the contract must:
1. Resolve the challenge-key.txt contradiction (pick one of options a/b/c from Issue #3 above)
2. Specify generator fallback for missing watcher sections (Issue #4)
3. Add verification criteria for Q4 none case, position randomization, distractor rotation, and post-write-check coexistence (Issue #5)
4. Specify response.md expected format
5. Specify how the hook extracts the target file path from tool input
