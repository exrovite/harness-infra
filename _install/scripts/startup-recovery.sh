#!/bin/bash
# startup-recovery.sh — Crash recovery
# Runs at harness start. Detects stale artifacts from crashed sessions.
# Cleans lockdir, kills orphaned dev server, writes fresh handoff.
#
# Usage: bash startup-recovery.sh
# Exit: 0 always

source "$HOME/.claude/scripts/lib-helpers.sh" 2>/dev/null

STATE_DIR="${HARNESS_STATE_DIR:-.claude/state}"

# Never AUTO-CREATE a .claude project root in a non-harness folder. Resolve to an EXISTING project root;
# if there is none (no HARNESS_STATE_DIR and no ancestor .claude below $HOME), do nothing. This is what
# stopped the harness minting .claude in scratch/new folders. Explicit setup goes through
# `bash init-project.sh` (or run-harness.sh, which calls init-project.sh first) — not this recovery path.
if [ -z "${HARNESS_STATE_DIR:-}" ] && type find_project_state_dir >/dev/null 2>&1; then
  _sr_root="$(find_project_state_dir "$(pwd -W 2>/dev/null || pwd)" 2>/dev/null)"
  if [ -n "$_sr_root" ]; then
    STATE_DIR="$_sr_root"
    # Export the resolved root so child scripts (write-handoff.sh, notify.sh, …) write into THIS
    # project's state instead of a cwd-relative .claude — otherwise running from a subdir mints a
    # nested .claude. Scoped to this process; does not leak to the parent.
    export HARNESS_STATE_DIR="$STATE_DIR"
  else
    exit 0
  fi
fi
LOCKDIR="${STATE_DIR}/harness.lockdir"

if [ ! -d "$STATE_DIR" ] && [ ! -f "${STATE_DIR}/../state/current-phase.json" ]; then
  printf "startup-recovery: No previous state found. Starting fresh.\n" >&2
  mkdir -p "$STATE_DIR" 2>/dev/null
  printf '{"phase": "PLAN", "sprint": 0, "iteration": 0}\n' > "${STATE_DIR}/current-phase.json"
  exit 0
fi

PHASE=$(jq -r '.phase // "UNKNOWN"' "${STATE_DIR}/current-phase.json" 2>/dev/null || printf "UNKNOWN")
SPRINT=$(jq -r '.sprint // 0' "${STATE_DIR}/current-phase.json" 2>/dev/null || printf "0")

printf "startup-recovery: Recovering from previous session (phase=%s, sprint=%s)\n" "$PHASE" "$SPRINT" >&2

# Clean up stale artifacts from crashed session
rm -f "${STATE_DIR}/phase-complete-marker.md" 2>/dev/null
rm -f "${STATE_DIR}/agent-blocked.md" 2>/dev/null

# Clear strategy loop breaker session-scoped data
# bash-failure-log.jsonl tracks within-session command failures for loop detection.
# Stale entries from previous sessions cause false nudges/blocks.
rm -f "${STATE_DIR}/bash-failure-log.jsonl" 2>/dev/null
rm -f "${STATE_DIR}/strategy-ack.md" 2>/dev/null
# Reset strategy-loop-state.json (nudge counter, blocked flag) — fresh session, fresh slate
if [ -f "${STATE_DIR}/strategy-loop-state.json" ]; then
  atomic_write '{"nudge_count":0,"last_nudge_ts":null,"last_output_fingerprint":"","last_churn_files":[],"blocked":false}' \
    "${STATE_DIR}/strategy-loop-state.json"
fi

# Clear stale phase-feedback.md from previous sessions.
# If the feedback file exists and is older than 2 hours, it's likely from a previous session
# or from a now-fixed harness bug (e.g. bare pytest crash). Re-validate instead of blocking forever.
PHASE_FB="${STATE_DIR}/phase-feedback.md"
if [ -f "$PHASE_FB" ]; then
  FB_AGE=0
  if stat --format='%Y' "$PHASE_FB" >/dev/null 2>&1; then
    FB_MTIME=$(stat --format='%Y' "$PHASE_FB" 2>/dev/null)
    NOW=$(date +%s)
    FB_AGE=$(( NOW - FB_MTIME ))
  fi
  if [ "$FB_AGE" -gt 1800 ]; then
    printf "startup-recovery: Clearing stale phase-feedback.md (age: %ss, threshold: 30min). Agent can re-trigger validation.\n" "$FB_AGE" >&2
    rm -f "$PHASE_FB" 2>/dev/null
  else
    printf "startup-recovery: phase-feedback.md exists (age: %ss). Agent must address it.\n" "$FB_AGE" >&2
  fi
