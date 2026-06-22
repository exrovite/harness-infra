#!/bin/bash
# test-beast-reconcile-gate.sh — Sprint 38 D9: block-until-reconciled FORCING.
# Drives the LIVE beast-recall-hook.sh. On a HIGH-STAKES matching action the write is
# BLOCKED (exit 2) until a reconciliation referencing each [M#] exists; low-stakes stays
# inject-only; the reconcile file itself is never blocked (no deadlock); fail-safe.
# Usage: bash tests/test-beast-reconcile-gate.sh
set -u
HOOK="$HOME/.claude/hooks/beast-recall-hook.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

SBX=$(mktemp -d 2>/dev/null || echo "/tmp/brg-$$")
export HARNESS_STATE_DIR="$SBX/state"
export BEAST_LESSONS="$SBX/.beast/lessons.jsonl"
mkdir -p "$HARNESS_STATE_DIR" "$SBX/.beast"
trap 'rm -rf "$SBX" 2>/dev/null' EXIT
cat > "$BEAST_LESSONS" <<'EOF'
{"id":"1","scope":"*","trigger":"commit|release","lesson":"Releases must bump version + changelog.","fix":"Bump version and update CHANGELOG before committing.","dossier":"d"}
{"id":"2","scope":"phase-complete-marker.md","trigger":"complete|done","lesson":"Do not mark complete until verifier PASS.","fix":"Get verifier PASS first.","dossier":"d"}
{"id":"3","scope":"*.tsx","trigger":"auth","lesson":"Auth flow has a known race.","fix":"Guard the token refresh.","dossier":"d"}
EOF
printf 'beast mode on\n' > "$HARNESS_STATE_DIR/beast-mode.flag"
RF="$HARNESS_STATE_DIR/beast-reconcile.md"
run(){ printf '%s' "$1" | bash "$HOOK" >/tmp/brg_out 2>/tmp/brg_err; echo $?; }

[ -f "$HOOK" ] || { bad "hook exists"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

# T1 low-stakes match -> inject, NOT blocked (exit 0, additionalContext has M3)
RC=$(run '{"tool_name":"Write","tool_input":{"file_path":"src/app.tsx","content":"fix the auth race"}}')
CTX=$(jq -r '.hookSpecificOutput.additionalContext // ""' /tmp/brg_out 2>/dev/null)
{ [ "$RC" = 0 ] && printf '%s' "$CTX" | grep -q 'M3'; } && ok "T1 low-stakes -> inject, exit 0" || bad "T1 low-stakes (rc=$RC ctx=$CTX)"

# T2 high-stakes git commit, NO reconcile -> BLOCK (exit 2, stderr names reconcile + M1)
RC=$(run '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"release v2\""}}')
{ [ "$RC" = 2 ] && grep -qi 'reconcile' /tmp/brg_err && grep -q 'M1' /tmp/brg_err; } && ok "T2 high-stakes git commit -> BLOCKED" || bad "T2 expected block (rc=$RC err=$(cat /tmp/brg_err))"

# T3 write a valid reconciliation, retry -> ALLOWED (exit 0)
printf '[M1] applies: I bumped the version and updated CHANGELOG before committing this release.\n' > "$RF"
RC=$(run '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"release v2\""}}')
[ "$RC" = 0 ] && ok "T3 reconciled git commit -> allowed (exit 0)" || bad "T3 expected allow (rc=$RC err=$(cat /tmp/brg_err))"

# T4 phase-complete-marker high-stakes, reconcile lacks M2 -> still BLOCKED
RC=$(run '{"tool_name":"Write","tool_input":{"file_path":".claude/state/phase-complete-marker.md","content":"phase complete and done"}}')
{ [ "$RC" = 2 ] && grep -q 'M2' /tmp/brg_err; } && ok "T4 phase-complete-marker -> BLOCKED (M2 unreconciled)" || bad "T4 expected block (rc=$RC err=$(cat /tmp/brg_err))"

# T5 reconcile file itself is NEVER blocked (no deadlock), even if content would match
RC=$(run '{"tool_name":"Write","tool_input":{"file_path":".claude/state/beast-reconcile.md","content":"about the release commit"}}')
[ "$RC" = 0 ] && ok "T5 reconcile file write never blocked" || bad "T5 reconcile write blocked (rc=$RC)"

# T6 missing-id reconcile still blocks: reconcile has only M1, commit also triggers... (covered) ; test partial reconcile for M2
printf '[M1] applies: ...\n' > "$RF"   # no M2
RC=$(run '{"tool_name":"Write","tool_input":{"file_path":".claude/state/phase-complete-marker.md","content":"mark complete done"}}')
[ "$RC" = 2 ] && ok "T6 partial reconcile (M2 missing) -> still blocked" || bad "T6 expected block (rc=$RC)"

# T7 flag off -> no block (silence)
rm -f "$HARNESS_STATE_DIR/beast-mode.flag"
RC=$(run '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}')
{ [ "$RC" = 0 ] && [ ! -s /tmp/brg_out ]; } && ok "T7 flag off -> no block, silence" || bad "T7 flag off (rc=$RC)"
printf 'beast mode on\n' > "$HARNESS_STATE_DIR/beast-mode.flag"

# T8 harness disabled -> no block
printf 'off\n' > "$HARNESS_STATE_DIR/harness-disabled.flag"
RC=$(run '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}')
[ "$RC" = 0 ] && ok "T8 harness off -> no block" || bad "T8 harness off (rc=$RC)"
rm -f "$HARNESS_STATE_DIR/harness-disabled.flag"

# T9 fail-safe malformed input -> exit 0
RC=$(run 'not json {{{'); [ "$RC" = 0 ] && ok "T9 malformed -> exit 0" || bad "T9 malformed (rc=$RC)"

# T10 low-stakes never blocks even with NO reconcile (regression of S36 behavior)
rm -f "$RF"
RC=$(run '{"tool_name":"Write","tool_input":{"file_path":"src/app.tsx","content":"auth tweak"}}')
[ "$RC" = 0 ] && ok "T10 low-stakes never blocks" || bad "T10 low-stakes blocked (rc=$RC)"

# T11 bash -n
bash -n "$HOOK" 2>/dev/null && ok "T11 bash -n clean" || bad "T11 bash -n"

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
