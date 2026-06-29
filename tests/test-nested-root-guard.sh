#!/bin/bash
# test-nested-root-guard.sh — the harness must NOT create nested .claude project roots.
# init-project.sh must refuse to create a .claude when an ancestor already has one (an existing
# project), but still init a genuinely fresh project; the global ~/.claude must never block.
# pre-flight-gate.sh / agent-call-tracker.sh must not create a bare cwd-relative .claude/pre-flight.
set -u
INIT="$HOME/.claude/scripts/init-project.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/nrg-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT

# an existing project with a root .claude
mkdir -p "$SBX/proj/.claude/state" "$SBX/proj/sub/deeper" "$SBX/proj/.claude/specs"
printf '{"phase":"BUILD","sprint":1}\n' > "$SBX/proj/.claude/state/current-phase.json"

[ -f "$INIT" ] || { bad "init-project.sh exists"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
ok "init-project.sh exists"

# T1: running init from a SUBDIR of an existing project -> must NOT create a nested .claude there
( cd "$SBX/proj/sub" && bash "$INIT" >/dev/null 2>&1 )
[ ! -d "$SBX/proj/sub/.claude" ] && ok "T1 no nested .claude in a subdir of an existing project" || bad "T1 nested .claude created in subdir"

# T2: deeper subdir -> still refuses
( cd "$SBX/proj/sub/deeper" && bash "$INIT" >/dev/null 2>&1 )
[ ! -d "$SBX/proj/sub/deeper/.claude" ] && ok "T2 no nested .claude in a deep subdir" || bad "T2 nested .claude in deep subdir"

# T3: running init INSIDE .claude/state (a .claude inside .claude) -> must refuse
( cd "$SBX/proj/.claude/state" && bash "$INIT" >/dev/null 2>&1 )
[ ! -d "$SBX/proj/.claude/state/.claude" ] && ok "T3 no .claude inside .claude/state" || bad "T3 .claude created inside .claude/state"
( cd "$SBX/proj/.claude/specs" && bash "$INIT" >/dev/null 2>&1 )
[ ! -d "$SBX/proj/.claude/specs/.claude" ] && ok "T3b no .claude inside .claude/specs" || bad "T3b nested in specs"

# T4: a GENUINELY fresh project (no ancestor .claude up to $HOME) -> init DOES create .claude
mkdir -p "$SBX/fresh/code"
( cd "$SBX/fresh" && bash "$INIT" >/dev/null 2>&1 )
[ -d "$SBX/fresh/.claude" ] && ok "T4 fresh project still gets a .claude" || bad "T4 fresh project not initialized"

# T5: re-running init at the TRUE root is fine (idempotent, no nested)
( cd "$SBX/proj" && bash "$INIT" >/dev/null 2>&1 )
{ [ -d "$SBX/proj/.claude" ] && [ ! -d "$SBX/proj/.claude/.claude" ]; } && ok "T5 root re-init idempotent, no .claude/.claude" || bad "T5 root re-init created .claude/.claude"

# T6: the global ~/.claude must NEVER be treated as a project root (else projects under HOME break).
#     Simulate a project directly under a fake HOME that has its own ~/.claude.
mkdir -p "$SBX/home/.claude/state" "$SBX/home/myproject/src"
( cd "$SBX/home/myproject" && HOME="$SBX/home" bash "$INIT" >/dev/null 2>&1 )
[ -d "$SBX/home/myproject/.claude" ] && ok "T6 project under HOME inits (global ~/.claude doesn't block)" || bad "T6 ~/.claude wrongly blocked a project under HOME"
# but a subdir of that project still refuses
( cd "$SBX/home/myproject/src" && HOME="$SBX/home" bash "$INIT" >/dev/null 2>&1 )
[ ! -d "$SBX/home/myproject/src/.claude" ] && ok "T6b subdir under HOME-project still refuses" || bad "T6b nested under HOME-project"

# T7: static — no bare cwd-relative `mkdir -p .claude/pre-flight` in the pre-flight hooks
if grep -qnE '^[[:space:]]*mkdir -p \.claude/pre-flight([[:space:]]|$)' "$HOME/.claude/hooks/pre-flight-gate.sh" "$HOME/.claude/hooks/agent-call-tracker.sh" 2>/dev/null; then
  bad "T7 bare cwd-relative 'mkdir -p .claude/pre-flight' remains"
else ok "T7 no bare cwd-relative .claude/pre-flight mkdir"; fi

# T8: auto-firing hooks must not create a nested .claude when run from a SUBDIR of a project
mkdir -p "$SBX/proj2/.claude/state" "$SBX/proj2/sub"
printf '{"phase":"BUILD","sprint":1}\n' > "$SBX/proj2/.claude/state/current-phase.json"
H8=0
for h in agent-call-tracker.sh on-test-failure.sh on-stuck-detected.sh pre-phase-start.sh; do
  [ -f "$HOME/.claude/hooks/$h" ] || continue
  rm -rf "$SBX/proj2/sub/.claude"
  printf '%s' '{"tool_name":"Agent","tool_input":{"command":"pytest","description":"verify the build"}}' \
    | ( cd "$SBX/proj2/sub" && bash "$HOME/.claude/hooks/$h" >/dev/null 2>&1 )
  [ -d "$SBX/proj2/sub/.claude" ] && { H8=1; printf '   %s created a nested .claude\n' "$h"; }
done
[ "$H8" = 0 ] && ok "T8 auto-firing hooks create no nested .claude from a subdir" || bad "T8 a hook created a nested .claude"

bash -n "$INIT" 2>/dev/null && ok "bash -n init-project.sh" || bad "bash -n"
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
