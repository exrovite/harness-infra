# Sprint 31a — AC1 session_id Probe Findings (2026-06-06)

Method: temporarily instrumented the 3 stdin-reading hooks (on-prompt-submit/pre-write-gate/
post-write-check) + on-session-end to append the raw hook payload to a capture file; triggered events
via an Agent spawn + a sub-agent Write; then reverted all instrumentation (hooks bash -n clean).

## Captured (raw payloads)
- UserPromptSubmit | session_id 520d95ea  (a SECOND, concurrent user session in this folder)
- PreToolUse  Agent | session_id c836c5fa (this/parent session)
- PreToolUse  Write (sub-agent's marker file) | session_id c836c5fa (PARENT)
- PostToolUse Write (sub-agent's marker file) | session_id c836c5fa (PARENT)
All payloads also carried: cwd, transcript_path, hook_event_name, tool_name.

## FINDINGS
1. session_id IS PRESENT in PreToolUse, PostToolUse, UserPromptSubmit (+ cwd, transcript_path).
   => No CLAUDE_SESSION_ID env-var fallback needed for these events.
2. SUB-AGENT TOOL CALLS REPORT THE PARENT session_id (the sub-agent's own Write carried c836c5fa).
   => Sub-agent state writes auto-resolve to the PARENT lane. NO special sub-agent namespacing needed;
      the feared "sub-agent burns a lane / wrong namespace" largely dissolves.
3. A sub-agent does NOT fire its own UserPromptSubmit (the 520d95ea prompt was a real human message
   from a concurrent session). => Sub-agents never CLAIM a lane (claim is at UserPromptSubmit only).
   With (2), sub-agents are TRANSPARENT to the lane system.
4. LIVE CONCURRENCY PROOF: session 520d95ea was active in this same folder during the probe; session_id
   cleanly distinguished it from this session (c836c5fa) — the exact multilane scenario.
5. STOP EVENT NOT CAPTURED (0 for the finished sub-agent). Inconclusive — AC34 build must confirm
   whether real session-end fires on-session-end and carries session_id. If sub-agent end does NOT fire
   Stop, that is GOOD (no spurious parent release).

## DESIGN IMPACT (simplifies 31a)
- Lane claim keyed on session_id at first UserPromptSubmit: CONFIRMED viable.
- resolve_instance keys on .session_id across Pre/Post/UserPromptSubmit: CONFIRMED.
- Sub-agent handling: NO parent->child map needed for tool-call namespacing.
- Only open item: on-session-end firing + session_id for release (AC34) — settle during build.
