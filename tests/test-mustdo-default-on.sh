#!/bin/bash
# test-mustdo-default-on.sh — TDD for making the must-do system DEFAULT-ON.
#
# Today the must-do summary gate only fires when a `docs/must do/` folder already exists
# (opt-in). These tests assert the inverted default: when the harness is ACTIVE and a
# session writes source code in BUILD, the gate REQUIRES a must-do grounding — and if none
# exists it BLOCKS, telling the model to create `docs/must do/must-do.md`. The ONLY escape
# is the `---` kill-switch (harness-disabled.flag). pre-bash-gate must enforce the same so
# code can't be written via `python -c` to bypass it.
#
# Drives the LIVE hooks through a HARNESS_STATE_DIR sandbox (pattern from test-mustdo-pack.sh).
# Run: bash tests/test-mustdo-default-on.sh

set -u
PASS=0; FAIL=0
WRITE_HOOK="$HOME/.claude/hooks/pre-write-gate.sh"
BASH_HOOK="$HOME/.claude/hooks/pre-bash-gate.sh"

ok()   { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else no "$1"; fi; }

# Build a sandbox project that satisfies the EARLIER gates (contract present, 0 writes so the
# watcher gate stays quiet), isolating the must-do behaviour. $1 = phase, $2 = sprint.
mk_sbx() {
  local S; S=$(mktemp -d)
  mkdir -p "$S/.claude/state" "$S/.claude/contracts" "$S/.claude/specs" "$S/src"
  printf '{"phase":"%s","sprint":%s,"iteration":1}' "$1" "$2" > "$S/.claude/state/current-phase.json"
  : > "$S/.claude/contracts/sprint-${2}-contract.md"
  printf '%s' "$S"
}

# Run a Write/Edit through the live pre-write-gate. $1=sandbox $2=target file (relative).
# Echoes "<rc>::<stderr>".
run_write() {
  local S="$1" F="$2" OUT RC
  OUT=$( cd "$S" && printf '{"tool_name":"Write","tool_input":{"file_path":"%s/%s"}}' "$S" "$F" \
         | HARNESS_STATE_DIR="$S/.claude/state" bash "$WRITE_HOOK" 2>&1 >/dev/null )
  RC=$?
  printf '%s::%s' "$RC" "$OUT"
}

# Run a file-writing Bash command through the live pre-bash-gate. $1=sandbox $2=target file.
run_bash() {
  local S="$1" F="$2" OUT RC CMD JSON
  # A python file-write the gate's detector recognises (python + open + write).
  CMD=$(printf "python -c 'open(\"%s/%s\",\"w\").write(1)'" "$S" "$F")
  # Build the hook payload with jq so the embedded command is escaped correctly
  # (hand-rolled JSON breaks on the command's own quotes -> empty COMMAND -> false pass).
  JSON=$(jq -n --arg c "$CMD" '{tool_name:"Bash",tool_input:{command:$c}}')
  OUT=$( cd "$S" && printf '%s' "$JSON" \
         | HARNESS_STATE_DIR="$S/.claude/state" bash "$BASH_HOOK" 2>&1 >/dev/null )
  RC=$?
  printf '%s::%s' "$RC" "$OUT"
}

echo "== pre-write-gate: default-on must-do =="

