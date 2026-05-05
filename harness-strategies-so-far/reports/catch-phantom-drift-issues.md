# Catch Phantom Drift Issues — Must-Do Enforcement System

## What Is Phantom Drift?

An agent follows every process rule correctly — claims watchers, passes pre-flight, runs tests, advances through phases — but produces wrong output because it never absorbed the project's reference knowledge. It looks on-task but has silently drifted from what the work actually requires.

## The Incident That Exposed It

The Private Content Wizard (PCW) agent had access to five reference files containing 25 mistake guardrails, 23 proven techniques, a master process document, an experiment protocol, and model-specific research. The agent violated nearly every documented guardrail. When confronted, it admitted:

> "Every single mistake I made is already documented in the mistakes-catalog.md... I had all the information I needed to avoid these mistakes."

The harness enforced **process** (phases, contracts, TDD, watchers) but not **content knowledge**. The pre-flight MCQ tested "what is your task / step / file / constraint" — all watcher-slot awareness. None of it tested whether the agent understood the domain material that defines *how* to do the task correctly.

## Three Gaps The Must-Do System Closes

### Gap 1: No proof the agent read reference files

**Before:** CLAUDE.md said "read these files." Soft enforcement. The agent could skim, skip, or forget.

**After:** A **summary gate** blocks all code writes until the agent reads every file listed in `docs/must do/must-do.md` and writes a summary to `.claude/state/must-do-summary.md`. The summary must be ≥200 characters, must reference the files by name, and is **invalidated when the watcher step changes** — forcing a re-read on each new step.

**Implemented in:** `C:\Users\exrov\.claude\hooks\pre-write-gate.sh`

### Gap 2: Pre-flight tested process awareness, not domain knowledge

**Before:** Q1-Q4 asked about task, step, file, and constraints — all derived from the watcher slot. An agent could pass every pre-flight while knowing nothing about the actual reference material.

**After:** The pre-flight generates **one MCQ question per must-do file** (Q6, Q7, Q8... — variable count depending on how many files the project declares). Each question extracts a real line from the file and mixes it with lines from other must-do files as distractors. The agent must identify which statement belongs to which file — impossible without reading them.

**Implemented in:**
- `C:\Users\exrov\.claude\scripts\generate-pre-flight-challenge.sh` (question generation)
- `C:\Users\exrov\.claude\scripts\validate-pre-flight.sh` (answer validation)

### Gap 3: Knowledge decayed from context during work

**Before:** Even when the agent read reference files, the knowledge faded as context grew. By the time the agent was deep in implementation, the techniques and mistakes were gone from its working memory.

**After:** A **summary injection** appends the agent's own must-do summary (truncated to 800 chars) to every single prompt via `on-prompt-submit.sh`. The agent sees `[MUST-DO ACTIVE] ...` on every turn. The knowledge stays present throughout the session, not just at a gate.

**Implemented in:** `C:\Users\exrov\.claude\hooks\on-prompt-submit.sh`

## How It Works End-to-End

1. Project creator puts a `docs/must do/must-do.md` file listing reference file paths (one per line)
2. Agent starts working, tries to write code
3. **Summary gate fires** — blocks the write, tells agent to read the listed files and write a summary
4. Agent reads files, writes summary to `.claude/state/must-do-summary.md`
5. Gate checks: summary exists, ≥200 chars, mentions file names, matches current step → allows write
6. **Pre-flight fires** on next write — Q6+ test recall of each must-do file with cross-file distractors
7. Agent passes pre-flight, writes code
8. **On every subsequent prompt**, the agent sees its own summary injected into the harness state line
9. When the watcher step advances, summary is invalidated → agent must re-read and re-summarize

No configuration beyond creating the folder. No LLM review. No human approval. Fully deterministic.

## Debugging & Observability

An **injection log** at `.claude/state/must-do-injection-log.jsonl` records every time the summary is shown to the agent:

```json
{"ts":"2026-04-07T11:25:28+01:00","step":"Step 3: Redo strategies...","chars":796}
```

Useful commands:
```bash
# How many times has the agent seen the must-do?
wc -l "your-project/.claude/state/must-do-injection-log.jsonl"

# Recent injections
tail -10 "your-project/.claude/state/must-do-injection-log.jsonl"

# Count per step
jq -s 'group_by(.step) | map({step: .[0].step, count: length})' \
  "your-project/.claude/state/must-do-injection-log.jsonl"

# What the agent actually sees (the 800-char truncation)
head -c 800 "your-project/.claude/state/must-do-summary.md" | tr '\n' ' '

# Is the summary stale?
cat "your-project/.claude/state/must-do-summary-step.txt"
```

## Setting Up Must-Do For a New Project

Create one folder and one file:

```
your-project/
  docs/
    must do/
      must-do.md       ← file paths, one per line
```

Contents of `must-do.md`:
```
G:\Your Project\docs\source-of-truth.md
G:\Your Project\references\mistakes-catalog.md
G:\Your Project\references\technique-toolkit.md
```

That's it. The hooks detect the folder automatically. No folder = no enforcement.

Alternative locations: `docs/must-do/` or `.claude/must-do/`.

## Result

After deployment, the PCW agent:
- Wrote a 17-line summary covering all 5 reference files with specific, task-relevant detail
- Sees its summary on every prompt (13+ injections logged in the first 6 minutes)
- Answers domain-knowledge MCQ questions on every write
- Is now producing work that follows the documented techniques and avoids the cataloged mistakes

The developer confirmed: *"the agent is now doing beautiful work."*

## Files Modified

| File | What Changed |
|------|-------------|
| `~/.claude/hooks/pre-write-gate.sh` | Added must-do summary gate between contract gate and write counter |
| `~/.claude/scripts/generate-pre-flight-challenge.sh` | Added dynamic Q6+ MCQ generation, one per must-do file |
| `~/.claude/scripts/validate-pre-flight.sh` | Added variable Q6+ validation loop |
| `~/.claude/hooks/on-prompt-submit.sh` | Added summary injection + JSONL injection logging |
