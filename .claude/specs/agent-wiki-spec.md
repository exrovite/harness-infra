# Agent Wiki — Self-Evolving Knowledge System

## The Karpathy Pattern (what we're building)

Three layers:
1. **Raw Sources** (immutable) — `.agent-memory/`, session transcripts, `MEMORY.md`, progress notes. Never modified by the wiki system.
2. **The Wiki** (LLM-maintained) — `G:\AgentWiki\` Obsidian vault. The LLM creates, updates, cross-references, and maintains every page. No bash scripts do this work.
3. **The Schema** (co-evolved) — `G:\AgentWiki\_schema\SCHEMA.md`. Tells the LLM how the wiki is structured, what conventions to follow, what to do during ingest/query/lint.

Three operations:
1. **Ingest** — New session data arrives. The LLM reads it AND reads existing wiki pages. It decides what to create, what to update, what to cross-reference. A single session might touch 10-15 pages.
2. **Query** — At session start, the LLM reads index.md and relevant pages. When stuck, it searches across the whole vault. Good answers get filed back as new pages.
3. **Lint** — Periodic health check. The LLM finds contradictions, stale claims, orphan pages, missing cross-references, and gaps.

The key insight: **the LLM is the wiki editor**. Humans abandon wikis because maintenance grows faster than value. LLMs don't get bored, don't forget cross-references, and can touch 15 files in one pass.

## Vault Structure

```
G:\AgentWiki\
  _schema/
    SCHEMA.md                  <- Master schema (the LLM reads this first)
    conventions.md             <- Naming, formatting, frontmatter rules
  _templates/                  <- Obsidian template files
    bug.md
    pattern.md
    decision.md
    setup.md
    model.md
    session.md
    concept.md
    entity.md
  index.md                     <- Content catalog (updated every ingest)
  log.md                       <- Append-only chronological record

  harness-infra/               <- One folder per project
    bugs/
    patterns/
    decisions/
    setup/
    models/
    sessions/
    concepts/                  <- Synthesized topic pages
  pcw/
    ...same structure...
  [project-slug]/
    ...auto-created on first ingest...

  _global/                     <- Cross-project knowledge
    patterns/                  <- Patterns that apply everywhere
    bugs/                      <- Platform-level bugs (Windows, MSYS, etc.)
    concepts/                  <- Cross-cutting concepts
    project-map.md             <- Maps directory paths to vault slugs
```

## How Ingest Works (the LLM does this, not a bash script)

### Trigger
At session end, the harness calls a lightweight bash script that:
1. Checks if the session had >5 writes (skip trivial sessions)
2. Collects raw material: session summary, progress notes, MEMORY.md
3. Writes the raw material to a **dropbox file**: `G:\AgentWiki\_dropbox\{project-slug}_{timestamp}.md`
4. That's ALL the bash does. It collects and drops. It does NOT parse, extract, or write wiki pages.

### Processing (LLM-driven)
At the START of the next session (or triggered manually), the agent:
1. Reads `G:\AgentWiki\_schema\SCHEMA.md` to understand conventions
2. Reads `G:\AgentWiki\index.md` to know what pages exist
3. Checks `G:\AgentWiki\_dropbox\` for unprocessed files
4. For each dropbox file:
   a. Reads the raw session data
   b. Reads EXISTING wiki pages that might be affected
   c. Decides: create new pages? Update existing ones? Add cross-references?
   d. Writes/updates pages with proper frontmatter, tags, and wikilinks
   e. Updates `index.md` with any new pages
   f. Appends to `log.md`: `## [YYYY-MM-DD] ingest | {project} | {summary}`
   g. Moves processed file from `_dropbox/` to `_dropbox/_processed/`

### What the LLM decides during ingest
- **New bug discovered?** → Create `{project}/bugs/{slug}.md`, update related pattern pages
- **Existing bug fixed?** → Update the bug page status, add fix details, note the session
- **Pattern confirmed?** → Update existing pattern page (bump confidence), add new evidence
- **New pattern found?** → Create page with `confidence: low`, link to session
- **Decision made?** → Create decision page with context, alternatives, consequences
- **Contradiction found?** → Flag it explicitly, link both claims, note which is newer
- **Cross-project relevance?** → Create or update `_global/` page, link from both projects

## How Query Works

### At Session Start (added to CLAUDE.md startup protocol)
1. Read `G:\AgentWiki\index.md` — know what knowledge exists
2. Read `G:\AgentWiki\{project-slug}\` pages relevant to current task
3. Check `G:\AgentWiki\_dropbox\` — process any pending ingests
4. If stuck: search across entire vault with Grep

### During Work
- When hitting a bug: search `G:\AgentWiki\` for similar bugs
- When making a decision: check for prior decisions on same topic
- When discovering a pattern: check if it's already documented

### Filing Answers Back
Good query results (deep investigations, synthesized answers) get written as new concept pages in the vault. Queries compound into knowledge.

## How Lint Works

Triggered manually or on a schedule. The LLM:
1. Reads `index.md` and `log.md`
2. Scans for:
   - Pages with `confidence: low` that have been confirmed by later sessions → bump to `high`
   - Bug pages with `status: open` where fix was mentioned in later sessions → update to `fixed`
   - Orphan pages (no inbound wikilinks) → add links or mark for review
   - Contradictions between pages → create explicit contradiction notes
   - Concepts mentioned but lacking dedicated pages → flag as gaps
   - Pages not updated in >30 sessions → mark as potentially stale
3. Writes findings to `G:\AgentWiki\_lint\{date}-lint-report.md`
4. Optionally auto-fixes simple issues (confidence bumps, status updates)

## Page Format

Every page uses Obsidian-compatible YAML frontmatter.

### Frontmatter (required on every page)
```yaml
---
type: bug|pattern|decision|setup|model|session|concept|entity
project: {project-slug}           # or "_global" for cross-project
created: YYYY-MM-DD
updated: YYYY-MM-DD               # changes on every edit
confidence: high|medium|low        # for patterns
status: open|fixed|workaround      # for bugs
tags:
  - {type tag}
  - {project tag}
  - {topic tags...}
