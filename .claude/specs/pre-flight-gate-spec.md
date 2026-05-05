# Product Spec: Pre-Flight Gate System

## Problem
Agents bluff through the watcher system. They fill in the minimum to pass, then drift during implementation. The watcher enforces process (rhythm) but not comprehension (knowledge). Agents can write vague plans and coast.

## Solution: Two-System Pipeline

### System 1: Watcher + Cron (enhanced, existing)
The watcher slot, filled when the task is fresh and comprehension is highest, becomes the **ground truth anchor** for the entire task.

**Enhancements to existing watcher slot format:**
- Add `## SCOPE` — files/directories this task touches
- Add `## OUT OF SCOPE` — explicit boundaries (what this task is NOT)
- Add `## MISTAKES TO AVOID` — known pitfalls, prior failures

**Cron stays at 3 minutes** — catches agents that go quiet (not writing, stuck in read loops, analysis paralysis). The pre-flight gate cannot fire when no writes happen, so the cron remains the safety net for inactivity.

### System 2: Pre-Flight Gate (new)
A PreToolUse hook on Write|Edit that blocks every write until the agent passes a multiple-choice quiz derived from its own watcher slot.

**Core mechanism:**
1. Agent tries to Write/Edit any file
2. Hook checks: does a valid response file exist with correct answers?
3. If no/wrong: BLOCK. Generate challenge questions to `.claude/pre-flight/challenge.md`
4. Agent reads challenge, writes answers to `.claude/pre-flight/response.md`
5. Hook validates answers (deterministic, exact match on A/B/C/D)
6. If correct: Write proceeds. Response file is **deleted** (consumed on use)
7. Next Write/Edit requires fresh answers

**The pre-flight directory is exempted from the gate** (writes to `.claude/pre-flight/` don't trigger it).

### Multiple-Choice Questions (4 questions per challenge)

**Q1 — Ground Truth**: "What is your current task?"
- Correct answer: from watcher slot `**Task**:` line
- Distractors: 3 random entries from `distractor-pool/tasks.txt`

**Q2 — Protocol**: "Which step are you currently on?"
- Correct answer: first unchecked `- [ ]` item from watcher checklist
- Distractors: completed steps, later steps, or random from `distractor-pool/steps.txt`

**Q3 — Changes Planned**: "What file should this edit target?"
- Correct answer: the actual file from the Write/Edit tool call parameters
- Distractors: random files from project (via glob) or `distractor-pool/files.txt`

**Q4 — Mistakes to Avoid**: "What is out of scope for this task?"
- Correct answer: from watcher slot `## OUT OF SCOPE` or `## MISTAKES TO AVOID`
- If "none": correct answer is "None identified", distractors are fabricated constraints
- Distractors: from `distractor-pool/constraints.txt`

### Distractor Pool (rotating library)
Location: `C:\Users\exrov\.openclaw\distractor-pool\`

Four text files, one entry per line, ~100+ entries each:
- `tasks.txt` — plausible task descriptions
- `steps.txt` — plausible step descriptions
- `files.txt` — plausible file paths
- `constraints.txt` — plausible constraints/mistakes

Selection: `shuf -n 3` per question. Correct answer at random position. No stored answer key — correct answers re-derived from watcher slot at validation time.

### Question Advancement
Questions regenerate when:
- A checklist item is ticked off (new "current step")
- The challenge is consumed after correct answers (new random distractors)
- The watcher slot is updated

The agent sees different questions on every Write/Edit — cannot memorize patterns.

## Tool Access
| Tool | Gate |
|------|------|
| Read, Bash, Grep, Glob | Always open |
| Write/Edit to `.claude/pre-flight/*` | Always open (exempted) |
| Write/Edit to anything else | Blocked until MCQ passed |

## System Interaction Flow
```
Task arrives -> Agent reads/explores (open) -> Claims watcher (ground truth)
-> Starts cron (3-min inactivity net) -> Tries Write/Edit -> MCQ gate fires
-> Must answer correctly -> Write proceeds -> Response consumed -> Repeat
```

## What Each System Catches
| Failure | Watcher+Cron | Pre-Flight Gate |
|---------|-------------|-----------------|
| No task understanding | Captures truth early | Validates against it |
| Drift while coding | Soft 3-min nudge | Hard block every write |
| Gold-plating / scope creep | Out-of-scope field | Scope check on files |
| Skipping steps | Checklist in slot | Must reference current step |
| Going quiet / stuck | Cron catches this | Cannot fire (no writes) |
| Bluffing the gate | N/A | MCQ validated + rotated |

## Non-Goals
- Modifying the existing watcher claiming flow
- Changing the 3-minute cron interval
- Replacing the watcher — the gate augments it
- LLM-based validation — everything is Layer 2 deterministic
