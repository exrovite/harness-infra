#!/bin/bash
# classify-verification-need.sh — Layer 2 Verification Type Classifier
# Reads .claude/state/unverified-writes.jsonl, classifies files by extension,
# outputs JSON with required verification types.
#
# Usage: bash classify-verification-need.sh
# Output (stdout): {"required":[...],"files":[...],"prescription":"..."}

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
UNVERIFIED="${STATE_DIR}/unverified-writes.jsonl"

if [ ! -f "$UNVERIFIED" ] || [ ! -s "$UNVERIFIED" ]; then
  printf '{"required":[],"files":[],"prescription":"No unverified writes."}\n'
  exit 0
fi

# --- Collect unique file paths ---
declare -A SEEN
HAS_VISION="false"
HAS_FUNCTIONAL="false"
HAS_REVIEW="false"
FILES_JSON=""

while IFS= read -r line; do
  FILE=$(printf '%s' "$line" | jq -r '.file // ""' 2>/dev/null)
  [ -z "$FILE" ] && continue
  [ -n "${SEEN[$FILE]:-}" ] && continue
  SEEN[$FILE]=1

  BASENAME=$(basename "$FILE" 2>/dev/null)
  EXT="${BASENAME##*.}"
  EXT_LOWER=$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')
  BASE_LOWER=$(printf '%s' "$BASENAME" | tr '[:upper:]' '[:lower:]')
  FTYPE=""

  # Check test patterns first (before extension classification)
  case "$BASE_LOWER" in
    test_*|*_test.*|*.test.*|*.spec.*|*test.*|*_spec.*) FTYPE="functional"; HAS_FUNCTIONAL="true" ;;
  esac

  # Extension classification (only if not already classified as test)
  if [ -z "$FTYPE" ]; then
    case "$EXT_LOWER" in
      html|htm|css|scss|sass|less|jsx|tsx|vue|svelte|ejs|hbs|pug)
        FTYPE="vision"; HAS_VISION="true" ;;
      sh|bash|py|js|ts|go|rs|rb|java|cs|php|c|cpp|h)
        FTYPE="functional"; HAS_FUNCTIONAL="true" ;;
      json|yaml|yml|toml|ini|env|conf|cfg)
        FTYPE="functional"; HAS_FUNCTIONAL="true" ;;
      md|txt|rst|adoc)
        FTYPE="review"; HAS_REVIEW="true" ;;
      *)
        FTYPE="functional"; HAS_FUNCTIONAL="true" ;;
    esac
  fi

  # Build files array entry
  SAFE_F=$(printf '%s' "$FILE" | sed 's/\\/\\\\/g; s/"/\\"/g')
  if [ -n "$FILES_JSON" ]; then
    FILES_JSON="${FILES_JSON},"
  fi
  FILES_JSON="${FILES_JSON}{\"file\":\"${SAFE_F}\",\"type\":\"${FTYPE}\"}"
done < "$UNVERIFIED"

# --- Build required types array ---
REQUIRED=""
if [ "$HAS_VISION" = "true" ]; then
  REQUIRED="${REQUIRED}\"vision\","
fi
if [ "$HAS_FUNCTIONAL" = "true" ]; then
  REQUIRED="${REQUIRED}\"functional\","
fi
if [ -z "$REQUIRED" ] && [ "$HAS_REVIEW" = "true" ]; then
  REQUIRED="\"review\","
fi
# Trim trailing comma
REQUIRED="${REQUIRED%,}"

# --- Build prescription string ---
PRESCRIPTION=""
if [ "$HAS_VISION" = "true" ]; then
  PRESCRIPTION="UI files modified: vision validation needed (screenshot + visual check)."
fi
if [ "$HAS_FUNCTIONAL" = "true" ]; then
  [ -n "$PRESCRIPTION" ] && PRESCRIPTION="${PRESCRIPTION} "
  PRESCRIPTION="${PRESCRIPTION}Logic/config files modified: functional testing needed (execute + check output)."
fi
if [ -z "$PRESCRIPTION" ] && [ "$HAS_REVIEW" = "true" ]; then
  PRESCRIPTION="Documentation only: code review is sufficient."
fi
if [ -z "$PRESCRIPTION" ]; then
  PRESCRIPTION="No unverified writes requiring verification."
fi

# --- Output ---
printf '{"required":[%s],"files":[%s],"prescription":"%s"}\n' \
  "$REQUIRED" "$FILES_JSON" "$PRESCRIPTION"
