#!/bin/bash
# test-beast-pack.sh — Sprint 36 G2: deterministic per-project lesson pack (functional).
# Runs the REAL beast-pack.sh against a real temp git repo + an env-pointed KG-facts
# seam (NEVER the real ~95k palace), asserting:
#   B1 schema-valid lessons.jsonl written
#   B2 lessons reference the project's OWN seeded atoms (git fix-commit + KG fact)
#   B3 per-project isolation (packing X never writes Y/.beast)
#   B4 idempotent (re-run adds no duplicates)
#   B5 headless (no cmd.exe/start/powershell spawning)
#   round-trip-ready: a produced lesson is surfaceable by beast-surface.sh
# Usage: bash tests/test-beast-pack.sh
set -u

PACK="$HOME/.claude/scripts/beast-pack.sh"
SURFACE="$HOME/.claude/scripts/beast-surface.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

SBX=$(mktemp -d 2>/dev/null || echo "/tmp/bpack-$$")
cleanup() { rm -rf "$SBX" 2>/dev/null; }
trap cleanup EXIT

# --- Build a real temp git project X with a distinctive fix-commit ---
PX="$SBX/projX"; mkdir -p "$PX"
( cd "$PX" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'echo hi\n' > msys-helper.sh && git add . && git commit -q -m "init" \
  && printf 'tr backslash\n' >> msys-helper.sh && git add . \
  && git commit -q -m "Fix MSYS sed crash: use tr not sed in msys-helper.sh" ) 2>/dev/null

# --- Seed an env-pointed KG-facts file (NOT the real palace) ---
KG="$SBX/kg-facts.jsonl"
cat > "$KG" <<'EOF'
{"subject":"pre-write-gate.sh","predicate":"must_use","object":"find_project_state_dir for cwd-independent resolution"}
{"subject":"harness_state","predicate":"resolved_by","object":"WILDSENTINEL77 conceptual rule with no filename token"}
EOF

if [ ! -f "$PACK" ]; then bad "beast-pack.sh exists at $PACK"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; fi
ok "beast-pack.sh exists"

export BEAST_PACK_ROOT="$PX"
export BEAST_LESSONS="$PX/.beast/lessons.jsonl"
export BEAST_KG_FACTS_FILE="$KG"
bash "$PACK" >/dev/null 2>&1
RC=$?
[ "$RC" -eq 0 ] && ok "pack exits 0" || bad "pack exits 0 (rc=$RC)"

