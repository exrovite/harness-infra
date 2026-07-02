#!/bin/bash
# test-audit-fixes-sprint50.sh — TDD for Sprint 50 (fix all 2026-07-01 audit findings).
# Drives the LIVE hooks/scripts through sandboxes (HARNESS_STATE_DIR / HARNESS_REGISTRY / BEAST_WINS
# / fake HOME). Written BEFORE the fixes — the AC-tagged tests MUST FAIL first (red run captured to
# .claude/evidence/sprint50-tdd-red.txt). Anti-regression tests marked [keep] must pass both sides.
# Run: bash tests/test-audit-fixes-sprint50.sh
set -u
PASS=0; FAIL=0
WRITE_HOOK="$HOME/.claude/hooks/pre-write-gate.sh"
BASH_HOOK="$HOME/.claude/hooks/pre-bash-gate.sh"
PF_HOOK="$HOME/.claude/hooks/pre-flight-gate.sh"
BEAST_HOOK="$HOME/.claude/hooks/beast-protocol-gate.sh"
POST_HOOK="$HOME/.claude/hooks/post-write-check.sh"
GEN="$HOME/.claude/scripts/generate-pre-flight-challenge.sh"
VAL="$HOME/.claude/scripts/validate-pre-flight.sh"
PACK="$HOME/.claude/scripts/build-mustdo-pack.sh"

ok(){ PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else no "$1"; fi; }

# Sandbox: phase $1, sprint $2. Contract present. Empty registry file at $S/reg.json.
mk_sbx(){
  local S; S=$(mktemp -d)
  mkdir -p "$S/.claude/state" "$S/.claude/contracts" "$S/.claude/specs" "$S/.claude/evidence" "$S/src" "$S/docs"
  printf '{"phase":"%s","sprint":%s,"iteration":1}' "$1" "$2" > "$S/.claude/state/current-phase.json"
  : > "$S/.claude/contracts/sprint-${2}-contract.md"
  printf '{"version":"3.0.0","max_per_project":5,"watchers":[]}' > "$S/reg.json"
  printf '%s' "$S"
}
# Give sandbox a satisfied must-do (shared lane, no session id callers)
mk_mustdo_ok(){
  local S="$1"
  mkdir -p "$S/docs/must do"
  printf 'docs/ref.md\n' > "$S/docs/must do/must-do.md"
  : > "$S/docs/ref.md"
  { printf 'I read ref.md and the constraints in must-do.md. '
    printf 'This summary is deliberately longer than two hundred characters so that the must-do gate minimum length requirement is satisfied for the sandbox scenarios exercised by the sprint-50 audit-fix test suite.\n'
  } > "$S/.claude/state/must-do-summary.md"
}
# Run pre-write-gate. $1=sandbox $2=payload-json. Echo "<rc>::<stderr>"
run_pw(){
  local S="$1" P="$2" OUT RC
  OUT=$( cd "$S" && printf '%s' "$P" | HARNESS_STATE_DIR="$S/.claude/state" HARNESS_REGISTRY="$S/reg.json" bash "$WRITE_HOOK" 2>&1 >/dev/null ); RC=$?
  printf '%s::%s' "$RC" "$OUT"
}
run_bashgate(){
  local S="$1" CMD="$2" OUT RC J
  J=$(jq -n --arg c "$CMD" '{tool_name:"Bash",tool_input:{command:$c}}')
  OUT=$( cd "$S" && printf '%s' "$J" | HARNESS_STATE_DIR="$S/.claude/state" HARNESS_REGISTRY="$S/reg.json" bash "$BASH_HOOK" 2>&1 >/dev/null ); RC=$?
  printf '%s::%s' "$RC" "$OUT"
}

echo "== AC1: watcher admin lock exemptions (state paths + Agent) =="
S=$(mk_sbx BUILD 1); mk_mustdo_ok "$S"; printf '5' > "$S/.claude/state/write-count.txt"
R=$(run_pw "$S" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$S/.claude/state/foo.txt\"}}"); RC=${R%%::*}
check "AC1a: locked writes + no watcher -> .claude/state/ write ALLOWED" "[ \"$RC\" = 0 ]"
R=$(run_pw "$S" '{"tool_name":"Agent","tool_input":{}}'); RC=${R%%::*}
check "AC1b: locked writes + no watcher -> Agent tool ALLOWED" "[ \"$RC\" = 0 ]"
R=$(run_pw "$S" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$S/src/x.js\"}}"); RC=${R%%::*}
check "AC1c [keep]: locked writes + no watcher -> source write still BLOCKED" "[ \"$RC\" = 2 ]"
rm -rf "$S"

