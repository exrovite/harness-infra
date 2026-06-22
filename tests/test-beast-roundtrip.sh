#!/bin/bash
# test-beast-roundtrip.sh — Sprint 36 C: END-TO-END in a fresh SECOND project.
# Proves the whole intuition loop with NOTHING mocked and NO pre-planted lessons:
#   seed a real git project + KG facts -> beast-pack.sh builds ITS OWN lessons ->
#   a REAL Write and a REAL file-writing Bash action are fed to the LIVE recall
#   hook -> the matching lesson is surfaced. Pack and recall are connected ONLY
#   through the real <project>/.beast/lessons.jsonl on disk.
#   C13 surfacing (Write + Bash) · C14 negatives (flag off / unrelated) · C15 determinism
# Usage: bash tests/test-beast-roundtrip.sh
set -u

PACK="$HOME/.claude/scripts/beast-pack.sh"
HOOK="$HOME/.claude/hooks/beast-recall-hook.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

[ -f "$PACK" ] && [ -f "$HOOK" ] || { echo "FAIL  pack+hook present"; exit 1; }

SBX=$(mktemp -d 2>/dev/null || echo "/tmp/brt-$$")
cleanup() { rm -rf "$SBX" 2>/dev/null; }
trap cleanup EXIT

# --- A fresh SECOND project (not harness infra), built at runtime ---
P="$SBX/secondproj"
mkdir -p "$P/.claude/state"
( cd "$P" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'echo a\n' > msys-helper.sh && git add . && git commit -q -m "init" \
  && printf 'tr fix\n' >> msys-helper.sh && git add . \
  && git commit -q -m "Fix MSYS sed crash: use tr not sed in msys-helper.sh" ) 2>/dev/null
KG="$SBX/kg.jsonl"
printf '%s\n' '{"subject":"pre-write-gate.sh","predicate":"must_use","object":"find_project_state_dir for cwd-independent resolution"}' > "$KG"

# --- STEP 1: pack builds the project's OWN lessons from its OWN memory ---
( export BEAST_PACK_ROOT="$P"; export BEAST_KG_FACTS_FILE="$KG"; unset BEAST_LESSONS; bash "$PACK" >/dev/null 2>&1 )
L="$P/.beast/lessons.jsonl"
[ -f "$L" ] && [ "$(wc -l < "$L" | tr -d ' ')" -ge 2 ] && ok "pack built the second project's lessons" || { bad "pack built lessons"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

# --- STEP 2: drive the LIVE recall hook (resolves lessons via project root only) ---
export HARNESS_STATE_DIR="$P/.claude/state"
unset BEAST_LESSONS                      # force project-root resolution (no shortcut)
printf 'beast mode on\n' > "$HARNESS_STATE_DIR/beast-mode.flag"
rm -f "$HARNESS_STATE_DIR/harness-disabled.flag"
recall() { printf '%s' "$1" | bash "$HOOK" 2>/dev/null; }
ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
empty() { [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; }

# C13a: real Write touching the git-sourced atom -> surfaces
W='{"tool_name":"Write","tool_input":{"file_path":"msys-helper.sh","content":"add a sed pipeline here"}}'
OUT=$(recall "$W")
printf '%s' "$(ctx "$OUT")" | grep -qi 'tr ' && ok "C13: real Write surfaces the git lesson (fix=tr)" || bad "C13 Write (got: $OUT)"

# C13b: real Write touching the KG-sourced atom -> surfaces the unguessable symbol
WK='{"tool_name":"Write","tool_input":{"file_path":"pre-write-gate.sh","content":"resolve state via find_project_state_dir"}}'
OUT=$(recall "$WK")
printf '%s' "$(ctx "$OUT")" | grep -q 'find_project_state_dir' && ok "C13: real Write surfaces the KG lesson" || bad "C13 KG Write (got: $OUT)"

# C13c: real file-writing Bash touching a packed atom -> surfaces
B='{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ msys-helper.sh"}}'
OUT=$(recall "$B")
printf '%s' "$(ctx "$OUT")" | grep -qi 'tr ' && ok "C13: real Bash surfaces the git lesson" || bad "C13 Bash (got: $OUT)"

# C14a: flag OFF -> silence
rm -f "$HARNESS_STATE_DIR/beast-mode.flag"
OUT=$(recall "$W"); empty "$OUT" && ok "C14: flag off -> silence" || bad "C14 flag off (got: $OUT)"
printf 'beast mode on\n' > "$HARNESS_STATE_DIR/beast-mode.flag"

# C14b: unrelated atom -> silence
U='{"tool_name":"Write","tool_input":{"file_path":"notes.txt","content":"shopping list and weather"}}'
OUT=$(recall "$U"); empty "$OUT" && ok "C14: unrelated atom -> silence" || bad "C14 unrelated (got: $OUT)"

# C15: determinism
O1=$(recall "$W"); O2=$(recall "$W")
[ "$O1" = "$O2" ] && ok "C15: deterministic recall" || bad "C15 determinism"

echo "---------------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
