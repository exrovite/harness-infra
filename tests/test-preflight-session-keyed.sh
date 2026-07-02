#!/usr/bin/env bash
# Sprint 31a — per-session pre-flight isolation. Concurrent agents in one folder must NOT share
# challenge/response files. Each session gets its own .claude/pre-flight/<session_id>/ subdir; flat
# fallback when no session id.
# Sprint 50 REWRITE: since Sprint 47 the generator resolves the SESSION's OWN watcher slot (not the
# project's first), so fake session ids need real registry entries. This suite now runs the REAL
# generate + validate scripts inside a fake-HOME sandbox carrying its own registry, slot files, and
# distractor pool — preserving the original isolation assertions without touching the live registry.
set -u
GEN="$HOME/.claude/scripts/generate-pre-flight-challenge.sh"
VAL="$HOME/.claude/scripts/validate-pre-flight.sh"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

A="testsidAAA"; B="testsidBBB"
S=$(mktemp -d)
mkdir -p "$S/.openclaw/watchers" "$S/.openclaw/distractor-pool" "$S/.claude/state" "$S/tests"
# The generator's no-session fallback compares registry .project against `pwd -W` — store the
# Windows-form path so the flat-fallback assertion exercises the real comparison.
SW=$(cd "$S" && (pwd -W 2>/dev/null || pwd))
printf '{"version":"3.0.0","max_per_project":5,"watchers":[
  {"slot":8,"project":"%s","session_id":"%s","status":"active","claimed_by":"t","claimed_at":"2026-07-02T00:00:00","last_seen":"2026-07-02T00:00:00","cron_job_id":"x","cron_interval":"*/3 * * * *"},
  {"slot":9,"project":"%s","session_id":"%s","status":"active","claimed_by":"t","claimed_at":"2026-07-02T00:00:00","last_seen":"2026-07-02T00:00:00","cron_job_id":"x","cron_interval":"*/3 * * * *"}]}' \
  "$SW" "$A" "$SW" "$B" > "$S/.openclaw/watchers/REGISTRY.json"
for N in 8 9; do
  printf '# Watcher Slot %s\n\n**Status**: active\n**Task**: Session task %s\n\n## TO-DO LIST\n- [ ] Step 1: do thing %s\n\n## MISTAKES TO AVOID\n- Do not cross the streams %s\n' "$N" "$N" "$N" "$N" > "$S/.openclaw/watchers/slot-${N}.md"
done
for p in tasks steps files constraints; do
  printf 'Filler one %s\nFiller two %s\nFiller three %s\nFiller four %s\n' "$p" "$p" "$p" "$p" > "$S/.openclaw/distractor-pool/$p.txt"
done

PF="$S/.claude/pre-flight"

# Two concurrent sessions generate challenges (each keyed to its OWN watcher slot)
( cd "$S" && HOME="$S" bash "$GEN" "tests/aaa.js" "$A" >/dev/null 2>&1 )
( cd "$S" && HOME="$S" bash "$GEN" "tests/bbb.js" "$B" >/dev/null 2>&1 )

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
( cd "$S" && HOME="$S" bash "$VAL" "$A" >/dev/null 2>&1 ); RA=$?
if [ "$RA" -ne 0 ] && [ -f "$PF/$B/challenge.md" ]; then
  ok "validating session A (wrong answers) does not touch session B's files"
else
  no "cross-session validate isolation (RA=$RA)"
fi

# Flat fallback: no session id -> writes to flat .claude/pre-flight (back-compat, project-first slot)
( cd "$S" && HOME="$S" bash "$GEN" "tests/flat.js" >/dev/null 2>&1 )
if [ -f "$PF/challenge.md" ]; then ok "no-session -> flat .claude/pre-flight (back-compat)"; else no "flat fallback"; fi

rm -rf "$S"
echo "-- RESULT: $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
