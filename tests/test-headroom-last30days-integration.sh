#!/usr/bin/env bash
# headroom + last30days harness integration. Verifies the SHIPPED artifacts (_install) — the
# installer wiring, isolation guarantees, launcher, skills, licenses, and docs. Does NOT require
# headroom/last30days to be actually installed (network-free, deterministic).
set -u
ROOT="G:/harness infra"
INSTALL="$ROOT/_install/install.sh"
LAUNCHER="$ROOT/_install/scripts/claude-hr.sh"
HR_SKILL="$ROOT/_install/skills/headroom/SKILL.md"
L30_DIR="$ROOT/_install/skills/last30days"
LIC_DIR="$ROOT/_install/LICENSES"
README="$ROOT/_install/README.md"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "== headroom + last30days integration =="

# --- headroom: isolated install in installer ---
grep -q 'HEADROOM_VENV=' "$INSTALL" && ok "H1 installer defines HEADROOM_VENV" || no "H1 no HEADROOM_VENV"
grep -q 'headroom-venv' "$INSTALL" && ok "H2 venv path is ~/.claude/headroom-venv" || no "H2 venv path missing"
grep -qE 'uv venv --python' "$INSTALL" && ok "H3 installer creates isolated uv venv" || no "H3 no uv venv step"
grep -qE 'uv pip install .*headroom-ai' "$INSTALL" && ok "H4 installer pip-installs headroom-ai into venv" || no "H4 no headroom-ai install"
grep -qE 'command -v uv' "$INSTALL" && ok "H5 installer guards on uv presence" || no "H5 no uv guard"
# isolation: must NOT install headroom globally / into system python. The ONLY allowed install is the
# venv-scoped `uv pip install --python "$HEADROOM_VENV" ...`. Flag any global form (pipx, npm -g, or a
# bare pip/uv-pip without the venv --python target).
if grep -qE 'pipx install .*headroom|npm install -g .*headroom' "$INSTALL"; then
  no "H6 installer installs headroom globally (pipx/npm -g)"
elif grep -E '^[[:space:]]*(uv )?pip install' "$INSTALL" | grep -i headroom | grep -qv -- '--python'; then
  no "H6 a headroom pip install command is not scoped to the venv (--python)"
else
  ok "H6 headroom only installed into the isolated venv (no global/system install)"
fi
# set -e safety: the install commands are inside if-conditions (guarded)
grep -qE 'if uv venv' "$INSTALL" && ok "H7 uv venv is an if-condition (set -e safe)" || no "H7 uv venv not guarded as if-condition"
# DISABLED-BY-DEFAULT: headroom must NOT install unless HEADROOM_INSTALL=1 (opt-in only)
grep -qE 'HEADROOM_INSTALL.*!= *"1"|HEADROOM_INSTALL:-0' "$INSTALL" && ok "H7b headroom install is OFF by default (HEADROOM_INSTALL=1 to opt in)" || no "H7b headroom not gated behind HEADROOM_INSTALL"
# the install pack must NEVER wire always-on (no executable redirect/service/wrap — comments OK)
if grep -vE '^\s*#' "$INSTALL" | grep -qE 'ANTHROPIC_BASE_URL|install apply|install agent|schtasks|sc(\.exe)? create|headroom (wrap|unwrap)'; then
  no "H7c install.sh contains executable always-on wiring"
else
  ok "H7c install.sh has NO executable always-on wiring (no redirect/service/wrap)"
fi
# shipped settings.json must not contain a proxy redirect
if grep -qE 'ANTHROPIC_BASE_URL|127\.0\.0\.1:8787' "$ROOT/_install/settings.json"; then no "H7d shipped settings.json has a proxy redirect"; else ok "H7d shipped settings.json has NO proxy redirect"; fi

# --- headroom: launcher ---
[ -f "$LAUNCHER" ] && ok "H8 claude-hr.sh launcher shipped in _install/scripts/" || no "H8 launcher missing"
if [ -f "$LAUNCHER" ]; then
  grep -q 'wrap claude' "$LAUNCHER" && ok "H9 launcher runs 'headroom wrap claude'" || no "H9 launcher does not wrap claude"
  grep -q 'headroom-venv' "$LAUNCHER" && ok "H10 launcher targets the isolated venv" || no "H10 launcher not using isolated venv"
  grep -qE 'Scripts/headroom|bin/headroom' "$LAUNCHER" && ok "H11 launcher resolves venv entrypoint (win+unix)" || no "H11 no cross-platform entrypoint resolution"
  grep -q 'exec claude' "$LAUNCHER" && ok "H12 launcher falls back to plain claude when headroom absent" || no "H12 no plain-claude fallback"
  bash -n "$LAUNCHER" && ok "H13 launcher is syntactically valid bash" || no "H13 launcher bash -n failed"
fi

# --- headroom: skill ---
[ -f "$HR_SKILL" ] && ok "H14 headroom skill SKILL.md shipped" || no "H14 headroom skill missing"
[ -f "$HR_SKILL" ] && head -20 "$HR_SKILL" | grep -q 'name: headroom' && ok "H15 skill has frontmatter name: headroom" || no "H15 skill frontmatter missing"

# --- last30days: vendored skill ---
[ -d "$L30_DIR" ] && ok "L1 last30days vendored in _install/skills/last30days/" || no "L1 last30days dir missing"
[ -f "$L30_DIR/SKILL.md" ] && ok "L2 last30days SKILL.md present" || no "L2 SKILL.md missing"
[ -d "$L30_DIR/scripts" ] && ok "L3 last30days scripts/ present" || no "L3 scripts dir missing"
# lean: heavy demo assets must NOT be bundled
if [ -d "$L30_DIR/assets" ]; then no "L4 heavy assets/ were bundled (should be excluded)"; else ok "L4 demo assets excluded (lean vendor)"; fi
# installer copies skills generically (covers headroom + last30days)
grep -q 'skills' "$INSTALL" && ok "L5 installer copies _install/skills/* to ~/.claude/skills/" || no "L5 installer skills copy missing"

# --- licenses ---
[ -f "$LIC_DIR/headroom-LICENSE" ] && ok "P1 headroom license retained" || no "P1 headroom license missing"
[ -f "$LIC_DIR/last30days-LICENSE" ] && ok "P2 last30days license retained" || no "P2 last30days license missing"

# --- docs ---
grep -qi 'headroom' "$README" && ok "P3 README documents headroom" || no "P3 README missing headroom"
grep -qi 'last30days' "$README" && ok "P4 README documents last30days" || no "P4 README missing last30days"
grep -qi 'Apache' "$README" && ok "P5 README notes headroom Apache-2.0 license" || no "P5 README missing headroom license note"

echo ""
echo "== RESULT: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
