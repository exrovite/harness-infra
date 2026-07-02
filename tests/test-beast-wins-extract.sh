#!/bin/bash
# test-beast-wins-extract.sh — validated-wins extractor.
# Order-independent co-occurrence of (concept + user-validation/report), with exclusions
# (compaction summaries, system msgs, negations, contract/plan approvals). Output keyed by concept.
set -u
EX="$HOME/.claude/scripts/beast-wins-extract.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
SBX=$(mktemp -d 2>/dev/null || echo "/tmp/bwe-$$")
trap 'rm -rf "$SBX" 2>/dev/null' EXIT

# fixture transcript with: a real validated win, a negation, a summary, a contract-approval, an instruction
TR="$SBX/t.jsonl"
cat > "$TR" <<'EOF'
{"type":"user","message":{"content":"lets work on the microlabels in the bullet module"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Done — adjusted the microlabels."}]}}
{"type":"user","message":{"content":"the microlabels worked really well now, much better output"}}
{"type":"user","message":{"content":"the microlabels are still all wrong, broken output"}}
{"type":"user","message":{"content":"This session is being continued from a previous conversation. Summary: microlabels worked well earlier"}}
{"type":"user","message":{"content":"this is correct, please save the agreement and proceed to build the contract"}}
{"type":"user","message":{"content":"write a perfect microlabels prompt exactly like this"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"thinking budget bumped for the headline module."}]}}
{"type":"user","message":{"content":"can you write a report on how the thinking budget fix worked for headlines"}}
EOF
CON="$SBX/concepts.txt"
printf 'micro.?label\nthinking.?budget|thinking budget\n' > "$CON"
OUT="$SBX/wins.jsonl"

[ -f "$EX" ] || { bad "extractor exists at $EX"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
ok "extractor exists"

BEAST_WINS_SRC="$TR" BEAST_CONCEPTS="$CON" BEAST_WINS_OUT="$OUT" bash "$EX" >/dev/null 2>&1
[ -f "$OUT" ] && ok "produced validated-wins.jsonl" || { bad "no output"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

# every line schema-valid
SCH=1; while IFS= read -r l || [ -n "$l" ]; do [ -z "$l" ] && continue
  printf '%s' "$l" | jq -e 'has("concept") and has("quote") and (.quote|length>0)' >/dev/null 2>&1 || SCH=0; done < "$OUT"
[ "$SCH" = 1 ] && ok "all wins schema-valid" || bad "schema"

# 1. the REAL validated win is captured (microlabels worked well)
grep -q 'worked really well' "$OUT" && ok "captures real validation (worked really well)" || bad "missing real win"
# 2. Sprint 50 (audit D1): a report REQUEST is NOT a validation — it must be EXCLUDED. (This
# assertion previously required capturing it; that behavior filled the wins store with "please
# write a report" prompts that fired the protocol gate on irrelevant work.)
grep -qi 'report on how the thinking budget' "$OUT" && bad "report-request wrongly captured as a win" || ok "report-request excluded from wins"
# 3. NEGATION excluded
grep -q 'still all wrong' "$OUT" && bad "negation must be excluded" || ok "negation excluded"
# 4. compaction SUMMARY excluded
grep -q 'session is being continued' "$OUT" && bad "summary must be excluded" || ok "summary excluded"
# 5. CONTRACT/plan approval excluded
grep -q 'save the agreement' "$OUT" && bad "contract-approval must be excluded" || ok "contract-approval excluded"
# 6. INSTRUCTION-with-positive-word excluded
grep -q 'write a perfect microlabels prompt' "$OUT" && bad "instruction must be excluded" || ok "instruction excluded"
# 7. wins are keyed by concept (microlabels appears as a concept)
grep -q '"concept":"[^"]*micro' "$OUT" && ok "keyed by concept (microlabels)" || bad "concept key (got: $(head -1 "$OUT"))"

# 8. idempotent (re-run -> no duplicate lines)
N=$(wc -l < "$OUT"); BEAST_WINS_SRC="$TR" BEAST_CONCEPTS="$CON" BEAST_WINS_OUT="$OUT" bash "$EX" >/dev/null 2>&1
N2=$(wc -l < "$OUT"); [ "$N" = "$N2" ] && ok "idempotent ($N==$N2)" || bad "idempotent ($N->$N2)"

bash -n "$EX" 2>/dev/null && ok "bash -n clean" || bad "bash -n"
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
