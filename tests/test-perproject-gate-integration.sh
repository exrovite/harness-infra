#!/usr/bin/env bash
# Sprint 31a — per-project watcher pool, GATE-level integration.
# Proves: a brand-new project is NOT blocked just because the GLOBAL pool is "full" under the old
# 5-slot model. The gate's per-project COUNT (the exact jq from pre-write-gate.sh) sees 0 for the new
# project, the claim helper grants it its OWN slot, and the count then flips to 1 (gate would allow).
# Also proves a single project is still capped at 5 of its own.
set -u
HELPERS="$HOME/.claude/scripts/lib-helpers.sh"
GATE="$HOME/.claude/hooks/pre-write-gate.sh"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# The EXACT per-project active-count expression the gate uses (kept in sync with pre-write-gate.sh).
gate_count(){ # $1 registry  $2 normalized-project
  jq --arg proj "$2" \
    '[.watchers[] | select(.status == "active" and .project != null and ((.project | gsub("\\\\";"/") | sub("/$";"") | ascii_downcase) == $proj))] | length' \
    "$1" 2>/dev/null | tr -d '\r'
}
norm(){ printf '%s' "$1" | tr '\\\\' '/' | sed 's|/$||' | tr '[:upper:]' '[:lower:]'; }

D=$(mktemp -d); R="$D/REGISTRY.json"
printf '{"version":"3.0.0","max_per_project":5,"watchers":[]}' > "$R"

# Fill the GLOBAL pool with 5 active watchers across 5 DIFFERENT projects (old model = exhausted).
source "$HELPERS"
for i in 1 2 3 4 5; do watcher_claim_pp "sess$i" "g:/proj$i" "$R" >/dev/null; done
TOTAL=$(jq '[.watchers[]|select(.status=="active")]|length' "$R")
[ "$TOTAL" = "5" ] && ok "5 active watchers across 5 projects (global pool 'full' under old model)" || no "setup total=$TOTAL"

# A brand-new project: gate count must be 0 (=> gate blocks-to-claim, does NOT report 'no slots').
NEWP="g:/brand-new-project"
C=$(gate_count "$R" "$(norm "$NEWP")")
[ "$C" = "0" ] && ok "gate sees 0 watchers for brand-new project (would prompt a claim, not 'pool full')" || no "new-project count=$C"

# The new project claims its OWN watcher despite the global pool being 'full'.
S=$(watcher_claim_pp "sessNEW" "$NEWP" "$R")
[ -n "$S" ] && ok "brand-new project claims its own slot ($S) though 5 others are active" || no "new-project claim refused"

# Gate count now flips to 1 => gate would ALLOW writes for this project.
C2=$(gate_count "$R" "$(norm "$NEWP")")
[ "$C2" = "1" ] && ok "gate count flips to 1 after claim (gate would allow)" || no "post-claim count=$C2"

# Total is now 6 — proves NO global cap.
T2=$(jq '[.watchers[]|select(.status=="active")]|length' "$R")
[ "$T2" = "6" ] && ok "total active = 6 (no global cap)" || no "total after new claim=$T2"

# Single project still capped at 5 of its own.
CAPP="g:/cap-test"
for i in 1 2 3 4 5; do watcher_claim_pp "cap$i" "$CAPP" "$R" >/dev/null; done
sixth=$(watcher_claim_pp "cap6" "$CAPP" "$R" 2>/dev/null); rc=$?
{ [ -z "$sixth" ] && [ "$rc" -ne 0 ] && [ "$(gate_count "$R" "$(norm "$CAPP")")" = "5" ]; } \
  && ok "single project still capped at 5 of its own (6th refused)" || no "cap not enforced sixth='$sixth' rc=$rc"

# The live gate source actually instructs watcher_claim_pp (not the old fixed-index jq).
grep -q 'watcher_claim_pp' "$GATE" && ! grep -q 'watchers\[\[N\]-1\]' "$GATE" \
  && ok "pre-write-gate.sh block instructs watcher_claim_pp (old fixed-index jq removed)" \
  || no "gate still references old fixed-index claim"

rm -rf "$D"
echo "-- RESULT: $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
