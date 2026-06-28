#!/bin/bash
# beast-wins-extract.sh — extract USER-VALIDATED wins from transcripts, keyed by transferable concept.
#
# Order-independent co-occurrence (window=2): a USER validation/report marker near a concept term,
# in any order. EXCLUDES compaction summaries, system messages, negations, and contract/plan approvals
# (we capture praise of DONE WORK, never procedural sign-off or instructions). Output is keyed by the
# transferable CONCEPT (e.g. microlabels) so a protocol proven in one module reaches another.
#
# Env: BEAST_WINS_SRC (transcript file or dir), BEAST_CONCEPTS (file: one concept-regex per line),
#      BEAST_WINS_OUT (output jsonl; default <project>/.beast/validated-wins.jsonl). Idempotent.
set -u

SRC="${BEAST_WINS_SRC:-}"
CONF="${BEAST_CONCEPTS:-}"
ROOT="$(pwd -W 2>/dev/null || pwd)"
OUT="${BEAST_WINS_OUT:-$ROOT/.beast/validated-wins.jsonl}"
[ -n "$CONF" ] || CONF="$ROOT/.beast/concepts.txt"
mkdir -p "$(dirname "$OUT")" 2>/dev/null; [ -f "$OUT" ] || : > "$OUT"

FILES=""
if [ -d "$SRC" ]; then FILES="$(find "$SRC" -name '*.jsonl' 2>/dev/null)"; elif [ -f "$SRC" ]; then FILES="$SRC"; fi
[ -n "$FILES" ] || exit 0
[ -f "$CONF" ] || exit 0   # no concepts -> nothing to key on (v1)

TURNS="$(mktemp)"; EMIT="$(mktemp)"
for f in $FILES; do
  jq -rc 'select(.type=="user" or .type=="assistant") |
    (.type)+"\t"+((if (.message.content|type)=="string" then .message.content
      else ([.message.content[]?|select(.type=="text")|.text]|join(" ")) end)
      | gsub("[\n\t]";" ") | gsub("  +";" "))' "$f" 2>/dev/null >> "$TURNS"
done

awk -F'\t' -v CONF="$CONF" '
BEGIN{ IGNORECASE=1; W=2; nc=0
  while((getline line < CONF)>0){ if(line !~ /^[[:space:]]*$/){ concepts[nc]=line; nc++ } }
}
{
  role[NR]=$1; t=$0; sub(/^[^\t]*\t/,"",t); txt[NR]=t; low=tolower(t); isUser=($1=="user")
  noise=(low ~ /this session is being continued|primary request and intent|summary:|stop hook feedback|watcher reminder|system-reminder|caveat:|local-command|reply with exactly the word pong|you are an? |independent verifier|default verdict|your task|in the repo at|currently opt.?in|you are inside|you must read|^\s*-? ?\*\*|stop hook feedback/)
  neg=(low ~ /still (all )?wrong|not work|isn.?t work|doesn.?t work|not right|all wrong|is wrong|not good|didn.?t work|broke|broken|not correct/)
  contract=(low ~ /save the (agreement|contract)|approve the (plan|contract|proposal)|proceed to build|build the contract|yes,? proceed|sign off/)
  pos=(low ~ /worked? (really |very )?well|works well|works now|fixed it|that fixed|solved (it|the)|that.?s (great|perfect|brilliant)|this (is|has) (now )?work|now (work|beautiful)|love (it|this)|well done|amazing|happy with|spot on|fantastic|nailed it|good job|very good (result|output)|much better/)
  rep=(low ~ /(write|create|do|can we (create|do|make|write))[^.]{0,45}report|report (on|of|for|explaining)|how we (have )?(managed|achieved|fixed|got)|write (this )?up (what|how)/)
  if(isUser && !noise && !neg && !contract && (pos||rep)){
    q=txt[NR]; if(length(q)>400) q=substr(q,1,400)
    for(ci=0; ci<nc; ci++){
      cre=tolower(concepts[ci]); hit=0
      for(i=NR; i>NR-W && i>=1; i--){ if(tolower(txt[i]) ~ cre){ hit=1; break } }
      if(hit){ lbl=concepts[ci]; sub(/\|.*/,"",lbl); gsub(/[.?*+()\\[\]]/,"",lbl); print lbl "\t" q }
    }
  }
}' "$TURNS" > "$EMIT"

TAB="$(printf '\t')"
while IFS="$TAB" read -r concept quote || [ -n "$concept" ]; do
  [ -n "$concept" ] || continue
  key="$(printf '%s|%s' "$concept" "$quote" | cksum 2>/dev/null | awk '{print $1"_"$2}')"
  grep -qF "\"k\":\"$key\"" "$OUT" 2>/dev/null && continue
  BC="$concept" BQ="$quote" BK="$key" jq -cn '{concept:$ENV.BC,quote:$ENV.BQ,k:$ENV.BK}' 2>/dev/null >> "$OUT"
done < "$EMIT"
rm -f "$TURNS" "$EMIT"
exit 0
