#!/usr/bin/env bash
set -u

REAL_HOME="$HOME"
HOOK_SRC="$REAL_HOME/.claude/hooks/on-prompt-submit.sh"
HELPER_SRC="$REAL_HOME/.claude/scripts/lib-helpers.sh"
PASS=0
FAIL=0
LAST_TMP=""
LAST_HOME=""
LAST_PROJ=""
LAST_OUT=""

pass() { printf 'PASS %02d: %s\n' "$1" "$2"; PASS=$((PASS+1)); }
fail() { printf 'FAIL %02d: %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
check() { local n="$1" msg="$2"; shift 2; if "$@"; then pass "$n" "$msg"; else fail "$n" "$msg"; fi; }
contains() { printf '%s' "$LAST_OUT" | grep -Fq -- "$1"; }
not_contains() { ! printf '%s' "$LAST_OUT" | grep -Fq -- "$1"; }
line_no() { printf '%s\n' "$LAST_OUT" | awk -v pat="$1" 'index($0,pat){print NR; exit}'; }
state_hash() { find .claude/state -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1; }

new_env() {
  LAST_TMP=$(mktemp -d)
  LAST_HOME="$LAST_TMP/home"
  LAST_PROJ="$LAST_TMP/project"
  mkdir -p "$LAST_HOME/.claude/hooks" "$LAST_HOME/.claude/scripts" "$LAST_PROJ/.claude/state" "$LAST_PROJ/.claude/contracts"
  cp "$HOOK_SRC" "$LAST_HOME/.claude/hooks/on-prompt-submit.sh"
  cp "$HELPER_SRC" "$LAST_HOME/.claude/scripts/lib-helpers.sh"
}

write_phase() {
  local phase="$1" sprint="${2:-21}" iter="${3:-1}"
  printf '{"phase":"%s","sprint":%s,"iteration":%s}\n' "$phase" "$sprint" "$iter" > "$LAST_PROJ/.claude/state/current-phase.json"
  if [ "$sprint" != "0" ]; then
    printf '# sprint %s contract\n' "$sprint" > "$LAST_PROJ/.claude/contracts/sprint-${sprint}-contract.md"
  fi
}

add_watcher() {
  local scope="$1" cron="${2:-cron-1}"
  mkdir -p "$LAST_HOME/.openclaw/watchers"
  ( cd "$LAST_PROJ" && {
      local proj
      proj=$(pwd -W 2>/dev/null || pwd)
      printf '{"watchers":[{"slot":1,"status":"active","project":"%s","claimed_by":"tester","cron_job_id":"%s","cron_interval":"*/3 * * * *"}]}\n' "$proj" "$cron" > "$LAST_HOME/.openclaw/watchers/REGISTRY.json"
    } )
  cat > "$LAST_HOME/.openclaw/watchers/slot-1.md" <<EOF
## TO-DO
- [ ] Test step
## SCOPE
$scope
## MISTAKES TO AVOID
Do not widen scope
## DONE WHEN
Packet matches contract
EOF
}

run_case() {
  local phase="$1" scope="${2:-}" sprint="${3:-21}"
  new_env
  write_phase "$phase" "$sprint" 1
  if [ -n "$scope" ]; then add_watcher "$scope"; fi
  LAST_OUT=$(cd "$LAST_PROJ" && HOME="$LAST_HOME" HARNESS_STATE_DIR=".claude/state" bash "$LAST_HOME/.claude/hooks/on-prompt-submit.sh")
}

if bash -n "$HOOK_SRC"; then pass 0 "bash -n on-prompt-submit.sh"; else fail 0 "bash -n on-prompt-submit.sh"; fi

run_case PLAN ""
check 1 "PLAN guidance injected" contains 'GUIDANCE: Outcome-first — define result, criteria, constraints, stop condition BEFORE spec. Ambiguous request? Ask — do not assume.'
plan_out="$LAST_OUT"
run_case NEGOTIATE ""
check 2 "NEGOTIATE guidance injected" contains 'GUIDANCE: Skeptical reviewer — challenge your proposal.'
run_case BUILD ""
check 3 "BUILD guidance injected with auto-continue/ask rules" contains 'GUIDANCE: Executor — proceed on clear, low-risk, reversible steps. ASK only for destructive/irreversible/scope-changing. No "should I continue?" — continue.'
run_case EVALUATE ""
check 4 "EVALUATE adversarial verifier guidance injected" contains 'GUIDANCE: Adversarial verifier — default FAIL. Every criterion needs fresh evidence. Do not read progress-notes.md. No benefit of doubt.'
run_case COMPLETE ""
check 5 "COMPLETE handoff guidance injected" contains 'GUIDANCE: Handoff — name outcome (finished/blocked/failed), list evidence, state what user verifies. No "would you like me to..." softeners.'
run_case UNKNOWN ""
check 6 "UNKNOWN injects no guidance" not_contains 'GUIDANCE:'
LAST_OUT="$plan_out"
summary_ln=$(line_no '[HARNESS]') guidance_ln=$(line_no 'GUIDANCE:') read_ln=$(line_no 'READ FIRST:')
if [ -n "$summary_ln" ] && [ -n "$guidance_ln" ] && [ -n "$read_ln" ] && [ "$summary_ln" -lt "$guidance_ln" ] && [ "$guidance_ln" -lt "$read_ln" ]; then pass 7 "GUIDANCE appears after state summary before READ FIRST"; else fail 7 "GUIDANCE ordering"; fi
if python - "$HOOK_SRC" <<'PY'
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text(encoding='utf-8')
for line in re.findall(r"GUIDANCE_LINE=(?:'([^']+)'|\"([^\"]+)\")", text):
    value = line[0] or line[1]
    if len(value) >= 160:
        print(value, len(value))
        sys.exit(1)
PY
then pass 8 "Each guidance line is under 160 characters"; else fail 8 "Guidance line length under 160"; fi

run_case BUILD "single file config typo"
check 9 "Trivial watcher SCOPE triggers LIGHTWEIGHT" contains 'PROTOCOL: Lightweight — implement, test, verify inline. No contract or sub-agent verifier required.'
run_case BUILD "new system architecture migration"
check 10 "Large watcher SCOPE triggers FULL" contains 'PROTOCOL: Full — PRD artifact (.claude/specs/prd-*.md) and test spec (.claude/specs/test-spec-*.md) required before BUILD.'
run_case BUILD "ordinary feature work"
check 11 "Default watcher SCOPE injects no protocol" not_contains 'PROTOCOL:'
run_case BUILD "config"
guidance_ln=$(line_no 'GUIDANCE:') protocol_ln=$(line_no 'PROTOCOL:')
if [ -n "$guidance_ln" ] && [ -n "$protocol_ln" ] && [ "$guidance_ln" -lt "$protocol_ln" ]; then pass 12 "Advisory appears after GUIDANCE"; else fail 12 "Advisory ordering"; fi
new_env; write_phase BUILD 21 1; add_watcher "config"
before=$(cd "$LAST_PROJ" && state_hash)
LAST_OUT=$(cd "$LAST_PROJ" && HOME="$LAST_HOME" HARNESS_STATE_DIR=".claude/state" bash "$LAST_HOME/.claude/hooks/on-prompt-submit.sh")
after=$(cd "$LAST_PROJ" && state_hash)
if [ "$before" = "$after" ]; then pass 13 "Task-size advisory first run writes no state"; else fail 13 "Task-size advisory wrote state on first run"; fi

new_env; write_phase BUILD 21 1; printf '{"nudge_count":0,"last_nudge_ts":null,"last_output_fingerprint":"","last_churn_files":[],"blocked":false}\n' > "$LAST_PROJ/.claude/state/strategy-loop-state.json"
LAST_OUT=$(cd "$LAST_PROJ" && HOME="$LAST_HOME" HARNESS_STATE_DIR=".claude/state" bash "$LAST_HOME/.claude/hooks/on-prompt-submit.sh")
if jq -e '.fix_cycle_count == 0 and .max_fix_cycles == 3 and .last_sprint == "21"' "$LAST_PROJ/.claude/state/strategy-loop-state.json" >/dev/null; then pass 14 "strategy-loop-state gains fix fields"; else fail 14 "strategy-loop-state fields"; fi

new_env; write_phase BUILD 21 1; printf '{"nudge_count":0,"last_nudge_ts":null,"last_output_fingerprint":"","last_churn_files":[],"blocked":true,"fix_cycle_count":0,"max_fix_cycles":3,"last_sprint":"21"}\n' > "$LAST_PROJ/.claude/state/strategy-loop-state.json"; printf '## New Approach\nUse a different tested approach with enough detail to satisfy the strategy acknowledgement requirements.\n' > "$LAST_PROJ/.claude/state/strategy-ack.md"
LAST_OUT=$(cd "$LAST_PROJ" && HOME="$LAST_HOME" HARNESS_STATE_DIR=".claude/state" bash "$LAST_HOME/.claude/hooks/on-prompt-submit.sh")
if jq -e '.fix_cycle_count == 1 and .blocked == false' "$LAST_PROJ/.claude/state/strategy-loop-state.json" >/dev/null; then pass 15 "blocked:true + strategy-ack increments fix cycle"; else fail 15 "fix cycle increment on ack"; fi

new_env; write_phase BUILD 21 1; printf '{"blocked":false,"fix_cycle_count":3,"max_fix_cycles":3,"last_sprint":"21"}\n' > "$LAST_PROJ/.claude/state/strategy-loop-state.json"
LAST_OUT=$(cd "$LAST_PROJ" && HOME="$LAST_HOME" HARNESS_STATE_DIR=".claude/state" bash "$LAST_HOME/.claude/hooks/on-prompt-submit.sh")
check 16 "fix_cycle_count >= max injects STUCK" contains 'STUCK — 3 fix cycles exhausted.'
if contains 'stuck-report.md' && contains 'STOP.' && contains 'WAIT for user.'; then pass 17 "STUCK message tells agent to write report and stop"; else fail 17 "STUCK report/stop instruction"; fi
new_env; write_phase BUILD 21 1; printf '{"blocked":true,"fix_cycle_count":3,"max_fix_cycles":3,"last_sprint":"21"}\n' > "$LAST_PROJ/.claude/state/strategy-loop-state.json"; printf 'ack\n' > "$LAST_PROJ/.claude/state/strategy-ack.md"
LAST_OUT=$(cd "$LAST_PROJ" && HOME="$LAST_HOME" HARNESS_STATE_DIR=".claude/state" bash "$LAST_HOME/.claude/hooks/on-prompt-submit.sh")
if jq -e '.fix_cycle_count == 3 and .blocked == true' "$LAST_PROJ/.claude/state/strategy-loop-state.json" >/dev/null && contains 'STUCK — 3'; then pass 18 "STUCK cannot be cleared by agent ack"; else fail 18 "STUCK clear prevention"; fi
new_env; write_phase BUILD 21 1; printf '{"blocked":false,"fix_cycle_count":2,"max_fix_cycles":3,"last_sprint":"20"}\n' > "$LAST_PROJ/.claude/state/strategy-loop-state.json"
LAST_OUT=$(cd "$LAST_PROJ" && HOME="$LAST_HOME" HARNESS_STATE_DIR=".claude/state" bash "$LAST_HOME/.claude/hooks/on-prompt-submit.sh")
if jq -e '.fix_cycle_count == 0 and .last_sprint == "21"' "$LAST_PROJ/.claude/state/strategy-loop-state.json" >/dev/null; then pass 19 "Sprint advance resets fix_cycle_count"; else fail 19 "Sprint reset"; fi
new_env; write_phase BUILD 21 1; printf '{"blocked":false,"fix_cycle_count":4,"max_fix_cycles":5,"last_sprint":"21"}\n' > "$LAST_PROJ/.claude/state/strategy-loop-state.json"
LAST_OUT=$(cd "$LAST_PROJ" && HOME="$LAST_HOME" HARNESS_STATE_DIR=".claude/state" bash "$LAST_HOME/.claude/hooks/on-prompt-submit.sh")
not_contains 'STUCK' && nostuck=1 || nostuck=0
printf '{"blocked":false,"fix_cycle_count":5,"max_fix_cycles":5,"last_sprint":"21"}\n' > "$LAST_PROJ/.claude/state/strategy-loop-state.json"
LAST_OUT=$(cd "$LAST_PROJ" && HOME="$LAST_HOME" HARNESS_STATE_DIR=".claude/state" bash "$LAST_HOME/.claude/hooks/on-prompt-submit.sh")
if [ "$nostuck" -eq 1 ] && contains 'STUCK — 5 fix cycles exhausted.'; then pass 20 "custom max_fix_cycles triggers at 5"; else fail 20 "custom max_fix_cycles"; fi
new_env; write_phase BUILD 21 1; printf '{"blocked":true,"fix_cycle_count":2,"max_fix_cycles":3,"last_sprint":"21"}\n' > "$LAST_PROJ/.claude/state/strategy-loop-state.json"; printf 'ack\n' > "$LAST_PROJ/.claude/state/strategy-ack.md"
LAST_OUT=$(cd "$LAST_PROJ" && HOME="$LAST_HOME" HARNESS_STATE_DIR=".claude/state" bash "$LAST_HOME/.claude/hooks/on-prompt-submit.sh")
if jq -e '.fix_cycle_count == 3' "$LAST_PROJ/.claude/state/strategy-loop-state.json" >/dev/null; then pass 21 "count 2 plus clear becomes 3"; else fail 21 "count 2 clear to 3"; fi

run_case EVALUATE ""
check 22 "EVALUATE includes VERIFIER RULES" contains 'VERIFIER RULES:'
check 23 "Verifier rules prohibit progress-notes.md" contains 'Do NOT read .claude/state/progress-notes.md'
check 24 "Verifier rules require per-criterion evidence format" contains 'criterion number, pass/fail, evidence snippet'
run_case BUILD ""
check 25 "Verifier rules only during EVALUATE" not_contains 'VERIFIER RULES:'

hash_file() { sha256sum "$1" | cut -d' ' -f1; }
if [ "$(hash_file "$REAL_HOME/.claude/hooks/pre-write-gate.sh")" = "1349744583d85d129fa63539840a9b24e0d1b0f3205412dd73ebeba0a254edad" ] && [ "$(hash_file "$REAL_HOME/.claude/hooks/pre-bash-gate.sh")" = "fe92c4c05e56f9ee7bc431d613d706656d3b192a4e7eaf5ce9001f0c315112ef" ] && [ "$(hash_file "$REAL_HOME/.claude/hooks/pre-flight-gate.sh")" = "c649474340677ea5783cfbe3a014c9e97be5b690ccf36581b5776f5f26cde004" ]; then pass 26 "Gate scripts unchanged from pre-sprint hashes"; else fail 26 "Gate script hash mismatch"; fi
if [ "$(hash_file "$REAL_HOME/.claude/scripts/lib-helpers.sh")" = "93920917f0f92838f09062c6b0772314ea5d8300d72881f09a65bbf9879a9750" ]; then pass 27 "lib-helpers.sh unchanged"; else fail 27 "lib-helpers changed"; fi
if grep -Fq 'MUST-DO SUMMARY INJECTION' "$HOOK_SRC" && grep -Fq 'Evidence checkpoint' "$HOOK_SRC" && grep -Fq 'Strategy loop breaker' "$HOOK_SRC" && grep -Fq 'CURRENT STEP:' "$HOOK_SRC"; then pass 28 "Existing turn-packet features preserved in hook"; else fail 28 "Existing feature markers missing"; fi
if grep -Fq 'gt 2000' "$HOOK_SRC" && grep -Fq 'head -c 1990' "$HOOK_SRC" && ! grep -Fq 'gt 1490' "$HOOK_SRC"; then pass 29 "Hard packet cap raised to 2000"; else fail 29 "Packet cap not raised"; fi

new_env; write_phase EVALUATE 21 1; add_watcher "architecture migration"; printf 'FAIL: synthetic hard block for packet budget
' > "$LAST_PROJ/.claude/state/phase-feedback.md"
LAST_OUT=$(cd "$LAST_PROJ" && HOME="$LAST_HOME" HARNESS_STATE_DIR=".claude/state" bash "$LAST_HOME/.claude/hooks/on-prompt-submit.sh")
len=${#LAST_OUT}
if [ "$len" -lt 2000 ] && contains 'PROTOCOL: Full' && contains 'VERIFIER RULES:' && contains 'phase-feedback FAIL'; then pass 30 "Worst-case realistic packet with explicit hard block under 2000 chars ($len)"; else fail 30 "Worst-case packet length/content $len"; fi
run_case BUILD "ordinary watcher work"
len=${#LAST_OUT}
if [ "$len" -lt 700 ]; then pass 31 "Unblocked BUILD steady-state packet under 700 chars ($len)"; else fail 31 "BUILD packet length $len"; fi
run_case PLAN "" 0
len=${#LAST_OUT}
if [ "$len" -lt 300 ]; then pass 32 "Bare PLAN packet under 300 chars ($len)"; else fail 32 "PLAN packet length $len"; fi
run_case EVALUATE "ordinary watcher work"
len=${#LAST_OUT}
if [ "$len" -lt 900 ]; then pass 33 "EVALUATE packet under 900 chars ($len)"; else fail 33 "EVALUATE packet length $len"; fi

printf '\nSummary: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]