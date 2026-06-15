#!/bin/bash
# validate-agreement.sh — Independent agreement validation (D-Validate, C14-C17)
# Checks that the discussion-agreement file CONTAINS every agreed point present in the raw
# conversation. This is the deterministic core of the independent check: an independent agent supplies
# the list of agreed terms/points (extracted from the raw conversation, NOT from the author's notes),
# and this script verifies each appears in the agreement. Default verdict: FAIL if any term missing.
#
# Usage:
#   validate-agreement.sh --raw <raw-conversation> --agreement <agreement-file> \
#                         [--terms "TERM1 TERM2 ..."]
# If --terms is omitted, candidate terms are auto-extracted from the raw file as ALL-CAPS tokens
# (>=3 chars). Exit: 0 = all agreed terms present (PASS), 1 = at least one missing (FAIL), 2 = bad args.
set -u

RAW=""; AGREEMENT=""; TERMS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --raw)        RAW="$2"; shift 2 ;;
    --agreement)  AGREEMENT="$2"; shift 2 ;;
    --terms)      TERMS="$2"; shift 2 ;;
    *) printf 'validate-agreement: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "$RAW" ] || [ -z "$AGREEMENT" ]; then
  printf 'validate-agreement: --raw and --agreement are required\n' >&2
  exit 2
fi
if [ ! -f "$RAW" ];       then printf 'validate-agreement: raw file not found: %s\n' "$RAW" >&2; exit 2; fi
if [ ! -f "$AGREEMENT" ]; then printf 'validate-agreement: agreement file not found: %s\n' "$AGREEMENT" >&2; exit 2; fi

# Build the term list.
if [ -z "$TERMS" ]; then
  # Auto-extract ALL-CAPS tokens (>=3 chars) from the raw conversation as candidate agreed terms.
  TERMS=$(grep -oE '[A-Z][A-Z0-9_]{2,}' "$RAW" 2>/dev/null | sort -u | tr '\n' ' ')
fi

MISSING=""
for t in $TERMS; do
  if ! grep -qF -- "$t" "$AGREEMENT" 2>/dev/null; then
    MISSING="${MISSING}${t} "
  fi
done

if [ -n "$MISSING" ]; then
  printf 'validate-agreement: FAIL — agreement is missing agreed term(s): %s\n' "$MISSING" >&2
  exit 1
fi

printf 'validate-agreement: PASS — every agreed term is present in the agreement.\n' >&2
exit 0