if [ -f "$WRITE_HOOK" ]; then
  # 1. No folder + BUILD + source write -> BLOCKED, message names the must-do file to create.
  S=$(mk_sbx BUILD 1); R=$(run_write "$S" "src/x.js"); RC=${R%%::*}; MSG=${R#*::}
  check "1. no folder + BUILD + source -> blocked (exit 2)" "[ \"$RC\" = 2 ]"
  check "1b. block message names docs/must do/must-do.md" "printf '%s' \"\$MSG\" | grep -qiF 'must-do.md'"
  rm -rf "$S"

  # 2. No folder + kill-switch -> ALLOWED (--- wins).
  S=$(mk_sbx BUILD 1); : > "$S/.claude/state/harness-disabled.flag"
  R=$(run_write "$S" "src/x.js"); RC=${R%%::*}
  check "2. no folder + harness-disabled.flag -> allowed (exit 0)" "[ \"$RC\" = 0 ]"
  rm -rf "$S"

  # 3. No folder + PLAN: the must-do default-on must NOT fire (it is BUILD-scoped). A source
  #    write in PLAN is still blocked by the PHASE gate, but the block must NOT be the must-do
  #    one — proving must-do enforcement doesn't leak into PLAN and obstruct grounding work.
  S=$(mk_sbx PLAN 1); R=$(run_write "$S" "src/x.js"); MSG=${R#*::}
  check "3. no folder + PLAN -> block is NOT the must-do gate" "! printf '%s' \"\$MSG\" | grep -qiF 'must-do.md'"
  rm -rf "$S"

  # 4. No folder + BUILD + writing the must-do file / docs / .md -> ALLOWED (no deadlock).
  S=$(mk_sbx BUILD 1)
  R=$(run_write "$S" "docs/must do/must-do.md"); RC=${R%%::*}
  check "4a. writing docs/must do/must-do.md -> not blocked (exit != 2)" "[ \"$RC\" != 2 ]"
  R=$(run_write "$S" "README.md"); RC=${R%%::*}
  check "4b. writing a .md file -> not blocked (exit != 2)" "[ \"$RC\" != 2 ]"
  rm -rf "$S"

  # 5. Folder + file + valid summary -> ALLOWED (anti-regression: existing behaviour preserved).
  S=$(mk_sbx BUILD 1); mkdir -p "$S/docs/must do"
  printf 'docs/ref-one.md\n' > "$S/docs/must do/must-do.md"; : > "$S/docs/ref-one.md"
  printf 'I read ref-one.md and understand the constraints in must-do.md fully. ' > "$S/.claude/state/must-do-summary.md"
  printf 'This summary is intentionally over two hundred characters long so it satisfies the minimum length requirement that the must-do summary gate enforces before it permits any source code writes to proceed.\n' >> "$S/.claude/state/must-do-summary.md"
  R=$(run_write "$S" "src/x.js"); RC=${R%%::*}
  check "5. folder + valid summary -> allowed (exit 0)" "[ \"$RC\" = 0 ]"
  rm -rf "$S"
else
  no "pre-write-gate.sh present (skipped write-gate tests)"
fi

echo "== pre-bash-gate: same enforcement (no bash bypass) =="

if [ -f "$BASH_HOOK" ]; then
  # 6a. No folder + BUILD + bash source write -> BLOCKED (bypass closed).
  S=$(mk_sbx BUILD 1); R=$(run_bash "$S" "src/x.js"); RC=${R%%::*}; MSG=${R#*::}
  check "6a. bash source write + no folder -> blocked (exit 2)" "[ \"$RC\" = 2 ]"
  check "6b. bash block message names must-do.md" "printf '%s' \"\$MSG\" | grep -qiF 'must-do.md'"
  rm -rf "$S"

  # 6c. No folder + kill-switch -> ALLOWED via bash too.
  S=$(mk_sbx BUILD 1); : > "$S/.claude/state/harness-disabled.flag"
  R=$(run_bash "$S" "src/x.js"); RC=${R%%::*}
  check "6c. bash + harness-disabled.flag -> allowed (exit 0)" "[ \"$RC\" = 0 ]"
  rm -rf "$S"

  # 6d. No folder + bash writing the must-do file itself -> ALLOWED (no deadlock).
  S=$(mk_sbx BUILD 1); R=$(run_bash "$S" "docs/must do/must-do.md"); RC=${R%%::*}
  check "6d. bash writing docs/must do/must-do.md -> not blocked (exit != 2)" "[ \"$RC\" != 2 ]"
  rm -rf "$S"
else
  no "pre-bash-gate.sh present (skipped bash-gate tests)"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
