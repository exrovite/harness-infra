#!/usr/bin/env bash
# Launch Claude Code on GLM (Zhipu AI via Z.ai), through the local headroom
# compression proxy. Docs: https://docs.z.ai/devpack/faq
#
# This is a TEMPLATE. The installer renders it to the real launcher with your z.ai
# key injected in place of __ZAI_API_KEY__. The rendered launcher is gitignored and
# must never be committed.
#
# Why a dedicated CLAUDE_CONFIG_DIR: if claude.ai OAuth is logged in, it hijacks the
# z.ai token (401 Invalid bearer). Running GLM in its OWN config dir (no OAuth login)
# lets the clean official z.ai method (ANTHROPIC_AUTH_TOKEN only) authenticate.
export CLAUDE_CONFIG_DIR="$HOME/.claude-glm-config"

# Clear any inherited Anthropic API key so it can never be sent to z.ai (z.ai 401s on it).
unset ANTHROPIC_API_KEY
export ANTHROPIC_AUTH_TOKEN="__ZAI_API_KEY__"

# Route through the headroom GLM compression proxy (port 8791 -> https://api.z.ai/api/anthropic).
# The Anthropic proxy (port 8787) is untouched.
export ANTHROPIC_BASE_URL="http://127.0.0.1:8791"
export API_TIMEOUT_MS=3000000
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# Model: pinned to glm-5.1 for all slots.
export ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.1
export ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.1
export ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5.1
export ANTHROPIC_MODEL=glm-5.1

export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1

exec claude "$@"