fi

# Clear stale cron-paused.json (>2 hours old) — same pattern as phase-feedback.md
CRON_PAUSE="${STATE_DIR}/cron-paused.json"
if [ -f "$CRON_PAUSE" ]; then
  CP_AGE=0
  if stat --format='%Y' "$CRON_PAUSE" >/dev/null 2>&1; then
    CP_MTIME=$(stat --format='%Y' "$CRON_PAUSE" 2>/dev/null)
    CP_NOW=$(date +%s)
    CP_AGE=$(( CP_NOW - CP_MTIME ))
  fi
  if [ "$CP_AGE" -gt 7200 ]; then
    printf "startup-recovery: Clearing stale cron-paused.json (age: %ss, threshold: 2h).\n" "$CP_AGE" >&2
    rm -f "$CRON_PAUSE" 2>/dev/null
  fi
fi

# Clean stale watchers FOR THIS PROJECT ONLY (claimed_at > 4 hours ago or null)
# Only cleans watchers scoped to the current project — other projects' watchers are untouched.
# Uses bash date -d instead of jq strptime (strptime broken on Windows/MSYS)
WATCHER_REGISTRY="$HOME/.openclaw/watchers/REGISTRY.json"
if [ -f "$WATCHER_REGISTRY" ]; then
  NOW_EPOCH=$(date +%s)
  STALE_THRESHOLD=14400  # 4 hours

  # Normalize current project path
  CURRENT_PROJECT=$(pwd -W 2>/dev/null || pwd)
  CURRENT_PROJECT=$(printf '%s' "$CURRENT_PROJECT" | tr '\\\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]')

  STALE_SLOTS=""
  for SLOT_INFO in $(jq -r --arg proj "$CURRENT_PROJECT" \
    '.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj)) | "\(.slot)|\(.claimed_at // "null")"' \
    "$WATCHER_REGISTRY" 2>/dev/null); do
    SN="${SLOT_INFO%%|*}"
    CA="${SLOT_INFO#*|}"
    if [ "$CA" = "null" ]; then
      STALE_SLOTS="$STALE_SLOTS $SN"
    else
      CA_EPOCH=$(date -d "$CA" +%s 2>/dev/null || echo "0")
      if [ $((NOW_EPOCH - CA_EPOCH)) -gt $STALE_THRESHOLD ]; then
        STALE_SLOTS="$STALE_SLOTS $SN"
      fi
    fi
  done
  STALE_SLOTS=$(echo "$STALE_SLOTS" | xargs)  # trim whitespace

  if [ -n "$STALE_SLOTS" ]; then
    printf "startup-recovery: Cleaning stale watchers for %s: slots %s\n" "$CURRENT_PROJECT" "$STALE_SLOTS" >&2

    # Lock registry to prevent race conditions with other agents
    registry_lock || {
      printf "startup-recovery: WARNING — could not acquire registry lock, skipping stale cleanup\n" >&2
      STALE_SLOTS=""  # skip the loop
    }

    for SN in $STALE_SLOTS; do
      # Reset in registry
      UPDATED_REG=$(jq --argjson s "$SN" \
        '.watchers |= map(if .slot == $s then {slot, status: "available", claimed_by: null, claimed_at: null, cron_job_id: null} else . end)' \
        "$WATCHER_REGISTRY" 2>/dev/null)
      if [ -n "$UPDATED_REG" ]; then
        printf '%s\n' "$UPDATED_REG" > "$WATCHER_REGISTRY"
      fi
      # Reset slot file
      printf "# Watcher Slot %s\n\n**Status**: available\n" "$SN" > "$HOME/.openclaw/watchers/slot-${SN}.md" 2>/dev/null
    done

    registry_unlock
  fi

  # --- GLOBAL orphan reap: free ANY project's watchers older than 72h ---
  # The pool is shared; without this, week-old orphans from other projects exhaust it and a fresh
  # project can never claim. Threshold is 72h (NOT 24h): claimed_at is NOT refreshed (no heartbeat
  # yet — that's AC30), so a shorter window would reap a long-running ACTIVE session. 72h only catches
  # clearly-dead multi-day orphans. TODO(AC30): add a last_seen heartbeat, then this can safely tighten.
  GLOBAL_STALE=259200
  GLOBAL_SLOTS=""
  for SLOT_INFO in $(jq -r '.watchers[] | select(.status == "active") | "\(.slot)|\(.claimed_at // "null")"' "$WATCHER_REGISTRY" 2>/dev/null); do
    GSN="${SLOT_INFO%%|*}"; GCA="${SLOT_INFO#*|}"
    [ "$GCA" = "null" ] && continue
    GCA_EPOCH=$(date -d "$GCA" +%s 2>/dev/null || echo "$NOW_EPOCH")
    if [ $((NOW_EPOCH - GCA_EPOCH)) -gt $GLOBAL_STALE ]; then GLOBAL_SLOTS="$GLOBAL_SLOTS $GSN"; fi
  done
  GLOBAL_SLOTS=$(echo "$GLOBAL_SLOTS" | xargs)
  if [ -n "$GLOBAL_SLOTS" ]; then
    printf "startup-recovery: Global orphan reap (>72h): slots %s\n" "$GLOBAL_SLOTS" >&2
    if registry_lock; then
      for GSN in $GLOBAL_SLOTS; do
        UPDATED_REG=$(jq --argjson s "$GSN" '.watchers |= map(if .slot == $s then {slot, status: "available", claimed_by: null, claimed_at: null, cron_job_id: null} else . end)' "$WATCHER_REGISTRY" 2>/dev/null)
        [ -n "$UPDATED_REG" ] && printf '%s\n' "$UPDATED_REG" > "$WATCHER_REGISTRY"
        printf "# Watcher Slot %s\n\n**Status**: available\n" "$GSN" > "$HOME/.openclaw/watchers/slot-${GSN}.md" 2>/dev/null
      done
      registry_unlock
    fi
  fi

  # --- Clear stale cron data from active watchers for this project ---
  # CronCreate jobs only live within the session that created them.
  # When a new session starts, those crons are dead but the registry still has their IDs.
  # pre-write-gate.sh checks cron_job_id != null, so stale IDs bypass the cron requirement.
  # Fix: clear cron_job_id and cron_interval on startup, forcing agents to re-create each session.
  CRON_WATCHERS=$(jq -r --arg proj "$CURRENT_PROJECT" \
    '[.watchers[] | select(.status == "active" and .cron_job_id != null and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | length' \
    "$WATCHER_REGISTRY" 2>/dev/null || printf "0")

  if [ "$CRON_WATCHERS" -gt 0 ]; then
    printf "startup-recovery: Clearing stale cron data from %s active watcher(s) for %s (crons don't survive sessions)\n" "$CRON_WATCHERS" "$CURRENT_PROJECT" >&2

    registry_lock || {
      printf "startup-recovery: WARNING — could not acquire registry lock, skipping cron cleanup\n" >&2
      CRON_WATCHERS=0
    }

    if [ "$CRON_WATCHERS" -gt 0 ]; then
      UPDATED_REG=$(jq --arg proj "$CURRENT_PROJECT" \
        '.watchers |= map(if (.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj)) then .cron_job_id = null | .cron_interval = null else . end)' \
        "$WATCHER_REGISTRY" 2>/dev/null)
      if [ -n "$UPDATED_REG" ]; then
        printf '%s\n' "$UPDATED_REG" > "$WATCHER_REGISTRY"
      fi
      registry_unlock
    fi
  fi
