#!/bin/bash
# beast-pack.sh — Sprint 36 G2: deterministic per-project lesson populator.
#
# Builds <project-root>/.beast/lessons.jsonl from THAT project's OWN memory:
#   1. git fix-commits  (subjects matching fix/bug/crash/revert/regression/patch)
#   2. mempalace KG facts  (env-pointed seam: $BEAST_KG_FACTS_FILE = JSONL of
#      {subject,predicate,object}; in production sourced from the project's wing —
#      tests point this at a sandbox file, NEVER the real ~95k palace)
#
# DETERMINISTIC: no LLM at pack time. Same sources -> same lessons. Judgment was
# the human's, captured once here (cold path); recall stays a pure function.
# IDEMPOTENT: lessons are keyed by a stable id; re-running adds no duplicates.
# HEADLESS: no console windows, no interactive prompts.
#
# Env seams: BEAST_PACK_ROOT (project root), BEAST_LESSONS (output path),
#            BEAST_KG_FACTS_FILE (KG source), BEAST_PALACE (mempalace path, prod).
set -u

ROOT="${BEAST_PACK_ROOT:-$(pwd -W 2>/dev/null || pwd)}"
OUT="${BEAST_LESSONS:-$ROOT/.beast/lessons.jsonl}"
mkdir -p "$(dirname "$OUT")" 2>/dev/null
[ -f "$OUT" ] || : > "$OUT"

# --- existing ids (idempotency) ---
have_id() { grep -qF "\"id\":\"$1\"" "$OUT" 2>/dev/null; }

# slug: lowercase, keep [a-z0-9_], collapse, drop stopwords, join distinctive tokens with |
STOP=" the a an to for of in on with and or not use uses using fix fixes fixed bug bugs crash crashes revert reverts regression patch patches it its this that when then so we i is are be as at by from into out up off no yes "
mk_trigger() {
  local text="$1" tok out="" seen=" " n=0
  text="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_' ' ')"
  for tok in $text; do
    [ "${#tok}" -ge 3 ] || continue
    case "$STOP" in *" $tok "*) continue ;; esac
    case "$seen" in *" $tok "*) continue ;; esac
    seen="$seen$tok "
    if [ -z "$out" ]; then out="$tok"; else out="$out|$tok"; fi
    n=$((n+1)); [ "$n" -ge 6 ] && break
  done
  printf '%s' "$out"
}

# basename-or-wildcard scope: if text contains a filename token, use it; else *
mk_scope() {
  local f
  f="$(printf '%s' "$1" | grep -oE '[A-Za-z0-9_.-]+\.[A-Za-z0-9]+' 2>/dev/null | head -1)"
  if [ -n "$f" ]; then printf '%s' "$(basename "$f")"; else printf '*'; fi
}

emit() { # id scope trigger lesson fix dossier
  have_id "$1" && return 0
  # Pass EVERY field via the environment ($ENV), never via `jq --arg`. Native
  # Windows jq.exe glob-expands argv in its own CRT, so a value containing a glob
  # char (e.g. a bare `*` scope for a conceptual fact, or `?`) is mangled/aborted
  # BEFORE jq parses it — silently dropping the lesson. `$ENV` is glob-immune.
  # (Also avoids the jq-keyword arg-name trap, e.g. `do`.)
  BID="$1" BSC="$2" BTR="$3" BLE="$4" BFX="$5" BDS="$6" \
  jq -cn '{id:$ENV.BID,scope:$ENV.BSC,trigger:$ENV.BTR,lesson:$ENV.BLE,fix:$ENV.BFX,dossier:$ENV.BDS}' \
    2>/dev/null >> "$OUT"
}

# ---------------------------------------------------------------------------
# Source 1 — git fix-commits
# ---------------------------------------------------------------------------
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Portable: enumerate short hashes, then read subject/body/files per hash.
  # (Avoids \xHH separators, which MSYS tr/awk do not reliably interpret.)
  HASHES="$(git -C "$ROOT" log --no-merges --format='%h' 2>/dev/null | tr -d '\r')"
  for hash in $HASHES; do
    [ -n "$hash" ] || continue
    subj="$(git -C "$ROOT" log -1 --format='%s' "$hash" 2>/dev/null)"
    printf '%s' "$subj" | grep -qiE 'fix|bug|crash|revert|broke|broken|regression|patch' || continue
    body="$(git -C "$ROOT" log -1 --format='%b' "$hash" 2>/dev/null)"
    files="$(git -C "$ROOT" show --pretty=format: --name-only "$hash" 2>/dev/null | grep -v '^$' | tr '\n' ' ')"
    primary="$(printf '%s' "$files" | awk '{print $1}')"
    scope="$(mk_scope "$primary $subj")"
    trig="$(mk_trigger "$subj $primary")"
    [ -n "$trig" ] || trig="$(printf '%s' "$primary" | tr -d ' ')"
    lesson="$subj"
    fix="$subj (see commit $hash)"
    dossier="$(printf 'commit %s — files: %s\n%s' "$hash" "$files" "$body")"
    emit "g$hash" "$scope" "$trig" "$lesson" "$fix" "$dossier"
  done
fi

# ---------------------------------------------------------------------------
# Source 2 — mempalace KG facts (env-pointed seam; prod best-effort)
# ---------------------------------------------------------------------------
KG_SRC=""
if [ -n "${BEAST_KG_FACTS_FILE:-}" ] && [ -f "${BEAST_KG_FACTS_FILE}" ]; then
  KG_SRC="$BEAST_KG_FACTS_FILE"
fi
if [ -n "$KG_SRC" ]; then
  while IFS= read -r fact || [ -n "$fact" ]; do
    [ -z "$(printf '%s' "$fact" | tr -d '[:space:]')" ] && continue
    s="$(printf '%s' "$fact" | jq -r '.subject // ""' 2>/dev/null)"
    p="$(printf '%s' "$fact" | jq -r '.predicate // ""' 2>/dev/null)"
    o="$(printf '%s' "$fact" | jq -r '.object // ""' 2>/dev/null)"
    [ -n "$s$o" ] || continue
    fid="k$(printf '%s|%s|%s' "$s" "$p" "$o" | cksum 2>/dev/null | awk '{print $1}')"
    scope="$(mk_scope "$s $o")"
    trig="$(mk_trigger "$s $p $o")"
    [ -n "$trig" ] || trig="*"
    lesson="$(printf '%s %s %s' "$s" "$p" "$o" | sed 's/_/ /g')"
    fix="$o"
    dossier="$(printf 'KG fact: (%s) -[%s]-> (%s)' "$s" "$p" "$o")"
    emit "$fid" "$scope" "$trig" "$lesson" "$fix" "$dossier"
  done < "$KG_SRC"
fi

exit 0
