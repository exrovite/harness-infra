# Harness Bug Catalogue: Bugs Discovered While Building Deterministic Agent Control

**Date**: 2026-04-08
**Purpose**: Document every bug that arose in the Claude Code harness so another agent system (e.g. Codex via OMX) can be audited for analogous issues.
**Audience**: Any agent tasked with reviewing a hook/enforcement/orchestration system for potential failure modes.

---

## How To Use This Report

Each bug entry contains:
- **What broke** — the visible symptom
- **Root cause** — the underlying technical reason
- **Pattern** — the abstract failure class (use this to search for analogues in other systems)
- **Fix** — what we did
- **Where to look** — where an analogous bug would hide in another system

---

## Bug 1: Hook Data Channel Mismatch

**What broke**: PostToolUse hooks received empty strings for all tool input fields. The `unverified-writes.jsonl` file was never created despite hundreds of writes. Every hook that needed to know WHAT was written silently got nothing.

**Root cause**: Hooks were reading `TOOL_INPUT_FILE_PATH` as an environment variable. Claude Code does not pass tool context via environment variables — it sends a JSON object on STDIN. The hooks were reading from the wrong data channel entirely.

**Pattern**: **Assumed data interface**. The hook system documentation was ambiguous about how data reaches hooks. We assumed env vars (the common shell pattern). The actual mechanism was STDIN JSON. The mismatch was silent — no error, just empty strings.

**Fix**: `HOOK_INPUT=$(cat)` at the top of every hook, then `jq` extraction from the JSON. PreToolUse hooks use `INPUT=$(cat)` then `jq -r '.tool_input.file_path'`.

**Where to look**: In any hook/plugin system, verify HOW the orchestrator passes context to hooks. Check: Does the hook receive data via env vars, STDIN, arguments, a temp file, or a shared state file? Deploy a test hook that dumps everything (`env`, `cat /dev/stdin`, `echo "$@"`) and confirm which channel actually carries data. If the documentation says one thing but the runtime does another, every downstream hook is silently broken.

---

## Bug 2: Sub-Agent Lifecycle Triggers Parent Hooks

**What broke**: Every time the Agent tool spawned a sub-agent (e.g. a verifier), the PARENT agent's watcher was released. The agent would claim a watcher, spawn a verifier, and find its watcher gone when the verifier finished.

**Root cause**: Sub-agents trigger the Stop hook when they complete. The `on-session-end.sh` Stop hook released all watchers claimed by the current project. There was no distinction between "main session ending" and "sub-agent finishing". The hook ran in the parent's context, so it released the parent's watchers.

**Pattern**: **Shared lifecycle events across isolation boundaries**. The Stop event was meant for session teardown but fired for every nested agent completion. Any cleanup logic in a Stop/Shutdown hook will accidentally destroy parent state if sub-agents trigger the same event.

**Fix**: Removed all watcher auto-release from `on-session-end.sh`. Stale watcher cleanup happens only at session startup (`startup-recovery.sh`), scoped to watchers older than 4 hours.

**Where to look**: In any system with nested/parallel agents (OMX `$team`, worktree agents), check: Do child agents trigger the same lifecycle events as the parent? If a team agent finishes, does it fire a shutdown hook that clears shared state? Does the orchestrator distinguish between "agent finished a subtask" and "entire session ending"? If `.omx/state/` is shared, a finishing team member could corrupt the parent's state.

---

## Bug 3: Platform-Specific String Operation Crash

**What broke**: Watcher project path matching failed for ALL projects on Windows. Agents couldn't match their project to their watcher slot, so the system treated every agent as having no watcher. This cascaded: stale cleanup released the "unmatched" watcher, the agent was permanently locked out.

**Root cause**: `sed 's|\\|/|g'` (backslash-to-forward-slash normalization) crashes silently on MSYS/Git Bash with "unterminated s command". The backslash is an escape character in sed, and MSYS's sed handles it differently from GNU sed on Linux. The command produced no output instead of the normalized path.

**Pattern**: **Platform-specific shell command behavior**. A command that works on Linux/macOS silently fails or produces wrong output on Windows (Git Bash/MSYS). The failure is silent — no error code, just empty or wrong output. Downstream logic treats empty output as "no match" rather than "command failed".

**Fix**: Replaced `sed 's|\\|/|g'` with `tr '\\\\' '/'` in all 4 affected files. `tr` handles this reliably across platforms.

