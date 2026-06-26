#!/bin/bash
# test-beast-watch-hook.sh — Sprint 38 B: in-work interjection (PostToolUse).
# Drives the LIVE beast-watch-hook.sh. After a tool call it scans the agent's recent
# reasoning (from the transcript) + the action via beast-surface and surfaces matching
# lessons as additionalContext — but each lesson AT MOST ONCE per session, silent by
# default, flag-gated, kill-switch-honoring, fail-safe.
# Usage: bash tests/test-beast-watch-hook.sh
set -u
HOOK="$HOME/.claude/hooks/beast-watch-hook.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

SBX=$(mktemp -d 2>/dev/null || echo "/tmp/bwh-$$")
export HARNESS_STATE_DIR="$SBX/state"
export BEAST_LESSONS="$SBX/.beast/lessons.jsonl"
mkdir -p "$HARNESS_STATE_DIR" "$SBX/.beast"
export BEAST_MP_FIXTURE=/dev/null            # isolate from the semantic layer (literal in-work recall)
export BEAST_MP_CACHE_DIR="$SBX/mpcache"     # isolate the query cache from any shared/stale cache
trap 'rm -rf "$SBX" 2>/dev/null' EXIT
cat > "$BEAST_LESSONS" <<'EOF'
{"id":"7","scope":"*","trigger":"kill.?switch|cwd|current directory","lesson":"Kill-switch must resolve by PROJECT ROOT, not cwd.","fix":"Use find_project_state_dir; never read the flag relative to cwd.","dossier":"99353ff"}
EOF
printf 'beast mode on\n' > "$HARNESS_STATE_DIR/beast-mode.flag"

# a transcript where the agent is REASONING about doing the wrong thing
TR="$SBX/transcript.jsonl"
cat > "$TR" <<'EOF'
{"type":"user","message":{"content":"work on the killswitch"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"I will resolve the killswitch flag from the current directory cwd to keep it simple."}]}}
EOF

inp(){ jq -cn --arg t "$TR" --arg s "$1" '{session_id:$s,transcript_path:$t,tool_name:"Read",tool_input:{file_path:"x.sh"}}'; }
run(){ printf '%s' "$1" | bash "$HOOK" 2>/dev/null; }
ctx(){ printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }
empty(){ [ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]; }

[ -f "$HOOK" ] || { bad "hook exists"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
ok "hook exists"

# 1. surfaces the drift lesson from REASONING (not a write) as additionalContext
OUT=$(run "$(inp S1)")
printf '%s' "$(ctx "$OUT")" | grep -q 'M7' && ok "surfaces drift lesson from reasoning" || bad "expected M7 (got: $OUT)"
printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName=="PostToolUse"' >/dev/null 2>&1 && ok "emits PostToolUse additionalContext JSON" || bad "PostToolUse JSON shape"

# 2. dedup: same session, same drift -> SILENCE (already surfaced once)
OUT=$(run "$(inp S1)")
empty "$OUT" && ok "dedup: not surfaced twice in one session" || bad "dedup failed (got: $OUT)"

# 3. NEW session -> surfaces again
OUT=$(run "$(inp S2)")
printf '%s' "$(ctx "$OUT")" | grep -q 'M7' && ok "new session -> surfaces again" || bad "new session (got: $OUT)"

# 4. no drift in transcript -> silence
cat > "$TR" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Let me read the README and tidy some imports."}]}}
EOF
OUT=$(run "$(inp S3)")
empty "$OUT" && ok "no drift -> silence" || bad "expected silence (got: $OUT)"

# 5. flag off -> silence
rm -f "$HARNESS_STATE_DIR/beast-mode.flag"
cat > "$TR" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"resolve killswitch from cwd"}]}}
EOF
OUT=$(run "$(inp S4)"); empty "$OUT" && ok "flag off -> silence" || bad "flag off (got: $OUT)"
printf 'beast mode on\n' > "$HARNESS_STATE_DIR/beast-mode.flag"

# 6. harness disabled -> silence
printf 'off\n' > "$HARNESS_STATE_DIR/harness-disabled.flag"
OUT=$(run "$(inp S5)"); empty "$OUT" && ok "harness off -> silence" || bad "harness off (got: $OUT)"
rm -f "$HARNESS_STATE_DIR/harness-disabled.flag"

# 7. fail-safe: malformed / empty input -> exit 0, no output
printf 'garbage {{{' | bash "$HOOK" >/tmp/bwh_o 2>/dev/null; rc=$?
{ [ "$rc" = 0 ] && [ ! -s /tmp/bwh_o ]; } && ok "malformed -> exit 0, silent" || bad "fail-safe (rc=$rc)"
printf '' | bash "$HOOK" >/dev/null 2>&1; [ $? = 0 ] && ok "empty stdin -> exit 0" || bad "empty stdin"

# 8. bash -n
bash -n "$HOOK" 2>/dev/null && ok "bash -n clean" || bad "bash -n"

echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
