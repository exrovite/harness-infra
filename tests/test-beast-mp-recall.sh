#!/bin/bash
# test-beast-mp-recall.sh — Sprint 39: mempalace semantic backstop (D6), parse/threshold/emit.
# Uses the BEAST_MP_FIXTURE seam (canned mempalace CLI output) so it is deterministic and never
# touches the real palace. A separate live smoke test covers the real CLI.
# Usage: bash tests/test-beast-mp-recall.sh
set -u
MP="$HOME/.claude/scripts/beast-mp-recall.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

SBX=$(mktemp -d 2>/dev/null || echo "/tmp/bmp-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT
FIX="$SBX/fixture.txt"
cat > "$FIX" <<'EOF'

============================================================
  Results for: "temperature"
============================================================

  [1] g__wing / technical
      Source: foo.jsonl
      Match:  cosine=0.700  bm25=0.25

      leave the temperature for now just add the teenager voice

  ────────────────────────────────────────────────────────
  [2] g__wing / technical
      Source: bar.jsonl
      Match:  cosine=0.300  bm25=0.10

      UNRELATED low similarity result DROPME please

  ────────────────────────────────────────────────────────
EOF

run(){ BEAST_MP_FIXTURE="$FIX" BEAST_MP_CUTOFF="${2:-0.45}" bash "$MP" "$1" "g__wing" 2>/dev/null; }

[ -f "$MP" ] || { bad "beast-mp-recall.sh exists at $MP"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
ok "beast-mp-recall.sh exists"

# C1: surfaces the in-cutoff hit with an [MP<hash>] id + snippet
OUT=$(run "temperature")
printf '%s' "$OUT" | grep -q 'leave the temperature' && ok "C1: surfaces the relevant memory" || bad "C1 (got: $OUT)"
printf '%s' "$OUT" | grep -qE '\[MP[0-9A-Za-z]+\]' && ok "C1: emits stable [MP<hash>] id" || bad "C1 id (got: $OUT)"

# C2: threshold drops the high-distance result
printf '%s' "$OUT" | grep -q 'DROPME' && bad "C2: high-distance result should be dropped (got: $OUT)" || ok "C2: threshold drops cosine>cutoff"

# C2b: lowering the cutoff includes the low-similarity result
OUT2=$(run "temperature" "0.20")
printf '%s' "$OUT2" | grep -q 'DROPME' && ok "C2b: cutoff 0.20 includes the 0.300 result" || bad "C2b (got: $OUT2)"

# C3: deterministic + stable id
A=$(run "temperature"); B=$(run "temperature")
[ "$A" = "$B" ] && ok "C3: deterministic output" || bad "C3 determinism"
ID1=$(printf '%s' "$A" | grep -oE '\[MP[0-9A-Za-z]+\]' | head -1)
ID2=$(printf '%s' "$B" | grep -oE '\[MP[0-9A-Za-z]+\]' | head -1)
[ -n "$ID1" ] && [ "$ID1" = "$ID2" ] && ok "C3: id stable across runs ($ID1)" || bad "C3 id stability"

# C4: empty fixture -> silence
OUT=$(BEAST_MP_FIXTURE=/dev/null bash "$MP" "temperature" "g__wing" 2>/dev/null)
[ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ] && ok "C4: empty source -> silence" || bad "C4 (got: $OUT)"

# C4b: garbage with no cosine lines -> silence
echo "no results here" > "$SBX/g.txt"
OUT=$(BEAST_MP_FIXTURE="$SBX/g.txt" bash "$MP" "temperature" "g__wing" 2>/dev/null)
[ -z "$(printf '%s' "$OUT" | tr -d '[:space:]')" ] && ok "C4b: no cosine -> silence" || bad "C4b (got: $OUT)"

# C4c: empty query -> silence, exit 0
OUT=$(BEAST_MP_FIXTURE="$FIX" bash "$MP" "" "g__wing" 2>/dev/null); rc=$?
{ [ "$rc" = 0 ] && [ -z "$(printf '%s' "$OUT"|tr -d '[:space:]')" ]; } && ok "C4c: empty query -> silent exit 0" || bad "C4c (rc=$rc)"

# C5: read-only — no write/capture subcommand is INVOKED (ignore comments)
CODE=$(grep -vE '^[[:space:]]*#' "$MP")
printf '%s' "$CODE" | grep -qE '(MPBIN|mempalace)[^|]*(mine|hook|sweep|compress|repair|init|migrate)' && bad "C5: must NOT invoke mine/hook/capture" || ok "C5: read-only (no write subcommand invoked)"
printf '%s' "$CODE" | grep -q 'search' && ok "C5: uses search" || bad "C5: uses search"

# bash -n
bash -n "$MP" 2>/dev/null && ok "bash -n clean" || bad "bash -n"

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
