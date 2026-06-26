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
[ -n "$(printf '%s' "$QUERY" | tr -d '[:space:]' 2>/dev/null)" ] || exit 0

# cosine here is a SIMILARITY (higher = more relevant; empirically: noise floor ~0.33,
# relevant project memory ~0.41-0.73). Keep hits with cosine >= cutoff. Calibrate per project.
CUTOFF="${BEAST_MP_CUTOFF:-0.40}"
RESULTS="${BEAST_MP_RESULTS:-3}"

# --- Cache: reuse the search output for an identical (wing|query|cutoff) within TTL ---
# Makes repeated edits to the same area instant instead of re-hitting mempalace (~2.5s).
CACHE_TTL="${BEAST_MP_CACHE_TTL:-300}"
CACHE_DIR="${BEAST_MP_CACHE_DIR:-${TMPDIR:-/tmp}/beast-mp-cache}"
CKEY="$(printf '%s|%s|%s' "$WING" "$QUERY" "$CUTOFF" | cksum 2>/dev/null | awk '{print $1"_"$2}')"
CFILE="$CACHE_DIR/$CKEY"
RAW=""; FROM_CACHE=0
if [ "$CACHE_TTL" -gt 0 ] 2>/dev/null && [ -f "$CFILE" ]; then
  _now=$(date +%s 2>/dev/null || echo 0); _mt=$(stat -c %Y "$CFILE" 2>/dev/null || echo 0)
  if [ $(( _now - _mt )) -lt "$CACHE_TTL" ]; then RAW="$(cat "$CFILE" 2>/dev/null)"; FROM_CACHE=1; fi
fi

# --- Obtain raw CLI output (fixture seam for tests; else the real, read-only CLI) ---
if [ "$FROM_CACHE" = 0 ]; then
if [ -n "${BEAST_MP_FIXTURE:-}" ]; then
  [ -f "${BEAST_MP_FIXTURE}" ] && RAW="$(cat "${BEAST_MP_FIXTURE}" 2>/dev/null)"
else
  MPBIN="$(command -v mempalace 2>/dev/null)"
  [ -n "$MPBIN" ] || exit 0   # graceful degradation: no CLI -> silence (beast still has literal lessons)
  PAL=""; [ -n "${BEAST_MP_PALACE:-}" ] && PAL="--palace ${BEAST_MP_PALACE}"
  TO="${BEAST_MP_TIMEOUT:-5}"
  # NOTE: we do NOT pass --wing. The mempalace --wing filter is unreliable after a mine (returns 0)
  # and is slower; an UNSCOPED search is fast and correct, and we filter to $WING in post-processing
  # below. Fetch extra results so wing-filtering still yields enough.
  CLI_RESULTS=$(( RESULTS * 4 )); [ "$CLI_RESULTS" -lt 10 ] && CLI_RESULTS=10
  if command -v timeout >/dev/null 2>&1; then
    RAW="$(timeout "$TO" "$MPBIN" $PAL search "$QUERY" --results "$CLI_RESULTS" 2>/dev/null)"
  else
    RAW="$("$MPBIN" $PAL search "$QUERY" --results "$CLI_RESULTS" 2>/dev/null)"
  fi
fi
  # write to cache (best-effort) so the next identical fingerprint is instant
  if [ "$CACHE_TTL" -gt 0 ] 2>/dev/null && [ -n "$(printf '%s' "$RAW" | tr -d '[:space:]')" ]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null && printf '%s' "$RAW" > "$CFILE" 2>/dev/null
  fi
fi
[ -n "$(printf '%s' "$RAW" | tr -d '[:space:]')" ] || exit 0

# --- Parse result blocks. Each block:  "  [N] <wing> / <room>" ... "Match: cosine=X" ... snippet ---
# Keep hits with cosine >= cutoff AND (no wing filter OR block wing == target wing). Dedup; cap to RESULTS.
HITS=""; SEEN=" "; NHITS=0
score=""; snippet=""; in_snip=0; cur_wing=""; block_wing=""
flush() {
  [ -n "$score" ] || return 0
  [ "$NHITS" -ge "$RESULTS" ] && return 0
  awk -v a="$score" -v b="$CUTOFF" 'BEGIN{exit !((a+0)>=(b+0))}' || return 0   # similarity >= cutoff
  [ -z "$WING" ] || [ "$block_wing" = "$WING" ] || return 0                    # wing filter (post)
  local s; s="$(printf '%s' "$snippet" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$s" ] || return 0
  # Drop self-referential noise: beast's OWN injected packets that got mined back as "memory".
  case "$s" in
    *"BEFORE YOU ACT"*|*"FROM PROJECT MEMORY"*|*"IN-WORK CHECK"*|*"Past sessions on THIS project"*|\
    *"do not assume you remember"*|*"say which apply before proceeding"*|*"RECONCILE GATE"*) return 0 ;;
  esac
  local id; id="MP$(printf '%s' "$s" | cksum 2>/dev/null | awk '{print $1}')"
  case "$SEEN" in *" $id "*) return 0 ;; esac                                  # dedup
  SEEN="$SEEN$id "; NHITS=$((NHITS+1))
  HITS="${HITS}[${id}] ${s}"$'\n'
}
# Subprocess-free parse (case globs + parameter expansion). Per-line grep/sed here is fatal on
# MSYS — each fork is ~10-50ms, so a 12-result output spawned hundreds of procs (16s). This stays
# in-process: ~2s end-to-end (the mempalace query itself).
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    *cosine=*)
      flush
      tmp="${line#*cosine=}"; score="${tmp%% *}"; score="${score%%[!0-9.]*}"
      block_wing="$cur_wing"; snippet=""; in_snip=1
      ;;
    *────*|*------*)
      flush; score=""; snippet=""; in_snip=0
      ;;
    *'['[0-9]*']'*' / '*)                       # block header:  "  [N] <wing> / <room>"
      tmp="${line#*']'}"; tmp="${tmp# }"          # after "] "
      cur_wing="${tmp%% /*}"                       # before " /"
      cur_wing="${cur_wing%"${cur_wing##*[![:space:]]}"}"   # rtrim
      ;;
    *)
      if [ "$in_snip" = 1 ]; then
        t="${line#"${line%%[![:space:]]*}"}"      # ltrim leading spaces
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
