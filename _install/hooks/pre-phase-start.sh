#!/bin/bash
# pre-phase-start.sh — Harness-internal script (NOT a Claude Code hook)
# Called by run-harness.sh before each phase begins.
# Extracts domain keywords from product spec, greps known-fixes.md for matching symptoms,
# writes matches to injected-context.md. Agent sees fixes as briefing material.
#
# Usage: bash pre-phase-start.sh <phase_number>

PHASE="$1"
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
# resolve STATE_DIR to the PROJECT ROOT (avoid creating a nested .claude in a subdir cwd)
if [ -z "${HARNESS_STATE_DIR:-}" ]; then . "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null; type find_project_state_dir >/dev/null 2>&1 && { _r="$(find_project_state_dir "$(pwd -W 2>/dev/null || pwd)" 2>/dev/null)"; if [ -n "$_r" ]; then STATE_DIR="$_r"; else exit 0; fi; }; fi
SPEC_FILE=".claude/specs/product-spec.md"
KNOWN_FIXES=".claude/protocols/known-fixes.md"
INJECTED_FILE="${STATE_DIR}/injected-context.md"

mkdir -p "$STATE_DIR" 2>/dev/null

# Only inject on research (1) and execute (3) phases
if [ "$PHASE" != "1" ] && [ "$PHASE" != "3" ] && [ "$PHASE" != "PLAN" ] && [ "$PHASE" != "BUILD" ]; then
  exit 0
fi

# Extract domain keywords from product spec section headers
DOMAIN_KEYWORDS=""
if [ -f "$SPEC_FILE" ]; then
  # Use grep -E as PCRE fallback safe
  DOMAIN_KEYWORDS=$(grep -E '^## ' "$SPEC_FILE" 2>/dev/null | sed 's/^## //' | tr '\n' '|' | sed 's/|$//')
fi

if [ -z "$DOMAIN_KEYWORDS" ]; then
  printf "pre-phase-start: No domain keywords found in spec. Skipping known-fix injection.\n" >&2
  exit 0
fi

# Search known-fixes for matching symptoms
if [ ! -f "$KNOWN_FIXES" ]; then
  printf "pre-phase-start: No known-fixes.md found. Skipping.\n" >&2
  exit 0
fi

RELEVANT_FIXES=$(grep -B1 -A10 -iE "$DOMAIN_KEYWORDS" "$KNOWN_FIXES" 2>/dev/null)

if [ -n "$RELEVANT_FIXES" ]; then
  {
    printf "# Known Fixes Relevant To This Work\n"
    printf "# These are proven solutions. If you encounter these symptoms, apply the fix exactly.\n\n"
    printf "%s\n" "$RELEVANT_FIXES"
  } > "$INJECTED_FILE"
  printf "pre-phase-start: Injected %s lines of known fixes into context.\n" "$(printf '%s' "$RELEVANT_FIXES" | wc -l)" >&2
else
  printf "pre-phase-start: No matching known fixes for current domain.\n" >&2
  rm -f "$INJECTED_FILE" 2>/dev/null
fi

exit 0
