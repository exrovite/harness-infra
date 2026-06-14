# Headroom proxy supervisor (Windows) — keeps the compression proxy alive.
# Replaces headroom's native dual-task supervisor, which flaps on some hosts.
# Started at logon by the scheduled task "headroom-proxy-supervisor" (installed by headroom-alwayson.sh).
$ErrorActionPreference = 'SilentlyContinue'
$env:HEADROOM_SAVINGS_PROFILE = 'agent-90'
$env:HEADROOM_RUST_DETECT     = '0'    # <-- the fix: rust autodetect made compression hang on this host
$env:HEADROOM_PORT            = '8787'
$hr   = Join-Path $HOME '.claude\headroom-venv\Scripts\headroom.exe'
$base = Join-Path $HOME '.headroom'
New-Item -ItemType Directory -Force -Path $base | Out-Null
function Log($m) { ((Get-Date -Format 'o') + ' ' + $m) | Out-File (Join-Path $base 'supervisor.log') -Append -Encoding utf8 }
if (-not (Test-Path $hr)) { Log 'headroom.exe not found; supervisor exiting'; return }
Log 'supervisor started'
while ($true) {
  $up = Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue
  if (-not $up) {
    Log 'proxy DOWN -> starting'
    Start-Process -FilePath $hr -ArgumentList @('proxy','--log-file',(Join-Path $base 'proxy-requests.jsonl')) `
      -WindowStyle Hidden -RedirectStandardOutput (Join-Path $base 'proxy-srv.log') -RedirectStandardError (Join-Path $base 'proxy-srv.err')
  } else {
    Log ('proxy up pid ' + ($up.OwningProcess | Select-Object -First 1))
  }
  Start-Sleep -Seconds 20
}
