#!/bin/bash
# test-mustdo-summary-lane.sh — each session must have its OWN must-do SUMMARY lane.
# The packet injection must show ONLY this session's own summary (must-do-summary.<sid>.md), never
# another session's shared scratch, and the authoring action must name this session's own lane file.
# Drives the LIVE on-prompt-submit.sh via HARNESS_STATE_DIR sandboxes.
set -u
HOOKS="$HOME/.claude/hooks"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/msl-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT

D="$SBX/proj"; ST="$D/.claude/state"; MD="$D/docs/must do"
mkdir -p "$ST" "$MD" "$D/src"
printf '{"phase":"BUILD","sprint":1,"iteration":0}' > "$ST/current-phase.json"
printf '<!-- mustdo-session: AAA | built: pack -->\n- src/ref.md\n' > "$MD/must-do.md"
SA="aaaaaaaa-1111"; SB="bbbbbbbb-2222"
A_TEXT="ALPHA-SUMMARY-AAA $(printf 'x%.0s' $(seq 1 220)) references must-do.md"
B_TEXT="BETA-SUMMARY-BBB $(printf 'y%.0s' $(seq 1 220)) references must-do.md"

# Session A has authored its own lane summary; the SHARED scratch also holds A's content (legacy).
printf '%s\n' "$A_TEXT" > "$ST/must-do-summary.${SA}.md"
printf '%s\n' "$A_TEXT" > "$ST/must-do-summary.md"

pkt(){ # $1=session -> stdout of on-prompt-submit (the injected packet)
  ( cd "$D" && printf '{"session_id":"%s","prompt":"do the task","cwd":"%s"}' "$1" "$D" \
    | HARNESS_STATE_DIR="$ST" bash "$HOOKS/on-prompt-submit.sh" 2>/dev/null )
}

# T1: session B (no own summary yet) must NOT be shown A's summary via the shared scratch
OUT_B=$(pkt "$SB")
printf '%s' "$OUT_B" | grep -q 'ALPHA-SUMMARY-AAA' && bad "T1 B's packet leaked A's summary (shared scratch injected)" || ok "T1 B is NOT shown another session's summary"

# T2: B's packet names B's OWN lane file as the authoring target (not the shared file)
printf '%s' "$OUT_B" | grep -q "must-do-summary.${SB}.md" && ok "T2 B's packet names its own lane file (must-do-summary.${SB}.md)" || bad "T2 B's packet did not name its own lane"

# T3: after B authors its own lane, B's packet injects B's summary (and still not A's)
printf '%s\n' "$B_TEXT" > "$ST/must-do-summary.${SB}.md"
OUT_B2=$(pkt "$SB")
{ printf '%s' "$OUT_B2" | grep -q 'BETA-SUMMARY-BBB' && ! printf '%s' "$OUT_B2" | grep -q 'ALPHA-SUMMARY-AAA'; } \
  && ok "T3 B's packet injects B's own summary, not A's" || bad "T3 B injection wrong"

# T4: session A still sees its OWN summary (per-session injection didn't break A)
OUT_A=$(pkt "$SA")
printf '%s' "$OUT_A" | grep -q 'ALPHA-SUMMARY-AAA' && ok "T4 A still sees its own summary" || bad "T4 A no longer sees its own summary"

# T5: A's packet does NOT inject B's summary (lanes are isolated both ways)
printf '%s' "$OUT_A" | grep -q 'BETA-SUMMARY-BBB' && bad "T5 A's packet leaked B's summary" || ok "T5 A is not shown B's summary"

bash -n "$HOOKS/on-prompt-submit.sh" 2>/dev/null && ok "bash -n on-prompt-submit" || bad "bash -n"
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
