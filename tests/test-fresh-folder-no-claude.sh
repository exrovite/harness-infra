#!/bin/bash
# test-fresh-folder-no-claude.sh — THE real-scenario test.
# Simulate "user opens Claude in a brand-new folder and Claude writes a file": fire EVERY hook wired in
# settings.json, in order, with realistic stdin, from a fresh folder that is NOT a harness project.
# After EACH hook assert that NEITHER .claude NOR .agent-memory was created. Reports the exact culprit.
#
# Uses the REAL $HOME so hooks can source lib-helpers; the sandbox sits under the real $HOME, so the
# resolver's walk-up must stop at $HOME before reaching the global ~/.claude.
set -u
HOOKS="$HOME/.claude/hooks"
SCRIPTS="$HOME/.claude/scripts"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/ffnc-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT

# A genuinely fresh project folder — no .claude / .agent-memory anywhere inside or above (until $HOME).
NP="$SBX/BrandNewProject"
mkdir -p "$NP"

stdin_for(){ # realistic superset event for any harness hook
  printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"'"$NP"'/note.txt","content":"hello world"},"tool_response":{"filePath":"'"$NP"'/note.txt"},"prompt":"create a small file called note.txt","session_id":"fresh-test-sess","cwd":"'"$NP"'","stop_hook_active":false}'
}

# The full wired chain, in realistic firing order. (allow-claude-dir + collect-test-evidence included.)
# startup-recovery.sh is included because post-write-check / run-harness invoke it and it was THE creator.
CHAIN="on-prompt-submit.sh pre-write-gate.sh pre-flight-gate.sh pre-bash-gate.sh beast-recall-hook.sh beast-protocol-gate.sh allow-claude-dir.sh post-write-check.sh beast-watch-hook.sh agent-call-tracker.sh collect-test-evidence.sh on-session-end.sh"
SR="$SCRIPTS/startup-recovery.sh"

culprits=""
for h in $CHAIN; do
  [ -f "$HOOKS/$h" ] || continue
  # Claude itself would have created the file the user asked for; simulate that BEFORE post/stop hooks.
  case "$h" in post-write-check.sh|beast-watch-hook.sh|on-session-end.sh) [ -f "$NP/note.txt" ] || printf 'hello world\n' > "$NP/note.txt" ;; esac
  stdin_for | ( cd "$NP" && bash "$HOOKS/$h" >/dev/null 2>&1 )
  if [ -d "$NP/.claude" ] || [ -d "$NP/.agent-memory" ]; then
    culprits="$culprits $h"
    printf '   >> %s created: %s\n' "$h" "$(ls -d "$NP"/.claude "$NP"/.agent-memory 2>/dev/null | tr '\n' ' ')"
    rm -rf "$NP/.claude" "$NP/.agent-memory"   # reset so we catch EACH independently
  fi
done
[ -z "$culprits" ] && ok "no wired hook creates .claude/.agent-memory in a fresh folder" || bad "hooks that created state in a fresh folder:$culprits"

# startup-recovery.sh run DIRECTLY in a fresh folder must create NOTHING (it was THE confirmed creator).
rm -rf "$NP/.claude" "$NP/.agent-memory"
if [ -f "$SR" ]; then
  ( cd "$NP" && bash "$SR" >/dev/null 2>&1 )
  { [ ! -d "$NP/.claude" ] && [ ! -d "$NP/.agent-memory" ]; } && ok "startup-recovery creates no .claude in a fresh folder" || bad "startup-recovery created .claude in a fresh folder"
fi

# Transitive path: post-write-check is invoked from a fresh folder that happens to have a stray
# current-phase.json should still NOT exist; but verify the FIRST-write path (write-count 0) doesn't
# bootstrap. Run post-write-check 3x from the fresh folder — must stay clean (it must not reach
# startup-recovery, which only fires when current-phase.json already exists).
rm -rf "$NP/.claude" "$NP/.agent-memory"
for i in 1 2 3; do
  printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"'"$NP"'/g'"$i"'.txt","content":"y"},"session_id":"s","cwd":"'"$NP"'"}' \
    | ( cd "$NP" && bash "$HOOKS/post-write-check.sh" >/dev/null 2>&1 )
done
{ [ ! -d "$NP/.claude" ] && [ ! -d "$NP/.agent-memory" ]; } && ok "post-write-check first-write path bootstraps nothing in a fresh folder" || bad "post-write-check bootstrapped state in a fresh folder"

# write-handoff.sh (a confirmed cwd-relative creator) run directly in a fresh folder must create nothing.
rm -rf "$NP/.claude" "$NP/.agent-memory"
if [ -f "$SCRIPTS/write-handoff.sh" ]; then
  ( cd "$NP" && bash "$SCRIPTS/write-handoff.sh" "CRASH_RECOVERY" >/dev/null 2>&1 )
  [ ! -d "$NP/.claude" ] && ok "write-handoff creates no .claude in a fresh folder" || bad "write-handoff created .claude in a fresh folder"
fi

# OPT-IN still works: explicitly running init-project in a fresh folder DOES create .claude (the user's
# deliberate setup must not be broken by the no-autocreate guards).
OPT="$SBX/DeliberateProject"; mkdir -p "$OPT"
( cd "$OPT" && bash "$SCRIPTS/init-project.sh" >/dev/null 2>&1 )
[ -d "$OPT/.claude" ] && ok "explicit init-project still creates .claude (opt-in preserved)" || bad "explicit init-project no longer initializes a fresh project"

# A real project: startup-recovery resolves to the EXISTING root and does its job, creating nothing new
# outside it.
SRP="$SBX/sr_realproj"; mkdir -p "$SRP/.claude/state" "$SRP/work"; printf '{"phase":"BUILD","sprint":1,"iteration":0}\n' > "$SRP/.claude/state/current-phase.json"
( cd "$SRP/work" && bash "$SR" >/dev/null 2>&1 )
[ ! -d "$SRP/work/.claude" ] && ok "startup-recovery in a real-project subdir makes no nested .claude" || bad "startup-recovery made a nested .claude in a real project subdir"

# Also: a direct file write that triggers post-write-check via its real PostToolUse contract, repeated
# (simulates several writes — the write-counter path that used to mkdir .claude/state).
rm -rf "$NP/.claude" "$NP/.agent-memory"
for i in 1 2 3 4 5; do
  printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"'"$NP"'/f'"$i"'.txt","content":"x"},"session_id":"s","cwd":"'"$NP"'"}' \
    | ( cd "$NP" && bash "$HOOKS/post-write-check.sh" >/dev/null 2>&1 )
done
{ [ ! -d "$NP/.claude" ] && [ ! -d "$NP/.agent-memory" ]; } && ok "5x post-write-check writes create no state in a fresh folder" || bad "repeated post-write-check created state"

# Sanity: a REAL project still works — its hooks DO write into the existing root (don't over-correct).
RP="$SBX/realproj"; mkdir -p "$RP/.claude/state"; printf '{"phase":"BUILD","sprint":1}\n' > "$RP/.claude/state/current-phase.json"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"'"$RP"'/a.txt","content":"x"},"session_id":"s","cwd":"'"$RP"'"}' \
  | ( cd "$RP" && bash "$HOOKS/post-write-check.sh" >/dev/null 2>&1 )
[ -f "$RP/.claude/state/write-count.txt" ] && ok "real project: post-write-check still records its write" || bad "real project: post-write-check did not record (over-corrected)"

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