echo "== AC2: must-do summary gate exempts Agent (empty target) =="
S=$(mk_sbx BUILD 1); mkdir -p "$S/docs/must do"; printf 'docs/ref.md\n' > "$S/docs/must do/must-do.md"; : > "$S/docs/ref.md"
R=$(run_pw "$S" '{"tool_name":"Agent","session_id":"sessA","tool_input":{}}'); RC=${R%%::*}
check "AC2a: no summary lane + Agent spawn -> ALLOWED" "[ \"$RC\" = 0 ]"
R=$(run_pw "$S" "{\"tool_name\":\"Write\",\"session_id\":\"sessA\",\"tool_input\":{\"file_path\":\"$S/src/y.js\"}}"); RC=${R%%::*}; MSG=${R#*::}
check "AC2b [keep]: no summary lane + source write -> BLOCKED naming own lane" "[ \"$RC\" = 2 ] && printf '%s' \"\$MSG\" | grep -qF 'must-do-summary.sessA'"
rm -rf "$S"

echo "== AC3: beast-protocol-gate read-only pass + Bash ack/state exemption =="
S=$(mk_sbx BUILD 1); mkdir -p "$S/.beast"
: > "$S/.claude/state/beast-mode.flag"
printf '{"concept":"widgetz","quote":"test quote"}\n' > "$S/.beast/validated-wins.jsonl"
run_beast(){
  local P="$1" OUT RC
  OUT=$( cd "$S" && printf '%s' "$P" | HARNESS_STATE_DIR="$S/.claude/state" BEAST_WINS="$S/.beast/validated-wins.jsonl" bash "$BEAST_HOOK" 2>&1 >/dev/null ); RC=$?
  printf '%s::%s' "$RC" "$OUT"
}
J=$(jq -n '{tool_name:"Bash",tool_input:{command:"wc -l widgetz-notes.txt"}}')
R=$(run_beast "$J"); RC=${R%%::*}
check "AC3a: read-only Bash touching concept -> ALLOWED (no ack)" "[ \"$RC\" = 0 ]"
J=$(jq -n '{tool_name:"Bash",tool_input:{command:"echo hi > widgetz.js"}}')
R=$(run_beast "$J"); RC=${R%%::*}
check "AC3b [keep]: Bash WRITE touching concept, no ack -> BLOCKED" "[ \"$RC\" = 2 ]"
J=$(jq -n '{tool_name:"Bash",tool_input:{command:"printf x > .claude/state/protocol-ack.widgetz.md"}}')
R=$(run_beast "$J"); RC=${R%%::*}
check "AC3c: Bash writing the ack file itself -> ALLOWED" "[ \"$RC\" = 0 ]"
J=$(jq -n '{tool_name:"Write",tool_input:{file_path:"src/w.js",content:"uses widgetz"}}')
R=$(run_beast "$J"); RC=${R%%::*}
check "AC3d [keep]: Write source touching concept, no ack -> BLOCKED" "[ \"$RC\" = 2 ]"
rm -rf "$S"

echo "== AC4: .claude/evidence/ exempt in phase gate + pre-flight feedback gate =="
S=$(mk_sbx EVALUATE 1)
R=$(run_pw "$S" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$S/.claude/evidence/x.json\"}}"); RC=${R%%::*}
check "AC4a: EVALUATE phase + evidence .json write -> ALLOWED" "[ \"$RC\" = 0 ]"
printf 'FAIL: something\n' > "$S/.claude/state/phase-feedback.md"
OUT=$( cd "$S" && printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/evidence/y.json"}}' "$S" | HARNESS_STATE_DIR="$S/.claude/state" bash "$PF_HOOK" 2>&1 >/dev/null ); RC=$?
check "AC4b: phase-feedback FAIL + evidence write via pre-flight-gate -> ALLOWED" "[ \"$RC\" = 0 ]"
rm -f "$S/.claude/state/phase-feedback.md"
# AC4c (residual B1, found live in EVALUATE iteration 3): a BASH command writing evidence must pass
# the pre-bash bootstrap exemptions even in a phase that forbids source writes.
R=$(run_bashgate "$S" 'echo x > .claude/evidence/sweep.txt'); RC=${R%%::*}
check "AC4c: EVALUATE phase + bash evidence write -> ALLOWED" "[ \"$RC\" = 0 ]"
rm -rf "$S"

echo "== AC5: pre-bash write detection additions =="
S=$(mk_sbx PLAN 1)
for CMD in 'echo x >> src/f.js' 'dd if=/dev/zero of=src/f.bin count=1' 'git apply fix.patch' 'patch -p1 < fix.patch' 'perl -e "open(F,\">src/f.pl\");print F 1"'; do
  R=$(run_bashgate "$S" "$CMD"); RC=${R%%::*}
  check "AC5: PLAN phase detects+blocks: $CMD" "[ \"$RC\" = 2 ]"
done
for CMD in 'git status' 'grep -r foo src/' 'ls -la src'; do
  R=$(run_bashgate "$S" "$CMD"); RC=${R%%::*}
  check "AC5 [keep]: read-only allowed: $CMD" "[ \"$RC\" = 0 ]"
done
rm -rf "$S"

echo "== AC6/AC8: pre-flight answer key sidecar, distractor uniqueness, hardening =="
S6=$(mktemp -d)
mkdir -p "$S6/.openclaw/watchers" "$S6/.openclaw/distractor-pool" "$S6/docs/must do" "$S6/.claude/state" "$S6/src"
TASKD="Test task sprint50 sandbox"
STEPD="Step 1: do the sandbox thing"
MISTD="Do not touch the production sandbox"
printf '{"version":"3.0.0","max_per_project":5,"watchers":[{"slot":9,"project":"%s","session_id":"pfsess","status":"active","claimed_by":"t","claimed_at":"2026-07-02T00:00:00","last_seen":"2026-07-02T00:00:00","cron_job_id":"x","cron_interval":"*/3 * * * *"}]}' "$S6" > "$S6/.openclaw/watchers/REGISTRY.json"
{ printf '# Watcher Slot 9\n\n**Status**: active\n**Task**: %s\n\n## TO-DO LIST\n- [ ] %s\n\n## MISTAKES TO AVOID\n- %s\n' "$TASKD" "$STEPD" "$MISTD"; } > "$S6/.openclaw/watchers/slot-9.md"
for p in tasks steps files constraints; do
  printf 'Pool filler line one for %s\nPool filler line two for %s\nPool filler line three for %s\nPool filler line four for %s\n' "$p" "$p" "$p" "$p" > "$S6/.openclaw/distractor-pool/$p.txt"
done
LINE_A1="NEVER remove the alpha sandbox invariant from the widget processing pipeline here"
LINE_A2="ALWAYS validate the beta sandbox invariant before the widget pipeline commits data"
printf '%s\n%s\n' "$LINE_A1" "$LINE_A2" > "$S6/docs/ref-a.md"
printf '%s\n%s\n' "$LINE_A1" "$LINE_A2" > "$S6/docs/ref-b.md"
printf 'docs/ref-a.md\ndocs/ref-b.md\n' > "$S6/docs/must do/must-do.md"

CH="$S6/.claude/pre-flight/pfsess/challenge.md"
KEY="$S6/.claude/pre-flight/pfsess/answer-key"
RESP="$S6/.claude/pre-flight/pfsess/response.md"
gen_ch(){ ( cd "$S6" && HOME="$S6" bash "$GEN" "src/target.js" "pfsess" >/dev/null 2>&1 ); }

# letter of the option whose text matches exactly, within question $1
letter_of(){ awk -v q="## Q$1:" -v t="$2" '
  index($0,q){f=1;next} /^## Q[0-9]+:/{f=0}
  f && match($0,/^[A-D]\) /){ if (substr($0,4)==t){ print substr($0,1,1); exit } }' "$CH"; }
# meta lookup: sidecar first (post-fix), challenge comments fallback (pre-fix)
meta_of(){ local k="$1" v=""
  [ -f "$KEY" ] && v=$(sed -n "s/.*$k: \([^>]*\).*/\1/p" "$KEY" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//')
  [ -n "$v" ] || v=$(sed -n "s/.*<!-- $k: \([^>]*\) -->.*/\1/p" "$CH" 2>/dev/null | head -1 | sed 's/[[:space:]]*$//')
  printf '%s' "$v"; }
build_resp(){ # correct answers everywhere; Q5 = the "No" option
  local l1 l2 l3 l4 l5 lyes n corr
  l1=$(letter_of 1 "$TASKD"); l2=$(letter_of 2 "$STEPD"); l3=$(letter_of 3 "src/target.js"); l4=$(letter_of 4 "$MISTD")
  lyes=$(meta_of q5_yes_label)
  if [ "$lyes" = "A" ]; then l5="B"; else l5="A"; fi
  { printf 'Q1: %s\nQ2: %s\nQ3: %s\nQ4: %s\nQ5: %s\n' "$l1" "$l2" "$l3" "$l4" "$l5"
    n=6
    while true; do
      corr=$(meta_of "q${n}_correct_label"); [ -n "$corr" ] || break
      printf 'Q%s: %s\n' "$n" "$corr"; n=$((n+1))
    done
  } > "$RESP"
}

gen_ch
check "AC6a: challenge.md carries NO answer-key metadata" "! grep -qE 'correct_label|q5_yes_label' \"$CH\""
check "AC6b: sidecar answer-key exists" "[ -f \"$KEY\" ]"
# distractor uniqueness: for each Q6+ question, no NON-correct option may appear verbatim in its source file
UNIQ_OK=1
n=6
while true; do
  corr=$(meta_of "q${n}_correct_label"); [ -n "$corr" ] || break
  src=$(meta_of "q${n}_source")
  SRCF="$S6/docs/$src"; [ -f "$SRCF" ] || SRCF=$(find "$S6/docs" -name "$src" 2>/dev/null | head -1)
  while IFS= read -r line; do
    L=${line%%\)*}; T=${line#*\) }
    [ "$L" = "$corr" ] && continue
    if [ -n "$SRCF" ] && [ -f "$SRCF" ] && grep -qxF "$T" "$SRCF" 2>/dev/null; then UNIQ_OK=0; fi
  done < <(awk -v q="## Q$n:" 'index($0,q){f=1;next} /^## Q[0-9]+:/{f=0} f && /^[A-D]\) /' "$CH")
  n=$((n+1))
done
check "AC6c: no distractor appears verbatim in its question's source file" "[ \"$UNIQ_OK\" = 1 ]"
build_resp
( cd "$S6" && HOME="$S6" bash "$VAL" "pfsess" >/dev/null 2>&1 ); RC=$?
check "AC6d [keep]: correct answers validate PASS" "[ \"$RC\" = 0 ]"
gen_ch; build_resp
corr=$(meta_of q6_correct_label)
case "$corr" in A) W=B;; B) W=C;; C) W=D;; *) W=A;; esac
sed -i "s/^Q6: .*/Q6: $W/" "$RESP"
( cd "$S6" && HOME="$S6" bash "$VAL" "pfsess" >/dev/null 2>&1 ); RC=$?
check "AC6e [keep]: wrong Q6 answer FAILS validation" "[ \"$RC\" = 1 ]"
rm -rf "$S6/.claude/pre-flight/pfsess"

