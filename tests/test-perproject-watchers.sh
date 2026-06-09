#!/usr/bin/env bash
# Per-project watcher pool TDD: unlimited total watchers, capped 5 PER PROJECT, global-unique slot
# numbers, cross-project independent. Helpers operate on .watchers[] (a dynamic list, not a fixed 5).
# MUST fail before implementation.
set -u
HELPERS="$HOME/.claude/scripts/lib-helpers.sh"
PASS=0; FAIL=0
ok(){ echo "  PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

newreg(){ local d; d=$(mktemp -d); local r="$d/REGISTRY.json"
  printf '{"version":"3.0.0","max_per_project":5,"watchers":[]}' > "$r"; echo "$r"; }
src(){ source "$HELPERS"; }

# 5 per project, 6th refused
t_cap(){
  local R; R=$(newreg)
  ( src
    for i in 1 2 3 4 5; do
      s=$(watcher_claim_pp "sA$i" "g:/projA" "$R")
      [ -n "$s" ] || { echo "claim $i empty"; exit 1; }
    done
    sixth=$(watcher_claim_pp "sA6" "g:/projA" "$R" 2>/dev/null); rc=$?
    [ -z "$sixth" ] && [ "$rc" -ne 0 ] || { echo "6th not refused: '$sixth' rc=$rc"; exit 1; }
    [ "$(jq '[.watchers[] | select(.status=="active")] | length' "$R")" = "5" ] || { echo "not 5 active"; exit 1; }
    true
  ) && ok "t_cap projA gets 5, 6th refused" || no "t_cap"
  rm -rf "$(dirname "$R")"
}
# cross-project independence + unlimited total
t_cross(){
  local R; R=$(newreg)
  ( src
    for i in 1 2 3 4 5; do watcher_claim_pp "sA$i" "g:/projA" "$R" >/dev/null; done
    b=$(watcher_claim_pp "sB1" "g:/projB" "$R")
    [ -n "$b" ] || { echo "projB refused despite own quota"; exit 1; }
    [ "$(jq '[.watchers[] | select(.status=="active")] | length' "$R")" = "6" ] || { echo "total != 6"; exit 1; }
    true
  ) && ok "t_cross projB gets its own slot while projA full; total>5 allowed" || no "t_cross"
  rm -rf "$(dirname "$R")"
}
# per-project count
t_count(){
  local R; R=$(newreg)
  ( src
    watcher_claim_pp s1 "g:/p" "$R" >/dev/null; watcher_claim_pp s2 "g:/p" "$R" >/dev/null
    watcher_claim_pp s3 "g:/other" "$R" >/dev/null
    [ "$(watcher_count_pp "g:/p" "$R")" = "2" ] || { echo "count p != 2"; exit 1; }
    [ "$(watcher_count_pp "g:/other" "$R")" = "1" ] || { echo "count other != 1"; exit 1; }
    true
  ) && ok "t_count per-project active count correct" || no "t_count"
  rm -rf "$(dirname "$R")"
}
# idempotent: same session twice -> same slot, no dup
t_idempotent(){
  local R; R=$(newreg)
  ( src
    a=$(watcher_claim_pp sX "g:/p" "$R"); b=$(watcher_claim_pp sX "g:/p" "$R")
    [ "$a" = "$b" ] || { echo "idempotent slot differs $a/$b"; exit 1; }
    [ "$(jq '[.watchers[] | select(.session_id=="sX")] | length' "$R")" = "1" ] || { echo "dup entry"; exit 1; }
    true
  ) && ok "t_idempotent same session -> same slot, no duplicate" || no "t_idempotent"
  rm -rf "$(dirname "$R")"
}
# release frees the project quota + removes entry
t_release(){
  local R; R=$(newreg)
  ( src
    for i in 1 2 3 4 5; do watcher_claim_pp "sR$i" "g:/p" "$R" >/dev/null; done
    watcher_release_pp "sR3" "$R"
    [ "$(watcher_count_pp "g:/p" "$R")" = "4" ] || { echo "count after release != 4"; exit 1; }
    jq -e '.watchers[] | select(.session_id=="sR3")' "$R" >/dev/null 2>&1 && { echo "sR3 still present"; exit 1; }
    n=$(watcher_claim_pp "sR6" "g:/p" "$R")
    [ -n "$n" ] || { echo "claim after release refused"; exit 1; }
    true
  ) && ok "t_release frees quota + removes entry; re-claim allowed" || no "t_release"
  rm -rf "$(dirname "$R")"
}
# global-unique slot numbers (no two active watchers share a slot number)
t_unique_slots(){
  local R; R=$(newreg)
  ( src
    watcher_claim_pp w1 "g:/pa" "$R" >/dev/null; watcher_claim_pp w2 "g:/pb" "$R" >/dev/null
    watcher_claim_pp w3 "g:/pc" "$R" >/dev/null
    dup=$(jq '[.watchers[] | select(.status=="active") | .slot] | (length) - (unique | length)' "$R")
    [ "$dup" = "0" ] || { echo "duplicate slot numbers: $dup"; exit 1; }
    true
  ) && ok "t_unique_slots active watchers have distinct global slot numbers" || no "t_unique_slots"
  rm -rf "$(dirname "$R")"
}

echo "== Per-project watcher pool TDD =="
t_cap; t_cross; t_count; t_idempotent; t_release; t_unique_slots
echo "-- RESULT: $PASS passed, $FAIL failed --"
[ "$FAIL" -eq 0 ]
