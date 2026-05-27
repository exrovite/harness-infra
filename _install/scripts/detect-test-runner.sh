#!/bin/bash
# detect-test-runner.sh — Layer 2: Auto-detect test framework from project config
# Called by harness at BUILD phase start to determine if TDD enforcement applies.
#
# Checks (in order): custom config, package.json, pytest/pyproject/setup.cfg,
#                     Cargo.toml, go.mod, Gemfile
#
# Output: writes .claude/state/tdd/tdd-config.json on success
# Exit:   0 = framework detected, 1 = no framework found
#
# Usage: bash detect-test-runner.sh [project-root]

set -euo pipefail

source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null || { echo "ERROR: lib-helpers.sh not found" >&2; exit 1; }

PROJECT_ROOT="${1:-.}"
STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"
TDD_DIR="${STATE_DIR}/tdd"
CONFIG_FILE=".claude/config/test-command.txt"

cd "$PROJECT_ROOT" 2>/dev/null || { echo "ERROR: Cannot cd to $PROJECT_ROOT" >&2; exit 1; }

mkdir -p "$TDD_DIR" 2>/dev/null

TEST_CMD=""
FRAMEWORK=""

# --- Priority 1: Explicit user override ---
if [ -f "$CONFIG_FILE" ]; then
  TEST_CMD=$(head -1 "$CONFIG_FILE" | tr -d '\r' | xargs)
  if [ -n "$TEST_CMD" ]; then
    FRAMEWORK="custom"
    echo "Detected: custom test command from $CONFIG_FILE" >&2
  fi
fi

# --- Priority 2: Node.js (package.json) ---
if [ -z "$TEST_CMD" ] && [ -f "package.json" ]; then
  # Check for test script in package.json
  if command -v jq >/dev/null 2>&1; then
    PKG_TEST=$(jq -r '.scripts.test // empty' package.json 2>/dev/null)
  else
    # Fallback: grep for test script
    PKG_TEST=$(sed -n 's/.*"test"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json 2>/dev/null || true)
  fi

  if [ -n "$PKG_TEST" ] && [ "$PKG_TEST" != "echo \"Error: no test specified\" && exit 1" ]; then
    # Detect specific framework from the test script
    if echo "$PKG_TEST" | grep -qiE '(vitest|jest|mocha|ava|tap|jasmine)'; then
      FRAMEWORK=$(echo "$PKG_TEST" | grep -oiE '(vitest|jest|mocha|ava|tap|jasmine)' | head -1 | tr '[:upper:]' '[:lower:]')
      TEST_CMD="npm test"
    else
      FRAMEWORK="npm-test"
      TEST_CMD="npm test"
    fi
    echo "Detected: $FRAMEWORK via package.json" >&2
  fi
fi

# --- Priority 3: Python (pytest via pyproject.toml, pytest.ini, setup.cfg, or tox.ini) ---
if [ -z "$TEST_CMD" ]; then
  PYTEST_DETECTED=false

  if [ -f "pytest.ini" ]; then
    PYTEST_DETECTED=true
  elif [ -f "pyproject.toml" ] && grep -qE '\[tool\.pytest' pyproject.toml 2>/dev/null; then
    PYTEST_DETECTED=true
  elif [ -f "setup.cfg" ] && grep -qE '\[tool:pytest\]' setup.cfg 2>/dev/null; then
    PYTEST_DETECTED=true
  elif [ -f "tox.ini" ] && grep -qE '\[pytest\]' tox.ini 2>/dev/null; then
    PYTEST_DETECTED=true
  fi

  if [ "$PYTEST_DETECTED" = true ]; then
    FRAMEWORK="pytest"
    TEST_CMD="python -m pytest"
    echo "Detected: pytest via config file" >&2
  fi
fi

# --- Priority 4: Python fallback (any .py test files with no config) ---
if [ -z "$TEST_CMD" ]; then
  PY_TEST_FILES=$(find . -maxdepth 3 \( -name 'test_*.py' -o -name '*_test.py' \) 2>/dev/null | head -1)
  if [ -n "$PY_TEST_FILES" ]; then
    # Check if pytest is importable
    if command -v pytest >/dev/null 2>&1; then
      FRAMEWORK="pytest"
      TEST_CMD="python -m pytest"
      echo "Detected: pytest (found test_*.py files and pytest on PATH)" >&2
    elif command -v python >/dev/null 2>&1; then
      FRAMEWORK="unittest"
      TEST_CMD="python -m unittest discover"
      echo "Detected: python unittest (found test_*.py files)" >&2
    fi
  fi
fi

# --- Priority 5: Rust (Cargo.toml) ---
if [ -z "$TEST_CMD" ] && [ -f "Cargo.toml" ]; then
  FRAMEWORK="cargo"
  TEST_CMD="cargo test"
  echo "Detected: cargo test via Cargo.toml" >&2
fi

# --- Priority 6: Go (go.mod) ---
if [ -z "$TEST_CMD" ] && [ -f "go.mod" ]; then
  FRAMEWORK="go"
  TEST_CMD="go test ./..."
  echo "Detected: go test via go.mod" >&2
fi

# --- Priority 7: Ruby (Gemfile with rspec or Rakefile with test task) ---
if [ -z "$TEST_CMD" ]; then
  if [ -f "Gemfile" ] && grep -q 'rspec' Gemfile 2>/dev/null; then
    FRAMEWORK="rspec"
    TEST_CMD="bundle exec rspec"
    echo "Detected: rspec via Gemfile" >&2
  elif [ -f "Rakefile" ] && grep -qE '(Rake::TestTask|task.*:test)' Rakefile 2>/dev/null; then
    FRAMEWORK="rake-test"
    TEST_CMD="rake test"
    echo "Detected: rake test via Rakefile" >&2
  fi
fi

# --- Priority 8: .NET (*.csproj or *.sln) ---
if [ -z "$TEST_CMD" ]; then
  CSPROJ=$(find . -maxdepth 2 -name '*.csproj' 2>/dev/null | head -1)
  SLN=$(find . -maxdepth 1 -name '*.sln' 2>/dev/null | head -1)
  if [ -n "$CSPROJ" ] || [ -n "$SLN" ]; then
    FRAMEWORK="dotnet"
    TEST_CMD="dotnet test"
    echo "Detected: dotnet test" >&2
  fi
fi

# --- No framework found ---
if [ -z "$TEST_CMD" ]; then
  echo "ERROR: No test framework detected." >&2
  echo "Create $CONFIG_FILE with your test command (one line) to enable TDD enforcement." >&2
  exit 1
fi

# --- Write tdd-config.json ---
TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
# Escape test command for safe JSON embedding (backslashes first, then quotes)
SAFE_CMD=$(printf '%s' "$TEST_CMD" | sed 's|\\|\\\\|g; s|"|\\"|g')
CONFIG_JSON=$(printf '{"tdd_required":true,"test_cmd":"%s","framework":"%s","detected_at":"%s"}' \
  "$SAFE_CMD" "$FRAMEWORK" "$TS")

atomic_write "$CONFIG_JSON" "${TDD_DIR}/tdd-config.json"

echo "TDD config written: framework=$FRAMEWORK cmd=$TEST_CMD" >&2
exit 0
