# Seven Expert Domains

These are lenses, not modes. Most problems require 2-3 experts combined.

---

## 1. Context Engineer
**Domain**: Prompt design, context window optimisation, instruction architecture, token budget allocation.

### Core Knowledge
- Token budget allocation: System prompt vs conversation history vs tool definitions vs response space
- Instruction hierarchy: Directives (MUST/NEVER) > structured examples > soft constraints
- Progressive disclosure: System prompt (always loaded) vs skills (on-demand) vs file system (retrieved when needed)
- Model-specific prompt adaptation: Claude handles inference. Codex needs decision trees. MiniMax needs checkpoints. Gemma needs anti-commentary + multi-turn format.

### Key Patterns
- Phase-specific instruction loading — agent only sees current phase's instructions
- Handoff artifacts at context boundaries — rich enough for a fresh session to orient
- Anti-commentary directives for Gemma: "CRITICAL JSON OUTPUT RULES" format with numbered rules, capital NO
- Multi-turn format for Gemma: `<start turns>...<end turns>` dramatically improves output consistency

---

## 2. Memory Systems Architect
**Domain**: Information retrieval, knowledge representation, persistence, summary DAG design.

### Core Knowledge
- Three-tier retrieval: File search (recent) -> embeddings (semantic) -> LCM (long-term summary DAG)
- Compaction lifecycle: Bootstrap -> ingest -> afterTurn evaluation -> incremental or full sweep
- Context anxiety vs context saturation — distinct failure modes with different fixes
- Clean context resets vs compaction — compaction preserves continuity but accumulates pollution

### Key Patterns
- State lives in files, not in conversation
- Progress notes (what learned/decided) are distinct from state tracking (where am I)
- Handoff artifact structure: completed features, codebase state, modified files, architectural decisions, known issues, active contract, test status, next steps

---

## 3. Harness Engineer
**Domain**: Agent infrastructure, SDK pipeline, tool design, hook architecture, patch management.

### Core Knowledge
- Hook architecture: scoped to Write/Edit operations only (NOT every tool use)
- Phase transitions are harness-controlled — agent writes marker, harness validates and advances
- The harness decides what the agent sees — loads active-instructions.md, injects known-fixes
- Prompts via file (stdin), not command-line arguments (avoids shell length limits)
- Concurrency protection via lockfile

### Key Patterns
- `run-claude-safe.sh` — retry wrapper with exponential backoff
- `write-handoff.sh` — rich handoff artifact from disk state (git log, file list, decisions, test status)
- `startup-recovery.sh` — detect and recover from hard crashes
- `init-project.sh` — one-command project setup

---

## 4. Reliability Engineer (SRE)
**Domain**: System uptime, fault tolerance, incident response, monitoring, graceful degradation.

### Core Knowledge
- SLI/SLO thinking: What defines "working"
- Incident response: Diagnose -> contain -> fix -> postmortem
- Circuit breaker patterns: Retry logic, dedicated connections, rescue systems
- Budget circuit breaker: time cap + cost estimate cap → hard stop with state save

### Key Patterns
- Telegram polling daemon with heartbeat monitor — harness restarts if dead
- `wait-for-human.sh` with timeout → auto-saves state, generates resume-on-reply script
- `ensure-dev-server.sh` — pre-evaluator health check
- Crash recovery → clean stale artifacts, kill orphaned processes, write fresh handoff

---

## 5. Model Behaviorist
**Domain**: Per-model failure taxonomies, compensation strategies, behavioral profiling, guardrail design.

### Core Principle
**"Model-agnostic" does NOT mean "one size fits all."** It means knowing each model deeply enough to compensate.

### Golden Rule
- Opus trusts inference
- Codex needs decision trees
- MiniMax needs narration + reality checks + anti-drift guardrails
- Gemma needs explicit anti-commentary directives, multi-turn format, and Gemma-optimal parameters

### LLM-Specific Prompt Engineering Protocol
When integrating a new LLM or fixing a broken LLM integration:
1. Audit existing working modules — study successful prompt patterns first
2. Identify artifacts — run the LLM and grep for common artifacts ("Output:", "Response:", code fences)
3. Check parameters — temperature, top_k, repeat_penalty, max_tokens often wrong, not the prompt
4. Multi-turn format — `<start turns>...<end turns>` for Gemma
5. Raw JSON in examples — show without markdown code fences if model emits fences
6. Anti-commentary must be explicit — capital NO, enumerated rules, numbered directives

**Evidence-first**: Always capture raw model output before diagnosing.

---

## 6. Eval & Feedback Loop Architect
**Domain**: Testing agentic systems, contract-first development, harness verification, regression detection.

### Core Knowledge
- Contract-first: Define success criteria BEFORE implementation
- Sub-agent verification: Spawn independent verifiers
- Trace analysis: What sequence of actions led to this outcome?
- Calibration gate: Plant a deliberate failure, verify the verifier catches it

### Key Patterns
- 7-layer verification protocol (evidence-first, structured chain, adversarial framing, calibration, independent env, cross-examination, immutable archive)
- Sprint contracts negotiated between Generator and Evaluator before code
- Evaluator interacts with live output (Playwright, curl), not just reads code
- Evaluator graded on scepticism — default should be to fail if in doubt
- Protocol compliance is a hard evaluation gate (did agent follow process, regardless of code quality)

---

## 7. Skills Architect
**Domain**: Progressive disclosure, model-specific variant design, transformation tools, skill quality.

### Core Knowledge
- Skills are markdown instruction files loaded on-demand, NOT in system prompt
- Model-specific variants: Base SKILL.md targets Opus; SKILL-codex.md and SKILL-minimax.md adapt for other models
- Role-lock pattern: AGENTS.md (functional contract) + SOUL.md (personality contract)

### Key Patterns
- Break skill files into phase-specific chunks for re-injection at transitions
- Never load full 200-line skill — load only current phase's 30-line chunk
- Skill quality measured by protocol fidelity under context pressure

---

## Expert Combination Patterns

| Situation | Experts Combined | Why |
|-----------|-----------------|-----|
| Model generates XML instead of tool_use | Model Behaviorist + Harness Engineer | Classify failure, then fix SDK pipeline |
| Agent forgets context after long session | Memory Architect + Context Engineer | Check compaction, then optimise what survives |
| New skill needs multi-model support | Skills Architect + Model Behaviorist + Context Engineer | Design base, generate variants with guardrails |
| Auth failures after update | Reliability Engineer + Harness Engineer | Incident response, then restore patches |
| Building test harness for a change | Eval Architect + domain expert | Contract-first, then domain-specific verification |
| LLM generates preamble instead of clean output | Model Behaviorist + Context Engineer | Identify model-specific anti-pattern, compensate |
| Integrating a new LLM into pipeline | Model Behaviorist + Harness Engineer + Context Engineer | Profile failure modes, define prompt patterns, verify |
| Agent stuck in negative loop | Harness Engineer + Reliability Engineer | Loop detector blocks, known-fix injection or escalation |
| Phase transition failing validation | Harness Engineer + Eval Architect | Check deterministic guards, fix validation script |
| Protocol fidelity degrading mid-session | Context Engineer + Memory Architect + Skills Architect | Progressive disclosure, phase re-injection, checkpoint files |
