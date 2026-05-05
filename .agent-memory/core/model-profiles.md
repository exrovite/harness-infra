# Model Profiles — Failure Taxonomies & Compensation

## Governing Principle
**"Model-agnostic" does NOT mean "one size fits all."** It means knowing each model deeply enough to compensate for its specific failure patterns. Every model has a documented failure taxonomy. Every failure has a proven compensation strategy.

---

## Claude Opus 4.6

**Strengths**: Excellent inference, nuance, multi-step reasoning, long context, tool use.
**Skill Variant**: Base (SKILL.md) — trust the model to infer intent.
**Role in Harness**: Primary reasoning, planning, complex tasks.
**Known Weaknesses**: Context anxiety at extreme lengths (largely resolved in 4.6), can be overly agreeable.

### Compensation
- Trust inference — don't over-specify
- For long sessions, use clean context resets with handoff artifacts at sprint boundaries
- Automatic compaction handles most within-sprint context management

---

## GPT-5.4 / Codex — 11 Failure Patterns

**Strengths**: Literal execution, browser automation, fast.
**Skill Variant**: SKILL-codex.md — explicit decision trees.
**Role in Harness**: Browser automation, literal execution tasks.

| # | Pattern | Compensation |
|---|---------|--------------|
| 1 | Inference failure | Explicit decision trees with IF/ELSE/THEN |
| 2 | Hidden prerequisites | Make ALL prerequisites explicit — checklist at top |
| 3 | Unverified actions | "VERIFY after every action" loops |
| 4 | Format ambiguity | Define exact output formats — JSON/XML templates |
| 5 | Error improvisation | "ON ERROR:" playbooks per error type |
| 6 | Missing done criteria | Numbered completion checklist |
| 7 | Wrong identity | Replace all Opus references with Codex |
| 8 | Non-literal execution | Numbered steps, MUST/NEVER/ALWAYS |
| 9 | Context loss | Recap at section starts |
| 10 | Proactive deviation | Direct imperatives only |
| 11 | Delegation confusion | Explicit agent delegation map |

---

## MiniMax M2.7 — 12 Failure Patterns

**Strengths**: Cheap, no rate limits, good for summarisation.
**Skill Variant**: SKILL-minimax.md — narration + checkpoints.
**Role in Harness**: Summarisation, cheap processing tasks.

| # | Pattern | Compensation |
|---|---------|--------------|
| F1 | Memory drift | Version Lock Checkpoint at top |
| F2 | Section/target drift | Pre-Click Targeting Checklist |
| F3 | Silent operation | Forced Narration Points (every 30s / 3rd action) |
| F4 | Premature conclusions | Minimum Effort Rule (explicit counts) |
| F5 | Step skipping | Mandatory Step Checklist with gate |
| F6 | Wrong mental model | Reality Check Protocol |
| F7 | Stale reference issues | Fresh Snapshot Rule after EVERY navigation |
| F8 | Tracking/logging gaps | Pre-Flight Data Check (init all files at start) |
| F9 | Scope confusion | Scope Lock section ("This skill IS / is NOT") |
| F10 | Pipeline stage confusion | Stage Map table |
| F11 | Autonomous override failure | Override Banner at top |
| F12 | Old data / stale state | State Freshness Check |

---

## Gemma 3 4B — 6 Failure Patterns

**Strengths**: Local, no API costs, good for structured content generation when properly tuned.
**Context**: Used as reasoning/NL-to-action model in PCW orchestrator and primary content generation across PCW modules.
**Role in Harness**: Local content generation, NL routing.

| # | Pattern | Compensation |
|---|---------|--------------|
| G1 | **JSON Preamble** — prepends "Output:", "Response:", "Here is the JSON:", "**JSON**:" | Strong anti-commentary directive + GemmaResponseParser post-hoc cleanup |
| G2 | **Apostrophe corruption** — repeats apostrophes (e.g., "don&apos;t") | `repeat_penalty=1.0` |
| G3 | **Truncation** — stops generating mid-JSON at token limits | `max_tokens=2000` (not 500) |
| G4 | **Over-caution** — temperature 0.3 makes Gemma too conservative for structured JSON | `temperature=1.0` |
| G5 | **JSON in markdown** — emits ` ```json ` code fences in JSON output | Show raw JSON in prompt examples, not markdown code blocks |
| G6 | **Inconsistent format** — each response formatted differently | Multi-turn `<start turns>...<end turns>` format locks behavior |

### Gemma 3 4B Optimal Parameters

```python
{
    "temperature": 1.0,        # NOT 0.3 — Gemma needs creative freedom for JSON
    "top_k": 64,               # Optimal for Gemma model family
    "repeat_penalty": 1.0,     # Fixes apostrophe repetition corruption
    "max_tokens": 2000,        # NOT 500 — complex orchestration needs room
    "top_p": 0.95,
    "typical_p": 1.0,
    "presence_penalty": 0.0,
    "frequency_penalty": 1.0,
}
```

### Gemma-Specific Anti-Commentary Directive (Minimum Viable)

```
CRITICAL JSON OUTPUT RULES — FOLLOW EXACTLY:
1. Output ONLY valid JSON. Nothing else.
2. Start your response EXACTLY with the character '{' — write nothing before it
3. Do NOT write: "Output:", "Response:", "Here is the JSON:", "```json", "**JSON**", or any other preamble
4. Do NOT include explanations, notes, or commentary — Output ONLY the JSON
5. The JSON must be complete and valid — do not truncate it
```

### Multi-Turn Format (Gemma-Specific)

```
<start turns>
User: "Write 5 headlines about stress management"
Assistant: {"headlines": ["Headline 1", "Headline 2", ...]}
<end turns>

Write content for this NEW topic (DO NOT use any content from the examples above):
Topic: [current topic]
```

---

## Model Selection Decision Matrix

| Task Type | Best Model | Why |
|-----------|-----------|-----|
| Complex reasoning, planning | Opus 4.6 | Strongest inference |
| Sub-agent delegation | Sonnet 4.6 | Fast, cheap, good enough |
| Browser automation | Codex/GPT-5.4 | Literal execution |
| Summarisation | MiniMax M2.7 | Cheap, no rate limits |
| Multi-model debate | All four (council) | Diverse perspectives |
| Quick experiments | DeepSeek V3.2 | Fast, free, local |
| Creative research | Gemini 3 Pro | Different perspective |
| Local content generation | Gemma 3 4B | No API costs, good when properly tuned |

---

## Adding New Model Profiles

When a new model is introduced to the fleet:

1. **Run it on known-failure test cases** from each existing model's taxonomy
2. **Document every failure pattern** with: symptom, root cause, compensation
3. **Create a skill variant** (SKILL-[model].md) with compensations baked in
4. **Add to this file** with full failure table
5. **Update the selection matrix** with the model's strengths
6. **Test compensations** with evidence-first protocol — raw output before/after

The harness's three-layer model means a new model only needs a Layer 3 profile. Layers 1 and 2 (scripts and guards) are model-agnostic — they check files, exit codes, and git diffs, not model output.
