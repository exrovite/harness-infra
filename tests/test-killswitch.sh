#!/bin/bash
# test-killswitch.sh — Harness Kill-Switch (Sprint 33)
# Verifies the per-project `---`=OFF / `===`=ON toggle and that every enforcement
# hook short-circuits (allows) while the project flag is present.
#
# Tests run against the LIVE hooks/scripts, sandboxed via HARNESS_STATE_DIR so the
# real project state is never touched.
#
# Usage: bash tests/test-killswitch.sh
set -u

HOOKS="$HOME/.claude/hooks"
SCRIPTS="$HOME/.claude/scripts"
LIB="$SCRIPTS/lib-helpers.sh"

PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

# Fresh sandbox state dir per run
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/ks-$$")
STATE="$SBX/.claude/state"
mkdir -p "$STATE"
FLAG="$STATE/harness-disabled.flag"
export HARNESS_STATE_DIR="$STATE"

cleanup() { rm -rf "$SBX" 2>/dev/null; }
trap cleanup EXIT

seed_phase() { printf '{"phase":"%s","sprint":33,"iteration":0}' "$1" > "$STATE/current-phase.json"; }

# ---------------------------------------------------------------------------
# 1. lib-helpers guard functions
# ---------------------------------------------------------------------------
if [ -f "$LIB" ]; then source "$LIB" 2>/dev/null; fi

rm -f "$FLAG"
if type harness_is_disabled >/dev/null 2>&1; then
  if harness_is_disabled "$STATE"; then bad "harness_is_disabled false when no flag"; else ok "harness_is_disabled false when no flag"; fi
  harness_disable "$STATE" 2>/dev/null
  if [ -f "$FLAG" ]; then ok "harness_disable creates flag"; else bad "harness_disable creates flag"; fi
  if harness_is_disabled "$STATE"; then ok "harness_is_disabled true when flag present"; else bad "harness_is_disabled true when flag present"; fi
  harness_enable "$STATE" 2>/dev/null
  if [ -f "$FLAG" ]; then bad "harness_enable removes flag"; else ok "harness_enable removes flag"; fi
else
  bad "harness_is_disabled helper exists in lib-helpers.sh"
  bad "harness_disable helper exists"
  bad "harness_is_disabled true when flag present"
  bad "harness_enable helper exists"
fi

# ---------------------------------------------------------------------------
# 2. on-prompt-submit toggle: `---` writes flag + OFF banner
# ---------------------------------------------------------------------------
OPS="$HOOKS/on-prompt-submit.sh"

rm -f "$FLAG"; seed_phase BUILD
OUT=$(printf '{"prompt":"---"}' | bash "$OPS" 2>/dev/null)
if [ -f "$FLAG" ]; then ok "prompt '---' writes harness-disabled.flag"; else bad "prompt '---' writes harness-disabled.flag"; fi
if printf '%s' "$OUT" | grep -qi 'HARNESS OFF'; then ok "prompt '---' injects HARNESS OFF banner"; else bad "prompt '---' injects HARNESS OFF banner (got: $OUT)"; fi

# 3. ordinary prompt while OFF -> only the OFF banner, no full packet
OUT=$(printf '{"prompt":"please add a feature"}' | bash "$OPS" 2>/dev/null)
if printf '%s' "$OUT" | grep -qi 'HARNESS OFF'; then ok "OFF: ordinary prompt still shows OFF banner"; else bad "OFF: ordinary prompt still shows OFF banner"; fi
if printf '%s' "$OUT" | grep -q 'BUILD LOOP'; then bad "OFF: full packet suppressed (BUILD LOOP leaked)"; else ok "OFF: full packet suppressed"; fi

# 4. `===` deletes flag + ON banner
OUT=$(printf '{"prompt":"==="}' | bash "$OPS" 2>/dev/null)
if [ -f "$FLAG" ]; then bad "prompt '===' deletes flag"; else ok "prompt '===' deletes flag"; fi
if printf '%s' "$OUT" | grep -qi 'HARNESS ON'; then ok "prompt '===' injects HARNESS ON banner"; else bad "prompt '===' injects HARNESS ON banner (got: $OUT)"; fi

