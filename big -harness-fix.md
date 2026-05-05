● This is the core insight. Let me state it back clearly.
                                      
  ---
  The Problem With Our Harness                                                                                                
  Our harness is a courtroom. The agent acts, gets blocked, reads an error message, adapts, tries again, gets blocked again   somewhere else. The flow is:                                   

  Agent thinks → Agent acts → Hook blocks → Agent reads stderr → Agent adapts → Agent retries

  Every gate we built — pre-write, pre-bash, pre-flight MCQ, must-do summary, evidence checkpoint, strategy loop, contract
  gate, phase-feedback block — is a cop at the end of a road the agent has already turned down.

  The agent doesn't know it's wrong until it's already tried. Then it spends tokens recovering. Then it hits the next gate.   Then it recovers again. Across 626 writes and 19 sprints, the agent has been fighting the harness more than building the   product.

  What The Turn Kernel Concept Says

  Flip the relationship. Instead of the agent discovering rules by hitting blocks:

  Kernel prepares full context → Agent thinks inside correct frame → Agent acts correctly → Hooks verify (rarely block)

  The on-prompt-submit.sh hook we have is a primitive version of this — it injects a one-line status. But one line of
  [HARNESS STATE] Phase: BUILD | Sprint: 19 | Watcher: NOT CLAIMED doesn't tell the agent:

  - What it needs to do before it can write (claim watcher, write contract, pass MCQ)
  - What paths are exempt and what paths will be blocked
  - What files it needs to read first (must-do, reference docs)
  - What the current step is and what "done" looks like
  - What actions are available vs. what will definitely fail

  The agent has to discover all of that by trial and error against our gates.

  How This Relates To Us Specifically

  Our harness has ~8 independent gates that can block, each with its own exemption logic, its own error message, and its
  own resolution path. An agent entering a fresh session has to navigate:

  1. Watcher claim (pre-write-gate)
  2. Cron reminder (pre-write-gate)
  3. Phase compliance (pre-write-gate)
  4. Contract existence (pre-write-gate)
  5. Phase-feedback FAIL clear (pre-flight-gate)
  6. Must-do summary written (pre-write-gate)
  7. Evidence checkpoint clear (pre-write-gate)
  8. Pre-flight MCQ passed (pre-flight-gate)

  If the agent doesn't know the order and dependencies between these, it bounces from block to block. We've seen this — the   sprint transition deadlock was exactly this: three gates creating a cycle because none of them told the agent what to do   first.

  The Shift

  The Turn Kernel idea applied to our harness means: on-prompt-submit.sh should assemble a complete "turn packet" — not
  just status, but a sequenced action list. Before the agent does anything, it should see something like:

  [TURN PACKET] Phase: BUILD | Sprint: 19
  BEFORE YOU CAN WRITE CODE:
    1. Claim watcher slot (Bash: jq update REGISTRY.json)
    2. Start 3-min cron (CronCreate */3 * * * *)
    3. Read sprint-19-contract.md
    4. Read must-do files and write summary to .claude/state/must-do-summary.md
    5. Then your Write/Edit tools unlock.
  EXEMPT PATHS (always writable): .claude/state/, .openclaw/watchers/, .claude/contracts/, .claude/specs/, .agent-memory/
  CURRENT STEP: [from watcher slot]
  BLOCKED BY: [nothing / phase-feedback FAIL / evidence checkpoint pending / strategy loop]

  The gates stay as safety nets — but they almost never fire because the agent already knows the correct path.

  The gates become guardrails on a road the agent is already driving correctly, not roadblocks on a road the agent is
  driving blind.
