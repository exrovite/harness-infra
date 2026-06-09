#!/usr/bin/env bash
# Sprint 31a — per-session pre-flight isolation. Concurrent agents in one folder must NOT share
# challenge/response files (that caused a regenerate/file-rotation thrash). Each session gets its own
# .claude/pre-flight/<session_id>/ subdir. Flat fallback when no session id.
# Drives the REAL generate + validate scripts. Needs an active watcher for the test project, so it runs
# against THIS project's cwd (which has a claimed watcher) using two distinct session ids.
set -u
GEN="$HOME/.claude/scripts/generate-pre-flight-challenge.sh"
VAL="$HOME/.claude/scripts/validate-pre-flight.sh"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

A="testsidAAA"; B="testsidBBB"
PF=".claude/pre-flight"

# clean any leftovers
rm -rf "$PF/$A" "$PF/$B" 2>/dev/null

# Two concurrent sessions generate challenges (real watcher slot of THIS project)
bash "$GEN" "tests/aaa.js" "$A" >/dev/null 2>&1
bash "$GEN" "tests/bbb.js" "$B" >/dev/null 2>&1

if [ -f "$PF/$A/challenge.md" ] && [ -f "$PF/$B/challenge.md" ]; then
  ok "two sessions -> two isolated challenge subdirs (no shared file)"
else
  no "isolated subdirs (A=$([ -f "$PF/$A/challenge.md" ] && echo y||echo n) B=$([ -f "$PF/$B/challenge.md" ] && echo y||echo n))"
fi

# Each challenge references its OWN target file (proves no cross-contamination)
if grep -q 'tests/aaa.js' "$PF/$A/challenge.md" 2>/dev/null && grep -q 'tests/bbb.js' "$PF/$B/challenge.md" 2>/dev/null; then
  ok "each session's challenge holds its OWN target file"
else
  no "per-session target isolation"
fi

# A's response does not affect B: write A a (wrong) response, validate A fails, B's challenge untouched
printf 'Q1: Z\n' > "$PF/$A/response.md"
VA=$(bash "$VAL" "$A" 2>&1); RA=$?
if [ "$RA" -ne 0 ] && [ -f "$PF/$B/challenge.md" ]; then
  ok "validating session A (wrong answers) does not touch session B's files"
else
  no "cross-session validate isolation (RA=$RA)"
fi

# Flat fallback: no session id -> writes to flat .claude/pre-flight (back-compat)
rm -f "$PF/challenge.md" 2>/dev/null
bash "$GEN" "tests/flat.js" >/dev/null 2>&1
if [ -f "$PF/challenge.md" ]; then ok "no-session -> flat .claude/pre-flight (back-compat)"; else no "flat fallback"; fi

# cleanup test artifacts
rm -rf "$PF/$A" "$PF/$B" 2>/dev/null
rm -f "$PF/challenge.md" 2>/dev/null

echo "-- RESULT: $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
