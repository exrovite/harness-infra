#!/usr/bin/env bash
# Packaging TDD for the secret-safe GLM add-on (Sprint 34).
# Asserts C1-C13 of .claude/contracts/sprint-34-contract.md against the repo tree.
# No live proxy / browser needed — pure static + sandboxed checks.
#
# Usage: bash tests/test-glm-packaging.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INST="$ROOT/_install"
CMD_TPL="$INST/templates/claude-glm.cmd.template"
SH_TPL="$INST/templates/claude-glm.template.sh"
SUP_PS1="$INST/scripts/headroom-supervisor.ps1"
SUP_SH="$INST/scripts/headroom-supervisor.sh"
GLM_SETUP="$INST/scripts/glm-setup.sh"
INSTALL_SH="$INST/install.sh"
GITIGNORE="$ROOT/.gitignore"

PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
has(){ [ -f "$1" ] && grep -qiE "$2" "$1"; }     # file $1 contains ERE $2 (case-insensitive)
hasx(){ [ -f "$1" ] && grep -qE "$2" "$1"; }     # case-sensitive

echo "== GLM packaging TDD =="

# ---- C1: no real z.ai token in any file git would commit (tracked OR untracked-not-ignored) ----
TOKEN_RE='[0-9a-f]{32}\.[A-Za-z0-9_-]{8,}'
cd "$ROOT" || exit 1
committable="$( { git ls-files; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u )"
hits=""
while IFS= read -r f || [ -n "$f" ]; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  if grep -nEI "$TOKEN_RE" "$f" >/dev/null 2>&1; then hits="$hits $f"; fi
done <<EOF
$committable
EOF
if [ -z "$hits" ]; then
  ok "C1 no z.ai-token-shaped secret in any committable file"
else
  no "C1 token-shaped secret found in:$hits"
fi

# ---- C4: both launcher templates ship ----
[ -f "$CMD_TPL" ] && ok "C4 .cmd template present" || no "C4 .cmd template missing ($CMD_TPL)"
[ -f "$SH_TPL" ]  && ok "C4 .sh template present"  || no "C4 .sh template missing ($SH_TPL)"

# ---- C2: placeholder, not a real key ----
has "$CMD_TPL" '__ZAI_API_KEY__' && ok "C2 .cmd uses __ZAI_API_KEY__ placeholder" || no "C2 .cmd placeholder missing"
has "$SH_TPL"  '__ZAI_API_KEY__' && ok "C2 .sh uses __ZAI_API_KEY__ placeholder"  || no "C2 .sh placeholder missing"

# ---- C5: dedicated CLAUDE_CONFIG_DIR ----
has "$CMD_TPL" 'CLAUDE_CONFIG_DIR' && ok "C5 .cmd sets CLAUDE_CONFIG_DIR" || no "C5 .cmd CLAUDE_CONFIG_DIR missing"
has "$SH_TPL"  'CLAUDE_CONFIG_DIR' && ok "C5 .sh sets CLAUDE_CONFIG_DIR"  || no "C5 .sh CLAUDE_CONFIG_DIR missing"

# ---- C6: clear ANTHROPIC_API_KEY + set AUTH_TOKEN from placeholder ----
has "$CMD_TPL" '^[[:space:]]*set ANTHROPIC_API_KEY=[[:space:]]*$' && ok "C6 .cmd clears ANTHROPIC_API_KEY" || no "C6 .cmd does not clear ANTHROPIC_API_KEY"
has "$CMD_TPL" 'ANTHROPIC_AUTH_TOKEN=__ZAI_API_KEY__' && ok "C6 .cmd AUTH_TOKEN from placeholder" || no "C6 .cmd AUTH_TOKEN placeholder missing"
has "$SH_TPL"  '(unset[[:space:]]+ANTHROPIC_API_KEY|ANTHROPIC_API_KEY=)' && ok "C6 .sh clears/unsets ANTHROPIC_API_KEY" || no "C6 .sh ANTHROPIC_API_KEY handling missing"
has "$SH_TPL"  'ANTHROPIC_AUTH_TOKEN=.*__ZAI_API_KEY__' && ok "C6 .sh AUTH_TOKEN from placeholder" || no "C6 .sh AUTH_TOKEN placeholder missing"

# ---- C7: 8791 base url + glm-5.1 pin ----
has "$CMD_TPL" 'ANTHROPIC_BASE_URL=.{0,1}http://127.0.0.1:8791' && ok "C7 .cmd routes 8791" || no "C7 .cmd 8791 missing"
has "$CMD_TPL" 'glm-5\.1' && ok "C7 .cmd pins glm-5.1" || no "C7 .cmd glm-5.1 missing"
has "$SH_TPL"  'ANTHROPIC_BASE_URL=.{0,1}http://127.0.0.1:8791' && ok "C7 .sh routes 8791" || no "C7 .sh 8791 missing"
has "$SH_TPL"  'glm-5\.1' && ok "C7 .sh pins glm-5.1" || no "C7 .sh glm-5.1 missing"

