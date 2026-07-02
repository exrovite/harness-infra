# Evaluation Criteria — Sprint 50 (fix all audit findings)

Source of findings: `.claude/reports/audit-2026-07-01-remaining-problems.md`.
All criteria are binary. The independent verifier defaults to FAIL and must cite evidence
(file:line or command output) per criterion.

## Acceptance criteria

- **AC1 (A1)** pre-write-gate watcher admin lock: with write-count ≥2 and NO watcher, (a) a Write to
  `.claude/state/x.md` is ALLOWED, (b) tool_name=Agent is ALLOWED, (c) a Write to `src/x.js` is
  still BLOCKED (exit 2). Same allowance via pre-bash-gate for `.claude/state/` commands (already
  exempt — must remain so).
- **AC2 (A3)** must-do summary gate: with a must-do folder present and NO summary lane, tool_name=
  Agent (empty file_path) is ALLOWED; a source Write is still BLOCKED naming the caller's own lane.
- **AC3 (A2)** beast-protocol-gate: a read-only Bash command (`wc -l <file-with-concept-name>`) is
  ALLOWED with no ack on file; a Bash command WRITING a source file whose text touches a validated
  concept is still BLOCKED without an ack; a Bash command writing `protocol-ack.*` or a
  `.claude/state/` path is ALLOWED without an ack (no self-deadlock).
- **AC4 (B1)** `.claude/evidence/` present in the exemption lists of: pre-write-gate phase gate,
  strategy-loop gate, must-do ownership + summary lists, default-on list; and pre-flight-gate
  feedback list. A Write to `.claude/evidence/x.json` in EVALUATE phase is ALLOWED.
- **AC5 (B2)** pre-bash-gate detects as file-writing: `echo x >> f.js`, `dd of=f.js`,
  `git apply p.patch`, `patch -p1 < p.patch`, `perl -e 'open(...)'`. Existing detections unchanged.
- **AC6 (B3)** generate-pre-flight-challenge: challenge.md contains NO `*_correct_label` /
  `q5_yes_label` metadata; labels live in a sidecar file consumed by validate-pre-flight; validation
  still passes correct answers and fails wrong ones. Distractors that occur verbatim in the
  question's own source file are rejected during generation.
- **AC7 (B4)** on-prompt-submit: when the assembled packet exceeds the cap, the MUST-DO summary and
  WARNINGS sections are dropped/shortened FIRST; ACTIONS and BLOCKED BY survive intact for packets
  up to the cap; hard truncation remains as last resort.
- **AC8 (C3)** validate-pre-flight: when `no_verify_count` reaches 5, `last_reset` is stamped and a
  subsequent Q5=No answer FAILS validation until a ledger entry newer than `last_reset` exists.
- **AC9 (A5)** write counter is per-session (`write-count.<session_id>.txt`) when a session id is
  present (fallback: shared file). post-write-check increments the per-session counter; both gates
  and the packet read it. A NEW session id starts with its own 2 free writes.
- **AC10 (C4/C5)** build-mustdo-pack grounding loop handles paths with spaces (a grounding entry
  `docs/must do/x.md` emits ONE link line); startup-recovery slot loop uses read -r (no unquoted
  word-splitting of jq output).
- **AC11 (D1)** beast-wins-extract: quotes that are report/summary requests (e.g. contain "report")
  or that do NOT contain the concept token are excluded; regenerated `.beast/validated-wins.jsonl`
  contains no such entries; at least one genuine win survives (or the file is empty — acceptable).
- **AC12 (C1/E4)** REGISTRY.json contains no `.instances` array, no `max_lanes_per_project`, and no
  placeholder `available` watcher entries; the live claim/reap flow still works (claim → slot,
  reap → removal).
- **AC13 (E1/E2/E3)** `current-phase.json` reflects the real sprint; stale artifacts (test-backups,
  Apr–Jun evaluation leftovers, dead session lanes) are archived under `.claude/state/archive/` or
  deleted; `backlog.json` and `knowledge-gaps.json` regenerated to reflect reality (scripts built).
- **AC14** every changed hook/script is byte-identical between live `~/.claude/` and `_install/`;
  `bash -n` clean on all changed files.
- **AC15** TDD: `tests/test-audit-fixes-sprint50.sh` exists, covers AC1-AC9, and demonstrably FAILED
  before the fixes (failure run captured in `.claude/evidence/sprint50-tdd-red.txt`).
- **AC16** FULL regression: every `tests/test-*.sh` runs; zero NEW failures vs the pre-sprint
  baseline (baseline captured first to `.claude/evidence/sprint50-baseline.txt`).
- **AC17 (beast works)** beast-mode functional: `beast-surface.sh` still surfaces a matching lesson
  for a triggering action; beast toggle truth table suite green; beast-protocol-gate suite green
  with the new read-only exemption; recall remains inject-only.
- **AC18** dispositions documented in the sprint report for: A6, audit-C2 phantom crons, B5
  fallback, cron_pause churn, D3/D4/D6/D8 backlog.
