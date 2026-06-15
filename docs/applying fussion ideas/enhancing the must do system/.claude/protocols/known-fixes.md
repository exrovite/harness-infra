# Known Fixes Registry
# Add fixes as they are discovered using the template format below.

# ## FIX-NNN: [Short description]
# - **Symptom**: [Exact error text or pattern]
# - **Root cause**: [Why this happens]
# - **Fix**: [What to do]
# - **File**: [Which file(s)]
# - **Verified**: [Date]
#
# ## Verify
# - type: file_exists
#   file: [path]
#
# - type: file_contains
#   file: [path]
#   pattern: [regex]
#   before_pattern: [optional ordering check]
#
# - type: test_passes
#   command: [pytest|npm test|cargo test|python -m unittest]
