#!/bin/bash
# test-beast-recall-wiring.sh — Sprint 36 G1: global recall wiring (functional).
# Drives the REAL beast-recall-hook.sh via the real PreToolUse stdin contract in a
# sandbox project (HARNESS_STATE_DIR + BEAST_LESSONS), asserting:
#   A1  match -> valid JSON hookSpecificOutput.additionalContext carrying the packet
#   A1' empty surface -> no output (silence)
#   A3  gated by beast-mode.flag (absent -> silence even with lessons)
#   A4  kill-switch superset (harness-disabled.flag -> silence)
#   A5  silent by default (no lessons / non-matching action)
#   A7/C6b  file-writing Bash surfaces; non-file Bash (ls/git status) -> silence
#   Edit (new_string) path matches; determinism; bash -n clean; never blocks.
# Usage: bash tests/test-beast-recall-wiring.sh
set -u

HOOK="$HOME/.claude/hooks/beast-recall-hook.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

SBX=$(mktemp -d 2>/dev/null || echo "/tmp/brecall-$$")
export HARNESS_STATE_DIR="$SBX/state"
export BEAST_LESSONS="$SBX/.beast/lessons.jsonl"
mkdir -p "$HARNESS_STATE_DIR" "$SBX/.beast" 2>/dev/null
cleanup() { rm -rf "$SBX" 2>/dev/null; }
trap cleanup EXIT

# Genuine project lesson: MSYS sed->tr (scope *.sh, trigger sed).
cat > "$BEAST_LESSONS" <<'EOF'
{"id":"M1","scope":"*.sh","trigger":"sed","lesson":"On MSYS/Git Bash sed 's|\\\\|/|g' crashes.","fix":"Use tr '\\\\' '/' instead of sed.","dossier":"MEMORY.md#msys-sed"}
EOF

beast_on()  { printf 'beast mode on\n' > "$HARNESS_STATE_DIR/beast-mode.flag"; }
beast_off() { rm -f "$HARNESS_STATE_DIR/beast-mode.flag"; }
harness_off(){ printf 'off\n' > "$HARNESS_STATE_DIR/harness-disabled.flag"; }
harness_on() { rm -f "$HARNESS_STATE_DIR/harness-disabled.flag"; }
run() { printf '%s' "$1" | bash "$HOOK" 2>/dev/null; }
ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
is_empty() { [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; }

if [ ! -f "$HOOK" ]; then
  bad "beast-recall-hook.sh exists at $HOOK"
  echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
ok "beast-recall-hook.sh exists"

beast_on; harness_on

# A1: Write matching a lesson -> valid JSON additionalContext naming [M1] + fix
W='{"tool_name":"Write","tool_input":{"file_path":"convert.sh","content":"use sed to swap backslashes"}}'
OUT=$(run "$W")
printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && ok "A1: Write surface is valid JSON" || bad "A1: valid JSON (got: $OUT)"
C=$(ctx "$OUT")
printf '%s' "$C" | grep -q 'M1' && ok "A1: additionalContext carries [M1]" || bad "A1: additionalContext [M1] (got: $C)"
printf '%s' "$C" | grep -qi 'tr ' && ok "A1: additionalContext carries the fix" || bad "A1: fix present (got: $C)"

# A1': non-matching Write -> silence
OUT=$(run '{"tool_name":"Write","tool_input":{"file_path":"hello.sh","content":"echo hi"}}')
is_empty "$OUT" && ok "A1': non-matching Write -> silence" || bad "A1': expected silence (got: $OUT)"

# Edit via new_string -> matches
OUT=$(run '{"tool_name":"Edit","tool_input":{"file_path":"convert.sh","new_string":"a sed pipeline"}}')
printf '%s' "$(ctx "$OUT")" | grep -q 'M1' && ok "Edit(new_string): surfaces [M1]" || bad "Edit(new_string) surfaces (got: $OUT)"

# A3: flag absent -> silence even though lessons + match exist
beast_off
OUT=$(run "$W"); is_empty "$OUT" && ok "A3: no beast flag -> silence" || bad "A3: expected silence (got: $OUT)"
beast_on

# A4: kill-switch superset -> silence
harness_off
OUT=$(run "$W"); is_empty "$OUT" && ok "A4: harness disabled -> silence" || bad "A4: expected silence (got: $OUT)"
harness_on

# A5: flag on but no lessons -> silence
mv "$BEAST_LESSONS" "$BEAST_LESSONS.bak"
OUT=$(run "$W"); is_empty "$OUT" && ok "A5: no lessons -> silence" || bad "A5: expected silence (got: $OUT)"
mv "$BEAST_LESSONS.bak" "$BEAST_LESSONS"

# A7/C6b: file-writing Bash referencing the packed file -> surfaces
B='{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ convert.sh"}}'
OUT=$(run "$B")
printf '%s' "$(ctx "$OUT")" | grep -q 'M1' && ok "C6b: file-writing Bash surfaces [M1]" || bad "C6b: Bash surfaces (got: $OUT)"

# C6b: non-file Bash -> silence
OUT=$(run '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}')
is_empty "$OUT" && ok "C6b: 'ls -la' -> silence" || bad "C6b: ls silence (got: $OUT)"
OUT=$(run '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
is_empty "$OUT" && ok "C6b: 'git status' -> silence" || bad "C6b: git status silence (got: $OUT)"

# Determinism
O1=$(run "$W"); O2=$(run "$W")
[ "$O1" = "$O2" ] && ok "deterministic: identical output on repeat" || bad "deterministic"

# Never blocks: exit code is 0 even on match
printf '%s' "$W" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "hook exits 0 (never blocks)" || bad "hook exit 0"

# bash -n clean
bash -n "$HOOK" 2>/dev/null && ok "beast-recall-hook.sh bash -n clean" || bad "bash -n clean"

echo "---------------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