# 5. near-miss tokens do NOT toggle
for NM in "----" "==" "-- -" "foo---" ; do
  rm -f "$FLAG"
  printf '{"prompt":%s}' "$(printf '%s' "$NM" | jq -Rs .)" | bash "$OPS" >/dev/null 2>&1
  if [ -f "$FLAG" ]; then bad "near-miss '$NM' must NOT toggle OFF"; else ok "near-miss '$NM' does not toggle"; fi
done
# whitespace-padded exact token SHOULD toggle (trim)
rm -f "$FLAG"
printf '{"prompt":"   ---   "}' | bash "$OPS" >/dev/null 2>&1
if [ -f "$FLAG" ]; then ok "padded '   ---   ' toggles OFF (trimmed)"; else bad "padded '   ---   ' toggles OFF (trimmed)"; fi
rm -f "$FLAG"

# ---------------------------------------------------------------------------
# 6. Enforcement hooks short-circuit (allow) when flag present
# ---------------------------------------------------------------------------
# Build a PreToolUse input that writes a NON-exempt source file during PLAN phase
# (normally blocked). With the flag, it must be ALLOWED (exit 0).
SRC_JSON='{"tool_name":"Write","tool_input":{"file_path":"src/app/foo.py","content":"x=1"}}'

test_gate_allows_when_off() {
  local name="$1" hook="$2" input="$3"
  seed_phase PLAN
  # baseline: WITHOUT flag the gate should block (exit 2) — proves the gate is real
  rm -f "$FLAG"
  printf '%s' "$input" | bash "$HOOKS/$hook" >/dev/null 2>&1
  local rc_off=$?
  # with flag: must allow (exit 0)
  : > "$FLAG"
  printf '%s' "$input" | bash "$HOOKS/$hook" >/dev/null 2>&1
  local rc_on=$?
  rm -f "$FLAG"
  if [ "$rc_off" = "2" ]; then ok "$name blocks (exit 2) when harness ON"; else bad "$name should block when ON (got exit $rc_off)"; fi
  if [ "$rc_on" = "0" ]; then ok "$name ALLOWS (exit 0) when harness OFF"; else bad "$name should allow when OFF (got exit $rc_on)"; fi
}

test_gate_allows_when_off "pre-write-gate" "pre-write-gate.sh" "$SRC_JSON"

# pre-bash-gate: a file-writing bash command during PLAN
BASH_JSON='{"tool_name":"Bash","tool_input":{"command":"echo hi > src/app/foo.py"}}'
test_gate_allows_when_off "pre-bash-gate" "pre-bash-gate.sh" "$BASH_JSON"

# pre-flight-gate: blocking depends on a pending MCQ (not seedable in a bare sandbox),
# so assert only the kill-switch guarantee: with the flag present it ALLOWS (exit 0).
seed_phase PLAN
: > "$FLAG"
printf '%s' "$SRC_JSON" | bash "$HOOKS/pre-flight-gate.sh" >/dev/null 2>&1
PF_RC=$?
rm -f "$FLAG"
if [ "$PF_RC" = "0" ]; then ok "pre-flight-gate ALLOWS (exit 0) when harness OFF"; else bad "pre-flight-gate should allow when OFF (got exit $PF_RC)"; fi

# 7. post-write-check exits 0 and does NOT increment write-count while OFF
seed_phase BUILD
printf '0' > "$STATE/write-count.txt"
: > "$FLAG"
printf '%s' "$SRC_JSON" | bash "$HOOKS/post-write-check.sh" >/dev/null 2>&1
RC=$?
WC=$(cat "$STATE/write-count.txt" 2>/dev/null | tr -d ' \r\n')
rm -f "$FLAG"
if [ "$RC" = "0" ]; then ok "post-write-check exit 0 when OFF"; else bad "post-write-check exit 0 when OFF (got $RC)"; fi
if [ "${WC:-0}" = "0" ]; then ok "post-write-check does not count writes when OFF"; else bad "post-write-check counted a write when OFF (wc=$WC)"; fi

# ---------------------------------------------------------------------------
echo "---------------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
