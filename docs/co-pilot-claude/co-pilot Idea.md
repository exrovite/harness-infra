  The Problem:                                                                                                                                         You have an agent working on a task. There's one or two specific instructions it keeps forgetting — not all the time, just periodically. It drifts.
   You're currently the human safety net: you sit watching the Claude Code terminal output in VS Code, and when you spot the agent making that         mistake again, you manually type in a correction ("you forgot to do X") and hit enter so it course-corrects.

  This works, but it requires you to babysit the terminal. You want to automate yourself out of that loop.

  The Solution You Want:
  A second Claude Code instance (or a script-driven system) that acts as a live monitor / co-pilot. Specifically:

  1. It reads the same output stream you're reading — the running Claude Code CLI's terminal output, in real-time
  2. It has a small set of watch-rules — the specific instructions the agent keeps forgetting (e.g., "always run tests after edits", "never skip the
  summary step")
  3. When it detects the agent is about to omit or has omitted one of those steps, it injects a message into the CLI — exactly like you would by
  typing into the terminal
  4. Then it types "continue" (or equivalent) so the working agent picks up the correction and course-corrects on its own

  Essentially: an automated supervisor that reads the agent's output stream, pattern-matches against known drift behaviors, and steers it back by
  injecting prompts through the same CLI interface you use.

  The key constraint is that this isn't a hook or a gate — it's a real-time stream watcher that intervenes mid-conversation the same way a human
  operator would.

  Is that accurate, or am I missing a piece?