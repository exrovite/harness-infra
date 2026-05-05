#!/usr/bin/env python3
"""
Skill Initializer - Creates a new skill from template

Usage:
    init_skill.py <skill-name> --path <path>

Examples:
    init_skill.py my-new-skill --path skills/public
    init_skill.py my-api-helper --path skills/private
    init_skill.py custom-skill --path /custom/location
"""

import sys
from pathlib import Path


SKILL_TEMPLATE = """---
name: {skill_name}
description: [TODO: This is the PRIMARY TRIGGER for your skill. Include BOTH what the skill does AND when to use it. Example: "Comprehensive document creation, editing, and analysis with support for tracked changes. Use when Claude needs to work with professional documents (.docx files) for: (1) Creating new documents, (2) Modifying content, (3) Working with tracked changes." Max 1024 chars, no angle brackets.]
---

# {skill_title}

[TODO: 1-2 sentences explaining what this skill enables. Remember: Claude is already smart - only include information Claude doesn't already have.]

## Quick Start

[TODO: Add the most common use case with a concrete example. Keep it concise.]

## Core Workflow

[TODO: Choose ONE of these patterns based on your skill's purpose:

**Pattern A: Task-Based** (for tool collections)
```
## Quick Start
[Most common operation]

## Task: [Operation 1]
[How to do it]

## Task: [Operation 2]
[How to do it]
```

**Pattern B: Decision Tree** (for complex branching)
```
## Workflow Decision Tree

**If** [condition 1]:
→ [Action or link to section]

**If** [condition 2]:
→ [Action or link to section]
```

**Pattern C: Sequential** (for step-by-step processes)
```
## Step 1: [First step]
[Instructions]

## Step 2: [Second step]
[Instructions]
```

Delete this guidance section after choosing your pattern.]

## Resources

[TODO: Reference any bundled resources here. Delete unused directories.]

### scripts/
[TODO: List any executable scripts. Example: `scripts/process.py` - Description of what it does]

### references/
[TODO: List reference files. Example: See `references/api.md` for API documentation]

### assets/
[TODO: List template/asset files. Example: `assets/template.docx` for document template]

---

**Delete any unused resource directories.** Keep the skill lean.

**Remember:**
- The context window is a public good - be concise
- Claude is already smart - only add what Claude doesn't know
- All "when to use" info belongs in the description, not here (body loads after triggering)
"""

EXAMPLE_SCRIPT = '''#!/usr/bin/env python3
"""
Example script for {skill_name}

Replace with actual implementation or delete if not needed.
Scripts execute without loading into context - only output is returned.
"""

def main():
    # TODO: Add actual script logic
    print("Example output from {skill_name}")

if __name__ == "__main__":
    main()
'''

EXAMPLE_REFERENCE = """# {skill_title} Reference

[TODO: Add detailed reference content here. This file is loaded only when needed.]

## Table of Contents

1. [Section 1](#section-1)
2. [Section 2](#section-2)

---

## Section 1

[TODO: Add content. Keep files under 100 lines or include a table of contents.]

## Section 2

[TODO: Add content]

---

**Note:** Reference files should contain information that:
- Is too detailed for SKILL.md
- Is only needed for specific use cases
- Would bloat the main skill file

Delete this file if not needed.
"""

EXAMPLE_ASSET = """# Example Asset Placeholder

This is a placeholder. Replace with actual asset files or delete this directory.

Assets are files used in output (not loaded into context):
- Templates: .pptx, .docx, boilerplate code
- Images: .png, .jpg, .svg
- Fonts: .ttf, .woff2
- Data files: .csv, .json

Delete this file and add your actual assets.
"""


def title_case_skill_name(skill_name):
    """Convert hyphenated skill name to Title Case for display."""
    return ' '.join(word.capitalize() for word in skill_name.split('-'))


def init_skill(skill_name, path):
    """
    Initialize a new skill directory with template SKILL.md.

    Args:
        skill_name: Name of the skill
        path: Path where the skill directory should be created

    Returns:
        Path to created skill directory, or None if error
    """
    # Determine skill directory path
    skill_dir = Path(path).resolve() / skill_name

    # Check if directory already exists
    if skill_dir.exists():
        print(f"[ERROR] Skill directory already exists: {skill_dir}")
        return None

    # Create skill directory
    try:
        skill_dir.mkdir(parents=True, exist_ok=False)
        print(f"[OK] Created skill directory: {skill_dir}")
    except Exception as e:
        print(f"❌ Error creating directory: {e}")
        return None

    # Create SKILL.md from template
    skill_title = title_case_skill_name(skill_name)
    skill_content = SKILL_TEMPLATE.format(
        skill_name=skill_name,
        skill_title=skill_title
    )

    skill_md_path = skill_dir / 'SKILL.md'
    try:
        skill_md_path.write_text(skill_content)
        print("[OK] Created SKILL.md")
    except Exception as e:
        print(f"❌ Error creating SKILL.md: {e}")
        return None

    # Create resource directories with example files
    try:
        # Create scripts/ directory with example script
        scripts_dir = skill_dir / 'scripts'
        scripts_dir.mkdir(exist_ok=True)
        example_script = scripts_dir / 'example.py'
        example_script.write_text(EXAMPLE_SCRIPT.format(skill_name=skill_name))
        example_script.chmod(0o755)
        print("[OK] Created scripts/example.py")

        # Create references/ directory with example reference doc
        references_dir = skill_dir / 'references'
        references_dir.mkdir(exist_ok=True)
        example_reference = references_dir / 'api_reference.md'
        example_reference.write_text(EXAMPLE_REFERENCE.format(skill_title=skill_title))
        print("[OK] Created references/api_reference.md")

        # Create assets/ directory with example asset placeholder
        assets_dir = skill_dir / 'assets'
        assets_dir.mkdir(exist_ok=True)
        example_asset = assets_dir / 'example_asset.txt'
        example_asset.write_text(EXAMPLE_ASSET)
        print("[OK] Created assets/example_asset.txt")
    except Exception as e:
        print(f"❌ Error creating resource directories: {e}")
        return None

    # Print next steps
    print(f"\n[DONE] Skill '{skill_name}' initialized successfully at {skill_dir}")
    print("\nNext steps:")
    print("1. Edit SKILL.md to complete the TODO items and update the description")
    print("2. Customize or delete the example files in scripts/, references/, and assets/")
    print("3. Run the validator when ready to check the skill structure")

    return skill_dir


def main():
    if len(sys.argv) < 4 or sys.argv[2] != '--path':
        print("Usage: init_skill.py <skill-name> --path <path>")
        print("\nSkill name requirements:")
        print("  - Hyphen-case identifier (e.g., 'data-analyzer')")
        print("  - Lowercase letters, digits, and hyphens only")
        print("  - Max 40 characters")
        print("  - Must match directory name exactly")
        print("\nExamples:")
        print("  init_skill.py my-new-skill --path skills/public")
        print("  init_skill.py my-api-helper --path skills/private")
        print("  init_skill.py custom-skill --path /custom/location")
        sys.exit(1)

    skill_name = sys.argv[1]
    path = sys.argv[3]

    print(f"Initializing skill: {skill_name}")
    print(f"   Location: {path}")
    print()

    result = init_skill(skill_name, path)

    if result:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
