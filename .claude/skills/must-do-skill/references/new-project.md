# New Project Mode — Analysis Procedure

## Step 1: Gather Task Context

Read these files if they exist:
- `CLAUDE.md` — project instructions
- `.claude/state/active-instructions.md` — current task
- `.claude/specs/product-spec.md` — if a spec was written
- `.claude/contracts/` — any sprint contracts
- `package.json` / `requirements.txt` / `Cargo.toml` / `go.mod` — dependencies and project type
- `README.md` — project overview

If none of these exist, use the user's task description as the sole context source.

## Step 2: Scan Codebase Structure

Map the file tree (top 3 levels is usually sufficient). Identify:

| Category | What to Look For |
|----------|-----------------|
| Entry points | `main.*`, `app.*`, `index.*`, `server.*` |
| Config | `.*rc`, `*.config.*`, `.env.example`, `tsconfig.*` |
| Architecture | `src/`, `lib/`, `internal/`, `pkg/` structure |
| Tests | `test/`, `tests/`, `__tests__/`, `*_test.*`, `*.test.*` |
| Docs | `docs/`, `*.md` files |
| CI/CD | `.github/`, `.gitlab-ci.*`, `Jenkinsfile` |
| Database | `migrations/`, `prisma/`, `*.sql` |

## Step 3: Suggest Existing Files

Based on task type, suggest files the agent must read:

| Task Type | Must-Read Files |
|-----------|----------------|
| Feature implementation | Entry points, relevant module files, test patterns, config |
| Bug fix | Error logs, related module, test files for that module |
| Refactoring | Architecture docs, module boundaries, all test files |
| API work | Route definitions, middleware, auth config, API docs |
| Frontend | Component structure, state management, design system, routing |
| Database | Schema, migrations, ORM config, seed files |
| DevOps | CI config, deploy scripts, env templates, Dockerfiles |

**Rule**: Only suggest files that actually exist. Don't list aspirational paths.

## Step 4: Identify Gaps

For each task type, check whether these supporting files exist. If missing, flag them as candidates for creation:

| Gap | File to Create | When It Matters |
|-----|---------------|-----------------|
| No architecture documentation | `docs/architecture.md` | Multi-module projects, complex systems |
| No testing conventions | `docs/testing-conventions.md` | All projects with tests |
| No environment setup | `docs/setup.md` | Projects with non-trivial config |
| No API design doc | `docs/api-design.md` | API work, backend projects |
| No coding conventions | `docs/conventions.md` | Team projects, multi-contributor |
| No failure mode notes | `docs/failure-modes.md` | Projects where agents have failed before |
| No data model doc | `docs/data-model.md` | Projects with database/complex state |

**Rule**: Only suggest creating files that are genuinely useful for THIS specific task. Don't gold-plate.

## Step 5: Draft New Files

For each gap identified, produce a draft:

1. **Title and purpose** — What this doc covers
2. **Skeleton structure** — Section headers relevant to the task
3. **Placeholder content** — Brief notes on what should go in each section
4. **Do NOT write** — Final polished content. That requires domain knowledge the user should validate.

Keep drafts concise. The user will fill in the real content.

## Step 6: Output Suggestions

Present as two sections:

```
## Existing Files to Add
1. `src/app.ts` — Main entry point, agent needs to understand routing
2. `src/config/database.ts` — DB config, must read before any schema changes
...

## New Files to Create
1. `docs/architecture.md` — No arch doc exists. Agent needs to understand module boundaries.
   Draft:
   # Architecture
   ## Overview
   [describe system]
   ## Module Structure
   [list modules and their responsibilities]
   ...

## Recommendation
Create `docs/must do/must-do.md` with these entries.
```

Ask the user to approve, modify, or discard each suggestion before proceeding.
