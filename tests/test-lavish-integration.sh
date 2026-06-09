#!/usr/bin/env bash
# Sprint 32 — lavish-axi harness integration. TDD: must fail before implementation.
# Verifies the SHIPPED artifacts (_install) + live gate exemptions + skill, NOT a live browser.
set -u
ROOT="G:/harness infra"
INSTALL="$ROOT/_install/install.sh"
SETTINGS_SHIP="$ROOT/_install/settings.json"
PWG="$HOME/.claude/hooks/pre-write-gate.sh"
PBG="$HOME/.claude/hooks/pre-bash-gate.sh"
PFG="$HOME/.claude/hooks/pre-flight-gate.sh"
SKILL_DIR="$HOME/.claude/skills/lavish-review"
HELPER="$SKILL_DIR/lavish-review.sh"
LIC_DIR="$ROOT/_install/LICENSES"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "== Sprint 32 lavish-axi integration =="

# C1: installer has a pinned, guarded npm step + runs setup hooks
if { grep -q 'lavish-axi@0.1.20' "$INSTALL"; } || { grep -q 'LAVISH_VERSION="0.1.20"' "$INSTALL" && grep -qE 'npm install -g .*lavish-axi@' "$INSTALL"; }; then
  ok "C1a installer pins lavish-axi@0.1.20"
else
  no "C1a no pinned npm step in install.sh"
fi
grep -qE 'command -v npm|command -v node|which npm' "$INSTALL" && ok "C1b installer guards on npm/node presence" || no "C1b no node/npm guard"
[ -f "$ROOT/_install/vendor/lavish-axi-0.1.20.tgz" ] && ok "C1c vendored lavish-axi bundle present in _install/vendor/" || no "C1c vendor bundle missing"
{ grep -q 'vendor/lavish-axi' "$INSTALL" && grep -q -- '--offline' "$INSTALL"; } && ok "C1d installer installs from the vendored bundle offline-first" || no "C1d installer not using vendored bundle/offline"

# C2: shipped settings.json keeps our 4 hook types and is valid JSON (we do NOT bake an absolute path)
if jq -e . "$SETTINGS_SHIP" >/dev/null 2>&1; then ok "C2a _install/settings.json is valid JSON"; else no "C2a _install/settings.json invalid"; fi
MISS=""
for h in PreToolUse PostToolUse Stop UserPromptSubmit; do
  jq -e --arg k "$h" '.hooks[$k]' "$SETTINGS_SHIP" >/dev/null 2>&1 || MISS="$MISS $h"
done
[ -z "$MISS" ] && ok "C2b _install/settings.json retains all 4 harness hook types" || no "C2b missing hook types:$MISS"
# must NOT ship a machine-specific absolute path
if grep -qi 'Users\\\\exrov\|/c/Users/exrov\|AppData' "$SETTINGS_SHIP"; then no "C2c shipped settings leaks a machine-specific path"; else ok "C2c shipped settings has no machine-specific path"; fi
# C2d: shipped settings now BAKES a portable SessionStart (lavish-axi bin, no absolute path)
if jq -e '.hooks.SessionStart[0].hooks[0].command | test("lavish-axi")' "$SETTINGS_SHIP" >/dev/null 2>&1; then ok "C2d shipped settings bakes a portable SessionStart (lavish-axi)"; else no "C2d no portable SessionStart baked in shipped settings"; fi

# C3: .lavish-axi/ exempt in all three gates
grep -q '.lavish-axi/' "$PWG" && ok "C3a pre-write-gate exempts .lavish-axi/" || no "C3a pre-write-gate missing .lavish-axi/ exemption"
grep -q '.lavish-axi/' "$PBG" && ok "C3b pre-bash-gate exempts .lavish-axi/" || no "C3b pre-bash-gate missing .lavish-axi/ exemption"
grep -q '.lavish-axi/' "$PFG" && ok "C3c pre-flight-gate exempts .lavish-axi/" || no "C3c pre-flight-gate missing .lavish-axi/ exemption"

# C4: skill + helper exist; helper sequences cron_pause -> poll -> cron_resume
[ -f "$SKILL_DIR/SKILL.md" ] && ok "C4a skill SKILL.md exists" || no "C4a skill missing"
[ -f "$HELPER" ] && ok "C4b helper lavish-review.sh exists" || no "C4b helper missing"
if [ -f "$HELPER" ]; then
  bash -n "$HELPER" 2>/dev/null && ok "C4c helper is syntactically valid" || no "C4c helper bad syntax"
  grep -q 'cron_pause' "$HELPER" && grep -q 'lavish-axi poll' "$HELPER" && grep -q 'cron_resume' "$HELPER" \
    && ok "C4d helper does cron_pause -> poll -> cron_resume" || no "C4d helper missing pause/poll/resume sequence"
  # dry-run ordering with a stub lavish-axi + stubbed helpers
  TMP=$(mktemp -d); BIN="$TMP/bin"; mkdir -p "$BIN"
  cat > "$BIN/lavish-axi" <<'STUB'
#!/usr/bin/env bash
echo "lavish-axi $*" >> "$LAVISH_TRACE"
[ "$1" = "poll" ] && echo "STUB_FEEDBACK: change the heading"
exit 0
STUB
  chmod +x "$BIN/lavish-axi"
  export LAVISH_TRACE="$TMP/trace.log"; : > "$LAVISH_TRACE"
  # stub cron_pause/cron_resume by sourcing a fake lib if helper sources lib-helpers
  OUT=$(PATH="$BIN:$PATH" HARNESS_SKIP_CRON=1 bash "$HELPER" "$TMP/artifact.html" 2>&1)
  if grep -q 'poll' "$LAVISH_TRACE" 2>/dev/null; then ok "C4e helper invokes lavish-axi poll on dry-run"; else no "C4e helper did not call poll (trace: $(cat "$LAVISH_TRACE" 2>/dev/null | tr '\n' ';'))"; fi
  echo "$OUT" | grep -q 'STUB_FEEDBACK' && ok "C4f helper returns the human feedback to caller" || no "C4f helper did not surface feedback"
  rm -rf "$TMP"
fi

# C5: MIT notices for lavish-axi + axi-sdk-js
[ -f "$LIC_DIR/lavish-axi-LICENSE" ] && grep -qi 'MIT' "$LIC_DIR/lavish-axi-LICENSE" && ok "C5a lavish-axi MIT notice present" || no "C5a lavish-axi LICENSE missing"
[ -f "$LIC_DIR/axi-sdk-js-LICENSE" ] && grep -qi 'MIT' "$LIC_DIR/axi-sdk-js-LICENSE" && ok "C5b axi-sdk-js MIT notice present" || no "C5b axi-sdk-js LICENSE missing"

echo "-- RESULT: $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