# AC8 hardening: arm at 5th No (stamps last_reset), block next, unblock on fresh ledger entry
mkdir -p "$S6/.claude/pre-flight"
printf '{"no_verify_count":4,"hardened":false,"last_reset":""}' > "$S6/.claude/pre-flight/verify-counter.json"
gen_ch; build_resp
( cd "$S6" && HOME="$S6" bash "$VAL" "pfsess" >/dev/null 2>&1 )
LR=$(jq -r '.last_reset // ""' "$S6/.claude/pre-flight/verify-counter.json" 2>/dev/null)
HD=$(jq -r '.hardened' "$S6/.claude/pre-flight/verify-counter.json" 2>/dev/null)
check "AC8a: 5th 'No' arms hardening WITH last_reset stamped" "[ \"$HD\" = true ] && [ -n \"$LR\" ]"
gen_ch; build_resp
( cd "$S6" && HOME="$S6" bash "$VAL" "pfsess" >/dev/null 2>&1 ); RC=$?
check "AC8b: hardened + no fresh verification -> validation BLOCKED" "[ \"$RC\" = 1 ]"
printf '{"ts":"9999-01-01T00:00:00","agent":"verifier"}\n' >> "$S6/.claude/state/verification-ledger.jsonl"
gen_ch; build_resp
( cd "$S6" && HOME="$S6" bash "$VAL" "pfsess" >/dev/null 2>&1 ); RC=$?
check "AC8c: fresh ledger entry newer than last_reset -> unblocked" "[ \"$RC\" = 0 ]"
rm -rf "$S6"

