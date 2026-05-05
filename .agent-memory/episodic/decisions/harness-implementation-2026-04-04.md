# Decision Log: Harness Infrastructure Implementation
**Date**: 2026-04-04
**Decision Maker**: Harness Infrastructure Controller (Opus 4.6)

## Architectural Decisions

### 1. Explicit bash.exe path in settings.json hooks
**Decision**: Use `"C:/Program Files/Git/bin/bash.exe"` instead of just `bash`
**Why**: Claude Code hook executor may use PowerShell or cmd.exe on Windows. Explicit path guarantees bash execution.

### 2. Copy not symlink for operating-procedure.md
**Decision**: init-project.sh uses `cp` not `ln -s` for .agent-memory projects
**Why**: Windows 10 Home requires admin privileges for symlinks. Copy is functionally equivalent since file is read-only during harness operation.

### 3. printf not echo for all file writes
**Decision**: HARD RULE — all harness scripts use `printf "%s\n"` never `echo`
**Why**: `echo` may produce CRLF on Windows depending on system config. `printf` always produces LF.

### 4. mkdir-based atomic locking
**Decision**: Use `mkdir lockdir` instead of file-based PID lock
**Why**: `mkdir` is atomic on all platforms including NTFS. File-based locks have race conditions.

### 5. Integer arithmetic for budget (no bc)
**Decision**: Cost = iterations × $4 using bash $(( )) arithmetic
**Why**: `bc` not guaranteed on Windows. Integer math sufficient for budget estimates.

### 6. Calibration gate via contract file hiding
**Decision**: Harness temporarily renames sprint contract before evaluator runs, checks if evaluator notices
**Why**: Simple, deterministic, tests evaluator's ability to detect missing required files.

### 7. on-stuck-detected.sh does NOT call wait-for-human.sh
**Decision**: Hook writes agent-blocked.md and exits. Harness calls wait-for-human.sh.
**Why**: Separation of concerns — hooks detect and report, harness manages blocking/waiting.

### 8. PCRE (grep -P) validated in Phase A with grep -E fallback
**Decision**: Phase A checks grep -P support. If unavailable, scripts use grep -E.
**Why**: Git Bash grep usually supports -P but not guaranteed on all installations.

## Validation Protocol Used
- 5×5 scope validation: 25 independent sub-agents across 5 focus areas
- Per-phase implementation validation: independent sub-agent per phase
- All consensus issues fixed before proceeding
