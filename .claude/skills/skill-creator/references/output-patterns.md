# Output Patterns and Templates

This reference provides patterns for defining output formats and quality standards in skills.

## Table of Contents

1. [Template Patterns](#template-patterns)
2. [Example-Driven Outputs](#example-driven-outputs)
3. [Quality Standards](#quality-standards)
4. [Format Specifications](#format-specifications)
5. [Validation Patterns](#validation-patterns)

---

## Template Patterns

Use templates when output should follow a consistent structure.

### Pattern: Slot-Based Templates

Define templates with clear placeholders:

```markdown
## Output Template

```
# {title}

## Summary
{brief_description}

## Details
{main_content}

## Next Steps
{action_items}
```

**Slot definitions:**
- `{title}` - Concise, descriptive heading (5-10 words)
- `{brief_description}` - One paragraph overview
- `{main_content}` - Detailed content (varies by use case)
- `{action_items}` - Bulleted list of recommended actions
```

### Pattern: Conditional Sections

Include sections based on context:

```markdown
## Report Template

# {title}

## Executive Summary
{summary}

## Findings
{findings}

<!-- Include if errors were found -->
## Issues Identified
{issues}

<!-- Include if recommendations requested -->
## Recommendations
{recommendations}

## Appendix
{supporting_data}
```

### Pattern: Nested Templates

For complex outputs with sub-structures:

```markdown
## Document Structure

# Main Document
├── Header Section
│   ├── Title: {title}
│   ├── Author: {author}
│   └── Date: {date}
├── Body Sections (repeat for each)
│   ├── Heading: {section_heading}
│   ├── Content: {section_content}
│   └── Subsections: [nested structure]
└── Footer Section
    ├── References: {references}
    └── Appendices: {appendices}
```

---

## Example-Driven Outputs

Use concrete examples to demonstrate expected output.

### Pattern: Before/After Examples

```markdown
## Transformation Example

**Input:**
```
rough draft text with errors and poor formatting
```

**Output:**
```
Polished text with proper grammar, clear structure,
and professional formatting.
```

**Key transformations applied:**
- Corrected grammatical errors
- Improved sentence structure
- Added proper formatting
```

### Pattern: Multiple Examples

Show variations to clarify expectations:

```markdown
## Output Examples

**Example 1: Simple case**
Input: "meeting tomorrow 3pm"
Output: "Meeting scheduled for tomorrow at 3:00 PM"

**Example 2: Complex case**
Input: "weekly sync john mary starting next monday"
Output: "Recurring weekly meeting with John and Mary,
        starting Monday, [date]"

**Example 3: Edge case**
Input: "cancel all meetings"
Output: "Please confirm: Cancel all scheduled meetings?
        This will affect [N] events."
```

### Pattern: Annotated Examples

Explain why the output is correct:

```markdown
## Annotated Output Example

**Input:** User asks for a summary of a 10-page document

**Output:**
```
## Document Summary

**Main Topic:** [identified from document title and introduction]

**Key Points:**
1. [First major point - from section 1]
2. [Second major point - from section 3]
3. [Third major point - from conclusion]

**Notable Details:**
- [Specific fact that supports key points]
- [Quantitative data if present]

**Conclusion:** [Paraphrased from document's conclusion]
```

**Why this works:**
- Hierarchical structure aids scanning
- Key points limited to 3-5 for readability
- Source sections noted for verification
- Conclusion provides closure
```

---

## Quality Standards

Define clear quality criteria for outputs.

### Pattern: Quality Checklist

```markdown
## Output Quality Checklist

Before delivering output, verify:

**Completeness:**
- [ ] All requested information included
- [ ] No placeholder text remaining
- [ ] All sections filled appropriately

**Accuracy:**
- [ ] Facts verified against source
- [ ] Calculations double-checked
- [ ] Names and dates correct

**Clarity:**
- [ ] Language appropriate for audience
- [ ] Technical terms explained if needed
- [ ] Logical flow maintained

**Formatting:**
- [ ] Consistent heading hierarchy
- [ ] Proper list formatting
- [ ] Code blocks syntax-highlighted
```

### Pattern: Quality Tiers

Define different quality levels:

```markdown
## Quality Levels

**Draft quality** (fast, approximate):
- Key information captured
- May contain minor errors
- Formatting is functional

**Standard quality** (balanced):
- Information is accurate
- Grammar and spelling checked
- Professional formatting

**Publication quality** (thorough):
- Fact-checked against sources
- Professionally edited
- Meets style guide requirements
- Includes proper citations
```

### Pattern: Acceptance Criteria

```markdown
## Acceptance Criteria

Output is acceptable when:

1. **Functional requirements met:**
   - Contains all required sections
   - Addresses the user's question
   - Provides actionable information

2. **Non-functional requirements met:**
   - Response time under 30 seconds
   - File size within limits
   - Format compatible with target system

3. **No blocking issues:**
   - No factual errors
   - No broken links or references
   - No security concerns
```

---

## Format Specifications

Define precise format requirements.

### Pattern: Structured Data Format

```markdown
## JSON Output Format

```json
{
  "status": "success" | "error",
  "data": {
    "id": "string (UUID format)",
    "name": "string (max 100 chars)",
    "created": "ISO 8601 datetime",
    "items": [
      {
        "key": "string",
        "value": "any"
      }
    ]
  },
  "metadata": {
    "version": "1.0",
    "generated": "ISO 8601 datetime"
  }
}
```

**Field requirements:**
- `status`: Required, indicates operation result
- `data.id`: Required, unique identifier
- `data.items`: Optional, array of key-value pairs
```

### Pattern: Document Format

```markdown
## Document Specifications

**File format:** Markdown (.md)

**Structure requirements:**
- H1 heading for document title (one only)
- H2 headings for major sections
- H3 headings for subsections
- No skipping heading levels

**Content requirements:**
- Maximum line length: 100 characters
- Code blocks must specify language
- Links must be valid URLs or relative paths
- Images must have alt text

**Naming convention:**
- Lowercase with hyphens
- No spaces or special characters
- Descriptive but concise
- Example: `project-overview.md`
```

---

## Validation Patterns

Ensure outputs meet specifications.

### Pattern: Schema Validation

```markdown
## Output Validation

Validate output against schema:

1. **Structure check** - Required fields present
2. **Type check** - Values match expected types
3. **Constraint check** - Values within allowed ranges
4. **Relationship check** - References resolve correctly

**On validation failure:**
- Identify specific violations
- Attempt automatic correction
- Report remaining issues to user
```

### Pattern: Content Validation

```markdown
## Content Validation Rules

**Text content:**
- No profanity or inappropriate language
- No personally identifiable information unless requested
- No placeholder text (e.g., "Lorem ipsum", "[TODO]")

**Numerical content:**
- Values within reasonable ranges
- Units specified where applicable
- Precision appropriate to context

**Reference content:**
- All citations have sources
- All links are functional
- All code examples are syntactically valid
```

### Pattern: Self-Verification

```markdown
## Output Self-Check

Before finalizing output, verify:

1. **Re-read the original request** - Does output address it?
2. **Check for completeness** - Any missing pieces?
3. **Verify accuracy** - Any potential errors?
4. **Review formatting** - Consistent and clean?
5. **Consider the user** - Will this be useful to them?
```

---

## Anti-Patterns to Avoid

1. **Vague specifications** - "Make it look nice" vs specific formatting rules
2. **Missing examples** - Abstract descriptions without concrete instances
3. **Inconsistent formats** - Different structures for similar content
4. **No validation** - Assuming output is correct without checking
5. **Over-specification** - Constraining format unnecessarily
