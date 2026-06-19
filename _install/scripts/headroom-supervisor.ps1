# Headroom proxy supervisor (Windows) — keeps the compression proxy alive.
# Replaces headroom's native dual-task supervisor, which flaps on some hosts.
# Started at logon by the scheduled task "headroom-proxy-supervisor" (installed by headroom-alwayson.sh).
#
# GLM (opt-in): if the marker file ~/.headroom/glm.enabled exists, this ALSO keeps a second
# compression proxy alive on 8791 -> https://api.z.ai/api/anthropic for `claude-glm`. The marker is
# created by glm-setup.sh. With NO marker, ONLY 8787 (-> anthropic) runs — behavior is unchanged.
# This supervisor holds NO z.ai token; the token lives only in the claude-glm launcher.
$ErrorActionPreference = 'SilentlyContinue'
$env:HEADROOM_SAVINGS_PROFILE = 'agent-90'
$env:HEADROOM_RUST_DETECT     = '0'    # <-- the fix: rust autodetect made compression hang on this host
$hr   = Join-Path $HOME '.claude\headroom-venv\Scripts\headroom.exe'
$base = Join-Path $HOME '.headroom'
$glmMarker = Join-Path $base 'glm.enabled'
New-Item -ItemType Directory -Force -Path $base | Out-Null
function Log($m) { ((Get-Date -Format 'o') + ' ' + $m) | Out-File (Join-Path $base 'supervisor.log') -Append -Encoding utf8 }
if (-not (Test-Path $hr)) { Log 'headroom.exe not found; supervisor exiting'; return }

# Ensure a proxy is listening on $port; $extra adds args (e.g. the z.ai upstream for GLM).
function Ensure($port, $extra, $jsonl, $srvout, $srverr) {
  $up = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
  if (-not $up) {
    Log ("port $port DOWN -> starting")
    $a = @('proxy','--port',"$port",'--log-file',(Join-Path $base $jsonl)) + $extra
    Start-Process -FilePath $hr -ArgumentList $a -WindowStyle Hidden `
      -RedirectStandardOutput (Join-Path $base $srvout) -RedirectStandardError (Join-Path $base $srverr)
  } else {
    Log ("port $port up pid " + ($up.OwningProcess | Select-Object -First 1))
  }
}

Log 'supervisor started'
while ($true) {
  # 8787 -> anthropic (always; the normal `claude` path).
  Ensure 8787 @() 'proxy-requests.jsonl' 'proxy-srv.log' 'proxy-srv.err'
  # 8791 -> z.ai (GLM compression) only when the opt-in marker is present.
  if (Test-Path $glmMarker) {
    Ensure 8791 @('--anthropic-api-url','https://api.z.ai/api/anthropic') 'proxy-glm.jsonl' 'proxy-glm-srv.log' 'proxy-glm-srv.err'
  }
  Start-Sleep -Seconds 20
}