**Where to look**: In any system running on Windows (native or Git Bash), audit every `sed`, `awk`, `grep`, and path manipulation command. Specifically check: backslash handling in sed substitutions, path separators in comparisons, case sensitivity in path matching (`C:\Users` vs `c:/users`), and whether commands that work on Linux are tested on the actual deployment platform. OMX runs on Windows — check if its hook scripts or `.rules` files contain platform-sensitive shell commands.

---

## Bug 4: Lock-Free Concurrent State Modification

**What broke**: Multiple agents reading and writing `REGISTRY.json` simultaneously would clobber each other's claims. Agent A reads the file, Agent B reads the same file, both modify their copy, Agent A writes, Agent B writes — Agent A's changes are lost.

**Root cause**: No locking mechanism on the shared state file. JSON read-modify-write is not atomic. With parallel agents (or a parent + sub-agent), concurrent access was guaranteed.

**Pattern**: **Race condition on shared mutable state**. Any file that multiple agents read-modify-write without coordination will eventually lose data. The more agents, the more frequent the corruption.

**Fix**: Added `registry_lock()`, `registry_unlock()`, `registry_modify()` to `lib-helpers.sh`. Uses `mkdir` as an atomic lock (atomic on all platforms), 10-second timeout, stale lock detection.

**Where to look**: In any multi-agent system, identify ALL shared mutable files. For OMX: `.omx/state/`, `.omx/plans/`, any shared config. For `$team` mode with parallel worktree agents: Do they share any state files? Is there a merge step? If two team agents write to `.omx/logs/` simultaneously, is there a collision risk? Check if the orchestrator serializes state writes or if agents write directly.

---

## Bug 5: Circular Gate Dependency (Deadlock)

**What broke**: Agent could not start a new sprint after completing the previous one. Three gates formed a cycle:
1. Phase-feedback FAIL block prevented writing to `.claude/contracts/` (needed to create new sprint contract)
2. Contract gate blocked Agent tool (needed to spawn verifier to clear the FAIL)
3. Bash gate blocked the workaround path to contracts

The agent was completely stuck with no possible action to unblock itself.

**Root cause**: Each gate was correct in isolation. The phase-feedback gate correctly blocked writes during FAIL. The contract gate correctly required a contract before BUILD. The bash gate correctly prevented bypasses. But together, they created a state where no legal action could make progress. No gate designer considered the interaction with the other gates.

**Pattern**: **Emergent deadlock from independent safety gates**. Each gate is correct individually but the combination creates an unreachable state. This is the #1 risk in any multi-gate enforcement system. It's invisible during single-gate testing because each gate passes its own tests.

**Fix**: Added path exemptions to each gate for infrastructure paths (contracts, specs, state, watchers, agent-memory). The principle: gates block SOURCE CODE writes, never infrastructure writes needed to operate the harness itself.

**Where to look**: This is the most likely bug class in any enforcement system. For OMX: If the planning gate blocks implementation until PRD + test-spec exist, can the agent actually CREATE those files? If `.rules` files block certain commands, can the agent still run the commands needed to satisfy the planning gate? If `$ralph` requires a plan but the plan-creation step is blocked by a verification requirement, is there a cycle? Map every gate's block condition and every gate's exemptions. Then trace: starting from a clean state, can the agent reach every required state through legal actions only? If any state is unreachable, there's a deadlock.

---

## Bug 6: Stale Enforcement State With No Expiry

**What broke**: Agent was permanently blocked by a `phase-feedback.md` file containing FAIL from a bug that had already been fixed. The file was written during a previous session, the underlying issue was resolved, but the FAIL file persisted and continued blocking all source code writes indefinitely.

**Root cause**: The phase-feedback gate checked file EXISTENCE and CONTENT but not AGE. There was no expiry mechanism. A FAIL written hours ago was treated identically to a FAIL written seconds ago.

**Pattern**: **Immortal enforcement artifacts**. Any file-based gate that checks "does file X exist with content Y" without checking freshness will eventually block agents due to stale state from previous sessions, crashed sessions, or resolved issues.

**Fix**: `startup-recovery.sh` checks age of `phase-feedback.md` on session start. If older than 2 hours, it's auto-removed. The assumption: if you're starting a new session, stale failures from hours ago are no longer relevant.

