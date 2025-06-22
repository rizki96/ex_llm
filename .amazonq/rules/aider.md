# Aider Configuration Rules

## Working Directory

When using aider, remember that its current working directory is `/Users/azmaveth/code`. 

**ALWAYS prefix file paths with `ex_llm/`** so aider writes code in the correct directory.

## File Path Examples

**Correct:**
- `ex_llm/lib/ex_llm/consent_handler.ex`
- `ex_llm/test/ex_llm/compliance/security_compliance_test.exs`
- `ex_llm/config/config.exs`

**Incorrect:**
- `lib/ex_llm/consent_handler.ex` (missing ex_llm/ prefix)
- `test/ex_llm/compliance/security_compliance_test.exs` (missing ex_llm/ prefix)
- `config/config.exs` (missing ex_llm/ prefix)

## Implementation Notes

- All file paths in aider commands must include the `ex_llm/` prefix
- This ensures files are created in the correct ExLLM project directory
- Verify file locations after creation to confirm proper placement
