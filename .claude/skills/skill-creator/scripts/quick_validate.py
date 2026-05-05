#!/usr/bin/env python3
"""
Quick validation script for skills - validates against Anthropic's skill specification
"""

import sys
import re
from pathlib import Path

# Reserved words that cannot appear in skill names
RESERVED_WORDS = ['anthropic', 'claude']

# Maximum lengths per specification
MAX_NAME_LENGTH = 64
MAX_DESCRIPTION_LENGTH = 1024


def validate_skill(skill_path):
    """
    Validate a skill against Anthropic's specification.

    Returns:
        tuple: (is_valid: bool, message: str, warnings: list)
    """
    skill_path = Path(skill_path)
    warnings = []

    # Check skill directory exists
    if not skill_path.exists():
        return False, f"Skill directory not found: {skill_path}", []

    if not skill_path.is_dir():
        return False, f"Path is not a directory: {skill_path}", []

    # Check SKILL.md exists
    skill_md = skill_path / 'SKILL.md'
    if not skill_md.exists():
        return False, "SKILL.md not found", []

    # Read and validate content
    try:
        content = skill_md.read_text(encoding='utf-8')
    except Exception as e:
        return False, f"Error reading SKILL.md: {e}", []

    # Validate frontmatter exists
    if not content.startswith('---'):
        return False, "No YAML frontmatter found (must start with ---)", []

    # Extract frontmatter
    match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not match:
        return False, "Invalid frontmatter format (missing closing ---)", []

    frontmatter = match.group(1)

    # Check required fields exist
    if 'name:' not in frontmatter:
        return False, "Missing 'name' field in frontmatter", []
    if 'description:' not in frontmatter:
        return False, "Missing 'description' field in frontmatter", []

    # Extract and validate name
    name_match = re.search(r'name:\s*(.+)', frontmatter)
    if name_match:
        name = name_match.group(1).strip()

        # Check name is not empty
        if not name:
            return False, "Name field cannot be empty", []

        # Check max length
        if len(name) > MAX_NAME_LENGTH:
            return False, f"Name exceeds {MAX_NAME_LENGTH} characters (has {len(name)})", []

        # Check naming convention (hyphen-case: lowercase with hyphens and digits)
        if not re.match(r'^[a-z0-9-]+$', name):
            return False, f"Name '{name}' must be hyphen-case (lowercase letters, digits, and hyphens only)", []

        # Check for invalid hyphen patterns
        if name.startswith('-'):
            return False, f"Name '{name}' cannot start with a hyphen", []
        if name.endswith('-'):
            return False, f"Name '{name}' cannot end with a hyphen", []
        if '--' in name:
            return False, f"Name '{name}' cannot contain consecutive hyphens", []

        # Check for reserved words (warning for personal skills about Claude products)
        name_lower = name.lower()
        for reserved in RESERVED_WORDS:
            if reserved in name_lower:
                warnings.append(f"Name contains '{reserved}' - OK for personal skills, but avoid for public distribution")

        # Check that name matches directory name
        if name != skill_path.name:
            return False, f"Name '{name}' does not match directory name '{skill_path.name}'", []
    else:
        return False, "Could not parse name field", []

    # Extract and validate description
    # Handle multi-line descriptions
    desc_match = re.search(r'description:\s*(.+?)(?=\n[a-z_-]+:|$)', frontmatter, re.DOTALL)
    if desc_match:
        description = desc_match.group(1).strip()

        # Check description is not empty
        if not description:
            return False, "Description field cannot be empty", []

        # Check max length
        if len(description) > MAX_DESCRIPTION_LENGTH:
            return False, f"Description exceeds {MAX_DESCRIPTION_LENGTH} characters (has {len(description)})", []

        # Check for XML tags / angle brackets
        if '<' in description or '>' in description:
            return False, "Description cannot contain angle brackets (< or >) or XML tags", []

        # Check for TODO placeholders
        if '[TODO' in description.upper():
            return False, "Description contains TODO placeholder - please complete it", []
    else:
        return False, "Could not parse description field", []

    # Check for body content after frontmatter
    body_start = content.find('---', 3) + 3
    body = content[body_start:].strip()
    if not body:
        return False, "SKILL.md has no body content after frontmatter", []

    # Validate body has at least a heading
    if not re.search(r'^#\s+', body, re.MULTILINE):
        return False, "SKILL.md body should have at least one markdown heading", []

    return True, "Skill is valid!", warnings


def main():
    if len(sys.argv) != 2:
        print("Usage: python quick_validate.py <skill_directory>")
        print("\nValidates a skill against Anthropic's specification:")
        print(f"  - name: max {MAX_NAME_LENGTH} chars, hyphen-case")
        print(f"  - description: max {MAX_DESCRIPTION_LENGTH} chars, no XML tags")
        print("  - SKILL.md structure and content")
        sys.exit(1)

    skill_path = sys.argv[1]
    valid, message, warnings = validate_skill(skill_path)

    if valid:
        print(f"[PASS] {message}")
        for warning in warnings:
            print(f"[WARN] {warning}")
    else:
        print(f"[FAIL] {message}")

    sys.exit(0 if valid else 1)


if __name__ == "__main__":
    main()
