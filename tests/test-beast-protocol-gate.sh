#!/bin/bash
# test-beast-protocol-gate.sh — surface validated protocols + ENFORCE adherence.
# When the action's content touches a concept that has a USER-validated win, the gate BLOCKS the
# action until an adherence artifact exists (explanation + INDEPENDENT-CHECK). Fail-safe, flag-gated.
set -u
GATE="$HOME/.claude/hooks/beast-protocol-gate.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/bpg-$$")
export HARNESS_STATE_DIR="$SBX/state"
export BEAST_WINS="$SBX/.beast/validated-wins.jsonl"
mkdir -p "$HARNESS_STATE_DIR" "$SBX/.beast"
trap 'rm -rf "$SBX" 2>/dev/null' EXIT
printf '%s\n' '{"concept":"microlabel","quote":"the microlabels worked really well now, much better output","k":"1_1"}' > "$BEAST_WINS"
printf 'beast mode on\n' > "$HARNESS_STATE_DIR/beast-mode.flag"
run(){ printf '%s' "$1" | bash "$GATE" >/tmp/bpg_o 2>/tmp/bpg_e; echo $?; }

[ -f "$GATE" ] || { bad "gate exists at $GATE"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
ok "gate exists"

ACT='{"tool_name":"Write","tool_input":{"file_path":"src/headline.js","content":"refine the microlabels that direct each section"}}'

# 1. concept touched, NO ack -> BLOCK (exit 2) with the IMPORTANT PROTOCOL packet + the real quote
RC=$(run "$ACT")
{ [ "$RC" = 2 ] && grep -qi 'IMPORTANT PROTOCOL' /tmp/bpg_e && grep -q 'worked really well' /tmp/bpg_e; } && ok "blocks on validated concept (no ack)" || bad "expected block (rc=$RC err=$(cat /tmp/bpg_e))"
# packet asks the relevance question + the deep search + independent check
grep -qi 'Are you working with' /tmp/bpg_e && ok "packet asks relevance question" || bad "relevance Q"
grep -qi 'independent subagent' /tmp/bpg_e && ok "packet requires independent check" || bad "independent check ask"
grep -qi 'mempalace_search' /tmp/bpg_e && ok "packet tells agent to do its own search" || bad "own search ask"

# 2. write a VALID ack (explanation + INDEPENDENT-CHECK) -> ALLOW (exit 0, additionalContext)
cat > "$HARNESS_STATE_DIR/protocol-ack.microlabel.md" <<'EOF'
Relevant: yes. The headline module uses microlabels the same way bullets did.
Plan: follow the proven part-instruction + thinking-budget approach from the bullets win.
INDEPENDENT-CHECK: spawned a neutral subagent; verdict CONFIRMED the plan matches the proven protocol.
EOF
RC=$(run "$ACT")
[ "$RC" = 0 ] && ok "allows once valid ack on file (exit 0)" || bad "expected allow (rc=$RC err=$(cat /tmp/bpg_e))"

# 3. ack present but MISSING the independent-check marker -> still BLOCK
printf 'Relevant: yes. I will just follow it.\n' > "$HARNESS_STATE_DIR/protocol-ack.microlabel.md"
RC=$(run "$ACT"); [ "$RC" = 2 ] && ok "blocks when ack lacks INDEPENDENT-CHECK" || bad "expected block (rc=$RC)"
# restore valid ack
printf 'Relevant: yes.\nINDEPENDENT-CHECK: neutral subagent CONFIRMED.\n' > "$HARNESS_STATE_DIR/protocol-ack.microlabel.md"

# 3b. a dismissal ack (RELEVANT: NO + reason) unblocks cheaply (relevance gate handling noise)
printf 'RELEVANT: NO — this concept match is incidental; my edit is unrelated to the proven protocol.\n' > "$HARNESS_STATE_DIR/protocol-ack.microlabel.md"
RC=$(run "$ACT"); [ "$RC" = 0 ] && ok "dismissal (RELEVANT: NO) unblocks without independent check" || bad "dismissal should unblock (rc=$RC)"
printf 'Relevant: yes.\nINDEPENDENT-CHECK: neutral subagent CONFIRMED.\n' > "$HARNESS_STATE_DIR/protocol-ack.microlabel.md"

# 4. action NOT touching any validated concept -> silence (exit 0, no output)
RC=$(run '{"tool_name":"Write","tool_input":{"file_path":"src/footer.js","content":"add a copyright line"}}')
{ [ "$RC" = 0 ] && [ ! -s /tmp/bpg_o ] && [ ! -s /tmp/bpg_e ]; } && ok "unrelated action -> silence" || bad "expected silence (rc=$RC)"

# 5. the ack file write itself is NEVER blocked (no deadlock)
RC=$(run '{"tool_name":"Write","tool_input":{"file_path":".claude/state/protocol-ack.microlabel.md","content":"about microlabels INDEPENDENT-CHECK done"}}')
[ "$RC" = 0 ] && ok "ack file write never blocked" || bad "ack write blocked (rc=$RC)"

# 6. flag off -> no block
rm -f "$HARNESS_STATE_DIR/beast-mode.flag"; rm -f "$HARNESS_STATE_DIR/protocol-ack.microlabel.md"
RC=$(run "$ACT"); [ "$RC" = 0 ] && ok "beast flag off -> no block" || bad "flag off (rc=$RC)"
printf 'beast mode on\n' > "$HARNESS_STATE_DIR/beast-mode.flag"
# 7. kill-switch -> no block
printf 'off\n' > "$HARNESS_STATE_DIR/harness-disabled.flag"
RC=$(run "$ACT"); [ "$RC" = 0 ] && ok "harness disabled -> no block" || bad "kill-switch (rc=$RC)"
rm -f "$HARNESS_STATE_DIR/harness-disabled.flag"
# 8. fail-safe malformed
RC=$(run 'garbage{{{'); [ "$RC" = 0 ] && ok "malformed -> exit 0" || bad "malformed (rc=$RC)"

bash -n "$GATE" 2>/dev/null && ok "bash -n clean" || bad "bash -n"
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
