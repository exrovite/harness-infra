#!/usr/bin/env bash
set -uo pipefail

# PreToolUse hook: Auto-approve Edit/Write operations inside .claude/ directories
# Uses PreToolUse instead of PermissionRequest because PermissionRequest has known bugs:
#   - Race condition: dialog shows before hook returns (#12176)
#   - Cannot deny: prompt appears regardless (#19298)
#   - .claude/ protection bypasses PermissionRequest hooks since v2.1.78

# Read the PreToolUse payload from stdin
input="$(cat)"

# Extract the file path (works for Edit and Write tools)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")

# Normalize backslashes to forward slashes for consistent matching (Windows paths)
file_path="${file_path//\\//}"

# Auto-approve anything inside .claude/ (or .claude/skills/, /agents/, /commands/, etc.)
if [[ "$file_path" == *"/.claude/"* ]]; then
    # Exit 0 = allow tool to proceed
    exit 0
fi

# All other paths: exit 0 to proceed with normal permission flow
# (other PreToolUse hooks or the permission system will handle these)
exit 0
