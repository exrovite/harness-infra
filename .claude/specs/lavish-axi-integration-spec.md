# Spec — lavish-axi Harness Integration (Sprint 32)

## Goal
Make lavish-axi (local-first human↔agent HTML-artifact feedback loop) a first-class part of
the Enhanced Agent Harness: available to ALL agents and ALL projects, shipped in `_install` so it
deploys with our (private) products. Combine the MIT-licensed lavish-axi into our harness while
retaining its license notices.

## User decisions (locked)
- **Install vector:** npm global, pinned (`lavish-axi@0.1.20`).
- **Activation:** always-on `SessionStart` ambient-context hook.
- **Integration depth:** full harness-native (skill, gate exemptions, cron-pause during poll,
  independent validation).

## What it must do (capabilities, not implementation)
1. **Install** — a fresh harness install (`bash _install/install.sh`) installs lavish-axi globally at
   the pinned version and wires its always-on `SessionStart` hook, without breaking if npm/node is
   absent (warn + continue, harness still works).
2. **Always-on ambient context** — every agent session receives lavish's SessionStart context,
   coexisting with the existing Pre/PostToolUse, Stop, and UserPromptSubmit harness hooks (no clobber).
3. **Agents can invoke it the harness way** — a skill that opens/ensures a lavish session for an HTML
   artifact and blocks for human feedback, returning that feedback to the agent.
4. **Lavish's own writes never trip our gates** — `.lavish-axi/` is exempt from pre-write, pre-bash,
   and pre-flight gates (like `.claude/state/`, `agentwiki/`).
5. **Long human-feedback waits don't look like drift** — while blocked polling for feedback, the 3-min
   watcher cron is paused, then resumed.
6. **License compliance** — lavish-axi's and axi-sdk-js's MIT notices are retained in our distribution.
7. **No regression** — every existing harness ability (gates, watcher pool, phases, ralph, evidence)
   keeps working exactly as before.

## Non-goals
- Modifying lavish-axi's own source/behavior.
- Cloud/multi-user features (lavish is local-first by design).
- Replacing our text-based human escalation (`wait-for-human`) — lavish complements it for HTML.

## Success = evaluation criteria
See `.claude/specs/evaluation-criteria.md` and the sprint-32 contract. Independent validator must
confirm: install wiring correct + idempotent, SessionStart coexists, `.lavish-axi/` exempt across all
gate lists, skill works end-to-end (sandbox), cron-pause around poll, MIT notices present, full
regression green, zero bugs.
