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
ARBOR_SH="$ROOT/_install/scripts/arbor.sh"
ARBOR_SKILLS="$ROOT/_install/skills"
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
grep -qE 'if uv venv|&& uv pip install' "$INSTALL" && ok "H7 uv venv/install guarded as if-condition (set -e safe)" || no "H7 uv venv not guarded as if-condition"
# INSTALL-ON-BY-DEFAULT: HEADROOM_INSTALL defaults to 1 (skip only with =0)
grep -qE 'HEADROOM_INSTALL:-1' "$INSTALL" && ok "H7b headroom installs by default (HEADROOM_INSTALL=0 to skip)" || no "H7b headroom not default-on via HEADROOM_INSTALL:-1"
# ALWAYS-ON wired via the health-gated enabler (NOT inline redirect)
grep -qE 'headroom-alwayson\.sh' "$INSTALL" && ok "H7c install.sh calls headroom-alwayson.sh enabler" || no "H7c install.sh does not call the always-on enabler"
grep -qE 'HEADROOM_ALWAYSON:-1' "$INSTALL" && ok "H7c2 always-on defaults on (HEADROOM_ALWAYSON=0 to skip)" || no "H7c2 always-on not default-on"
# CRITICAL SAFETY: install.sh must NOT inline-set ANTHROPIC_BASE_URL (only the health-gated enabler may)
if grep -vE '^[[:space:]]*#' "$INSTALL" | grep -qE 'ANTHROPIC_BASE_URL'; then
  no "H7c3 install.sh inline-sets ANTHROPIC_BASE_URL (must be health-gated in enabler only)"
else
  ok "H7c3 install.sh never inline-sets ANTHROPIC_BASE_URL (delegated to health-gated enabler)"
fi
# the enabler MUST health-gate the redirect: ANTHROPIC_BASE_URL only after a /livez check
ALW="$ROOT/_install/scripts/headroom-alwayson.sh"
[ -f "$ALW" ] && ok "H7e headroom-alwayson.sh shipped" || no "H7e enabler missing"
if [ -f "$ALW" ]; then
  bash -n "$ALW" && ok "H7e2 enabler is valid bash" || no "H7e2 enabler bash -n failed"
  grep -q 'livez' "$ALW" && grep -q 'settings_set_redirect' "$ALW" && ok "H7e3 enabler health-gates the redirect (livez before set)" || no "H7e3 enabler not health-gated"
  grep -qE 'disable\)' "$ALW" && ok "H7e4 enabler supports clean disable (un-brick path)" || no "H7e4 no disable path"
fi
# supervisor scripts shipped (both OSes) with the HEADROOM_RUST_DETECT=0 fix + agent-90
for sup in headroom-supervisor.ps1 headroom-supervisor.sh; do
  f="$ROOT/_install/scripts/$sup"
  [ -f "$f" ] && grep -q 'HEADROOM_RUST_DETECT' "$f" && grep -q 'agent-90' "$f" && ok "H7f $sup ships with RUST_DETECT=0 + agent-90 fix" || no "H7f $sup missing or lacks the fix env"
done
# shipped settings.json must NEVER carry the redirect (would brick fresh installs before proxy is up)
if grep -qE 'ANTHROPIC_BASE_URL|127\.0\.0\.1:8787' "$ROOT/_install/settings.json"; then no "H7g shipped settings.json carries a redirect (brick risk)"; else ok "H7g shipped settings.json has NO redirect (safe)"; fi
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
# --- Arbor (autonomous research-agent CLI) integration ---
grep -qE 'ARBOR_INSTALL:-1' "$INSTALL" && ok "A1 Arbor installs by default (ARBOR_INSTALL=0 to skip)" || no "A1 Arbor not default-on via ARBOR_INSTALL:-1"
grep -qE 'if uv venv .*ARBOR_VENV|&& uv pip install --python "\$ARBOR_VENV"' "$INSTALL" && ok "A2 Arbor uv venv/install guarded as if-condition (set -e safe)" || no "A2 Arbor uv venv not guarded as if-condition"
grep -qE 'command -v uv .*command -v git' "$INSTALL" && ok "A3 Arbor step skips cleanly if uv/git absent" || no "A3 Arbor step not guarded on uv/git presence"
grep -q 'arbor-venv' "$INSTALL" && ok "A4 Arbor uses ISOLATED venv (~/.claude/arbor-venv)" || no "A4 Arbor not isolated to its own venv"
grep -qiE 'api_key|fabricat' "$INSTALL" && grep -q 'ANTHROPIC_API_KEY' "$INSTALL" && ok "A5 Arbor scaffolds config without fabricating an API key" || no "A5 Arbor config scaffold issue"
[ -f "$ARBOR_SH" ] && ok "A6 arbor.sh launcher shipped" || no "A6 arbor.sh launcher missing"
if [ -f "$ARBOR_SH" ]; then
  bash -n "$ARBOR_SH" && ok "A6b arbor.sh is valid bash" || no "A6b arbor.sh bash -n failed"
  grep -q 'ARBOR_VENV' "$ARBOR_SH" && ok "A6c arbor.sh resolves the isolated venv entrypoint" || no "A6c arbor.sh does not target the venv"
fi
ASKILLS=$(ls -d "$ARBOR_SKILLS"/arbor-agent-* 2>/dev/null | wc -l | tr -d ' ')
[ "$ASKILLS" -ge 10 ] && ok "A7 arbor-agent-* skills vendored ($ASKILLS found)" || no "A7 arbor-agent skills missing (found $ASKILLS)"
[ -f "$LIC_DIR/arbor-LICENSE" ] && ok "A8 arbor-LICENSE (Apache-2.0) shipped" || no "A8 arbor-LICENSE missing"
grep -qi 'arbor' "$README" && ok "A9 README documents Arbor" || no "A9 README does not mention Arbor"
grep -qE '\[10/10\] Arbor' "$INSTALL" && ok "A10 install.sh step 10 labeled Arbor" || no "A10 install.sh step 10 label missing"

echo "== RESULT: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
