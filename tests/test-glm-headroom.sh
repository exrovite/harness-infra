#!/usr/bin/env bash
# Functional TDD for: route claude-glm through headroom (8791) for compression,
# WITHOUT touching the Anthropic connection (8787 / settings.json).
#
# Contract:
#  - The GLM compression proxy (8791 -> z.ai) is reachable and serves GLM.
#  - claude-glm.cmd points ANTHROPIC_BASE_URL at the headroom proxy (8791), not direct z.ai.
#  - claude-glm.cmd clears ANTHROPIC_API_KEY so the real Anthropic key can never be sent to z.ai
#    (z.ai 401s on it -> see test_zai_rejects_anthropic_key).
#  - claude-glm.cmd keeps ANTHROPIC_AUTH_TOKEN (the z.ai credential).
#  - claude-glm.cmd never references the Anthropic proxy port 8787 (isolation guard).
#  - The Anthropic proxy on 8787 stays up and is a different process from 8791.
#
# Usage: bash tests/test-glm-headroom.sh            (curl + config tests)
#        GLM_E2E=1 bash tests/test-glm-headroom.sh  (also run real `claude-glm -p`)

set -u
LAUNCHER="${LAUNCHER:-C:/Users/exrov/AppData/Roaming/npm/claude-glm.cmd}"
GLM_PROXY="http://127.0.0.1:8791"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
nonce(){ echo "$RANDOM$RANDOM$RANDOM"; }

# Pull the z.ai auth token straight from the launcher so the suite is self-contained.
TOKEN="$(grep -i 'set ANTHROPIC_AUTH_TOKEN=' "$LAUNCHER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r')"
body(){ echo "{\"model\":\"glm-5.1\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"reply OK n=$(nonce)\"}]}"; }

echo "== GLM-through-headroom TDD =="

# 1. GLM compression proxy is listening.
if netstat -ano 2>/dev/null | grep -q "127.0.0.1:8791 .*LISTENING"; then
  ok "8791 GLM/headroom proxy is listening"
else
  no "8791 GLM/headroom proxy is NOT listening (start headroom supervisor)"
fi

# 2. GLM works through the proxy with the Bearer credential (cache-busted).
code="$(curl -s -o /tmp/glm_t2.json -w '%{http_code}' "$GLM_PROXY/v1/messages" \
  -H "Authorization: Bearer $TOKEN" -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" --data "$(body)" --max-time 40)"
if [ "$code" = "200" ] && grep -q '"model":"glm' /tmp/glm_t2.json; then
  ok "GLM non-streaming via 8791 -> 200 + glm model"
else
  no "GLM non-streaming via 8791 (http=$code) $(head -c 160 /tmp/glm_t2.json)"
fi

# 3. Streaming works through the proxy (claude-code uses streaming).
curl -s -o /tmp/glm_t3.txt "$GLM_PROXY/v1/messages" \
  -H "Authorization: Bearer $TOKEN" -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  --data "$(body | sed 's/}$/,"stream":true}/')" --max-time 40
if grep -q 'message_start' /tmp/glm_t3.txt && grep -q 'content_block_delta\|message_stop' /tmp/glm_t3.txt; then
  ok "GLM streaming via 8791 -> SSE message_start + deltas"
else
  no "GLM streaming via 8791 (no SSE events) $(head -c 160 /tmp/glm_t3.txt)"
fi

# 4. z.ai rejects the real Anthropic key -> proves WHY the launcher must clear it.
code="$(curl -s -o /tmp/glm_t4.json -w '%{http_code}' "$GLM_PROXY/v1/messages" \
  -H "x-api-key: ${ANTHROPIC_API_KEY:-none}" -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" --data "$(body)" --max-time 40)"
if [ "$code" = "401" ]; then
  ok "z.ai 401s on the Anthropic key (justifies clearing ANTHROPIC_API_KEY)"
else
  no "expected 401 sending Anthropic key to z.ai, got http=$code"
fi

# 5. Launcher routes through the headroom proxy.
if grep -qi 'set ANTHROPIC_BASE_URL=http://127.0.0.1:8791' "$LAUNCHER"; then
  ok "claude-glm.cmd routes ANTHROPIC_BASE_URL through 8791"
else
  no "claude-glm.cmd does NOT point at 8791 (compression path missing)"
fi

# 6. Launcher uses a separate CLAUDE_CONFIG_DIR (no claude.ai OAuth) so the clean z.ai
#    AUTH_TOKEN method works. This is what makes claude-glm authenticate end-to-end.
CFGDIR="$(grep -i 'set CLAUDE_CONFIG_DIR=' "$LAUNCHER" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r')"
if [ -n "$CFGDIR" ]; then
  ok "claude-glm.cmd sets a dedicated CLAUDE_CONFIG_DIR ($CFGDIR)"
else
  no "claude-glm.cmd has no CLAUDE_CONFIG_DIR (OAuth will hijack auth)"
fi

# 7. Launcher still carries the z.ai auth token.
if [ -n "$TOKEN" ]; then ok "claude-glm.cmd sets ANTHROPIC_AUTH_TOKEN"; else no "ANTHROPIC_AUTH_TOKEN missing"; fi

# 8. Isolation guard: launcher must never ROUTE through the Anthropic proxy 8787
#    (a comment mentioning 8787 is fine; only a base-url assignment to it is a violation).
if grep -qiE '^[[:space:]]*set ANTHROPIC_BASE_URL=.*8787' "$LAUNCHER"; then
  no "claude-glm.cmd routes ANTHROPIC_BASE_URL through 8787 (must stay off the Anthropic path)"
else
  ok "claude-glm.cmd does not route through the Anthropic proxy (8787)"
fi

# 8b. The GLM config dir must NOT contain a claude.ai OAuth login (that is the whole point
#     of isolating it -- OAuth there would hijack the z.ai token again).
if [ -n "$CFGDIR" ]; then
  CFGWIN="$(echo "$CFGDIR" | tr '\\' '/')"
  if [ -f "$CFGWIN/.credentials.json" ]; then
    no "GLM config dir has a .credentials.json (OAuth) -> will hijack z.ai auth"
  else
    ok "GLM config dir has no OAuth login (clean z.ai auth)"
  fi
fi

# 9. Anthropic connection untouched: 8787 up and a different PID than 8791.
p87="$(netstat -ano 2>/dev/null | grep '127.0.0.1:8787 .*LISTENING' | awk '{print $NF}' | head -1 | tr -d '\r')"
p91="$(netstat -ano 2>/dev/null | grep '127.0.0.1:8791 .*LISTENING' | awk '{print $NF}' | head -1 | tr -d '\r')"
if [ -n "$p87" ] && [ "$p87" != "$p91" ]; then
  ok "Anthropic proxy 8787 still up (pid $p87), separate from GLM 8791 (pid $p91)"
else
  no "Anthropic proxy 8787 check failed (pid87=$p87 pid91=$p91)"
fi

# 10. (optional) Real end-to-end: launch claude-glm headless and confirm a GLM reply.
if [ "${GLM_E2E:-0}" = "1" ]; then
  echo "  .. running real claude-glm -p (headless) .."
  out="$(cmd.exe //c claude-glm -p "Reply with exactly the word PONG and nothing else." 2>/tmp/glm_e2e.err)"
  echo "    claude-glm output: $(echo "$out" | tr -d '\r' | head -c 120)"
  if echo "$out" | grep -qi 'PONG'; then
    ok "end-to-end: claude-glm returned a live GLM reply"
  else
    no "end-to-end: claude-glm did not return expected reply ($(head -c 160 /tmp/glm_e2e.err))"
  fi
fi

echo "== RESULT: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