**Where to look**: In any file-based enforcement system, identify every gate file and ask: What happens if this file is left over from a crashed session? From yesterday? From a completed sprint? For OMX: `.omx/state/` files, `.omx/plans/` files, any lock files or status files. If `$ralph` checks for a plan file's existence, what happens if a stale plan from a previous task is still there? Does the system distinguish "fresh and relevant" from "leftover and stale"?

---

## Bug 7: Phantom Process References

**What broke**: `REGISTRY.json` contained `cron_job_id` values pointing to cron jobs that no longer existed. When the system tried to reference or manage these crons, it failed or behaved unpredictably.

**Root cause**: CronCreate jobs are tied to the session process. When the session ends, the cron dies. But `REGISTRY.json` is persistent — it survived across sessions with the dead cron's ID still recorded. The next session saw an "active" watcher with a cron ID, but the cron was gone.

**Pattern**: **Persistent references to ephemeral resources**. Any time a persistent store (file, database) holds a reference to a runtime resource (process ID, cron job, socket, temp file), the reference will become stale when the runtime resource dies. If the system trusts the reference without validating the resource still exists, it breaks.

**Fix**: `startup-recovery.sh` clears `cron_job_id` and `cron_interval` from all active watchers on session startup. Watcher claims survive (they're persistent), but agents must re-create crons each session (they're ephemeral).

**Where to look**: In OMX: Does `$team` mode store process IDs for parallel agents? If a team agent crashes, does the orchestrator hold a stale PID? Does psmux track session IDs that could become invalid after a terminal crash? In `.omx/state/`, are there references to running processes, temp files, or network ports that might not survive a restart?

---

## Bug 8: Test Runner Platform Incompatibility

**What broke**: Test detection and execution scripts called `pytest.exe` directly. On Windows with Git Bash and a Python venv, `pytest.exe` crashes silently — no output, no error, just a non-zero exit code. All test verification appeared to show "no tests found" or "tests failed" when the runner itself was crashing.

**Root cause**: `pytest.exe` is a Windows executable wrapper. In Git Bash running inside a venv, the executable path resolution fails silently. `python -m pytest` works because it uses Python's module system instead of the OS executable lookup.

**Pattern**: **Silent tool failure on target platform**. A tool invocation that works in one environment (Linux, native Windows CMD) fails silently in the actual deployment environment (Git Bash on Windows). The failure looks like "no results" rather than "tool crashed", making it extremely hard to diagnose.

**Fix**: Replaced `pytest.exe` / `pytest` with `python -m pytest` in all 4 locations in the harness.

**Where to look**: In any system that invokes external tools, check: Is each tool invocation tested on the actual deployment platform? For OMX on Windows: Does `codex exec` work identically in Git Bash vs CMD vs PowerShell? Do `.rules` file commands assume a specific shell? If OMX spawns processes via `node`, does the Node process resolution work in Git Bash? Check every `exec`, `spawn`, or shell command for platform assumptions.

---

## Bug 9: Overly Aggressive Gate Scope

**What broke**: Phase gate blocked ALL file writes in PLAN and NEGOTIATE phases, including markdown files. Agents couldn't write specs (`.md`) during PLAN or contracts (`.md`) during NEGOTIATE — the exact phases where those files are supposed to be written.

**Root cause**: The phase gate was designed to prevent source code writes outside BUILD. But it used a blanket block on all file extensions. Markdown files aren't source code, but the gate didn't distinguish.

**Pattern**: **Gate blocks its own required workflow**. A safety gate intended to prevent one class of action (source code writes) accidentally prevents a different class of action (documentation writes) that is essential to the workflow the gate is supposed to protect.

**Fix**: Added `.md` file exemption to the phase gate for PLAN, NEGOTIATE, EVALUATE, and COMPLETE phases. BUILD phase still blocks everything that isn't in an exempt path.

**Where to look**: For every gate in any enforcement system, ask: What files/actions does the agent NEED to perform in the gated phase? Does the gate allow those actions? For OMX: If the planning gate blocks implementation until PRD exists, can the agent write the PRD? If `.rules` files restrict commands, can the agent still run the commands needed to create plans and test specs? Test each gate by walking through the intended workflow step by step.

---

## Bug 10: Diagnostic Void (Gate Blocks Without Explanation)

**What broke**: The must-do summary gate blocked writes but didn't say WHY. The agent saw "BLOCKED" with no indication of which specific check failed (missing summary? stale step? too short? missing file mentions?). The agent couldn't fix what it couldn't identify.