---
```

### Wikilinks
Use `[[page-name]]` for same-project links.
Use `[[project/category/page-name]]` for cross-project links.
Every page should have a `## See Also` section with relevant links.

### Index.md Format
```markdown
# Agent Wiki Index

Last ingested: {timestamp}
Total pages: {count}
Projects: {list}

## harness-infra
### Bugs
- [[harness-infra/bugs/msys-sed-path-bug]] — MSYS sed crashes on backslash paths (FIXED)
- ...
### Patterns
- [[harness-infra/patterns/hooks-read-stdin]] — PostToolUse hooks read STDIN not env vars (HIGH)
- ...
### Decisions
- ...

## pcw
- ...

## _global
- ...
```

### Log.md Format
```markdown
# Agent Wiki Log

## [2026-04-07] ingest | harness-infra | Session hardening + watcher fix
- Created: harness-infra/bugs/watcher-auto-release.md
- Updated: harness-infra/patterns/hooks-read-stdin.md (added STDIN example)
- Created: harness-infra/decisions/remove-watcher-auto-release.md
- Updated: index.md (+3 pages)

## [2026-04-07] ingest | pcw | Server startup debugging
- Created: pcw/setup/server-startup.md
- Updated: _global/patterns/bare-pytest-fix.md (added PCW context)
```

## Tags Strategy

### Category Tags (every page gets one)
`#bug` `#pattern` `#decision` `#setup` `#model` `#session` `#concept`

### Project Tags (every page gets one)
`#project/harness-infra` `#project/pcw` `#project/ai-producer` etc.

### Topic Tags (cross-cutting)
`#bash` `#hooks` `#watcher` `#msys` `#windows` `#memory` `#testing`
`#gemma` `#claude` `#codex` (model-specific)

### Status Tags (for bugs)
`#fixed` `#open` `#workaround`

### Confidence Tags (for patterns)
`#confidence/high` `#confidence/medium` `#confidence/low`

## Obsidian Integration

### Plugins to Enable
- **Dataview** — query pages by frontmatter
  - All open bugs: `TABLE status, project FROM #bug WHERE status = "open"`
  - Recent sessions: `TABLE date FROM #session SORT date DESC LIMIT 10`
  - Low-confidence patterns: `TABLE confidence FROM #pattern WHERE confidence = "low"`
- **Templates** — use `_templates/` for consistent page creation
- **Graph view** — built-in, shows wikilink connections
- **Tag pane** — built-in, browse by tag hierarchy

### Vault Settings
- Template folder: `_templates/`
- Default new note location: root

## Implementation: What Gets Built

### 1. wiki-dropbox.sh (bash — lightweight collector)
The ONLY bash script. Runs at session end from `on-session-end.sh`.
- Collects: session summary, progress notes, MEMORY.md
- Writes to: `G:\AgentWiki\_dropbox\{slug}_{timestamp}.md`
- Does NOT parse, extract, categorize, or write wiki pages
- Non-blocking: if it fails, session ends normally

### 2. SCHEMA.md (the LLM's instructions)
Lives at `G:\AgentWiki\_schema\SCHEMA.md`. Tells any agent:
- How to process dropbox files
- What frontmatter to use
- How to update index.md and log.md
- When to create vs update pages
- How to handle cross-references and contradictions
- Naming conventions for files and slugs

### 3. Startup protocol update (CLAUDE.md)
Add wiki query step to session startup:
- Read `G:\AgentWiki\index.md`
- Check `_dropbox/` for pending ingests
- Read project-relevant pages

### 4. Templates (Obsidian)
6 template files in `_templates/` with frontmatter skeletons.

### 5. Initial backfill
Manually (LLM-driven) ingest the existing MEMORY.md files from top projects to seed the vault with initial knowledge.

## What This Is NOT

- NOT a bash keyword scanner dumping raw excerpts
- NOT an automatic extraction pipeline
- NOT a write-once-never-update dump
- NOT a replacement for `.agent-memory/` (that's the raw source layer)
- NOT a replacement for `MEMORY.md` (that's per-session auto-memory)

## Design Principles

1. **The LLM is the editor** — it reads, thinks, decides, writes. No dumb extraction.
2. **One vault, all projects** — search works across everything.
3. **Frontmatter first** — structured YAML for Dataview queries.
4. **Self-evolving** — pages get updated, not just created. Confidence grows. Contradictions get flagged.
5. **Gentle** — dropbox collection never blocks. Ingest is best-effort.
6. **Human-browsable** — open Obsidian, see everything, use graph view.
7. **Agent-queryable** — agents read markdown directly, no API needed.
8. **Compounding** — each session adds AND refines. Queries become pages. Links strengthen.
