#!/bin/bash
# headroom-alwayson.sh — enable (or disable) transparent always-on headroom compression.
#
#   enable  (default): prefetch model -> install autostart supervisor -> start proxy ->
#                       HEALTH-CHECK -> only THEN set ANTHROPIC_BASE_URL in ~/.claude/settings.json.
#   disable          : remove redirect, stop supervisor/proxy, remove autostart.
#
# SAFETY (the lesson from the 2026-06-13 incident): the global ANTHROPIC_BASE_URL redirect is written
# ONLY after the proxy answers /livez. If the proxy can't be started or stays down, we DO NOT set the
# redirect — so a machine never ends up pointing Claude at a dead proxy (which bricks every session).
# Everything is guarded; failure leaves Claude talking to Anthropic directly + the claude-hr.sh
# opt-in launcher still available.
#
# Usage: bash headroom-alwayson.sh [enable|disable]
set -u
ACTION="${1:-enable}"
PORT="${HEADROOM_PORT:-8787}"
BASE="$HOME/.headroom"
VENV="$HOME/.claude/headroom-venv"
SETTINGS="$HOME/.claude/settings.json"
SCRIPTS="$HOME/.claude/scripts"
BASE_URL="http://127.0.0.1:${PORT}"

# Resolve headroom entrypoint (Unix bin/, Windows Scripts/).
HR="$VENV/bin/headroom"; [ -x "$HR" ] || HR="$VENV/Scripts/headroom.exe"; [ -x "$HR" ] || HR="$VENV/Scripts/headroom"

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  Darwin) OS=mac ;;
  *) OS=linux ;;
esac

settings_set_redirect() {  # $1 = url, or empty to delete
  [ -f "$SETTINGS" ] || printf '{}' > "$SETTINGS"
  cp "$SETTINGS" "${SETTINGS}.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  local tmp; tmp=$(mktemp)
  if [ -n "$1" ]; then
    jq --arg u "$1" '.env.ANTHROPIC_BASE_URL = $u' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  else
    jq 'del(.env.ANTHROPIC_BASE_URL)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  fi
}

proxy_healthy() { curl -s -m 4 "${BASE_URL}/livez" >/dev/null 2>&1; }

if [ "$ACTION" = "disable" ]; then
  echo "[headroom] disabling always-on..."
  settings_set_redirect ""              # remove the redirect FIRST (un-brick), then tear down proxy
  if [ "$OS" = windows ]; then
    MSYS_NO_PATHCONV=1 schtasks //End //TN "headroom-proxy-supervisor" >/dev/null 2>&1 || true
    MSYS_NO_PATHCONV=1 schtasks //Delete //TN "headroom-proxy-supervisor" //F >/dev/null 2>&1 || true
    powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort $PORT -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1 || true
  else
    systemctl --user disable --now headroom-proxy.service >/dev/null 2>&1 || true
    rm -f "$HOME/.config/systemd/user/headroom-proxy.service" 2>/dev/null || true
    ( crontab -l 2>/dev/null | grep -v 'headroom-supervisor.sh' | crontab - ) 2>/dev/null || true
    pkill -f "$VENV/.*headroom.*proxy" 2>/dev/null || true
  fi
  echo "[headroom] always-on disabled. Claude now talks to Anthropic directly."
  exit 0
fi

# ---------- enable ----------
[ -x "$HR" ] || { echo "[headroom] not installed ($VENV); skipping always-on."; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "[headroom] jq required to edit settings.json; skipping always-on."; exit 0; }
mkdir -p "$BASE"

echo "[headroom] prefetching compression model (one-time, may take minutes)..."
HEADROOM_RUST_DETECT=0 HEADROOM_SAVINGS_PROFILE=agent-90 "$HR" proxy --port "$PORT" --log-file "$BASE/proxy-requests.jsonl" \
  >/dev/null 2>&1 &
PREWARM_PID=$!

echo "[headroom] installing autostart supervisor ($OS)..."
if [ "$OS" = windows ]; then
  if MSYS_NO_PATHCONV=1 schtasks //Create //TN "headroom-proxy-supervisor" //SC ONLOGON //F \
       //TR "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"$HOME\\.claude\\scripts\\headroom-supervisor.ps1\"" >/dev/null 2>&1; then
    MSYS_NO_PATHCONV=1 schtasks //Run //TN "headroom-proxy-supervisor" >/dev/null 2>&1 || true
    echo "  -> logon supervisor task installed"
  else
    echo "  -> WARN: could not create scheduled task (needs permission?). Proxy will run only this session."
  fi
else
  # Prefer systemd --user (no root); fall back to @reboot cron.
  if command -v systemctl >/dev/null 2>&1 && systemctl --user >/dev/null 2>&1; then
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/headroom-proxy.service" <<UNIT
[Unit]
Description=Headroom compression proxy supervisor
[Service]
ExecStart=/bin/bash $SCRIPTS/headroom-supervisor.sh
Restart=always
[Install]
WantedBy=default.target
UNIT
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable --now headroom-proxy.service >/dev/null 2>&1 && echo "  -> systemd --user service installed" \
      || echo "  -> WARN: systemd --user enable failed; proxy may not survive reboot."
  else
    ( crontab -l 2>/dev/null | grep -v 'headroom-supervisor.sh'; echo "@reboot /bin/bash $SCRIPTS/headroom-supervisor.sh" ) | crontab - 2>/dev/null \
      && echo "  -> @reboot cron supervisor installed" || echo "  -> WARN: no systemd/cron; proxy won't auto-start at boot."
    nohup /bin/bash "$SCRIPTS/headroom-supervisor.sh" >/dev/null 2>&1 &
  fi
fi

echo "[headroom] waiting for proxy to become healthy (up to 180s; first run downloads the model)..."
HEALTHY=0
for i in $(seq 1 60); do
  if proxy_healthy; then HEALTHY=1; break; fi
  sleep 3
done

if [ "$HEALTHY" = "1" ]; then
  settings_set_redirect "$BASE_URL"
  echo "[headroom] HEALTHY. Global redirect set: ANTHROPIC_BASE_URL=$BASE_URL"
  echo "           Always-on compression is active. Restart Claude Code to pick it up."
  echo "           Disable anytime: bash $SCRIPTS/headroom-alwayson.sh disable"
else
  echo "[headroom] WARN: proxy did NOT become healthy. Redirect NOT set (this is the safety net)."
  echo "           Claude continues talking to Anthropic directly. No session is broken."
  echo "           Use opt-in compression via: bash $SCRIPTS/claude-hr.sh  — and investigate the proxy."
  kill "$PREWARM_PID" 2>/dev/null || true
fi
