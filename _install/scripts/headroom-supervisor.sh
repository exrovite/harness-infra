#!/bin/bash
# Headroom proxy supervisor (Linux/macOS) — keeps the compression proxy alive.
# Started at boot/login by systemd --user (or @reboot cron / nohup) installed by headroom-alwayson.sh.
# Mirrors headroom-supervisor.ps1: agent-90 profile, HEADROOM_RUST_DETECT=0 (the hang fix), watchdog loop.
#
# GLM (opt-in): if the marker file ~/.headroom/glm.enabled exists, this ALSO keeps a second
# compression proxy alive on 8791 -> https://api.z.ai/api/anthropic for `claude-glm`. The marker is
# created by glm-setup.sh. With NO marker, ONLY 8787 (-> anthropic) runs — behavior is unchanged.
# This supervisor holds NO z.ai token; the token lives only in the claude-glm launcher.
export HEADROOM_SAVINGS_PROFILE=agent-90
export HEADROOM_RUST_DETECT=0          # the fix: rust autodetect made compression hang
BASE="$HOME/.headroom"
GLM_MARKER="$BASE/glm.enabled"
mkdir -p "$BASE"
# Resolve the isolated venv's headroom entrypoint (Unix bin/, fall back to Windows Scripts/ under MSYS).
HR="$HOME/.claude/headroom-venv/bin/headroom"
[ -x "$HR" ] || HR="$HOME/.claude/headroom-venv/Scripts/headroom"
log(){ printf '%s %s\n' "$(date -Iseconds)" "$1" >> "$BASE/supervisor.log"; }
if [ ! -x "$HR" ]; then log "headroom not found ($HR); supervisor exiting"; exit 0; fi

# Ensure a proxy is listening on $1; remaining args are extra headroom flags (e.g. z.ai upstream).
ensure(){
  local port="$1" jsonl="$2"; shift 2
  if curl -s -m 3 "http://127.0.0.1:${port}/livez" >/dev/null 2>&1; then
    log "proxy $port up"
  else
    log "proxy $port DOWN -> starting"
    nohup "$HR" proxy --port "$port" --log-file "$BASE/$jsonl" "$@" \
      >> "$BASE/proxy-srv.log" 2>> "$BASE/proxy-srv.err" &
  fi
}

log "supervisor started"
while true; do
  # 8787 -> anthropic (always; the normal `claude` path).
  ensure 8787 proxy-requests.jsonl
  # 8791 -> z.ai (GLM compression) only when the opt-in marker is present.
  if [ -f "$GLM_MARKER" ]; then
    ensure 8791 proxy-glm.jsonl --anthropic-api-url https://api.z.ai/api/anthropic
  fi
  sleep 20
done
