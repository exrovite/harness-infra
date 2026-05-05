#!/bin/bash
# validate-state-transition.sh — State machine enforcement (Layer 2)
# Validates that state transitions follow allowed paths.
# REQUESTED→CONTRACT_LOCKED→IMPLEMENTED→VERIFIED→ACCEPTED with STUCK from any state.
# Prevents skipping states.
#
# Usage: bash validate-state-transition.sh <current_state> <requested_state>
# Exit: 0 = valid transition, 1 = invalid transition

CURRENT="$1"
REQUESTED="$2"

if [ -z "$CURRENT" ] || [ -z "$REQUESTED" ]; then
  printf "validate-state-transition: ERROR — usage: validate-state-transition.sh <current> <requested>\n" >&2
  exit 1
fi

# STUCK can be entered from any active state
if [ "$REQUESTED" = "STUCK" ]; then
  case "$CURRENT" in
    "REQUESTED"|"CONTRACT_LOCKED"|"IMPLEMENTED"|"VERIFIED")
      printf "VALID: %s → STUCK (escalation)\n" "$CURRENT" >&2
      exit 0
      ;;
    *)
      printf "INVALID: Cannot enter STUCK from %s\n" "$CURRENT" >&2
      exit 1
      ;;
  esac
fi

# Define valid forward transitions
case "$CURRENT" in
  "REQUESTED")
    if [ "$REQUESTED" = "CONTRACT_LOCKED" ]; then
      printf "VALID: REQUESTED → CONTRACT_LOCKED\n" >&2
      exit 0
    fi
    ;;
  "CONTRACT_LOCKED")
    if [ "$REQUESTED" = "IMPLEMENTED" ]; then
      printf "VALID: CONTRACT_LOCKED → IMPLEMENTED\n" >&2
      exit 0
    fi
    ;;
  "IMPLEMENTED")
    if [ "$REQUESTED" = "VERIFIED" ]; then
      printf "VALID: IMPLEMENTED → VERIFIED\n" >&2
      exit 0
    fi
    ;;
  "VERIFIED")
    # Can go forward to ACCEPTED or backward to IMPLEMENTED
    if [ "$REQUESTED" = "ACCEPTED" ] || [ "$REQUESTED" = "IMPLEMENTED" ]; then
      printf "VALID: VERIFIED → %s\n" "$REQUESTED" >&2
      exit 0
    fi
    ;;
  "STUCK")
    # STUCK exits to any active state (resuming from pre-STUCK state)
    case "$REQUESTED" in
      "REQUESTED"|"CONTRACT_LOCKED"|"IMPLEMENTED"|"VERIFIED")
        printf "VALID: STUCK → %s (resume after guidance)\n" "$REQUESTED" >&2
        exit 0
        ;;
    esac
    ;;
  "ACCEPTED")
    printf "INVALID: ACCEPTED is terminal. No further transitions.\n" >&2
    exit 1
    ;;
esac

printf "INVALID: %s → %s is not an allowed transition\n" "$CURRENT" "$REQUESTED" >&2
exit 1