echo "== AC9: per-session write counter =="
S=$(mk_sbx BUILD 1); mk_mustdo_ok "$S"
( cd "$S" && printf '{"tool_name":"Write","session_id":"sessX","tool_input":{"file_path":"%s/src/a.js"}}' "$S" | HARNESS_STATE_DIR="$S/.claude/state" HARNESS_REGISTRY="$S/reg.json" bash "$POST_HOOK" >/dev/null 2>&1 )
CNT=$(cat "$S/.claude/state/write-count.sessX.txt" 2>/dev/null | tr -dc '0-9')
check "AC9a: post-write-check increments per-session counter" "[ \"$CNT\" = 1 ]"
printf '9' > "$S/.claude/state/write-count.txt"
cp "$S/.claude/state/must-do-summary.md" "$S/.claude/state/must-do-summary.sessY.md"
R=$(run_pw "$S" "{\"tool_name\":\"Write\",\"session_id\":\"sessY\",\"tool_input\":{\"file_path\":\"$S/src/z.js\"}}"); RC=${R%%::*}
check "AC9b: NEW session gets its own free writes despite shared count=9" "[ \"$RC\" = 0 ]"
rm -rf "$S"

echo "== AC10: space-safe grounding links in build-mustdo-pack =="
S=$(mktemp -d); mkdir -p "$S/docs/must do"; : > "$S/docs/must do/x file.md"
( cd "$S" && bash "$PACK" --own "docs/must do/must-do.md" --no-transcript --session tsess --grounding "docs/must do/x file.md" >/dev/null 2>&1 )
LINKS=$(grep -c '^- \[' "$S/docs/must do/must-do.md" 2>/dev/null)
check "AC10a: grounding path with spaces emits exactly ONE link" "[ \"$LINKS\" = 1 ] && grep -qF '[docs/must do/x file.md](docs/must do/x file.md)' \"$S/docs/must do/must-do.md\""
rm -rf "$S"

