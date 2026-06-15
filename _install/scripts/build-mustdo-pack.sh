#!/bin/bash
# build-mustdo-pack.sh — Automated Must-Do Pack Builder (D-Raw, D-Clear)
# Builds the caller's must-do PACK before PLAN: clears ONLY the caller's OWN must-do file, captures
# the originating conversation in raw form (transcript JSONL), and relinks the raw conversation,
# the (validated) discussion-agreement, and any grounding files.
#
# SAFETY: never touches a sibling agent's must-do file. The --own path is the single file mutated.
#
# Usage:
#   build-mustdo-pack.sh --own <must-do-file> [--transcript <src.jsonl> | --no-transcript]
#                        [--agreement <file>] [--grounding "f1 f2 ..."]
# Exit: 0 ok, non-zero on bad args / unwritable own file.
set -u

OWN=""; TRANSCRIPT=""; NO_TRANSCRIPT=0; AGREEMENT=""; GROUNDING=""
while [ $# -gt 0 ]; do
  case "$1" in
    --own)         OWN="$2"; shift 2 ;;
    --transcript)  TRANSCRIPT="$2"; shift 2 ;;
    --no-transcript) NO_TRANSCRIPT=1; shift ;;
    --agreement)   AGREEMENT="$2"; shift 2 ;;
    --grounding)   GROUNDING="$2"; shift 2 ;;
    *) printf 'build-mustdo-pack: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "$OWN" ]; then
  printf 'build-mustdo-pack: --own <must-do-file> is required\n' >&2
  exit 2
fi

OWN_DIR=$(dirname "$OWN")
mkdir -p "$OWN_DIR" 2>/dev/null

# 1) Raw capture (D-Raw) — copy the transcript JSONL verbatim into the pack.
RAW_REL=""
if [ "$NO_TRANSCRIPT" -ne 1 ]; then
  if [ -z "$TRANSCRIPT" ]; then
    # Best-effort: locate this session's transcript via CLAUDE env if present.
    TRANSCRIPT="${CLAUDE_TRANSCRIPT_PATH:-}"
  fi
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    cp -f "$TRANSCRIPT" "$OWN_DIR/raw-conversation.jsonl" 2>/dev/null && RAW_REL="raw-conversation.jsonl"
  fi
fi

# 2) Clear + repopulate ONLY the caller's own file (D-Clear). This overwrite is the single mutation;
#    sibling must-do-*.md files are never opened.
{
  printf '# Must-Do — current task pack\n\n'
  printf '> Auto-built by build-mustdo-pack.sh. Links below ground the agent in the current task.\n\n'
  printf '## Grounding\n'
  [ -n "$RAW_REL" ]    && printf -- '- [Raw conversation (verbatim)](%s)\n' "$RAW_REL"
  [ -n "$AGREEMENT" ]  && printf -- '- [Discussion agreement (validated)](%s)\n' "$AGREEMENT"
  if [ -n "$GROUNDING" ]; then
    for g in $GROUNDING; do
      printf -- '- [%s](%s)\n' "$g" "$g"
    done
  fi
} > "$OWN" || { printf 'build-mustdo-pack: cannot write own file: %s\n' "$OWN" >&2; exit 1; }

printf 'build-mustdo-pack: built pack in %s (own=%s)\n' "$OWN_DIR" "$OWN" >&2
exit 0
