RELEVANT: YES

What is relevant: I am claiming a per-project watcher before a multi-step whole-harness audit, exactly as the turn packet instructs.
Why: my own mempalace search confirmed the Sprint 31a per-project pool as the established approach: watcher_claim_pp / watcher_set_cron in lib-helpers.sh, registry v3.0.0, */3 cron recorded on the claimed entry. The surfaced quotes (stale cleaning in untouched projects, per-project pool build goal) describe the same system and do not contradict this.
Intent: claim via watcher_claim_pp for session 624b9285-3b10-4f2b-a1ed-225eb2b6256d, write slot-N.md to-do, CronCreate */3, record via watcher_set_cron; release only at COMPLETE.

INDEPENDENT-CHECK: CONFIRMED - independent headless reviewer (haiku, read-only tools) verified against lib-helpers.sh:1043-1071 and 1084-1093 that the claim+cron procedure matches the code exactly (verdict stored in .claude/state/indep-verdict.txt).
