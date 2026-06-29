#!/bin/bash
# test-no-autocreate-claude.sh — running the harness in a NON-project folder must create NO .claude.
# find_project_state_dir must NOT treat the global ~/.claude as a project root, and the hooks must be
# INERT (create nothing) when there is no project .claude up the tree.
set -u
HELP="$HOME/.claude/scripts/lib-helpers.sh"
HOOKS="$HOME/.claude/hooks"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/nac-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT

resolve(){ # $1=cwd $2=HOME-override -> echoes find_project_state_dir result
  ( cd "$1" 2>/dev/null && HOME="$2" bash -c 'source "'"$HELP"'" 2>/dev/null; find_project_state_dir "$(pwd -W 2>/dev/null || pwd)" 2>/dev/null' )
}

# T1: a no-project folder under a HOME that has its OWN ~/.claude -> resolves to EMPTY (global excluded)
mkdir -p "$SBX/home/.claude/state" "$SBX/home/newfolder/sub"
R=$(resolve "$SBX/home/newfolder/sub" "$SBX/home")
[ -z "$R" ] && ok "T1 no-project folder under HOME -> empty (global ~/.claude not a root)" || bad "T1 returned '$R'"

# T2: a no-project folder NOT under any .claude -> empty (HOME=sandbox root so the walk stops there
#     instead of escaping up to the real ~/.claude, which physically sits above the temp sandbox)
mkdir -p "$SBX/elsewhere/proj/code"
R=$(resolve "$SBX/elsewhere/proj/code" "$SBX")
[ -z "$R" ] && ok "T2 isolated no-project folder -> empty" || bad "T2 returned '$R'"

# T3: a REAL project (has .claude) still resolves to it (don't break the harness)
mkdir -p "$SBX/home/realproj/.claude/state" "$SBX/home/realproj/sub"
R=$(resolve "$SBX/home/realproj/sub" "$SBX/home")
printf '%s' "$R" | grep -q "realproj/.claude/state" && ok "T3 real project still resolves to its root" || bad "T3 '$R'"

# T4: running the auto-firing hooks from a NO-PROJECT folder must create NO .claude.
#     (Real HOME so hooks can source lib-helpers; the folder is isolated with no .claude above it
#      before $HOME, and $HOME's own ~/.claude must be excluded.)
NP="$SBX/scratch_no_project"; mkdir -p "$NP"
made=""
for h in on-prompt-submit.sh post-write-check.sh agent-call-tracker.sh on-test-failure.sh on-stuck-detected.sh pre-phase-start.sh; do
  [ -f "$HOOKS/$h" ] || continue
  rm -rf "$NP/.claude"
  printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"note.txt","content":"hello"},"prompt":"please do a small task","session_id":"t","cwd":"'"$NP"'"}' \
    | ( cd "$NP" && bash "$HOOKS/$h" >/dev/null 2>&1 )
  [ -d "$NP/.claude" ] && made="$made $h"
done
[ -z "$made" ] && ok "T4 no hook creates .claude in a no-project folder" || bad "T4 these created .claude:$made"

# T5: HARNESS_STATE_DIR override still works (sandboxed tests unaffected)
R=$(cd "$SBX/elsewhere" && HARNESS_STATE_DIR="$SBX/sb/state" bash -c 'source "'"$HELP"'" 2>/dev/null; find_project_state_dir "$(pwd)"' 2>/dev/null)
[ "$R" = "$SBX/sb/state" ] && ok "T5 HARNESS_STATE_DIR override honored" || bad "T5 '$R'"

bash -n "$HELP" 2>/dev/null && ok "bash -n lib-helpers" || bad "bash -n"
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
