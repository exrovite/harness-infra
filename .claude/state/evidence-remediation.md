# Remediation Plan — Sprint 51 verifier FAIL (AC4 only)

Failed phase/criterion: **AC4 (no Windows-isms)** — post-write-check.sh:158 ships the hardcoded
machine path C:\Users\exrov\.openclaw\watchers\ inside the agent-facing WATCHER SELF-CHECK message
(both live and _install copies). All other criteria (AC1-AC3, AC5-AC7) passed with evidence.

Consulted must-do documents: gentle-mapping-hejlsberg.md (platform-neutral exemption/message
principle), pre-write-gate.sh (the model — its claim instructions already use $HOME-based paths),
pre-bash-gate.sh, on-prompt-submit.sh (tilde/relative path precedent), test-mustdo-default-on.sh
(regression law).

How I will produce the missing evidence:
1. Edit ~/.claude/hooks/post-write-check.sh:158 → `claim a watcher at ~/.openclaw/watchers/`.
2. cp to _install/hooks/post-write-check.sh; `cmp` proves byte parity; `bash -n` both.
3. `grep -rn 'exrov\|[A-Z]:\\' _install/hooks _install/scripts` → zero hits outside comments.
4. Re-run the full 43-suite sweep (message-text change; expect 0 failures).
5. Delete stale verdict, re-run the independent verifier on the AC4 delta → PASS expected.

Failed finding phase fields per the verdict JSON: null (the verdict schema keys findings by
criterion — AC4 — not by phase; noting the literal phase value null here for the gate's
phase-reference check, a schema mismatch worth a future cleanup).
