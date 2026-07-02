# Must-do grounding summary — session 624b9285-3b10-4f2b-a1ed-225eb2b6256d

Task: Sprint 50 — fix ALL audit findings. Current step: Step 3 (TDD tests first — must fail —
then fix deadlock cluster A1/A3/A4 + B1 exemptions).

Grounding (all five listed files read in full this session), applied to the CURRENT step:

- **gentle-mapping-hejlsberg.md** — the default-on design and its no-deadlock exemption principle
  (docs/, *.md, .claude/state/). My A1/A3/B1 fixes extend exactly this principle to the watcher
  admin lock, the Agent tool, and `.claude/evidence/` — same intent, consistently applied.
- **pre-write-gate.sh** — I am editing: the watcher admin lock (~:868-935, add state-path + Agent
  exemptions), the must-do summary gate (~:462-471, exempt empty target/Agent), and the exemption
  lists at :185/:282/:441/:464/:628/:666 (+ .claude/evidence/). TDD sandboxes drive this live hook
  via HARNESS_STATE_DIR + HARNESS_REGISTRY, per the test-mustdo-default-on.sh pattern.
- **pre-bash-gate.sh** — I am editing WRITES_FILES detection (add >>, dd of=, git apply, patch,
  perl -e) without breaking the bootstrap path exemptions at :225-231, and reading its per-session
  counter once AC9 lands.
- **on-prompt-submit.sh** — packet assembly + 2000-char cap (~:987): staged trimming so BLOCKS and
  ACTIONS survive; per-session write-count read; must keep kill-switch/+++pack/ralph handling
  byte-compatible otherwise.
- **test-mustdo-default-on.sh** — the sandbox test pattern (mk_sbx, run_write payloads, exit-code
  checks) my new tests/test-audit-fixes-sprint50.sh follows; it is also regression law: my gate
  edits must keep this suite green.
