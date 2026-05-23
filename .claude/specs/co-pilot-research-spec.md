# Product Spec: Co-Pilot Claude Research Document

## What
A technical research document that gives a developer everything they need to build a "co-pilot" system — a second process that monitors a running Claude Code CLI session, detects when the agent drifts from key instructions, and injects corrective prompts automatically.

## Why
The human operator currently babysits the terminal, watching for the agent to forget specific instructions. When drift is spotted, the human types a correction and the agent course-corrects. This works but doesn't scale — the human can't watch 24/7 and shouldn't have to.

## Deliverable
A single research document (`docs/co-pilot-claude/research-findings.md`) containing:

1. **Problem statement** — what drift looks like and why manual correction doesn't scale
2. **Technical feasibility** — can you inject text into a running Claude Code session? What works, what doesn't
3. **Architecture patterns** — at least 4 viable approaches with:
   - How it works (architecture diagram / pseudocode)
   - Pros and cons
   - Setup complexity
   - Platform support (Windows, Linux, macOS)
4. **Comparison matrix** — side-by-side table of all patterns
5. **Recommended phased approach** — what to build first, second, third
6. **CLI reference** — exact flags and commands needed
7. **Open questions** — what still needs testing/validation
8. **All sources cited** — URLs to official docs, GitHub issues, third-party guides

## What This Is NOT
- Not a build task — no scripts, no code changes, no harness modifications
- Not a spec for a specific implementation — it's research to inform a future build decision

## Evaluation Criteria
- EC1: Document exists at `docs/co-pilot-claude/research-findings.md`
- EC2: At least 4 architecture patterns documented
- EC3: Each pattern has pros, cons, and setup complexity
- EC4: Comparison matrix present
- EC5: Phased recommendation present
- EC6: CLI flags and commands are accurate
- EC7: All sources have URLs
- EC8: Committed to git
