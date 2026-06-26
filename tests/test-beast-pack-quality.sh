#!/bin/bash
# test-beast-pack-quality.sh — Sprint 40: precision of the literal pack (kill trigger noise).
# A lesson must anchor on a DISTINCTIVE token (identifier / technical term), never fire on
# common words alone, never default to wildcard scope, and skip harness/state-file commits.
set -u
PACK="$HOME/.claude/scripts/beast-pack.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

SBX=$(mktemp -d 2>/dev/null || echo "/tmp/bpq-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT
P="$SBX/p"; mkdir -p "$P"
( cd "$P" && git init -q && git config user.email a@a && git config user.name a
  printf 'x\n' > lib-helpers.sh && git add . && git commit -qm "init"
  # (A) distinctive fix -> should produce a lesson anchored on the identifier
  printf 'y\n' >> lib-helpers.sh && git add . && git commit -qm "Fix find_project_state_dir cwd resolution in lib-helpers.sh"
  # (B) generic-words-only fix -> should NOT produce a broad/common-word trigger
  printf 'z\n' >> lib-helpers.sh && git add . && git commit -qm "fix the working system on intro module so it is better now"
  # (C) harness/state-file commit -> should be skipped (not a real gotcha)
  mkdir -p .agent-memory && printf '{}' > .agent-memory/MEMORY_MANIFEST.json && git add . && git commit -qm "Fix update MEMORY_MANIFEST.json session summary parallel"
) 2>/dev/null

L="$P/.beast/lessons.jsonl"
[ -f "$PACK" ] || { bad "pack exists"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
BEAST_PACK_ROOT="$P" BEAST_LESSONS="$L" bash "$PACK" >/dev/null 2>&1
[ -f "$L" ] && ok "pack ran" || { bad "pack produced lessons.jsonl"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

COMMON='\bintro\b|\bsystem\b|\bworking\b|\bmodule\b|\bbetter\b|\bnow\b|\bsession\b|\bsummary\b|\bparallel\b|\bupdate\b'

# 1. The distinctive identifier becomes a trigger
grep -q 'find_project_state_dir' "$L" && ok "distinctive identifier captured as trigger" || bad "missing find_project_state_dir lesson"

# 2. NO lesson has a trigger built from common words
NOISE=0
while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  trig=$(printf '%s' "$line" | jq -r '.trigger' 2>/dev/null)
  printf '%s' "$trig" | grep -qE "$COMMON" && { NOISE=$((NOISE+1)); printf '   noisy trigger: %s\n' "$trig"; }
done < "$L"
[ "$NOISE" -eq 0 ] && ok "no common-word triggers" || bad "$NOISE common-word trigger(s) present"

# 3. No wildcard-scope lesson from a git commit (commits always have a file)
GITWILD=$(grep -c '"scope":"\*"' "$L" 2>/dev/null); [ -n "$GITWILD" ] || GITWILD=0
[ "$GITWILD" -eq 0 ] && ok "no wildcard-scope lessons" || bad "$GITWILD wildcard-scope lesson(s)"

# 4. Harness/state-file commit (MEMORY_MANIFEST.json) is skipped
grep -q 'MEMORY_MANIFEST' "$L" && bad "harness/state-file commit should be skipped" || ok "harness/state-file commit skipped"

# 5. Every lesson trigger has at least one DISTINCTIVE token (len>=5 or has _ or digit)
WEAK=0
while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  trig=$(printf '%s' "$line" | jq -r '.trigger' 2>/dev/null)
  printf '%s' "$trig" | tr '|' '\n' | grep -qE '.{6,}|_|[0-9]' || { WEAK=$((WEAK+1)); printf '   weak trigger: %s\n' "$trig"; }
done < "$L"
[ "$WEAK" -eq 0 ] && ok "every trigger has a distinctive token" || bad "$WEAK weak trigger(s)"

bash -n "$PACK" 2>/dev/null && ok "bash -n clean" || bad "bash -n"
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