fi

# Clean stale lockdir
if [ -d "$LOCKDIR" ]; then
  STALE_PID=$(cat "$LOCKDIR/pid" 2>/dev/null)
  if [ -n "$STALE_PID" ] && ! kill -0 "$STALE_PID" 2>/dev/null; then
    printf "startup-recovery: Stale lockdir found (PID %s dead). Cleaning.\n" "$STALE_PID" >&2
    rm -rf "$LOCKDIR" 2>/dev/null
    # Retry if rm failed (Windows file handle issue)
    if [ -d "$LOCKDIR" ]; then
      sleep 1
      rm -rf "$LOCKDIR" 2>/dev/null
    fi
  fi
fi

# Kill orphaned dev server
if [ -f "${STATE_DIR}/dev-server.pid" ]; then
  OLD_PID=$(cat "${STATE_DIR}/dev-server.pid" 2>/dev/null)
  if [ -n "$OLD_PID" ]; then
    kill "$OLD_PID" 2>/dev/null
    printf "startup-recovery: Killed orphaned dev server (PID %s)\n" "$OLD_PID" >&2
  fi
  rm -f "${STATE_DIR}/dev-server.pid" 2>/dev/null
fi

# --- DETECT MISSED SESSION-END (terminal closed without clean Stop) ---
# If the previous session didn't write a session summary, the Stop hook never fired.
# Write a recovery summary now so memory stays accurate.
MEMORY_DIR=".agent-memory"