L="$PX/.beast/lessons.jsonl"
[ -f "$L" ] && ok "B1: lessons.jsonl created" || { bad "B1: lessons.jsonl created"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
N=$(wc -l < "$L" 2>/dev/null | tr -d ' ')
[ "${N:-0}" -ge 1 ] && ok "B1: >=1 lesson ($N)" || bad "B1: >=1 lesson (got $N)"

# B1: every line schema-valid (all six fields present, non-empty id/scope/lesson)
SCHEMA_OK=1
while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  printf '%s' "$line" | jq -e 'has("id") and has("scope") and has("trigger") and has("lesson") and has("fix") and has("dossier") and (.id|length>0) and (.scope|length>0)' >/dev/null 2>&1 || SCHEMA_OK=0
done < "$L"
[ "$SCHEMA_OK" = 1 ] && ok "B1: all lessons schema-valid" || bad "B1: schema-valid"

# B2: a lesson derived from the git fix-commit (references msys-helper.sh + tr/sed)
grep -qi 'msys-helper.sh' "$L" && ok "B2: git-sourced lesson references msys-helper.sh" || bad "B2: git atom (file)"
grep -qiE '\btr\b|\bsed\b|msys' "$L" && ok "B2: git-sourced lesson carries the fix keyword" || bad "B2: git atom (keyword)"
# B2: a lesson derived from the seeded KG fact (references the unguessable symbol)
grep -q 'find_project_state_dir' "$L" && ok "B2: KG-sourced lesson references seeded symbol" || bad "B2: KG atom"
grep -q 'pre-write-gate.sh' "$L" && ok "B2: KG-sourced lesson references seeded file" || bad "B2: KG atom (file)"
# B2: a CONCEPTUAL KG fact with NO filename token -> scope "*" -> must still pack
# (regression for native jq.exe glob-expanding a bare '*' in argv).
grep -q 'WILDSENTINEL77' "$L" && ok "B2: wildcard-scope KG fact packed (no filename token)" || bad "B2: wildcard-scope KG fact DROPPED"
if grep -q 'WILDSENTINEL77' "$L" && [ "$(grep 'WILDSENTINEL77' "$L" | jq -r '.scope' 2>/dev/null)" = '*' ]; then ok "B2: wildcard fact has scope '*'"; else bad "B2: wildcard fact scope '*'"; fi

# B3: isolation — a sibling project Y is never written
PY="$SBX/projY"; mkdir -p "$PY"
[ ! -e "$PY/.beast" ] && ok "B3: sibling project Y has no .beast" || bad "B3: isolation violated"

# B4: idempotent — re-run, line count unchanged
bash "$PACK" >/dev/null 2>&1
N2=$(wc -l < "$L" 2>/dev/null | tr -d ' ')
[ "$N2" = "$N" ] && ok "B4: idempotent (no dup lessons: $N -> $N2)" || bad "B4: idempotent ($N -> $N2)"

# No literal null rows (jq-keyword bug regression): every line must be an object
if grep -qxE 'null' "$L" || grep -q '"id":null' "$L"; then bad "no null JSONL rows"; else ok "no null JSONL rows"; fi

# CWD-INDEPENDENCE (jq `$do` keyword bug): pack from a NEUTRAL cwd must still emit
# the seeded unguessable KG symbol, deterministically. Run twice from different cwds.
PZ="$SBX/projZ"; mkdir -p "$PZ"
( cd "$PZ" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'x\n' > zfile.sh && git add . && git commit -q -m "init" \
  && printf 'y\n' >> zfile.sh && git add . && git commit -q -m "Fix crash in zfile.sh use tr" ) 2>/dev/null
LZ1="$SBX/z1.jsonl"; LZ2="$SBX/z2.jsonl"
( cd / 2>/dev/null;       BEAST_PACK_ROOT="$PZ" BEAST_LESSONS="$LZ1" BEAST_KG_FACTS_FILE="$KG" bash "$PACK" >/dev/null 2>&1 )
( cd "$HOME" 2>/dev/null; BEAST_PACK_ROOT="$PZ" BEAST_LESSONS="$LZ2" BEAST_KG_FACTS_FILE="$KG" bash "$PACK" >/dev/null 2>&1 )
grep -q 'find_project_state_dir' "$LZ1" && ok "cwd-independent: KG symbol present (run from /)" || bad "cwd-independent: KG symbol missing (run from /)"
if [ -f "$LZ1" ] && [ -f "$LZ2" ] && diff -q <(sort "$LZ1") <(sort "$LZ2") >/dev/null 2>&1; then ok "deterministic across different cwds"; else bad "deterministic across different cwds"; fi

# B5: headless — script spawns no console windows
# detect actual console-spawning (start/cmd.exe/powershell/conhost AS A COMMAND), not the word in data
if grep -qE '(cmd\.exe|powershell|conhost|(^|[;&|`]|\bdo )\s*start[[:space:]]+["'"'"'/.a-z])' "$PACK"; then bad "B5: no CMD-window spawning"; else ok "B5: no CMD-window spawning"; fi

# Round-trip-ready: feed the KG-sourced lesson's atom to beast-surface -> it surfaces
export BEAST_LESSONS="$L"
ACT='{"file_path":"pre-write-gate.sh","content":"editing pre-write-gate.sh to use find_project_state_dir"}'
OUT=$(printf '%s' "$ACT" | bash "$SURFACE" 2>/dev/null)
printf '%s' "$OUT" | grep -q 'find_project_state_dir' && ok "round-trip-ready: produced lesson surfaces" || bad "round-trip-ready (got: $OUT)"

# bash -n clean
bash -n "$PACK" 2>/dev/null && ok "beast-pack.sh bash -n clean" || bad "bash -n clean"

echo "---------------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
