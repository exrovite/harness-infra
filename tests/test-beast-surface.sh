#!/bin/bash
# test-beast-surface.sh — Deterministic intuition surfacing (Sprint 35)
# The core mechanism of the intuition system: given a proposed action, the
# harness deterministically scans planted lessons by their stable atoms
# (file scope glob + trigger regex over content) and emits an adversarial
# injection packet for matches, or SILENCE for non-matches. Pure function:
# same input -> identical output. No LLM at recall time.
#
# Usage: bash tests/test-beast-surface.sh
set -u

SCRIPTS="$HOME/.claude/scripts"
SURFACE="$SCRIPTS/beast-surface.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

SBX=$(mktemp -d 2>/dev/null || echo "/tmp/bsurf-$$")
LESSONS="$SBX/lessons.jsonl"
export BEAST_LESSONS="$LESSONS"
cleanup() { rm -rf "$SBX" 2>/dev/null; }
trap cleanup EXIT

# Plant a single, genuinely-true lesson from this project's history:
# the MSYS sed->tr bug (MEMORY.md "MSYS sed Path Bug").
cat > "$LESSONS" <<'EOF'
{"id":"M1","scope":"*.sh","trigger":"sed","lesson":"On MSYS/Git Bash, `sed 's|\\\\|/|g'` crashes with 'unterminated s command' — this has broken the harness TWICE.","fix":"Use `tr '\\\\' '/'` instead of sed for backslash-to-forward-slash conversion.","dossier":"MEMORY.md#msys-sed"}
EOF

run() { printf '%s' "$1" | bash "$SURFACE" 2>/dev/null; }

if [ ! -f "$SURFACE" ]; then
  bad "beast-surface.sh exists at $SURFACE"
  echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
ok "beast-surface.sh exists"

# 1. MATCH: a .sh action whose content mentions sed -> packet fires, names M1 + the fix
MATCH='{"file_path":"convert-paths.sh","content":"write a sed command to convert backslashes to forward slashes"}'
OUT=$(run "$MATCH")
printf '%s' "$OUT" | grep -q 'M1' && ok "match: packet contains [M1]" || bad "match: packet contains [M1] (got: $OUT)"
printf '%s' "$OUT" | grep -qi 'tr ' && ok "match: packet carries the fix (tr)" || bad "match: packet carries the fix (got: $OUT)"
printf '%s' "$OUT" | grep -qiE 'before you|stop|past-you' && ok "match: adversarial framing present" || bad "match: adversarial framing present"

# 2. NON-MATCH by scope: a .md file -> SILENCE (empty output)
NOMATCH_SCOPE='{"file_path":"notes.md","content":"use sed here"}'
OUT=$(run "$NOMATCH_SCOPE")
[ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ] && ok "non-match (scope): silence" || bad "non-match (scope): expected silence (got: $OUT)"

# 3. NON-MATCH by trigger: a .sh file with no trigger keyword -> SILENCE
NOMATCH_TRIG='{"file_path":"hello.sh","content":"echo hello world"}'
OUT=$(run "$NOMATCH_TRIG")
[ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ] && ok "non-match (trigger): silence" || bad "non-match (trigger): expected silence (got: $OUT)"

# 4. PURE / DETERMINISTIC: identical output across two runs on the same input
O1=$(run "$MATCH"); O2=$(run "$MATCH")
[ "$O1" = "$O2" ] && ok "deterministic: identical output on repeat" || bad "deterministic: output differs between runs"

# 5. SILENCE-BY-DEFAULT when no lessons file present
rm -f "$LESSONS"
OUT=$(run "$MATCH")
[ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ] && ok "no lessons file -> silence (no crash)" || bad "no lessons file -> expected silence (got: $OUT)"

# 6. bash -n clean
bash -n "$SURFACE" 2>/dev/null && ok "beast-surface.sh bash -n clean" || bad "beast-surface.sh bash -n clean"

echo "---------------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
