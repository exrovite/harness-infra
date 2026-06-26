#!/bin/bash
# test-beast-mp-cache.sh — Sprint 40: query cache so repeated fingerprints don't re-hit mempalace.
# Caches the search output keyed on (wing|query|cutoff) with a TTL; within TTL the cached result is
# reused (proven by swapping the source and still getting the old result); TTL=0 disables.
set -u
MP="$HOME/.claude/scripts/beast-mp-recall.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/bmc-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT
export BEAST_MP_CACHE_DIR="$SBX/cache"
export BEAST_MP_WING=g__wing

mkfix(){ # $1 = marker text in the snippet
  cat > "$SBX/fix.txt" <<EOF

  [1] g__wing / technical
      Source: x.jsonl
      Match:  cosine=0.700  bm25=2.0

      memory snippet $1 here

  ────────────────────────────────────────────────────────
EOF
}
[ -f "$MP" ] || { bad "exists"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

# 1. first call (TTL on) caches MARKERA
mkfix MARKERA
OUT=$(BEAST_MP_FIXTURE="$SBX/fix.txt" BEAST_MP_CACHE_TTL=300 bash "$MP" "some query about temperature" g__wing 2>/dev/null)
printf '%s' "$OUT" | grep -q MARKERA && ok "first call returns MARKERA" || bad "first call (got: $OUT)"
ls "$BEAST_MP_CACHE_DIR"/* >/dev/null 2>&1 && ok "cache file written" || bad "cache file missing"

# 2. swap source to MARKERB, same query within TTL -> still MARKERA (cache hit)
mkfix MARKERB
OUT=$(BEAST_MP_FIXTURE="$SBX/fix.txt" BEAST_MP_CACHE_TTL=300 bash "$MP" "some query about temperature" g__wing 2>/dev/null)
printf '%s' "$OUT" | grep -q MARKERA && ok "cache hit: still MARKERA (source ignored)" || bad "cache hit failed (got: $OUT)"
printf '%s' "$OUT" | grep -q MARKERB && bad "cache hit should NOT show MARKERB" || ok "cache hit: MARKERB not shown"

# 3. TTL=0 disables cache -> sees MARKERB
OUT=$(BEAST_MP_FIXTURE="$SBX/fix.txt" BEAST_MP_CACHE_TTL=0 bash "$MP" "some query about temperature" g__wing 2>/dev/null)
printf '%s' "$OUT" | grep -q MARKERB && ok "TTL=0 bypasses cache -> MARKERB" || bad "TTL=0 (got: $OUT)"

# 4. different query -> different cache key -> sees current source (MARKERB)
OUT=$(BEAST_MP_FIXTURE="$SBX/fix.txt" BEAST_MP_CACHE_TTL=300 bash "$MP" "totally different query string" g__wing 2>/dev/null)
printf '%s' "$OUT" | grep -q MARKERB && ok "different query -> fresh (MARKERB)" || bad "different query (got: $OUT)"

# 5. fail-safe: bad cache dir still works
OUT=$(BEAST_MP_FIXTURE="$SBX/fix.txt" BEAST_MP_CACHE_DIR=/root/nope/cannot BEAST_MP_CACHE_TTL=300 bash "$MP" "q2" g__wing 2>/dev/null; echo "rc=$?")
echo "$OUT" | grep -q 'rc=0' && ok "unwritable cache dir -> still exit 0" || bad "cache fail-safe"

bash -n "$MP" 2>/dev/null && ok "bash -n clean" || bad "bash -n"
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
