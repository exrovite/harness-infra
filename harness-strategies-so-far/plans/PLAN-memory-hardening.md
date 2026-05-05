# Plan: Memory System Hardening

## Problem
Current hooks use `jq` to edit JSON files in-place and `printf` with string interpolation to write structured files. This is fragile:
- jq in-place edit can corrupt the entire file on bad input
- printf with untested variables can produce malformed output
- No change detection — rewrites even when nothing changed
- No recovery — one bad write and data is lost

## Research Findings (proven patterns)
1. **Append-only JSONL** — one JSON object per line, never edit previous lines (claude-mem, episodic-memory)
2. **Atomic writes** — write to temp file, then `mv` (prevents partial writes)
3. **Hash-based change detection** — only write if content actually changed (Oh-My-OpenAgent)
4. **Shard pattern** — lightweight index + detail in separate files (Clawhip)
5. **Write-gating** — only store if data is different from last entry (total-recall)
6. **Claude Code native auto-memory** — let Claude handle semantic knowledge via built-in system

## Changes

### Change 1: Replace jq JSON edits with append-only JSONL

**Files affected**: `post-write-check.sh`, `on-session-end.sh`

**Current (fragile)**:
```bash
jq --arg ts "$TIMESTAMP" '.activities += [{"timestamp":$ts}]' file.json > file.json.tmp && mv file.json.tmp file.json
```

**New (robust)**:
```bash
# Append one line. Previous lines untouched. Can't corrupt.
printf '{"timestamp":"%s","phase":"%s","writes":%s}\n' "$TIMESTAMP" "$PHASE" "$WRITES" >> activity.jsonl
```

Files changed:
- `recent-activity.json` → `recent-activity.jsonl` (append-only log)
- Remove all jq WRITE operations from hooks (jq READ is fine — reading JSON is safe)

### Change 2: Atomic writes for state files

**Files affected**: `post-write-check.sh`, `on-session-end.sh`, `run-harness.sh`

**Current (fragile)**:
```bash
printf '{"phase":"BUILD"}' > current-phase.json  # partial write if interrupted
```

**New (robust)**:
```bash
# Write to temp, then atomic mv
printf '{"phase":"BUILD"}\n' > current-phase.json.tmp
mv current-phase.json.tmp current-phase.json
```

Apply to: `current-phase.json`, `session-context.md`, `active-tasks.json`, `MEMORY_MANIFEST.json`

### Change 3: Hash-based change detection for session-context.md

**Files affected**: `post-write-check.sh`

**Current**: Rewrites session-context.md on EVERY Write/Edit (wasteful, risks corruption)

**New**: 
```bash
# Generate new content into variable
NEW_CONTENT=$(generate_session_context)
# Hash it
NEW_HASH=$(printf "%s" "$NEW_CONTENT" | sha256sum | cut -d' ' -f1)
# Compare with stored hash
OLD_HASH=$(cat "${STATE_DIR}/session-context.hash" 2>/dev/null)
# Only write if changed
if [ "$NEW_HASH" != "$OLD_HASH" ]; then
  printf "%s" "$NEW_CONTENT" > "${STATE_DIR}/session-context.md.tmp"
  mv "${STATE_DIR}/session-context.md.tmp" "${STATE_DIR}/session-context.md"
  printf "%s" "$NEW_HASH" > "${STATE_DIR}/session-context.hash"
fi
```

### Change 4: Simplify MEMORY_MANIFEST.json updates

**Files affected**: `on-session-end.sh`

**Current**: jq reads, modifies, and rewrites entire MANIFEST

**New**: Append session record to JSONL log, keep MANIFEST as read-only reference
```bash
# Append session end record to sessions log (append-only, can't corrupt MANIFEST)
printf '{"event":"session_end","timestamp":"%s","phase":"%s","sprint":%s}\n' \
  "$TIMESTAMP" "$PHASE" "$SPRINT" >> "${MEMORY_DIR}/sessions.jsonl"
```

Only update MANIFEST at explicit "maintenance" points (not on every session end).

### Change 5: Remove jq WRITE from hooks entirely

**Rule**: Hooks may use `jq` to READ JSON (safe). Hooks NEVER use `jq` to WRITE/MODIFY JSON. All writes use either:
- Append to JSONL (for logs/activity)
- Atomic temp+mv (for state files)
- Plain printf to new files (for one-time artifacts like session summaries)

## What stays the same
- jq for READING current-phase.json (safe — reads don't corrupt)
- printf for writing one-time markdown files (session summaries, feedback — written once, never edited)
- git diff for gathering data (read-only)
- Claude Code native auto-memory for semantic knowledge (officially supported, not our responsibility)

## Implementation order
1. Create atomic_write() helper function in a shared library script
2. Convert recent-activity.json → recent-activity.jsonl (append-only)
3. Add hash-based change detection to session-context.md writes
4. Wrap all state file writes with atomic temp+mv pattern
5. Remove jq WRITE operations from hooks (keep jq READ)
6. Add sessions.jsonl append-only log alongside MANIFEST
7. Test all hooks still work
