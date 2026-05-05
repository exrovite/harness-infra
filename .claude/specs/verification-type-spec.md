# Sprint 6 Product Spec: Verification Type Enforcement

## Problem Statement

Sprint 5 forces agents to spawn verification subagents, but does not control what TYPE of verification is performed. Agents satisfy the gate by spawning a subagent that does code review — the weakest form of verification. For UI work, vision validation is needed. For scripts and APIs, functional testing is needed. Code review alone is insufficient.

## What the System Already Knows

On every Write/Edit, the PostToolUse hook receives `TOOL_INPUT_FILE_PATH`. This gives us the exact file being modified. File extensions deterministically indicate what type of work is being done and what verification is required.

## Solution: Prescriptive Verification Type Enforcement

### 1. File Write Tracker

Accumulate every file path written since the last verification into a rolling log: `.claude/state/unverified-writes.jsonl`. Each entry: `{"ts":"...","file":"path"}`. When a verification call is logged to the ledger, the tracker is consumed (cleared or archived).

### 2. Verification Type Classifier

A deterministic script that reads unverified-writes.jsonl, classifies each file by extension, and outputs the required verification types:

| File patterns | Required verification |
|---|---|
| `.html`, `.css`, `.scss`, `.jsx`, `.tsx`, `.vue`, `.svelte`, `.ejs` | `vision` |
| `.jsx`/`.tsx`/`.vue` + project has dev server | `browser` |
| `.sh`, `.bash`, `.py`, `.js`, `.ts` (non-UI) | `functional` |
| Test files (`*.test.*`, `*_test.*`, `*.spec.*`) | `functional` |
| Config (`.json`, `.yaml`, `.toml`, `.env`) | `functional` |
| `.md`, `.txt` only | `review` (sufficient) |

Output: JSON with required types, file list, and human-readable reason.

### 3. Prescriptive Block Messages

When any gate blocks (step gate, hardened gate, phase gate), it runs the classifier on unverified writes and includes the prescription in the block message:

```
BLOCKED: Verification required.

Files modified since last verification:
  - src/components/Dashboard.tsx  -> requires VISION validation
  - src/api/routes.ts             -> requires FUNCTIONAL test

Spawn verification subagent(s) covering:
  1. VISION: Screenshot Dashboard component, visually check layout
  2. FUNCTIONAL: Execute/curl routes.ts endpoints, check responses
```

### 4. Verification Type Matching

When agent-call-tracker detects a verification call, it classifies the prompt:
- Keywords: `screenshot`, `vision`, `visual`, `look at`, `render` -> `vision`
- Keywords: `browser`, `navigate`, `page`, `open`, `URL` -> `browser`
- Keywords: `run`, `execute`, `test`, `curl`, `output`, `functional` -> `functional`
- Keywords: `read`, `review`, `code`, `analyze` -> `review`

The ledger entry gets a `verification_type` field. The step/phase gates compare the ledger's `verification_type` against the classifier's `required` types.

Mismatch -> block with message saying what's still needed.

### 5. Strength Hierarchy

If the agent can't perform a required verification type (e.g., no browser available), it can satisfy the gate by using the next-strongest method:

`browser` > `vision` > `functional` > `review`

A `functional` test satisfies a `review` requirement. A `vision` check satisfies a `functional` requirement. But `review` alone never satisfies `vision` or `functional`.

## New Files

| File | Purpose |
|---|---|
| `~/.claude/scripts/classify-verification-need.sh` | Maps file extensions to required verification types |
| `.claude/state/unverified-writes.jsonl` | Rolling log of files written since last verification |

## Modified Files

| File | Change |
|---|---|
| `post-write-check.sh` | Append TOOL_INPUT_FILE_PATH to unverified-writes.jsonl |
| `agent-call-tracker.sh` | Classify prompt type, add verification_type to ledger, consume unverified-writes |
| `pre-flight-gate.sh` | Run classifier in block messages to show prescription |
| `validate-phase.sh` | Check verification type matches required types |

## Success Criteria

1. Every Write/Edit is logged to unverified-writes.jsonl with file path
2. Classifier correctly maps file extensions to verification types
3. Block messages include file-specific verification prescriptions
4. Ledger entries include verification_type field
5. Gates reject verification type mismatches (review-only for UI files)
6. Strength hierarchy allows stronger methods to satisfy weaker requirements
7. Existing Sprint 5 enforcement continues to work
8. Pure documentation edits (.md only) accept code review
