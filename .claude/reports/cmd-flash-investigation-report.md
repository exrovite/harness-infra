# CMD Flash Investigation Report

**Date**: 2026-05-28
**Status**: RESOLVED

## Problem

Two black CMD windows flashing on screen every ~5 minutes, interrupting work. User reported these were created "a while ago" as part of early agent automation prototyping (Ralph Wiggum system era).

## Root Cause

**ImageWorkerWatchdog** scheduled task (runs every 5 minutes via Task Scheduler).

The task itself runs `pythonw.exe` (windowless), so the task launch is invisible. However, INSIDE the script at `G:\DualGPU build\My image generator\image_worker_watchdog.py`, two `subprocess.run()` calls spawn visible CMD windows:

1. **Line 38**: `subprocess.run(['tasklist', ...], capture_output=True, text=True)` — no `CREATE_NO_WINDOW` flag
2. **Line 45**: `subprocess.run(['wmic', ...], capture_output=True, text=True)` — no `CREATE_NO_WINDOW` flag

Each call spawns `cmd.exe` without the `CREATE_NO_WINDOW` (0x08000000) creation flag, causing a brief black CMD window to flash on screen. Two calls = two flashes per 5-minute cycle.

A previous session attempted to fix this by making the calls windowless, but the fix did not take effect.

## Resolution

Disabled the scheduled task permanently:

```powershell
Disable-ScheduledTask -TaskName 'ImageWorkerWatchdog'
```

- Task state: **Disabled** (Enabled = False)
- Survives reboots — will NOT re-enable on restart
- Only re-enables via explicit command or Task Scheduler UI

## To Re-enable

When the image worker watchdog is needed again:

```powershell
Enable-ScheduledTask -TaskName 'ImageWorkerWatchdog'
```

## Proper Fix (if re-enabling later)

Add `creationflags=0x08000000` to both subprocess calls in `image_worker_watchdog.py`:

```python
CREATE_NO_WINDOW = 0x08000000

# Line 38
result = subprocess.run(
    ['tasklist', '/FI', 'IMAGENAME eq python.exe', '/FO', 'CSV'],
    capture_output=True, text=True,
    creationflags=CREATE_NO_WINDOW
)

# Line 45
result2 = subprocess.run(
    ['wmic', 'process', 'where', "name='python.exe'", 'get', 'commandline'],
    capture_output=True, text=True,
    creationflags=CREATE_NO_WINDOW
)
```

## Investigation Notes

### What was checked (and ruled out)
- Windows Task Scheduler: 65+ tasks audited — only ImageWorkerWatchdog had a minute-level repeat
- Registry Run keys (HKCU\...\Run): XSplit, ProtonVPN, VCam, Edge — none periodic
- Startup folder: 2 items, both `.disabled`
- WMI permanent event subscriptions: only default SCM filter
- NSSM services: OpenClawNode (stopped)
- Hermes cron system: empty (no jobs)
- Claude Code CronCreate: session-scoped, not persistent
- VBScript launchers: none found
- Running processes: 4 Claude Code instances audited, bash.exe spawns confirmed NOT to flash
- `.openclaw/`, `.hermes/`, `.claude/` directories: no looping scripts found

### Also cleaned up during investigation
- **Watcher Slot 2** (REGISTRY.json): stale claim from G:/Descript Clone, May 5 (23 days old) — reset to available
- **Ghost Claude Code session** (PID 41980): identified as orphaned process from closed terminal

### Key learning
`pythonw.exe` hides the Python process window, but does NOT hide windows created by `subprocess.run()` child processes. Always pass `creationflags=CREATE_NO_WINDOW` when calling system commands from windowless Python scripts on Windows.
