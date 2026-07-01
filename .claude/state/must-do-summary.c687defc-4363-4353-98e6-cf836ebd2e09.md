# Must-Do Grounding — Sprint 34 (Secret-Safe GLM Add-On)

Session c687defc. Read before BUILD writes.

## Files read
- **gentle-mapping-hejlsberg.md** — the plan that made the must-do system DEFAULT-ON. Key facts I must
  respect: the kill-switch check `if [ -f "${STATE_DIR}/harness-disabled.flag" ]; then exit 0; fi` sits
  at the TOP of every gate (pre-write-gate.sh:13, pre-bash-gate.sh:17, pre-flight-gate.sh:28) so `---`
  always wins; the must-do summary gate is BUILD-scoped; exemptions cover `.claude/state/`,
  `.claude/contracts/`, `.claude/specs/`, `.openclaw/watchers/`, `.agent-memory/`, `.claude/pre-flight/`,
  `agentwiki/`, `.lavish-axi/`, and the no-folder branch adds `docs/` + `*.md`. `_install/*` is kept
  byte-identical to live `~/.claude/*`.
- **_install/hooks/pre-write-gate.sh**, **_install/hooks/pre-bash-gate.sh**,
  **_install/hooks/on-prompt-submit.sh** — the three gate hooks the must-do default-on plan modifies.
  My task does NOT edit these; I must avoid touching them and keep them intact.
- **test-mustdo-default-on.sh** — TDD that drives the LIVE hooks through a `HARNESS_STATE_DIR` sandbox
  and asserts default-on verdicts (block without grounding, kill-switch wins, no deadlock writing the
  must-do file, anti-regression for the folder+summary path).

## Relevance to my CURRENT task
I am adding a GLM install-pack add-on: launcher templates, a marker-gated dual-capable supervisor
(`headroom-supervisor.ps1`/`.sh`), `glm-setup.sh`, an opt-in Step 11 in `install.sh`, `.gitignore`, and
`tests/test-glm-packaging.sh`. This is NEW code under `_install/scripts`, `_install/templates`, and
`tests/` — it does **not** modify the gate hooks above. The grounding confirms: (1) keep `_install` and
live `~/.claude` in parity ONLY for files I actually change (the gate hooks are out of scope), (2) write
my own tests first (TDD) following the sandbox pattern, (3) never commit the z.ai token, (4) the
supervisor must stay byte-equivalent for the no-GLM (no `glm.enabled` marker) path so I don't regress the
8787 compression behavior. No gate-hook edits, no kill-switch changes.