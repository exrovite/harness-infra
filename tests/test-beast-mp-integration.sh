#!/bin/bash
# test-beast-mp-integration.sh — Sprint 39: mempalace semantic backstop wired into the hooks.
# Uses BEAST_MP_FIXTURE so the hooks' mempalace layer is exercised deterministically (no palace).
# Recall hook (PreToolUse Write/Edit) and watch hook (PostToolUse) both surface the mempalace hit.
set -u
RECALL="$HOME/.claude/hooks/beast-recall-hook.sh"
WATCH="$HOME/.claude/hooks/beast-watch-hook.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

SBX=$(mktemp -d 2>/dev/null || echo "/tmp/bmpi-$$")
export HARNESS_STATE_DIR="$SBX/state"
export BEAST_LESSONS="$SBX/.beast/lessons.jsonl"     # empty -> isolates the mempalace layer
mkdir -p "$HARNESS_STATE_DIR" "$SBX/.beast"; : > "$BEAST_LESSONS"
trap 'rm -rf "$SBX" 2>/dev/null' EXIT
printf 'beast mode on\n' > "$HARNESS_STATE_DIR/beast-mode.flag"

FIX="$SBX/fix.txt"
cat > "$FIX" <<'EOF'

  [1] g__wing / planning
      Source: x.jsonl
      Match:  cosine=0.700  bm25=2.0

      leave the temperature for now do not keep changing it

  ────────────────────────────────────────────────────────
EOF
export BEAST_MP_FIXTURE="$FIX"
export BEAST_MP_THROTTLE=0   # disable throttle for the test
ctx(){ printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

[ -f "$RECALL" ] && [ -f "$WATCH" ] || { bad "hooks exist"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

# 1. Recall hook (Write to the temp file) surfaces the mempalace memory + [MP#] id
OUT=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"src/prompt-assembly.js","content":"change the temperature to 2.0"}}' | bash "$RECALL" 2>/dev/null)
C=$(ctx "$OUT")
printf '%s' "$C" | grep -q 'leave the temperature' && ok "recall: surfaces mempalace project memory" || bad "recall mp (got: $OUT)"
printf '%s' "$C" | grep -qE '\[MP[0-9A-Za-z]+\]' && ok "recall: carries [MP<hash>] id" || bad "recall mp id"

# 2. Watch hook (reasoning about temperature) surfaces it too, then dedups
TR="$SBX/t.jsonl"; printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"I think I should change the temperature setting now"}]}}' > "$TR"
inp(){ jq -cn --arg t "$TR" --arg s "$1" '{session_id:$s,transcript_path:$t,tool_name:"Edit",tool_input:{file_path:"src/prompt-assembly.js"}}'; }
OUT=$(printf '%s' "$(inp S1)" | bash "$WATCH" 2>/dev/null)
printf '%s' "$(ctx "$OUT")" | grep -q 'leave the temperature' && ok "watch: surfaces mempalace memory in-work" || bad "watch mp (got: $OUT)"
OUT=$(printf '%s' "$(inp S1)" | bash "$WATCH" 2>/dev/null)
[ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ] && ok "watch: dedups mempalace hit within session" || bad "watch dedup (got: $OUT)"

# 3. flag off -> no mempalace surfacing
rm -f "$HARNESS_STATE_DIR/beast-mode.flag"
OUT=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"src/prompt-assembly.js","content":"temperature"}}' | bash "$RECALL" 2>/dev/null)
[ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ] && ok "flag off -> no mempalace surfacing" || bad "flag off (got: $OUT)"
printf 'beast mode on\n' > "$HARNESS_STATE_DIR/beast-mode.flag"

# 4. mempalace unavailable (fixture points at nothing) -> recall still works, just silent on mp
OUT=$(BEAST_MP_FIXTURE=/dev/null printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"x.js","content":"hello"}}' | BEAST_MP_FIXTURE=/dev/null bash "$RECALL" 2>/dev/null; echo "rc=$?")
echo "$OUT" | grep -q 'rc=0' && ok "mempalace empty -> recall fail-safe (rc 0)" || bad "fail-safe rc"

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
