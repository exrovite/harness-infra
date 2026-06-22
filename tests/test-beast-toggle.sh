#!/bin/bash
# test-beast-toggle.sh — Beast-Mode toggle + helpers (Sprint 35)
# Verifies beast-on / beast-off exact-match tokens, the full truth table
# (D1/D2), and the beast_* helpers — against the LIVE hook/scripts, sandboxed
# via HARNESS_STATE_DIR so real project state is never touched.
#
# Usage: bash tests/test-beast-toggle.sh
set -u

HOOKS="$HOME/.claude/hooks"
SCRIPTS="$HOME/.claude/scripts"
LIB="$SCRIPTS/lib-helpers.sh"
OPS="$HOOKS/on-prompt-submit.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

SBX=$(mktemp -d 2>/dev/null || echo "/tmp/beast-$$")
STATE="$SBX/.claude/state"
mkdir -p "$STATE"
HFLAG="$STATE/harness-disabled.flag"
BFLAG="$STATE/beast-mode.flag"
export HARNESS_STATE_DIR="$STATE"
cleanup() { rm -rf "$SBX" 2>/dev/null; }
trap cleanup EXIT
seed_phase() { printf '{"phase":"%s","sprint":35,"iteration":0}' "$1" > "$STATE/current-phase.json"; }
run() { printf '{"prompt":%s}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$OPS" 2>/dev/null; }

seed_phase BUILD

# ---------------------------------------------------------------------------
# 1. Helpers
# ---------------------------------------------------------------------------
[ -f "$LIB" ] && source "$LIB" 2>/dev/null
rm -f "$BFLAG"
if type beast_is_on >/dev/null 2>&1; then
  if beast_is_on "$STATE"; then bad "beast_is_on false when no flag"; else ok "beast_is_on false when no flag"; fi
  beast_enable "$STATE" 2>/dev/null
  if [ -f "$BFLAG" ]; then ok "beast_enable creates flag"; else bad "beast_enable creates flag"; fi
  if beast_is_on "$STATE"; then ok "beast_is_on true when flag present"; else bad "beast_is_on true when flag present"; fi
  beast_disable "$STATE" 2>/dev/null
  if [ -f "$BFLAG" ]; then bad "beast_disable removes flag"; else ok "beast_disable removes flag"; fi
else
  bad "beast_is_on helper exists"; bad "beast_enable helper exists"
  bad "beast_is_on true when flag present"; bad "beast_disable helper exists"
fi

# ---------------------------------------------------------------------------
# 2. Truth table via the live hook
# ---------------------------------------------------------------------------
# A1: beast-on (harness already on) -> beast flag present + BEAST MODE ON banner
rm -f "$HFLAG" "$BFLAG"
OUT=$(run "beast-on")
[ -f "$BFLAG" ] && ok "A1 beast-on creates beast-mode.flag" || bad "A1 beast-on creates beast-mode.flag"
printf '%s' "$OUT" | grep -qi 'BEAST MODE ON' && ok "A1 beast-on banner" || bad "A1 beast-on banner (got: $OUT)"

# A2: beast-on while harness DISABLED -> harness flag removed + beast flag + exact re-enable notice
rm -f "$BFLAG"; : > "$HFLAG"
OUT=$(run "beast-on")
[ -f "$HFLAG" ] && bad "A2 beast-on removes harness-disabled.flag" || ok "A2 beast-on removes harness-disabled.flag"
[ -f "$BFLAG" ] && ok "A2 beast-on creates beast flag while disabled" || bad "A2 beast-on creates beast flag while disabled"
printf '%s' "$OUT" | grep -qF 'HARNESS RE-ENABLED — beast mode requires active gates' \
  && ok "A2 exact re-enable notice" || bad "A2 exact re-enable notice (got: $OUT)"

# A3: beast-off -> beast flag gone, harness flag still absent
rm -f "$HFLAG"; : > "$BFLAG"
OUT=$(run "beast-off")
[ -f "$BFLAG" ] && bad "A3 beast-off removes beast flag" || ok "A3 beast-off removes beast flag"
[ -f "$HFLAG" ] && bad "A3 beast-off leaves harness untouched" || ok "A3 beast-off leaves harness untouched"
printf '%s' "$OUT" | grep -qi 'BEAST MODE OFF' && ok "A3 beast-off banner" || bad "A3 beast-off banner (got: $OUT)"

# A4: '---' while in beast mode -> harness flag present AND beast flag cleared
rm -f "$HFLAG"; : > "$BFLAG"
run "---" >/dev/null
[ -f "$HFLAG" ] && ok "A4 '---' disables harness" || bad "A4 '---' disables harness"
[ -f "$BFLAG" ] && bad "A4 '---' also clears beast flag" || ok "A4 '---' also clears beast flag"

# A5: '===' after that -> harness flag removed AND beast flag still absent (no auto-resume)
# (state from A4: harness off, beast off)
run "===" >/dev/null
[ -f "$HFLAG" ] && bad "A5 '===' re-enables harness" || ok "A5 '===' re-enables harness"
[ -f "$BFLAG" ] && bad "A5 '===' does NOT auto-resume beast" || ok "A5 '===' does NOT auto-resume beast"

# A6: exact-match only
rm -f "$BFLAG"
run "beast-on please" >/dev/null
[ -f "$BFLAG" ] && bad "A6 'beast-on please' must NOT toggle" || ok "A6 'beast-on please' does not toggle"
rm -f "$BFLAG"
run "   beast-on   " >/dev/null
[ -f "$BFLAG" ] && ok "A6 padded '  beast-on  ' toggles (trim)" || bad "A6 padded '  beast-on  ' toggles (trim)"

# A7: no prefix collision — beast-off never creates the flag
rm -f "$BFLAG"
run "beast-off" >/dev/null
[ -f "$BFLAG" ] && bad "A7 beast-off must not trigger ON path" || ok "A7 beast-off no prefix collision"

# A8: bash -n clean
bash -n "$OPS" 2>/dev/null && ok "A8 on-prompt-submit.sh bash -n clean" || bad "A8 on-prompt-submit.sh bash -n clean"
bash -n "$LIB" 2>/dev/null && ok "A8 lib-helpers.sh bash -n clean" || bad "A8 lib-helpers.sh bash -n clean"

echo "---------------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
