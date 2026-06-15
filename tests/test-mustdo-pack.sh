#!/bin/bash
# test-mustdo-pack.sh — TDD for the Automated Must-Do Pack Builder (sprint 1, Parts A+B)
# Covers: lane-aware must-do file resolution (Part A), pack-builder clears-own-file + transcript
# capture (Part B), independent agreement validation (Part B / D-Validate).
# Run: bash tests/test-mustdo-pack.sh

set -u
PASS=0; FAIL=0
LIB="$HOME/.claude/scripts/lib-helpers.sh"
SCRIPTS="$HOME/.claude/scripts"
ROOT_LIB="$(cd "$(dirname "$0")/.." && pwd)/_install/scripts/lib-helpers.sh"

ok()   { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else no "$1"; fi; }

SBX=$(mktemp -d)
trap 'rm -rf "$SBX"' EXIT

# Source the live lib (fallback to _install copy)
if [ -f "$LIB" ]; then . "$LIB"; elif [ -f "$ROOT_LIB" ]; then . "$ROOT_LIB"; else echo "no lib-helpers"; exit 1; fi

echo "== Part A: lane-aware must-do resolution (mustdo_file_for_dir) =="

check "mustdo_file_for_dir is defined" "type mustdo_file_for_dir >/dev/null 2>&1"

# lane 1 / unset -> must-do.md
LANE=1; R1=$(mustdo_file_for_dir "docs/must do" 2>/dev/null)
check "lane 1 resolves to must-do.md" "[ \"$R1\" = 'docs/must do/must-do.md' ]"

unset LANE; R0=$(mustdo_file_for_dir "docs/must do" 2>/dev/null)
check "unset lane resolves to must-do.md" "[ \"$R0\" = 'docs/must do/must-do.md' ]"

# lane 3, numbered file present -> must-do-2.md
mkdir -p "$SBX/docs/must do"; : > "$SBX/docs/must do/must-do-2.md"
LANE=3; R3=$(cd "$SBX" && LANE=3 && . "$LIB" 2>/dev/null; mustdo_file_for_dir "docs/must do")
check "lane 3 with numbered file -> must-do-2.md" "[ \"$R3\" = 'docs/must do/must-do-2.md' ]"

# lane 3, numbered file absent -> fallback must-do.md
R3b=$(cd "$SBX" && rm -f 'docs/must do/must-do-2.md'; LANE=3 && . "$LIB" 2>/dev/null; mustdo_file_for_dir "docs/must do")
check "lane 3 without numbered file -> fallback must-do.md" "[ \"$R3b\" = 'docs/must do/must-do.md' ]"

echo "== Part B: pack-builder (build-mustdo-pack.sh) =="
PB="$SCRIPTS/build-mustdo-pack.sh"
check "build-mustdo-pack.sh exists" "[ -f \"$PB\" ]"
check "build-mustdo-pack.sh is valid bash" "bash -n \"$PB\" 2>/dev/null"

# clears ONLY caller's own file, leaves sibling untouched
if [ -f "$PB" ]; then
  WS=$(mktemp -d)
  mkdir -p "$WS/docs/must do"
  printf '# mine\n- [link old](old.md)\n'   > "$WS/docs/must do/must-do.md"
  printf '# sibling\n- [keep](keep.md)\n'    > "$WS/docs/must do/must-do-1.md"
  SIB_BEFORE=$(cat "$WS/docs/must do/must-do-1.md")
  ( cd "$WS" && LANE=1 bash "$PB" --own "docs/must do/must-do.md" --no-transcript >/dev/null 2>&1 )
  SIB_AFTER=$(cat "$WS/docs/must do/must-do-1.md")
  check "pack-builder leaves sibling file untouched (C11)" "[ \"$SIB_BEFORE\" = \"$SIB_AFTER\" ]"
  check "pack-builder cleared own stale link" "! grep -q 'old.md' \"$WS/docs/must do/must-do.md\""
  rm -rf "$WS"
else
  no "pack-builder leaves sibling file untouched (C11) [script missing]"
  no "pack-builder cleared own stale link [script missing]"
fi

echo "== Part B: independent agreement validation (validate-agreement.sh) =="
VA="$SCRIPTS/validate-agreement.sh"
check "validate-agreement.sh exists" "[ -f \"$VA\" ]"
check "validate-agreement.sh is valid bash" "bash -n \"$VA\" 2>/dev/null"

