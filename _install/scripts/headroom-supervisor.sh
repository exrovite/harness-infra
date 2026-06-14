#!/bin/bash
# Headroom proxy supervisor (Linux/macOS) — keeps the compression proxy alive.
# Started at boot/login by systemd --user (or @reboot cron / nohup) installed by headroom-alwayson.sh.
# Mirrors headroom-supervisor.ps1: agent-90 profile, HEADROOM_RUST_DETECT=0 (the hang fix), watchdog loop.
export HEADROOM_SAVINGS_PROFILE=agent-90
export HEADROOM_RUST_DETECT=0          # the fix: rust autodetect made compression hang
export HEADROOM_PORT=8787
BASE="$HOME/.headroom"
mkdir -p "$BASE"
# Resolve the isolated venv's headroom entrypoint (Unix bin/, fall back to Windows Scripts/ under MSYS).
HR="$HOME/.claude/headroom-venv/bin/headroom"
[ -x "$HR" ] || HR="$HOME/.claude/headroom-venv/Scripts/headroom"
log(){ printf '%s %s\n' "$(date -Iseconds)" "$1" >> "$BASE/supervisor.log"; }
if [ ! -x "$HR" ]; then log "headroom not found ($HR); supervisor exiting"; exit 0; fi
log "supervisor started"
while true; do
  # Is something listening on 8787?
  if curl -s -m 3 "http://127.0.0.1:8787/livez" >/dev/null 2>&1; then
    log "proxy up"
  else
    log "proxy DOWN -> starting"
    nohup "$HR" proxy --log-file "$BASE/proxy-requests.jsonl" \
      >> "$BASE/proxy-srv.log" 2>> "$BASE/proxy-srv.err" &
  fi
  sleep 20
done
