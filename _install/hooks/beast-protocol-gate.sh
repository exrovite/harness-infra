#!/bin/bash
# beast-protocol-gate.sh — surface USER-VALIDATED protocols + ENFORCE adherence (PreToolUse).
#
# When the action's content touches a CONCEPT that has a user-validated win, this gate BLOCKS the
# action (exit 2) until an adherence artifact exists for that concept:
#   <state>/protocol-ack.<concept>.md  — a short explanation + an INDEPENDENT-CHECK line (proof that a
#   neutral independent subagent cross-checked the plan). No independent check on file ⇒ blocked.
# Read-only over the wins store. Fail-safe (any error -> exit 0, never blocks). Flag-gated + kill-switch.
set -u

INPUT="$(cat 2>/dev/null)"; [ -z "$INPUT" ] && exit 0
# shellcheck disable=SC1091
source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null
CWD="$(pwd -W 2>/dev/null || pwd)"
if [ -n "${HARNESS_STATE_DIR:-}" ]; then STATE_DIR="$HARNESS_STATE_DIR"
elif type find_project_state_dir >/dev/null 2>&1; then STATE_DIR="$(find_project_state_dir "$CWD" 2>/dev/null)"; fi
[ -n "${STATE_DIR:-}" ] || STATE_DIR=".claude/state"

# kill-switch superset + beast gate
if type harness_disabled_resolved >/dev/null 2>&1 && harness_disabled_resolved "$CWD" "" 2>/dev/null; then exit 0; fi
[ -f "${STATE_DIR}/harness-disabled.flag" ] && exit 0
[ -f "${STATE_DIR}/beast-mode.flag" ] || exit 0

# wins store
if [ -n "${BEAST_WINS:-}" ]; then WINS="$BEAST_WINS"; else
  ROOT="${STATE_DIR%/.claude/state}"; [ "$ROOT" = "$STATE_DIR" ] && ROOT="$CWD"
  WINS="$ROOT/.beast/validated-wins.jsonl"
fi
[ -f "$WINS" ] || exit 0

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null | tr -d '\r')"
case "$TOOL" in Write|Edit|Bash) ;; *) exit 0 ;; esac
FP="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)"
CONTENT="$(printf '%s' "$INPUT" | jq -r '(.tool_input.content // .tool_input.new_string // .tool_input.command // "")' 2>/dev/null)"

# Never block the ack file itself or control paths (no deadlock).
BN="$(basename "${FP:-}" 2>/dev/null)"
case "$BN" in protocol-ack.*) exit 0 ;; esac
case "$FP" in *.beast/*|*.claude/state/*|*.agent-memory/*) exit 0 ;; esac

# Sprint 50 (audit A2): Bash has no file_path, so the exemptions above never applied to it and
# read-only commands were being blocked on filename mentions. Only enforce on commands that can
# WRITE, and let Bash writes to harness-state/ack/beast/memory paths through (the gate's own
# escape hatch — same blanket trade-off pre-bash-gate.sh already accepts for its bootstrap paths).
if [ "$TOOL" = "Bash" ]; then
  if ! printf '%s' "$CONTENT" | grep -qE '>|\b(tee|cp|mv|dd|truncate|install|rsync)\b|sed\b[^|]*-i|<<|\bgit\s+apply\b|\bpatch\b\s*(-|<)|python[^|]*\bopen\b|\bperl\b.*\bopen\b'; then
    exit 0
  fi
  if printf '%s' "$CONTENT" | grep -qiE 'protocol-ack\.|\.claude/state/|\.beast/|\.agent-memory/'; then
    exit 0
  fi
fi

HAY="$(printf '%s %s' "$FP" "$CONTENT" | tr '[:upper:]' '[:lower:]')"

# Find the first validated concept present in the action whose adherence ack is missing/invalid.
SEEN=" "
while IFS= read -r line || [ -n "$line" ]; do
  [ -z "$line" ] && continue
  concept="$(printf '%s' "$line" | jq -r '.concept // ""' 2>/dev/null)"
  quote="$(printf '%s' "$line" | jq -r '.quote // ""' 2>/dev/null)"
  [ -n "$concept" ] || continue
  clow="$(printf '%s' "$concept" | tr '[:upper:]' '[:lower:]')"
  case "$SEEN" in *" $clow "*) continue ;; esac
  case "$HAY" in *"$clow"*) ;; *) continue ;; esac      # concept must appear in the action
  SEEN="$SEEN$clow "
  slug="$(printf '%s' "$clow" | tr -cs 'a-z0-9_-' '-')"
  ACK="${STATE_DIR}/protocol-ack.${slug}.md"
  ackok=0
  if [ -f "$ACK" ] && [ "$(wc -c < "$ACK" 2>/dev/null)" -gt 50 ]; then
    # Two valid acks: (a) a dismissal — agent judged it NOT relevant (cheap, the relevance gate at
    # work); (b) RELEVANT + an INDEPENDENT-CHECK verdict (the enforced adherence path).
    if grep -qiE 'RELEVANT:[[:space:]]*NO|NOT[[:space:]]+RELEVANT' "$ACK" 2>/dev/null; then ackok=1
    elif grep -qiE 'INDEPENDENT-CHECK:.*(CONFIRMED|PASS|VERIFIED|APPROVED)' "$ACK" 2>/dev/null; then ackok=1; fi
    # a bare/ REJECTED independent check does NOT unblock — the agent must revise until CONFIRMED.
  fi
  if [ "$ackok" = 0 ]; then
    {
      printf '⚠️  IMPORTANT PROTOCOL — %s. Project memory surfaced this from a search of your past work:\n' "$concept"
      printf '   "%s"\n\n' "$quote"
      printf '❓ Are you working with %s here? If YES, before you proceed:\n' "$concept"
      printf ' 1. Do your OWN search — mempalace_search "%s protocol what worked" — read the docs, and look\n' "$concept"
      printf '    at WHAT made it work and WHETHER any reports were created — to get the approach we established.\n'
      printf ' 2. Follow it (this prevents wasting time and tokens going down a path we already know is wrong).\n'
      printf ' 3. ENFORCED: write %s with a short explanation (what is relevant, why, what you intend to do)\n' "$ACK"
      printf '    AND spawn an INDEPENDENT SUBAGENT (do NOT bias it — give it the question neutrally) to\n'
      printf '    cross-check it is correct; record its verdict on a line starting "INDEPENDENT-CHECK:".\n'
      printf '    If you choose NOT to follow, you must have a genuinely good cause AND the independent\n'
      printf '    subagent must check whether you are wrong.\n'
      printf 'You cannot proceed until that ack (with INDEPENDENT-CHECK) is on file — the gate blocks otherwise.\n'
    } >&2
    exit 2
  fi
done < "$WINS"

# All touched concepts have a valid (independent-checked) ack -> allow + confirm via context.
if [ "$SEEN" != " " ]; then
  jq -cn --arg ctx "[BEAST PROTOCOL — adherence ack(s) on file, independent-checked:${SEEN}— proceeding]" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}' 2>/dev/null
fi
exit 0
