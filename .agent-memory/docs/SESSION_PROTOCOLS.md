# Session Protocols

## Startup Protocol
1. Read `MEMORY_MANIFEST.json` — system overview
2. Read `core/identity.md` — who you are (7 expert domains)
3. Read `core/mission.md` — what you're building (three-layer control)
4. Read `core/expert-domains.md` — your diagnostic lenses
5. Read `core/model-profiles.md` — failure taxonomies per model
6. Read `core/operating-procedure.md` — the enhanced harness protocol
7. Read `working/session-context.md` — where you left off
8. Read `working/active-tasks.json` — what needs doing
9. Read `procedural/scripts/SCRIPT_REGISTRY.json` — what scripts exist

## During Session
- Update `working/session-context.md` every 10-15 minutes
- Check `procedural/scripts/SCRIPT_REGISTRY.json` before creating new scripts
- Log important decisions to `episodic/decisions/[topic]-decision.md`
- Register new scripts immediately

## Decision Logging
When making a significant decision:
```markdown
# Decision: [Topic]
**Date**: YYYY-MM-DD
**Context**: What situation prompted this decision
**Options Considered**: What alternatives were evaluated
**Decision**: What was chosen and why
**Consequences**: What this means for future work
**Layer**: Which enforcement layer this affects
```

## Session End (NEVER SKIP)
1. Write session summary to `episodic/sessions/YYYY-MM-DD_HH-MM-SS.md`
2. Update `MEMORY_MANIFEST.json` (last_accessed, sessions_count)
3. Update `working/session-context.md` with context for next session
4. Update `working/recent-activity.json`

## Script Creation Protocol
1. Check `SCRIPT_REGISTRY.json` — does it already exist?
2. If creating new: write script, then IMMEDIATELY register in `SCRIPT_REGISTRY.json`
3. Include: id, name, file_path, layer, purpose, input, output, dependencies, usage_example, tags
4. Update `MEMORY_MANIFEST.json` scripts_count
