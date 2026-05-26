# Sprint 26 Contract — Ralph Auto-Deactivation on Verifier PASS

## Deliverable
Add a ralph verdict processing section to `post-write-check.sh` that detects when `evidence-verdict.json` is written with verdict PASS while ralph mode is active, and immediately sets ralph state to `active: false`.

## Files Modified
- `C:\Users\exrov\.claude\hooks\post-write-check.sh` (live)
- `G:\harness infra\_install\hooks\post-write-check.sh` (install package)

## Files NOT Modified
- on-prompt-submit.sh (existing fallback stays)
- pre-write-gate.sh (existing ralph blocks stay)
- pre-bash-gate.sh (existing ralph blocks stay)

## Implementation

Insert after the evidence checkpoint counter section (~line 294), before the "CHECK FOR PENDING ACTIONS" section:

```
# --- RALPH AUTO-DEACTIVATION ON VERIFIER PASS ---
# When evidence-verdict.json is written with PASS while ralph is active,
# update ralph state immediately (don't wait for next UserPromptSubmit).
RALPH_STATE_FILE="${STATE_DIR}/ralph-mode.json"
VERDICT_NORM=$(printf '%s' "$TOOL_FILE_PATH" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')
if printf '%s' "$VERDICT_NORM" | grep -qF 'evidence-verdict.json'; then
  if [ -f "$RALPH_STATE_FILE" ] && jq -e '.active == true' "$RALPH_STATE_FILE" >/dev/null 2>&1; then
    RALPH_V=$(jq -r '.verdict // ""' "${STATE_DIR}/evidence-verdict.json" 2>/dev/null | tr -d '\r')
    if [ "$RALPH_V" = "PASS" ]; then
      RALPH_VTS=$(jq -r '.timestamp // .checked_at // .verdict_at // .created_at // .ts // ""' "${STATE_DIR}/evidence-verdict.json" 2>/dev/null | tr -d '\r')
      RALPH_LAST_AT=$(jq -r '.last_verdict_at // ""' "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
      # Timestamp freshness check (same logic as on-prompt-submit.sh)
      RALPH_IS_FRESH=false
      if [ -z "$RALPH_LAST_AT" ] || [ "$RALPH_LAST_AT" = "null" ]; then
        RALPH_IS_FRESH=true
      elif [ -n "$RALPH_VTS" ]; then
        R_NEW=$(date -d "$RALPH_VTS" +%s 2>/dev/null) || R_NEW=""
        R_OLD=$(date -d "$RALPH_LAST_AT" +%s 2>/dev/null) || R_OLD=""
        if [ -n "$R_NEW" ] && [ -n "$R_OLD" ]; then
          [ "$R_NEW" -gt "$R_OLD" ] && RALPH_IS_FRESH=true
        elif [[ "$RALPH_VTS" > "$RALPH_LAST_AT" ]]; then
          RALPH_IS_FRESH=true
        fi
      fi
      if [ "$RALPH_IS_FRESH" = true ]; then
        RALPH_UPDATED=$(jq -c --arg ts "$RALPH_VTS" \
          '.last_verdict="PASS" | .active=false | .last_verdict_at=$ts | .failed_criteria=[]' \
          "$RALPH_STATE_FILE" 2>/dev/null | tr -d '\r')
        if [ -n "$RALPH_UPDATED" ]; then
          if type atomic_write >/dev/null 2>&1; then
            atomic_write "$RALPH_UPDATED" "$RALPH_STATE_FILE"
          else
            printf '%s' "$RALPH_UPDATED" > "$RALPH_STATE_FILE"
          fi
          echo "ralph: auto-deactivated on verifier PASS" >&2
        fi
      fi
    fi
  fi
fi
```

## Acceptance Criteria

### Functional (AC1-AC7)
- AC1: post-write-check.sh contains the ralph verdict processing section
- AC2: Section triggers ONLY when written file path contains "evidence-verdict.json"
- AC3: Section triggers ONLY when ralph state file has active:true
- AC4: PASS verdict with fresh timestamp sets ralph state active:false
- AC5: Update includes last_verdict:"PASS" and last_verdict_at with verdict timestamp
- AC6: Timestamp freshness check uses epoch comparison with ISO lexicographic fallback
- AC7: Uses atomic_write when available, printf fallback otherwise

### Non-Regression (AC8-AC13)
- AC8: on-prompt-submit.sh is byte-identical before and after
- AC9: pre-write-gate.sh is byte-identical before and after
- AC10: pre-bash-gate.sh is byte-identical before and after
- AC11: Phase validation section in post-write-check.sh unchanged
- AC12: Evidence checkpoint section in post-write-check.sh unchanged
- AC13: Write tracking section in post-write-check.sh unchanged

### Sync + Syntax (AC14-AC15)
- AC14: Live and install copies have identical ralph auto-deactivation sections
- AC15: bash -n passes on both copies

## Verification Method
Independent sub-agent reads both files, checks all 15 criteria, runs bash -n.
