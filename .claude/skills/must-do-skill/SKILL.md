---
name: must-do-skill
description: "Generate must-do.md content suggestions for agent tasks. Use when setting up must-do enforcement for a project, when a user asks what files an agent should be required to read, or when configuring Layer 4 of the enforcement stack. Two modes: (1) New project - analyze task + codebase, suggest existing files to link and new files to create with draft content. (2) Ongoing project - mine agent memory, session history, failure logs, and evidence verdicts to suggest must-do entries that address past mistakes and recurring problems. Trigger: /must-do-skill, suggest must-do files, what should I add to must-do, set up must-do for this task, configure must-do."
---

# Must-Do Generator

Generate must-do.md file suggestions that feed into the enforcement stack's Layer 4 (Must-Do Summary Gate). The goal: ensure agents read the right files before writing code.

## Mode Selection

Detect which mode applies:

1. **Check for auto-memory**: Does `~/.claude/projects/*/memory/MEMORY.md` exist for this project? This is the richest source.
2. **Check for agent memory**: Does `.agent-memory/` exist with session history?
3. **Check for progress history**: Does `.claude/state/progress-notes.md` exist with substantive content?

If 2+ of these exist and contain real data (not placeholders), use **Ongoing Project** mode. Otherwise, use **New Project** mode.

---

## Mode 1: New Project

See [references/new-project.md](references/new-project.md) for the full analysis procedure.

### Workflow

1. **Gather task context** — Read the user's task description, any existing spec or contract files, CLAUDE.md
2. **Scan codebase structure** — Map file tree, identify key directories, existing docs, config files, test structure
3. **Suggest existing files** — Based on task type, identify which files an agent MUST read to do the work correctly
4. **Identify gaps** — Determine what files don't exist but should (architecture docs, testing conventions, env setup, failure mode notes)
5. **Draft new files** — For each gap, produce draft content for user review
6. **Output suggestions** — Present both categories (existing + new) with justification for each

### Output Format

Present suggestions as a numbered list with:
- File path
- Why it's essential (one sentence)
- For new files: draft content or outline

User reviews, approves, discards, or edits. Then write the approved files and create `docs/must do/must-do.md` listing the file paths.

---

## Mode 2: Ongoing Project

See [references/ongoing-project.md](references/ongoing-project.md) for the full analysis procedure and data source map.

### Workflow

1. **Mine failure history** — Read session summaries, progress notes, phase feedback, strategy loop state, evidence verdicts
2. **Extract patterns** — Identify: repeated mistakes, failed validations, recurring bugs, phases that consistently fail, knowledge gaps
3. **Cross-reference with current task** — Match failure patterns to what the agent is about to do
4. **Suggest must-do entries** — Files, patterns, or documentation that would have prevented each failure class
5. **Draft new files if needed** — If no existing file addresses a failure pattern, propose a new one
6. **Output suggestions** — Same format as Mode 1, with added context: "This would have prevented [specific past failure]"

### Data Sources

Priority order for mining:
1. Auto-memory `~/.claude/projects/*/memory/MEMORY.md` — curated lessons, patterns, bugs, gotchas from ALL sessions (START HERE)
2. `.agent-memory/episodic/sessions/` — session summaries with what went wrong
3. `.claude/state/progress-notes.md` — accumulated decisions and bugs
4. `.agent-memory/meta/knowledge-gaps.json` — known unknowns
5. `.agent-memory/episodic/decisions/` — past decisions and their rationale
6. Phase feedback and evidence verdicts — validation failures
7. Sprint contracts — scope that was agreed vs. what drifted

### Output Format

Same as Mode 1, but each suggestion includes a **failure evidence** section citing specific past incidents. This makes the case for why each must-do entry matters.

---

## Common Final Steps

After user approves suggestions:

1. Write any new files (drafts the user approved)
2. Create `docs/must do/` directory if it doesn't exist
3. Write `docs/must do/must-do.md` with one file path per line
4. Verify the must-do summary gate (Layer 4) will activate on next session
