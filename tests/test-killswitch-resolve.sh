#!/usr/bin/env bash
# TDD for the cwd-independent kill-switch (Sprint 35).
# The OFF flag must be honored by the PROJECT ROOT that owns the file being written (or the cwd),
# not by a cwd-relative .claude/state. This fixes nested-root projects (e.g. claude-mesh/seo/api)
# where `---` at one root left agents in another root locked.
#
# Drives the LIVE hooks. Run: bash tests/test-killswitch-resolve.sh
set -u
PASS=0; FAIL=0
WRITE_HOOK="$HOME/.claude/hooks/pre-write-gate.sh"
PROMPT_HOOK="$HOME/.claude/hooks/on-prompt-submit.sh"
ok(){ PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }

# Run a Write through the live pre-write-gate from a given cwd. $1=cwd $2=abs target file.
# Echoes the exit code. NOTE: we do NOT set HARNESS_STATE_DIR — we want the real cwd/path resolution.
run_write() {
  local CWD="$1" F="$2" RC
  ( cd "$CWD" && printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$F" \
      | bash "$WRITE_HOOK" >/dev/null 2>&1 ); RC=$?
  printf '%s' "$RC"
}

# Build a project root in PLAN phase (so source writes are blocked unless the kill-switch bypasses).
mk_root() {
  local R="$1"
  mkdir -p "$R/.claude/state"
  printf '{"phase":"PLAN","sprint":0,"iteration":1}' > "$R/.claude/state/current-phase.json"
}

BASE="$(mktemp -d)"
ROOT="$BASE/proj"; mk_root "$ROOT"                 # outer project root
NEST="$ROOT/seo/api"; mk_root "$NEST"              # NESTED project root (own .claude)
mkdir -p "$ROOT/sub"                               # plain subdir of ROOT (no .claude)

echo "== cwd-independent kill-switch =="

# Baseline: ROOT locked (no flag), PLAN -> writing a root source file is BLOCKED.
RC=$(run_write "$ROOT" "$ROOT/.editorconfig"); [ "$RC" = 2 ] && ok "baseline: locked ROOT blocks source write" || no "baseline expected block, got rc=$RC"

# Unlock ROOT only.
: > "$ROOT/.claude/state/harness-disabled.flag"

# T1 (the reported bug): agent cwd is the NESTED root (no flag), writing a ROOT-owned file.
#     Must be ALLOWED because the file's project (ROOT) is unlocked.
RC=$(run_write "$NEST" "$ROOT/.editorconfig"); [ "$RC" = 0 ] && ok "T1 nested cwd + ROOT-owned file + ROOT unlocked -> allowed" || no "T1 expected allow, got rc=$RC"

# T2: writing a NESTED-owned file from the nested root. NESTED has no flag -> stays governed (blocked).
#     (An unlocked parent must NOT silently unlock a locked child.)
RC=$(run_write "$NEST" "$NEST/x.py"); [ "$RC" = 2 ] && ok "T2 nested-owned file stays locked despite parent unlock" || no "T2 expected block, got rc=$RC"

# T3: cwd is ROOT (unlocked) -> writes bypass.
RC=$(run_write "$ROOT" "$ROOT/a.py"); [ "$RC" = 0 ] && ok "T3 cwd=unlocked ROOT -> allowed" || no "T3 expected allow, got rc=$RC"

# T4: cwd is a plain subdir of ROOT (no .claude); walk-up resolves to unlocked ROOT -> allowed.
RC=$(run_write "$ROOT/sub" "$ROOT/sub/b.py"); [ "$RC" = 0 ] && ok "T4 cwd=subdir resolves up to unlocked ROOT -> allowed" || no "T4 expected allow, got rc=$RC"

# Now unlock the NESTED root too and confirm nested writes free up.
: > "$NEST/.claude/state/harness-disabled.flag"
RC=$(run_write "$NEST" "$NEST/x.py"); [ "$RC" = 0 ] && ok "T5 nested unlocked -> nested write allowed" || no "T5 expected allow, got rc=$RC"

echo "== toggle write-side: --- lands the flag at the PROJECT ROOT =="
# Fresh root with a subdir; send '---' from the subdir; flag must land at ROOT/.claude/state.
ROOT2="$BASE/proj2"; mk_root "$ROOT2"; mkdir -p "$ROOT2/deep/dir"
( cd "$ROOT2/deep/dir" && printf '{"prompt":"---"}' | bash "$PROMPT_HOOK" >/dev/null 2>&1 )
if [ -f "$ROOT2/.claude/state/harness-disabled.flag" ]; then ok "--- from subdir writes flag to project ROOT"; else no "--- did not land flag at project root ($(find "$ROOT2" -name harness-disabled.flag 2>/dev/null | tr '\n' ' '))"; fi

rm -rf "$BASE"
echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
