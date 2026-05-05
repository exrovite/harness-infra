#!/bin/bash
# verify-fix-applied.sh — Structured fix verification (Layer 2, NO eval)
# Reads ## Verify section from known-fix entries.
# Three check types: file_exists, file_contains (with optional before_pattern), test_passes (allowlisted).
# Diffs actual code, never trusts commit messages.
#
# Usage: bash verify-fix-applied.sh
# Exit: 0 = fix verified (or no fix pending), 1 = fix not applied

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
FIX_FILE="${STATE_DIR}/next-fix.md"

# No fix pending — nothing to verify
if [ ! -f "$FIX_FILE" ]; then
  exit 0
fi

PASS=true
IN_VERIFY=false
CURRENT_TYPE=""
CURRENT_FILE=""
CURRENT_PATTERN=""
CURRENT_BEFORE=""
CURRENT_COMMAND=""

# Allowed test commands (security: no arbitrary execution)
ALLOWED_CMDS="pytest npm_test cargo_test python_-m_unittest"

while IFS= read -r line; do
  # Detect ## Verify section start
  if printf "%s" "$line" | grep -q "^## Verify" 2>/dev/null; then
    IN_VERIFY=true
    continue
  fi

  # Stop at next ## section
  if [ "$IN_VERIFY" = true ] && printf "%s" "$line" | grep -q "^## " 2>/dev/null; then
    break
  fi

  [ "$IN_VERIFY" = false ] && continue
  [ -z "$line" ] && continue

  # Parse structured verification format
  case "$line" in
    *"type: file_exists"*)
      # Execute any pending check first
      CURRENT_TYPE="file_exists"
      CURRENT_FILE="" ; CURRENT_PATTERN="" ; CURRENT_BEFORE="" ; CURRENT_COMMAND=""
      ;;
    *"type: file_contains"*)
      CURRENT_TYPE="file_contains"
      CURRENT_FILE="" ; CURRENT_PATTERN="" ; CURRENT_BEFORE="" ; CURRENT_COMMAND=""
      ;;
    *"type: test_passes"*)
      CURRENT_TYPE="test_passes"
      CURRENT_FILE="" ; CURRENT_PATTERN="" ; CURRENT_BEFORE="" ; CURRENT_COMMAND=""
      ;;
    *"file:"*)
      CURRENT_FILE=$(printf "%s" "$line" | sed 's/.*file: *//')
      ;;
    *"pattern:"*)
      CURRENT_PATTERN=$(printf "%s" "$line" | sed 's/.*pattern: *//')
      ;;
    *"before_pattern:"*)
      CURRENT_BEFORE=$(printf "%s" "$line" | sed 's/.*before_pattern: *//')

      # Execute file_contains check with ordering
      if [ "$CURRENT_TYPE" = "file_contains" ] && [ -n "$CURRENT_FILE" ] && [ -n "$CURRENT_PATTERN" ]; then
        if [ -n "$CURRENT_BEFORE" ]; then
          # Ordering check: pattern must appear BEFORE before_pattern
          PATTERN_LINE=$(grep -n "$CURRENT_PATTERN" "$CURRENT_FILE" 2>/dev/null | head -1 | cut -d: -f1)
          BEFORE_LINE=$(grep -n "$CURRENT_BEFORE" "$CURRENT_FILE" 2>/dev/null | head -1 | cut -d: -f1)
          if [ -z "$PATTERN_LINE" ] || [ -z "$BEFORE_LINE" ] || [ "$PATTERN_LINE" -gt "$BEFORE_LINE" ]; then
            printf "FAIL: Pattern ordering wrong in %s\n" "$CURRENT_FILE" >&2
            PASS=false
          fi
        else
          if ! grep -q "$CURRENT_PATTERN" "$CURRENT_FILE" 2>/dev/null; then
            printf "FAIL: Pattern not found in %s\n" "$CURRENT_FILE" >&2
            PASS=false
          fi
        fi
      fi
      ;;
    *"command:"*)
      CURRENT_COMMAND=$(printf "%s" "$line" | sed 's/.*command: *//')
      CMD_BASE=$(printf "%s" "$CURRENT_COMMAND" | awk '{print $1}')

      # Security: only run allowlisted commands
      ALLOWED=false
      case "$CMD_BASE" in
        "pytest"|"npm"|"cargo"|"python") ALLOWED=true ;;
      esac

      if [ "$ALLOWED" = true ]; then
        timeout 120 bash -c "$CURRENT_COMMAND" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
          printf "FAIL: Test command failed: %s\n" "$CURRENT_COMMAND" >&2
          PASS=false
        fi
      else
        printf "SKIP: Command not in allowlist: %s\n" "$CURRENT_COMMAND" >&2
      fi
      ;;
  esac

  # Execute file_exists check when we have enough info
  if [ "$CURRENT_TYPE" = "file_exists" ] && [ -n "$CURRENT_FILE" ]; then
    if [ ! -f "$CURRENT_FILE" ]; then
      printf "FAIL: %s does not exist\n" "$CURRENT_FILE" >&2
      PASS=false
    fi
    CURRENT_TYPE="" ; CURRENT_FILE=""
  fi

  # Execute file_contains without before_pattern (simple grep)
  if [ "$CURRENT_TYPE" = "file_contains" ] && [ -n "$CURRENT_FILE" ] && [ -n "$CURRENT_PATTERN" ] && [ -z "$CURRENT_BEFORE" ]; then
    # Check if next line is before_pattern — if not, execute now
    : # Defer until before_pattern line or end of block
  fi

done < "$FIX_FILE"

# Handle any pending file_contains without before_pattern
if [ "$CURRENT_TYPE" = "file_contains" ] && [ -n "$CURRENT_FILE" ] && [ -n "$CURRENT_PATTERN" ] && [ -z "$CURRENT_BEFORE" ]; then
  if ! grep -q "$CURRENT_PATTERN" "$CURRENT_FILE" 2>/dev/null; then
    printf "FAIL: Pattern not found in %s\n" "$CURRENT_FILE" >&2
    PASS=false
  fi
fi

if [ "$PASS" = false ]; then
  printf "verify-fix-applied: PROTOCOL FAIL — Known fix was not correctly applied.\n" >&2
  exit 1
fi

# Fix verified — clear pending
rm -f "$FIX_FILE"
printf "verify-fix-applied: PASS — Known fix verified in code.\n" >&2
exit 0
