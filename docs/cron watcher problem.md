 Problem 1: Cron interrupts during discussions

  The 3-minute watcher cron fires constantly — even when we're just talking, planning, or reviewing. It butts into the conversation with "WATCHER
  REMINDER" prompts that aren't useful during non-coding phases.

  What you want: A way to pause the cron, with two resume triggers:
  - Time-based: auto-resume after 30 minutes (so it doesn't stay paused forever if forgotten)
  - Activity-based: auto-resume the moment the agent starts actively writing or editing files — because that's when drift prevention actually matters
  This means during PLAN/NEGOTIATE discussions, the cron stays quiet. The second the agent starts BUILD work (Write/Edit calls), the cron kicks back
  in at 3-minute intervals.

  Problem 2: Premature watcher/cron cleanup

  Agents clean up their watcher (release slot, delete cron) after the verifier returns PASS, but before the COMPLETE phase has been properly
  concluded. This creates a catch-22:

  1. Verifier says PASS → agent thinks "done" → releases watcher → deletes cron
  2. But the phase-complete-marker still needs to be written
  3. Write/Edit tools are now locked (no watcher claimed)
  4. Agent can't write the marker → can't transition to COMPLETE
  5. Next sprint inherits stale phase state (still shows BUILD/EVALUATE for sprint N)
  6. This corrupts the next sprint's phase progression

  What you want: A guard that prevents watcher release and cron deletion until the COMPLETE phase has been properly finished. The harness should
  enforce the sequence: verifier PASS → write phase-complete-marker → transition to COMPLETE → then the agent is allowed to release the watcher and
  delete the cron. Not before.

  How they connect

  Both problems are about lifecycle timing. The cron fires too early (during discussion) and stops too early (before completion). The cron should be:  - Silent during planning/discussion (paused)
  - Active during building (auto-resumed on writes)
  - Held until done (can't be deleted until COMPLETE)

❯ Can we also add that the verifier muut pass must also include a reminder about the watcher cron release protocol o the agent is prewarned and not  
surprised by a block it still tries to proceed without following the right proceedure                                                                

● Yes — so the verifier PASS verdict message (injected by the harness) should include a reminder like:

  ▎ "Verifier PASS — DO NOT release watcher or delete cron yet. Complete the COMPLETE phase first: write phase-complete-marker.md, confirm phase
  transition, THEN release watcher and cron."

  This way the agent isn't surprised by the block. It knows the sequence before it tries to clean up. The harness tells the agent what's coming, and
  the guard enforces it if the agent ignores the reminder.

  Three layers:
  1. Soft: reminder in the PASS message (agent sees the protocol)
  2. Hard: guard blocks watcher release / cron delete if phase isn't COMPLETE (enforcement)
  3. Structural: the cron pause system means the cron is already quiet during discussion, so agents don't feel pressure to kill it early