if [ -f "$VA" ]; then
  WS=$(mktemp -d)
  # raw conversation mentions two agreed points; agreement missing one -> FAIL
  printf 'we agreed FEATURE_ALPHA and FEATURE_BETA must ship\n' > "$WS/raw-conversation.txt"
  printf 'Agreement: implement FEATURE_ALPHA\n'                  > "$WS/agreement.md"
  bash "$VA" --raw "$WS/raw-conversation.txt" --agreement "$WS/agreement.md" --terms "FEATURE_ALPHA FEATURE_BETA" >/dev/null 2>&1
  check "validation FAILs when an agreed term is missing (C15/C16)" "[ $? -ne 0 ]"
  printf 'Agreement: implement FEATURE_ALPHA and FEATURE_BETA\n' > "$WS/agreement.md"
  bash "$VA" --raw "$WS/raw-conversation.txt" --agreement "$WS/agreement.md" --terms "FEATURE_ALPHA FEATURE_BETA" >/dev/null 2>&1
  check "validation PASSes when all agreed terms present (C14/C17)" "[ $? -eq 0 ]"
  rm -rf "$WS"
else
  no "validation FAILs when an agreed term is missing (C15/C16) [script missing]"
  no "validation PASSes when all agreed terms present (C14/C17) [script missing]"
fi

echo "== Part C: hooks route must-do reads through the lane resolver (C1-C3) =="
# Every place a hook READS a must-do file (a `done < "...must-do..."` redirect) must go through
# mustdo_file_for_dir, never a hardcoded "${DIR}/must-do.md" literal. Otherwise lane-owned files
# are ignored and siblings collide.
for HK in pre-write-gate.sh on-prompt-submit.sh; do
  for BASE in "$HOME/.claude/hooks/$HK" "$(cd "$(dirname "$0")/.." && pwd)/_install/hooks/$HK"; do
    [ -f "$BASE" ] || continue
    LBL=$(basename "$(dirname "$BASE")")
    BAD=$(grep -nE 'done < "\$\{[A-Za-z_]+\}/must-do\.md"' "$BASE" 2>/dev/null | wc -l | tr -d ' ')
    check "$HK ($LBL): no hardcoded must-do.md read redirect" "[ \"$BAD\" -eq 0 ]"
    check "$HK ($LBL): references mustdo_file_for_dir" "grep -q 'mustdo_file_for_dir' \"$BASE\""
  done
done

echo "== Part D: trigger signal + PLAN-entry gate (C12) =="
PROMPT_HOOK="$HOME/.claude/hooks/on-prompt-submit.sh"
GATE_HOOK="$HOME/.claude/hooks/pre-write-gate.sh"

# D1: '+++pack' builds the owned pack (raw conversation captured + relinked).
if [ -f "$PROMPT_HOOK" ]; then
  D1=$(mktemp -d); mkdir -p "$D1/docs/must do" "$D1/.claude/state"
  printf '{"line":1}\n{"line":2}\n' > "$D1/transcript.jsonl"
  ( cd "$D1" && printf '{"prompt":"+++pack","transcript_path":"%s/transcript.jsonl"}' "$D1" \
      | HARNESS_STATE_DIR="$D1/.claude/state" bash "$PROMPT_HOOK" >/dev/null 2>&1 )
  check "+++pack built owned must-do.md with raw-conversation link" \
    "grep -qiF 'raw-conversation' '$D1/docs/must do/must-do.md'"
  check "+++pack copied transcript verbatim into pack" \
    "[ -f '$D1/docs/must do/raw-conversation.jsonl' ]"
  rm -rf "$D1"
else
  no "on-prompt-submit.sh present (skipped D1)"
fi

# D2: PLAN-entry gate blocks product-spec write with no pack, allows once pack exists (opt-in).
if [ -f "$GATE_HOOK" ]; then
  D2=$(mktemp -d); mkdir -p "$D2/docs/must do" "$D2/.claude/state" "$D2/.claude/specs"
  printf '{"phase":"PLAN","sprint":0}' > "$D2/.claude/state/current-phase.json"
  printf '{"require_pack":true}' > "$D2/.claude/mustdo-pack.json"
  GATE_IN=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/specs/product-spec.md"}}' "$D2")
  ( cd "$D2" && printf '%s' "$GATE_IN" | HARNESS_STATE_DIR="$D2/.claude/state" bash "$GATE_HOOK" >/dev/null 2>&1 )
  RC_NOPACK=$?
  check "PLAN-entry gate BLOCKS product-spec write when no pack (exit 2)" "[ $RC_NOPACK -eq 2 ]"
  # Now create a pack and re-test — should no longer block on the pack gate.
  printf '# Must-Do\n## Grounding\n- [Raw conversation](raw-conversation.jsonl)\n' > "$D2/docs/must do/must-do.md"
  ( cd "$D2" && printf '%s' "$GATE_IN" | HARNESS_STATE_DIR="$D2/.claude/state" bash "$GATE_HOOK" >/dev/null 2>&1 )
  RC_PACK=$?
  check "PLAN-entry gate does NOT block on pack once pack exists" "[ $RC_PACK -ne 2 ]"
  rm -rf "$D2"
else
  no "pre-write-gate.sh present (skipped D2)"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
