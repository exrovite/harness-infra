# Ongoing Project Mode — Analysis Procedure

## Data Source Map

Read these sources in priority order. Stop when you have enough failure patterns to make 5-10 suggestions.

### Priority 0: Auto-Memory (START HERE)

The auto-memory directory is the single richest source of distilled failure patterns. It contains curated lessons from ALL previous sessions, not raw logs.

**Location**: `~/.claude/projects/{project-hash}/memory/`

The project hash is derived from the project's root path. To find the correct directory:
1. List directories in `~/.claude/projects/`
2. Match by reading the `MEMORY.md` inside each — it will reference the project name or path
3. Alternatively, check the project's `.claude/` directory for symlinks or references

**Files to read** (all of them, in this order):
1. `MEMORY.md` — the primary auto-memory file. Always loaded into context. Contains condensed patterns, bugs fixed, key decisions, project structure. This is the most token-efficient source of failure history.
2. Any additional `.md` files in the `memory/` directory — these are topic-specific memory files (e.g., `debugging.md`, `patterns.md`, `api-conventions.md`). Read them ALL.

**What to extract**:
- "Key Patterns" sections — recurring issues and their solutions
- "Bugs Found and Fixed" — specific issues encountered across sessions
- Any sections with "gotcha", "pitfall", "mistake", "DO NOT", "NEVER", "ALWAYS" — these are hard-won lessons
- Project structure notes — tells you what files exist and their purpose
- Sprint/construction history — what was built, what broke during building

**Why auto-memory is Priority 0**: Every other data source (session logs, progress notes) requires reading multiple large files to reconstruct what happened. Auto-memory has already done that distillation. It is the compressed, curated output of many sessions of work. Start here, then go to other sources only if you need more detail on specific incidents.

### Priority 1: Direct Failure Evidence

| Source | Path | What to Extract |
|--------|------|-----------------|
| Session summaries | `.agent-memory/episodic/sessions/*.md` | "What went wrong", "bugs found", "stuck points" |
| Progress notes | `.claude/state/progress-notes.md` | "Bugs Found & Fixed", design decisions, failures |
| Phase feedback | `.claude/state/phase-feedback.md` | Validation failures (if exists) |
| Evidence verdicts | `.claude/state/evidence-verdict.json` | Failed verification phases |
| Strategy loop state | `.claude/state/strategy-loop-state.json` | Repeated failure patterns |

### Priority 2: Contextual Evidence

| Source | Path | What to Extract |
|--------|------|-----------------|
| Decisions log | `.agent-memory/episodic/decisions/*.md` | Decisions made and why |
| Knowledge gaps | `.agent-memory/meta/knowledge-gaps.json` | Known unknowns |
| Sprint contracts | `.claude/contracts/sprint-*-contract.md` | Scope agreed vs. scope delivered |
| Test evidence | `.claude/state/bash-failure-log.jsonl` | Command failures with fingerprints |

### Priority 3: Supplementary

| Source | Path | What to Extract |
|--------|------|-----------------|
| Confidence levels | `.agent-memory/meta/confidence.json` | Low-confidence areas |
| Backlog | `.agent-memory/prospective/backlog.json` | Known issues not yet addressed |
| Wiki pages | `G:\AgentWiki\{project-slug}\` | Accumulated project knowledge |

## Failure Pattern Extraction

From all sources, extract these failure categories:

### Category 1: Repeated Mistakes
Same error or wrong approach appearing in multiple sessions.
- **Signal**: Same file paths appearing in "bugs found" sections across sessions
- **Must-do fix**: Link to the file that documents the correct approach or the gotcha

### Category 2: Validation Failures
Phase feedback or evidence verdicts with FAIL status.
- **Signal**: `phase-feedback.md` containing "FAIL", or `evidence-verdict.json` with findings
- **Must-do fix**: Link to the process doc or checklist that would have prevented the failure

### Category 3: Strategy Loop Triggers
The agent was blocked for repeating the same failing approach.
- **Signal**: `strategy-loop-state.json` showing nudge_count > 0 or blocked=true
- **Must-do fix**: Link to debugging docs or known-fixes for that error class

### Category 4: Knowledge Gaps
Explicitly recorded gaps in understanding.
- **Signal**: `knowledge-gaps.json` entries, or "STUCK" markers in session summaries
- **Must-do fix**: Link to documentation that fills the gap, or create a new reference doc

### Category 5: Scope Drift
Sprint contracts showing work that expanded beyond agreed scope.
- **Signal**: Contract scope sections vs. actual files modified in sessions
- **Must-do fix**: Link to architecture docs that clarify boundaries

## Cross-Referencing with Current Task

After extracting patterns, match them to the CURRENT task:

1. Read the current task from `.claude/state/active-instructions.md` or the user's request
2. For each failure pattern, ask: "Is the agent about to do work that could trigger this same failure?"
3. Only suggest must-do entries for patterns relevant to the CURRENT task
4. If a pattern is irrelevant (e.g., a past DB failure but current task is frontend), skip it

## Suggesting Must-Do Entries

For each relevant failure pattern:

```
## Suggestion N: [file path or new file name]

**Why**: [description of past failure and how this file prevents it]

**Failure evidence**:
- Session [date]: [what went wrong]
- Progress notes: [specific bug or issue]
- [other sources as applicable]

**Action**: [Link existing file] OR [Create new file with draft below]

Draft (if new file):
[concise skeleton content]
```

## Generating New File Suggestions

When no existing file addresses a failure pattern, propose creating one:

| Failure Pattern | File to Create | Content Focus |
|----------------|---------------|---------------|
| Repeated MSYS/Windows bugs | `docs/platform-gotchas.md` | Platform-specific issues encountered |
| Tests keep failing for same reason | `docs/testing-conventions.md` | Test patterns, runner config, common pitfalls |
| Agent keeps misinterpreting architecture | `docs/architecture.md` | Clear module boundaries and data flow |
| Config errors recur | `docs/configuration.md` | All config files, env vars, their purpose |
| Agent drifts from agreed scope | `docs/scope-boundaries.md` | What's in scope, what's not, for current sprint |

Keep new file suggestions minimal — only create what the evidence demands.

## Output

Present all suggestions grouped by failure category. Include the failure evidence so the user understands WHY each must-do entry matters. Ask for approval before writing anything.
