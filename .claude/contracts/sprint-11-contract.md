# Sprint 11 Contract: Codex CLI Harness Integration

## Scope
Research, evaluate, and deploy an enforcement/orchestration layer for OpenAI Codex CLI on Windows, bringing it under structured control comparable to Claude Code's harness.

## Deliverables
1. Research report on Codex hook system, Windows limitations, and community solutions
2. Evaluation of enforcement approaches (hooks, WSL, plugin, MCP, wrapper scripts, OMX)
3. Installation and configuration of chosen solution (oh-my-codex + psmux)
4. Verification that Codex runs with OMX orchestration on Windows
5. Written report documenting everything built, how to use it, and future work

## Success Criteria
- [ ] Codex CLI confirmed working with OMX on Windows
- [ ] `omx doctor` passes
- [ ] psmux installed for Windows team support
- [ ] AGENTS.md generated and loaded by Codex
- [ ] Report written documenting architecture, usage, and comparison to Claude Code harness
- [ ] No Claude tokens required for Codex runtime operation

## Out of Scope
- Customizing AGENTS.md with full harness protocol (future sprint)
- Building per-project `.codex/AGENTS.md` templates (future sprint)
- Building a wrapper script for outer-loop control (future sprint)
