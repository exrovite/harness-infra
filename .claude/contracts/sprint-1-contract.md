# Sprint 1 Contract — Harness Hardening

## Scope
Fix and harden the agent harness infrastructure to prevent agent drift, bypass, and stale-state failures.

## Deliverables

1. **MSYS sed path bug fix** — Replace `sed 's|\\|/|g'` with `tr '\\\\' '/'` in all hooks that normalize paths (pre-write-gate.sh, pre-bash-gate.sh, on-session-end.sh, on-prompt-submit.sh)
2. **Bash bypass gate** — pre-bash-gate.sh blocks file-writing patterns via Bash with bootstrap exemptions for watcher/state paths
3. **Contract gate** — pre-write-gate.sh blocks BUILD writes without a sprint-specific contract, with NEGOTIATE instructions in block message
4. **Watcher lifecycle hardening** — Auto-release on session end, stale cleanup on startup (project-scoped only), improved block messages with timestamp instructions
5. **Stale feedback auto-clear** — startup-recovery.sh clears phase-feedback.md older than 2 hours
6. **Memory updates** — MEMORY.md updated with all fixes and patterns learned

## Verification Criteria
- All 4 sed replacements applied (no `sed 's|\\|/|g'` in any hook)
- Contract gate blocks BUILD without sprint-N contract, allows with it
- Stale cleanup in startup-recovery.sh is project-scoped
- pre-write-gate.sh does NOT do stale cleanup (removed)
- Block messages include timestamp command and stale threshold warning
- Bootstrap exemptions in pre-bash-gate.sh for .openclaw/watchers/, .claude/state/, .claude/pre-flight/, .agent-memory/

## Status
All deliverables implemented. Pending: MEMORY.md update.
