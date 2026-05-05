# Turn Packet System — Evaluation Criteria

## Spec Quality (PLAN/NEGOTIATE phase)

1. Spec/contract defines what the turn packet contains, not just implementation mechanics.
2. Spec covers ordered actions, hard blockers, exempt paths, watcher context, read-first files, and done criteria.
3. Spec covers all 8+ gate conditions from the existing harness gates.
4. Spec explicitly keeps gates untouched as safety nets.
5. Spec defines token budgets: steady watcher cockpit under 600 chars, full blocked packet under 1500 chars.
6. Spec defines dependency ordering: watcher > cron > contract > must-do > MCQ.
7. Spec addresses the sprint transition deadlock by surfacing missing contract in NEGOTIATE and BUILD.
8. Spec aligns with the courtroom-to-cockpit / turn-kernel shift in `big -harness-fix.md`.

## Implementation Criteria (BUILD phase)

9. Only `on-prompt-submit.sh` and helper additions in `lib-helpers.sh` are modified.
10. Gate scripts are untouched.
11. State summary is always present.
12. Read-first artifacts appear when relevant.
13. Blocked/fresh agents see a numbered action queue in dependency order.
14. Action queue items specify tool and target path.
15. Hard blocks appear as `BLOCKED BY` with resolution.
16. Exempt paths are listed when tools are locked.
17. Watcher cockpit shows current step, scope, mistakes, and done criteria when watcher active.
18. Full packet stays under 1500 chars.
19. Steady watcher packet stays under 600 chars.
20. New packet assembly reads state and exits 0; preserved legacy injection/strategy writes remain allowed.
21. Existing must-do injection/log, evidence checkpoint guidance, and strategy loop behavior are preserved.