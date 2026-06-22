#!/bin/bash
# beast-mp-recall.sh — Sprint 39: the SEMANTIC backstop (D6).
#
# Given a query (the action's folder/file/content fingerprint) + a project wing, it asks
# mempalace's CLI for semantically-related project memory, keeps only high-precision hits
# (cosine <= cutoff), and emits an injection packet naming each with a stable [MP<hash>] id.
#
# READ-ONLY: it only runs `mempalace … search …` (stderr suppressed, timeout-bounded). No mine,
# no hook, no capture — none of the disruptive write path. Deterministic given the index (the
# embedding engine ranks; no LLM judges). Fail-safe: missing CLI / timeout / no hit -> silence.
#
# Args:  $1 = query   $2 = wing (optional; override via BEAST_MP_WING)
# Env:   BEAST_MP_CUTOFF (cosine, default 0.45) · BEAST_MP_RESULTS (default 3)
#        BEAST_MP_TIMEOUT (s, default 5) · BEAST_MP_PALACE (test palace) · BEAST_MP_FIXTURE (test)
set -u

QUERY="${1:-}"
WING="${BEAST_MP_WING:-${2:-}}"
[ -n "$(printf '%s' "$QUERY" | tr -d '[:space:]')" ] || exit 0

# cosine here is a SIMILARITY (higher = more relevant; empirically: noise floor ~0.33,
# relevant project memory ~0.41-0.73). Keep hits with cosine >= cutoff. Calibrate per project.
CUTOFF="${BEAST_MP_CUTOFF:-0.40}"
RESULTS="${BEAST_MP_RESULTS:-3}"

# --- Obtain raw CLI output (fixture seam for tests; else the real, read-only CLI) ---
RAW=""
if [ -n "${BEAST_MP_FIXTURE:-}" ]; then
  [ -f "${BEAST_MP_FIXTURE}" ] && RAW="$(cat "${BEAST_MP_FIXTURE}" 2>/dev/null)"
else
  MPBIN="$(command -v mempalace 2>/dev/null)"
  [ -n "$MPBIN" ] || exit 0   # graceful degradation: no CLI -> silence (beast still has literal lessons)
  PAL=""; [ -n "${BEAST_MP_PALACE:-}" ] && PAL="--palace ${BEAST_MP_PALACE}"
  WA="";  [ -n "$WING" ] && WA="--wing $WING"
  TO="${BEAST_MP_TIMEOUT:-5}"
  if command -v timeout >/dev/null 2>&1; then
    RAW="$(timeout "$TO" "$MPBIN" $PAL search "$QUERY" $WA --results "$RESULTS" 2>/dev/null)"
  else
    RAW="$("$MPBIN" $PAL search "$QUERY" $WA --results "$RESULTS" 2>/dev/null)"
  fi
fi
[ -n "$(printf '%s' "$RAW" | tr -d '[:space:]')" ] || exit 0

# --- Parse result blocks: each has a "Match: cosine=X" line then snippet lines until a separator ---
HITS=""
score=""; snippet=""; in_snip=0
flush() {
  [ -n "$score" ] || return 0
  # numeric: keep only cosine >= cutoff (similarity; float compare via awk)
  awk -v a="$score" -v b="$CUTOFF" 'BEGIN{exit !((a+0)>=(b+0))}' || return 0
  local s; s="$(printf '%s' "$snippet" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$s" ] || return 0
  local id; id="MP$(printf '%s' "$s" | cksum 2>/dev/null | awk '{print $1}')"
  HITS="${HITS}[${id}] ${s}"$'\n'
}
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    *cosine=*)
      flush
      score="$(printf '%s' "$line" | grep -oE 'cosine=[0-9.]+' | head -1 | cut -d= -f2)"
      snippet=""; in_snip=1
      ;;
    *────*|*"------"*)
      flush; score=""; snippet=""; in_snip=0
      ;;
    *)
      if [ "$in_snip" = 1 ]; then
        t="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -n "$t" ] && snippet="${snippet} ${t}"
      fi
      ;;
  esac
done <<EOF
$RAW
EOF
flush

[ -n "$(printf '%s' "$HITS" | tr -d '[:space:]')" ] || exit 0

printf '🧠 FROM PROJECT MEMORY (semantic match on what you are doing):\n'
printf '%s\n' "$HITS"
printf 'STOP. Past sessions on THIS project recorded the above. For each [MP#]: does it apply to\n'
printf 'what you are about to do RIGHT NOW? If it does, you MUST honour it (e.g. a setting the user\n'
printf 'asked to leave alone) — do not override it from memory; say which apply before proceeding.\n'
exit 0
