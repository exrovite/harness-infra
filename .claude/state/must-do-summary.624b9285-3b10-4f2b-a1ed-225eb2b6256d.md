# Must-do grounding summary — session 624b9285-3b10-4f2b-a1ed-225eb2b6256d

Task: Sprint 51 — install pack completeness + Linux readiness. Current step: Step 6 (verifier
found ONE defect: hardcoded C:\Users path in post-write-check.sh:158 — fixing it now).

Grounding (all five listed files read in full this session):
- **gentle-mapping-hejlsberg.md** — the exemption-principle design; portability edits must not
  loosen enforcement, only make messages/paths platform-neutral.
- **pre-write-gate.sh** — untouched this sprint; its watcher/cron messages already use $HOME-based
  paths — the model for the post-write-check.sh:158 fix (~/.openclaw/watchers/).
- **pre-bash-gate.sh** — got the .claude/evidence/ bootstrap exemption in sprint 50 iter 3; this
  sprint only CRLF/parity checks (clean).
- **on-prompt-submit.sh** — verified LF + parity; its packet text uses relative/tilde paths (good
  Linux precedent).
- **test-mustdo-default-on.sh** — regression law; the full 43-suite sweep must stay green after the
  post-write-check message fix (it will — message text only).