if [ -d "$MEMORY_DIR" ]; then
  # Check if write-count > 0 (session was active) but no session file for today
  WRITE_COUNT=$(cat "${STATE_DIR}/write-count.txt" 2>/dev/null || printf "0")
  TODAY=$(date +%Y-%m-%d)
  TODAY_SESSION=$(find "${MEMORY_DIR}/episodic/sessions/" -name "${TODAY}*" -type f 2>/dev/null | tail -1)

  if [ "$WRITE_COUNT" -gt 0 ] && [ -z "$TODAY_SESSION" ]; then
    printf "startup-recovery: Previous session ended without Stop hook (terminal closed). Writing recovery summary.\n" >&2

    # Write recovery session summary
    SESSIONS_DIR="${MEMORY_DIR}/episodic/sessions"
    mkdir -p "$SESSIONS_DIR" 2>/dev/null
    RECOVERY_FILE="${SESSIONS_DIR}/${TODAY}_recovery.md"
    TIMESTAMP=$(date -Iseconds)

    PROGRESS=$(cat "${STATE_DIR}/progress-notes.md" 2>/dev/null || printf "No progress notes.")
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      MODIFIED=$(git diff --name-only HEAD~5 2>/dev/null | head -20 | sed 's/^/  - /')
      [ -z "$MODIFIED" ] && MODIFIED="(no uncommitted changes)"
    elif [ -f "${STATE_DIR}/unverified-writes.jsonl" ]; then
      MODIFIED=$(jq -r '.file' "${STATE_DIR}/unverified-writes.jsonl" 2>/dev/null | sort -u | head -20 | sed 's/^/  - /')
      [ -z "$MODIFIED" ] && MODIFIED="(no file tracking available)"
    else
      MODIFIED="(not a git repo — no file tracking available)"
    fi

    RECOVERY_CONTENT="# Session Summary — ${TIMESTAMP} (RECOVERY — terminal was closed without clean exit)

## Phase at End
Phase: ${PHASE}, Sprint: ${SPRINT}

## Progress Notes
${PROGRESS}

## Files Modified
${MODIFIED}

## Status
RECOVERY — Stop hook did not fire. This summary was generated by startup-recovery.sh."

    atomic_write "$RECOVERY_CONTENT" "$RECOVERY_FILE"

    # Append to sessions.jsonl
    append_jsonl "{\"event\":\"session_recovery\",\"ts\":\"${TIMESTAMP}\",\"phase\":\"${PHASE}\",\"sprint\":${SPRINT},\"writes\":${WRITE_COUNT}}" \
      "${MEMORY_DIR}/sessions.jsonl"

    # Update MANIFEST
    MANIFEST="${MEMORY_DIR}/MEMORY_MANIFEST.json"
    if [ -f "$MANIFEST" ]; then
      OLD_COUNT=$(jq -r '(.sessions_count // .quick_access.sessions_count // 0) | tonumber' "$MANIFEST" 2>/dev/null || printf "0")
      if ! [[ "$OLD_COUNT" =~ ^[0-9]+$ ]]; then OLD_COUNT=0; fi
      NEW_COUNT=$((OLD_COUNT + 1))
      UPDATED=$(sed \
        -e "s/\"last_accessed\": *\"[^\"]*\"/\"last_accessed\": \"${TIMESTAMP}\"/" \
        -e "s/\"sessions_count\": *[0-9]*/\"sessions_count\": ${NEW_COUNT}/" \
        "$MANIFEST" 2>/dev/null)
      if [ -n "$UPDATED" ]; then
        atomic_write "$UPDATED" "$MANIFEST"
      fi
    fi

    # Update active-tasks.json
    TASKS="{\"last_session_end\":\"${TIMESTAMP}\",\"phase_at_end\":\"${PHASE}\",\"sprint_at_end\":${SPRINT},\"resume_action\":\"Continue from phase ${PHASE} (recovered)\"}"
    mkdir -p "${MEMORY_DIR}/working" 2>/dev/null
    atomic_write "$TASKS" "${MEMORY_DIR}/working/active-tasks.json"

    # Trim JSONL files
    trim_jsonl "${MEMORY_DIR}/working/recent-activity.jsonl" 50
    trim_jsonl "${MEMORY_DIR}/sessions.jsonl" 100

    # Reset write counter (only after recovery actually ran)
    atomic_write "0" "${STATE_DIR}/write-count.txt"
  fi
fi

# Write a fresh handoff artifact from current disk state
bash "$HOME/.claude/scripts/write-handoff.sh" "CRASH_RECOVERY" 2>/dev/null

bash "$HOME/.claude/scripts/notify.sh" "Harness recovering. Resuming at phase $PHASE, sprint $SPRINT." 2>/dev/null

exit 0