# ---- C8: supervisors reference 8787 AND marker-gated 8791; no token ----
for sup in "$SUP_PS1" "$SUP_SH"; do
  base="$(basename "$sup")"
  if has "$sup" '8787' && has "$sup" '8791'; then ok "C8 $base references 8787 + 8791"; else no "C8 $base missing a port"; fi
  has "$sup" 'glm\.enabled' && ok "C8 $base gates 8791 on glm.enabled marker" || no "C8 $base has no glm.enabled gate"
  if hasx "$sup" "$TOKEN_RE"; then no "C8 $base contains a token-shaped secret"; else ok "C8 $base holds no token"; fi
done

# ---- C9: 8787 behavior preserved ----
for sup in "$SUP_PS1" "$SUP_SH"; do
  base="$(basename "$sup")"
  has "$sup" 'agent-90' && has "$sup" 'RUST_DETECT' && ok "C9 $base keeps agent-90 + RUST_DETECT=0" || no "C9 $base lost compression env"
done

# ---- C10: 8791 only under marker (marker token appears BEFORE the first 8791 reference) ----
for sup in "$SUP_PS1" "$SUP_SH"; do
  base="$(basename "$sup")"
  mline=$(grep -nE 'glm\.enabled' "$sup" 2>/dev/null | head -1 | cut -d: -f1)
  pline=$(grep -nE '8791' "$sup" 2>/dev/null | head -1 | cut -d: -f1)
  if [ -n "$mline" ] && [ -n "$pline" ] && [ "$mline" -le "$pline" ]; then
    ok "C10 $base gates 8791 (marker line $mline <= 8791 line $pline)"
  else
    no "C10 $base 8791 not clearly marker-gated (marker=$mline 8791=$pline)"
  fi
done

# ---- C11/C12: install.sh GLM step is opt-in & guarded ----
has "$INSTALL_SH" 'GLM_INSTALL' && ok "C11 install.sh honors GLM_INSTALL opt-out" || no "C11 GLM_INSTALL guard missing"
has "$INSTALL_SH" 'ZAI_API_KEY' && ok "C11 install.sh keys GLM on ZAI_API_KEY" || no "C11 ZAI_API_KEY gate missing"
has "$INSTALL_SH" 'glm-setup\.sh' && ok "C11 install.sh invokes glm-setup.sh" || no "C11 glm-setup.sh not wired"

# ---- C13: glm-setup.sh exists, never hardcodes the token, touches marker ----
[ -f "$GLM_SETUP" ] && ok "C13 glm-setup.sh present" || no "C13 glm-setup.sh missing"
has "$GLM_SETUP" 'glm\.enabled' && ok "C13 glm-setup touches glm.enabled marker" || no "C13 glm-setup marker missing"
if hasx "$GLM_SETUP" "$TOKEN_RE"; then no "C13 glm-setup.sh has a hardcoded token"; else ok "C13 glm-setup.sh has no hardcoded token"; fi

# ---- C3: generated launcher is gitignored ----
has "$GITIGNORE" 'claude-glm' && ok "C3 .gitignore covers generated claude-glm launcher" || no "C3 .gitignore missing claude-glm rule"

# ---- C18: glm-setup wires the harness into the GLM config dir (hooks merge + CLAUDE.md copy) ----
has "$GLM_SETUP" '\.hooks =' && ok "C18 glm-setup merges .hooks into GLM config" || no "C18 glm-setup hooks merge missing"
has "$GLM_SETUP" 'cp "\$SRC_CLAUDEMD"' && ok "C18 glm-setup copies CLAUDE.md into GLM config" || no "C18 glm-setup CLAUDE.md copy missing"

# ---- C19 (functional): enable merges ONLY hooks (never env/auth) + copies CLAUDE.md ----
SBX="$(mktemp -d)"
mkdir -p "$SBX/.claude"
cat > "$SBX/.claude/settings.json" <<'JSON'
{"env":{"ANTHROPIC_BASE_URL":"http://127.0.0.1:8787"},"hooks":{"PreToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"bash x.sh"}]}]},"theme":"dark"}
JSON
printf 'HARNESS PROTOCOL TEXT\n' > "$SBX/.claude/CLAUDE.md"
HOME="$SBX" bash "$GLM_SETUP" enable "zzztestkeyzzz.PLACEHOLDER" >/dev/null 2>&1
GCFG="$SBX/.claude-glm-config/settings.json"
if [ -f "$GCFG" ] && jq -e '.hooks.PreToolUse' "$GCFG" >/dev/null 2>&1; then ok "C19 GLM config received harness hooks"; else no "C19 GLM config has no hooks"; fi
if [ -f "$GCFG" ] && [ "$(jq 'has("env")' "$GCFG" 2>/dev/null)" = "false" ]; then ok "C19 GLM config did NOT inherit env/auth block"; else no "C19 GLM config leaked env (8787 redirect would break GLM)"; fi
if [ -f "$GCFG" ] && ! grep -q 'ANTHROPIC_BASE_URL' "$GCFG"; then ok "C19 no ANTHROPIC_BASE_URL in GLM config"; else no "C19 ANTHROPIC_BASE_URL present in GLM config"; fi
[ -f "$SBX/.claude-glm-config/CLAUDE.md" ] && ok "C19 global CLAUDE.md copied into GLM config" || no "C19 CLAUDE.md not copied"
rm -rf "$SBX"

echo "== RESULT: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
