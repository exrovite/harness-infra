# Sprint 6 Contract: Verification Type Enforcement

**Rev 1** — 2026-04-06

## What We Will Build

A deterministic system that maps modified files to required verification types, tells the agent exactly what verification is needed, and rejects verification that doesn't match the work done.

---

## Deliverable 1: File Write Tracker

### post-write-check.sh changes

**Change 1a — Append file path to unverified-writes.jsonl (insert after session-context update, ~line 112):**

```bash
WRITTEN_FILE="${TOOL_INPUT_FILE_PATH:-}"
if [ -n "$WRITTEN_FILE" ]; then
  NORM_FILE=$(printf '%s' "$WRITTEN_FILE" | tr '\\' '/')
  case "$NORM_FILE" in
    *.claude/state/*|*.claude/pre-flight/*|*.openclaw/watchers/*|*.agent-memory/*) ;;
    *)
      TS_W=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
      SAFE_W=$(printf '%s' "$NORM_FILE" | sed 's/\\/\\\\/g; s/"/\\"/g' | head -c 300)
      printf '{"ts":"%s","file":"%s"}\n' "$TS_W" "$SAFE_W" >> "${STATE_DIR}/unverified-writes.jsonl"
      ;;
  esac
fi
```

Exempt: `.claude/state/`, `.claude/pre-flight/`, `.openclaw/watchers/`, `.agent-memory/`

---

## Deliverable 2: Verification Type Classifier

### New file: `~/.claude/scripts/classify-verification-need.sh`

Reads `.claude/state/unverified-writes.jsonl`, classifies each file by extension, outputs JSON to stdout.

**Classification rules:**

| Category | Extensions/Patterns | Required type |
|---|---|---|
| UI | `.html .htm .css .scss .sass .less .jsx .tsx .vue .svelte .ejs .hbs .pug` | `vision` |
| Logic | `.sh .bash .py .js .ts .go .rs .rb .java .cs .php .c .cpp .h` (non-UI) | `functional` |
| Test | `test_* *_test.* *.test.* *.spec.* *Test.* *_spec.*` | `functional` |
| Config | `.json .yaml .yml .toml .ini .env .conf .cfg` | `functional` |
| Docs | `.md .txt .rst .adoc` | `review` |

**Logic:** If ANY file is UI -> add `vision`. If ANY non-UI logic/test/config -> add `functional`. If ALL docs -> `review` only. Empty input -> empty required set.

**Output:**
```json
{"required":["vision","functional"],"files":[{"file":"src/App.tsx","type":"vision"},{"file":"src/api.ts","type":"functional"}],"prescription":"UI files modified: vision validation needed. Logic files modified: functional testing needed."}
```

---

## Deliverable 3: Prescriptive Block Messages

All three block points (step gate, hardened gate, phase gate) run the classifier and include its output when blocking.

**Pattern (same for all three):**
```bash
PRESCRIPTION=""
if [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
  PRESCRIPTION=$(bash "$HOME/.claude/scripts/classify-verification-need.sh" 2>/dev/null)
fi
if [ -n "$PRESCRIPTION" ]; then
  printf "Files modified since last verification:\n" >&2
  printf '%s' "$PRESCRIPTION" | jq -r '.files[] | "  - \(.file)  -> requires \(.type | ascii_upcase) validation"' >&2
  printf "\nRequired: %s\n" "$(printf '%s' "$PRESCRIPTION" | jq -r '.prescription')" >&2
fi
```

---

## Deliverable 4: Verification Type Tagging and Matching

### agent-call-tracker.sh changes

**Change 4a — Classify prompt type (insert after IS_VERIFICATION=true, before ledger write):**

```bash
VTYPE="review"
if printf '%s' "$PROMPT" | grep -qiE 'screenshot|vision|visual|look at|render|UI|inspect.*layout'; then
  VTYPE="vision"
elif printf '%s' "$PROMPT" | grep -qiE 'browser|navigate|page|open.*url|website|localhost'; then
  VTYPE="browser"
elif printf '%s' "$PROMPT" | grep -qiE 'run|execute|test|curl|output|functional|invoke|call.*endpoint'; then
  VTYPE="functional"
fi
```

**Change 4b — Add `verification_type` to ledger entry ENTRY printf.**

**Change 4c — Consume unverified-writes.jsonl after ledger write:**
```bash
UNVERIFIED="${STATE_DIR}/unverified-writes.jsonl"
if [ -f "$UNVERIFIED" ]; then
  cat "$UNVERIFIED" >> "${STATE_DIR}/unverified-writes-archive.jsonl" 2>/dev/null
  rm -f "$UNVERIFIED"
fi
```

### pre-flight-gate.sh step gate changes

**Change 4d — After finding ledger match by prefix, check type satisfaction:**

Strength hierarchy: `browser > vision > functional > review`

- `vision` required -> satisfied by `vision` or `browser`
- `functional` required -> satisfied by `functional`, `vision`, or `browser`
- `browser` required -> satisfied by `browser` only
- `review` required -> satisfied by anything

If the strongest ledger type doesn't satisfy all required types -> block with prescription showing what's missing.

### validate-phase.sh changes

**Change 4e — After checking ledger entry exists, find strongest verification_type across all entries for this phase+sprint. Run classifier. Check satisfaction. Block if mismatch.**

---

## Verification Criteria (24 total)

### File Write Tracker (4)
1. post-write-check.sh appends TOOL_INPUT_FILE_PATH to unverified-writes.jsonl
2. Each entry contains ts and file fields in valid JSON
3. unverified-writes.jsonl is cleared when agent-call-tracker logs a verification call
4. Exempt paths are NOT logged

### Classifier (6)
5. classify-verification-need.sh outputs valid JSON to stdout
6. UI extensions produce required type "vision"
7. Logic extensions (non-UI) produce required type "functional"
8. Doc-only files produce required type "review"
9. Test files produce required type "functional"
10. Mixed types produce multiple required types

### Prescriptive Messages (3)
11. Step gate block lists modified files with required types
12. Hardened gate block includes prescription
13. Phase gate block includes prescription

### Type Tagging and Matching (5)
14. Ledger entries include verification_type field
15. Vision keywords in prompt -> type "vision"
16. Functional keywords in prompt -> type "functional"
17. Review keywords in prompt -> type "review"
18. Step gate rejects "review" when "vision" or "functional" required

### Strength Hierarchy (3)
19. "vision" satisfies "functional" requirement
20. "functional" satisfies "review" requirement
21. "review" does NOT satisfy "vision" or "functional"

### Integration (3)
22. Sprint 5 Q5 counter/hardening still works
23. Sprint 5 step completion gate still works
24. All modified scripts pass bash -n

## Accepted Limitations

- Browser type detection is prompt-keyword only
- Classifier uses extensions only — a .ts file rendering UI is classified "functional" not "vision"
- unverified-writes archive grows unbounded (acceptable for session-length work)