echo "== AC7: packet staged trimming (blocks/actions survive the 2000-char cap) =="
# (Added in BUILD iteration 2 after the verifier caught AC7 unimplemented; pre-fix behavior was the
# unconditional hard tail-cut appending the ellipsis marker, which this test forbids.)
S=$(mk_sbx BUILD 1)
mkdir -p "$S/docs/must do"; printf 'docs/ref.md\n' > "$S/docs/must do/must-do.md"; : > "$S/docs/ref.md"
LONG=$(printf 'x%.0s' $(seq 1 700)); printf 'ref.md %s' "$LONG" > "$S/.claude/state/must-do-summary.b4sess.md"
printf 'ref.md %s' "$LONG" > "$S/.claude/state/must-do-summary.md"
printf 'Step 1' > "$S/.claude/state/must-do-summary-step.b4sess.txt"
printf 'Step 1' > "$S/.claude/state/must-do-summary-step.txt"
printf 'FAIL: sandbox failure\n' > "$S/.claude/state/phase-feedback.md"
printf 'fix hint' > "$S/.claude/state/next-fix.md"
printf 'check' > "$S/.claude/state/watcher-self-check.md"
OUT=$( cd "$S" && printf '{"prompt":"hello","session_id":"b4sess"}' | HARNESS_STATE_DIR="$S/.claude/state" HARNESS_REGISTRY="$S/reg.json" bash "$HOME/.claude/hooks/on-prompt-submit.sh" 2>/dev/null )
LEN=${#OUT}
check "AC7a: packet stays within the 2000-char cap" "[ \"$LEN\" -le 2000 ]"
check "AC7b: hard blocks survive (BLOCKED BY present)" "printf '%s' \"\$OUT\" | grep -q 'BLOCKED BY'"
check "AC7c: no hard tail-cut marker (staged trimming sufficed)" "! printf '%s' \"\$OUT\" | grep -q 'â€¦'"
rm -rf "$S"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