**Root cause**: The gate had multiple failure conditions but a single generic error message. Each condition (no summary, wrong step, too short, missing references) needed its own diagnostic output.

**Pattern**: **Opaque enforcement failure**. A gate with multiple check conditions reports a single generic failure. The agent (or human) cannot determine which condition failed, making remediation impossible without reading the gate's source code.

**Fix**: Each failure condition now outputs a specific error message with the relevant values (e.g., "Summary is 142 characters, minimum is 200" or "Step mismatch: expected 'Write tests' but summary references 'Deploy server'").

**Where to look**: In any enforcement system, trigger every gate's failure path and check: Does the error message tell the agent EXACTLY what failed and what to do about it? For OMX: If the planning gate rejects a plan, does it say why? If `$ralph` verification fails, does the agent know which test failed and what to fix? If `.rules` files block a command, does the error say which rule matched? Vague block messages cause agents to flail, retry randomly, or get stuck.

---

## Bug 11: jq Path Mismatch in JSON State

**What broke**: Session counter in `MEMORY_MANIFEST.json` was stuck at 1 forever. Every session read the counter, incremented it, and wrote it back — but it was reading from one JSON path and writing to another.

**Root cause**: The JSON schema had `sessions_count` at the top level, but the jq read query looked for `.quick_access.sessions_count`. The write query put it at `.sessions_count`. Read always got null (defaulting to 0), write always stored 1.

**Pattern**: **Schema drift between reader and writer**. When one piece of code writes a JSON field at path A and another reads from path B, the data is silently lost. Both operations succeed — no errors — but the system never sees its own previous state.

**Fix**: Dual-path read: `(.sessions_count // .quick_access.sessions_count // 0) | tonumber`. Also standardized on the top-level path for all future writes.

**Where to look**: In any system using JSON/TOML/YAML state files, check: Is every field read from the same path it's written to? For OMX: `.omx/state/` files, `hud-config.json`, `setup-scope.json`. If one OMX component writes `{"status": "done"}` and another reads `{"state": "done"}`, the same class of bug exists. Grep for every jq/JSON read and every jq/JSON write and verify path consistency.

---

## Summary: Abstract Failure Patterns

These 11 bugs reduce to 8 abstract patterns. Use these as a checklist when auditing any agent enforcement system:

| # | Pattern | Question to Ask |
|---|---------|-----------------|
| 1 | **Assumed data interface** | How does context actually reach hooks/plugins at runtime? Is it tested, not assumed? |
| 2 | **Shared lifecycle events across isolation boundaries** | Do child/sub agents trigger parent-level cleanup? |
| 3 | **Platform-specific shell behavior** | Are all shell commands tested on the actual deployment platform (Windows/Git Bash)? |
| 4 | **Race condition on shared mutable state** | Is every shared file protected against concurrent read-modify-write? |
| 5 | **Emergent deadlock from independent gates** | Can the agent reach every required state through legal actions only? |
| 6 | **Immortal enforcement artifacts** | Do gate files expire? What happens to leftover state from crashed sessions? |
| 7 | **Persistent references to ephemeral resources** | Do state files hold process IDs, cron IDs, or temp paths that die between sessions? |
| 8 | **Silent tool failure on target platform** | Does every external tool invocation work (not just "not error") on the actual OS+shell? |
| 9 | **Gate blocks its own required workflow** | Can the agent perform the actions required by the gated phase? |
| 10 | **Opaque enforcement failure** | Does every block message say exactly what failed and how to fix it? |
| 11 | **Schema drift between reader and writer** | Is every JSON/config field read from the same path it's written to? |

---

## Recommended Audit Procedure

For any new enforcement system (OMX, custom wrapper, hooks):

1. **Deploy a canary hook** — Log everything the system passes to hooks (env vars, stdin, args, working directory). Verify against documentation.
2. **Test with nested agents** — Spawn a sub-agent and check if parent state survives.
3. **Run on target platform** — Every shell command, on the actual OS and shell the system will use in production.
4. **Trace the deadlock graph** — For every gate, list what it blocks. For every blocked state, list what actions are available. Look for cycles.
5. **Kill mid-session** — Force-quit the orchestrator and restart. Check what state survives, what's stale, what's corrupt.
6. **Run parallel agents** — Two agents writing to shared state simultaneously. Check for data loss.
7. **Trigger every failure path** — Each gate should produce a specific, actionable error message.
8. **Grep for schema consistency** — Every JSON read path must match a write path.
