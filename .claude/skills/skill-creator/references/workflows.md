# Workflow Design Patterns

This reference provides patterns for designing multi-step workflows in skills.

## Table of Contents

1. [Sequential Workflows](#sequential-workflows)
2. [Decision Trees](#decision-trees)
3. [Conditional Logic](#conditional-logic)
4. [Error Handling Patterns](#error-handling-patterns)
5. [State Management](#state-management)

---

## Sequential Workflows

Use sequential workflows when steps must execute in a specific order.

### Pattern: Numbered Steps

```markdown
## Workflow

1. **Gather inputs** - Collect all required information from the user
2. **Validate** - Check that inputs meet requirements
3. **Process** - Execute the main operation
4. **Verify** - Confirm the output is correct
5. **Deliver** - Present results to the user
```

### Pattern: Phase-Based

For longer workflows, group steps into phases:

```markdown
## Phase 1: Discovery

- Identify user requirements
- Analyze existing resources
- Document constraints

## Phase 2: Implementation

- Create initial structure
- Add core functionality
- Integrate components

## Phase 3: Verification

- Test against requirements
- Validate outputs
- Gather feedback
```

### Best Practices

- Keep each step atomic and independently verifiable
- Include clear completion criteria for each step
- Allow for iteration within phases when needed

---

## Decision Trees

Use decision trees when the workflow branches based on conditions.

### Pattern: If-Then Format

```markdown
## Workflow Decision Tree

**If** the user needs a new document:
→ Go to [Creating Documents](#creating-documents)

**If** the user needs to edit an existing document:
→ Go to [Editing Documents](#editing-documents)

**If** the user needs to analyze document content:
→ Go to [Analysis Tools](#analysis-tools)
```

### Pattern: Question-Based

```markdown
## Getting Started

Answer these questions to determine the right approach:

1. **Is this a new file or existing file?**
   - New → Use the creation workflow
   - Existing → Use the editing workflow

2. **What is the output format?**
   - Same format → Direct modification
   - Different format → Conversion required

3. **Are there quality requirements?**
   - Yes → Include validation step
   - No → Skip to delivery
```

### Pattern: Flowchart Style

```markdown
## Process Flow

START
  ↓
[Check file exists?]
  ├─ Yes → [Read file contents]
  │           ↓
  │        [Parse structure]
  │           ↓
  │        [Apply modifications]
  └─ No  → [Create new file]
              ↓
           [Initialize structure]
              ↓
           [Add content]
  ↓
[Validate output]
  ↓
END
```

---

## Conditional Logic

Use conditional patterns when behavior depends on context.

### Pattern: Context-Dependent Actions

```markdown
## Handling User Requests

**For simple requests** (single operation, clear outcome):
- Execute directly
- Report results

**For complex requests** (multiple operations, dependencies):
- Break into sub-tasks
- Execute sequentially
- Aggregate results

**For ambiguous requests** (unclear requirements):
- Ask clarifying questions
- Confirm understanding
- Then proceed
```

### Pattern: Fallback Chains

```markdown
## Data Extraction

Attempt extraction methods in order:

1. **Structured parsing** - If file has clear structure
   - Parse directly using format-specific tools

2. **Pattern matching** - If structure is irregular
   - Use regex to identify content

3. **AI extraction** - If patterns are inconsistent
   - Use semantic understanding

4. **Manual guidance** - If all else fails
   - Ask user to identify relevant sections
```

---

## Error Handling Patterns

### Pattern: Graceful Degradation

```markdown
## Error Handling

**On validation failure:**
1. Log the specific validation error
2. Attempt automatic correction if possible
3. If correction fails, report to user with suggestions

**On processing failure:**
1. Preserve any partial work
2. Identify the failure point
3. Offer options: retry, modify input, or abort

**On output failure:**
1. Save to temporary location
2. Notify user of alternative access
3. Diagnose delivery issue
```

### Pattern: Retry Logic

```markdown
## Retry Strategy

For transient failures:
1. Wait briefly (1-2 seconds)
2. Retry with same parameters
3. If still failing, try alternative approach
4. After 3 attempts, escalate to user
```

---

## State Management

### Pattern: Checkpoint System

```markdown
## Long-Running Operations

Save progress at checkpoints:

- **After input validation** → Checkpoint 1
- **After data transformation** → Checkpoint 2
- **After processing complete** → Checkpoint 3

If interrupted, resume from last checkpoint.
```

### Pattern: Context Preservation

```markdown
## Multi-Turn Workflows

Track across conversation turns:

1. **Initial state** - User's original request
2. **Current state** - What has been completed
3. **Next state** - What remains to be done
4. **Final state** - Expected outcome

Update state after each significant action.
```

---

## Combining Patterns

Most effective skills combine multiple patterns:

```markdown
## Complete Workflow Example

### Decision Phase
[Decision tree to determine approach]

### Execution Phase
[Sequential steps for chosen approach]

### Verification Phase
[Conditional checks based on output type]

### Error Recovery
[Fallback chains if issues arise]
```

---

## Anti-Patterns to Avoid

1. **Deeply nested conditions** - Flatten when possible
2. **Unclear branching** - Always specify what happens in each branch
3. **Missing error cases** - Account for failure modes
4. **Implicit state** - Make state changes explicit
5. **Unbounded loops** - Always have exit conditions
