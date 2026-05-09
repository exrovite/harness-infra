● The problem:

  Agents currently discover the harness gates by crashing into them one at a time. An agent starts a task, tries to write a file, gets blocked by the
  watcher gate. It claims a watcher, tries again, gets blocked by the contract gate. It writes a contract, tries again, gets blocked by must-do. Each
  block costs a round-trip — the agent reads the error, does the thing, retries. It works, but it burns tokens and turns on what are essentially
  administrative prerequisites that don't need to be discovered through failure.

  Why it matters:

  Not all gates serve the same purpose. Some gates exist to test the agent's understanding — the pre-flight MCQ, the evidence checkpoints, the must-do
  summary. These gates are supposed to block. The block is the point. If you pre-briefed the answers, you'd defeat the purpose.

  But other gates are just administrative setup — claim a watcher, make sure a contract exists for this sprint, read the must-do files. There's no
  evidence value in the agent discovering these by failing. It's just friction.

  The solution:

  Categorise every gate in the pipeline into two buckets:

  1. "Can pre-brief" — administrative prerequisites. Inject these into the turn packet at the start of each phase so the agent handles them proactively
  in one pass. No more bouncing.
  2. "Must block for evidence" — verification gates that prove the agent knows its task, hasn't drifted, and has actually read the required material.
  These stay as hard blocks. The agent still has to earn its way through them.

  The result: agents flow smoothly through the admin setup, then hit the evidence gates cleanly — which do their real job of catching drift and ensuring
  quality. Fewer wasted tokens on admin discovery, same enforcement rigour on the things that matter.


  
  1. Admin gate blocks — currently say "you need X to proceed." You want them to also say "and after you do X, expect Y and Z gates ahead." So the agent
  knows the full road, not just the current wall.
  2. Evidence gate blocks — currently say "prove X." You want them to also say "you're being tested because the harness needs to verify you haven't
  drifted. This is an evidence gate, not an admin gate — you can't shortcut it."
  3. Turn packet at phase start — currently says where you are. You want it to also say "here's the full sequence of gates you'll encounter in this
  phase, in order."

  So every block message becomes a map, not just a stop sign. The agent always knows:
  - What's blocking it right now
  - What to do about it
  - What's coming next after it clears this one
  - Whether the next gates are admin (just do the setup) or evidence (you'll be tested)

  The agent is never surprised. Even when it's stopped by an evidence gate, it expected it. It knew it was coming. It just needs to pass the test.

  The gates stay exactly as hard as they are now — nothing gets weakened. We're just adding forward visibility to every block message so the agent has a
  mental map of the full pipeline at all times.

❯ One more thing. The agent are often complaining when the gates are blocking them form what they regard as a simple task. so we need the gate and turn  
pa cket to highlight that even simple tasks matter that is why they should not assume they can do simple tasks without following the process             
  ⎿  Interrupted · What should Claude do instead?

❯ is this also clear                                                                                                                                     

● Yes, completely clear. The agents rationalise — "this is just a simple edit, I don't need to go through all this." They treat the harness as overhead
  rather than the process. The gates and turn packet need to reinforce that the process applies to everything, not just complex tasks. Simple tasks drift   too. Simple tasks introduce bugs too. The harness exists precisely because agents misjudge what's "simple."

  So the messaging needs to convey: "This isn't slowing you down — this IS the work. Every task, every time, no exceptions."

  Got it. Three things to build:

  1. Forward visibility — every block message includes a map of what's coming next (admin vs evidence gates)
  2. Gate type labelling — each block clearly says "this is an ADMIN gate" or "this is an EVIDENCE gate" so the agent understands why it's being stopped
  3. No-shortcut messaging — turn packet and block messages reinforce that all tasks go through the process, regardless of perceived complexity