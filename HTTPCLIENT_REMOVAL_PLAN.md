# Legacy HTTPClient Removal Plan

## Overview
This plan provides a systematic approach to completely remove the legacy HTTPClient compatibility layer from the ExLLM codebase, ensuring no functionality is lost while modernizing the HTTP infrastructure.

## Approach: Gradual Deprecation
Selected for maximum safety and traceability, allowing rollback at any checkpoint if issues arise.

---

## Phase 1: Discovery & Assessment

**Objective:** Map all HTTPClient dependencies and usage patterns

### Tasks:
1. **Find All References**
   ```bash
   git grep -n "HTTPClient" > httpclient_references.txt
   ```

2. **Categorize References**
   - Test files (can be updated)
   - Production code (needs careful migration)
   - Documentation (needs updating)
   - Configuration files

3. **Check Indirect Dependencies**
   - Search for aliases: `alias.*HTTPClient`
   - Import statements
   - Module attributes referencing HTTPClient

4. **Create Dependency Map**
   ```
   HTTPClient
   ├── StreamingCoordinator (verify migration)
   ├── EnhancedStreamingCoordinator (verify migration)
   ├── Legacy Tests
   │   ├── streaming_migration_test.exs
   │   ├── streaming_performance_test.exs
   │   └── http_core_streaming_validation_test.exs
   └── Stream Parsers (check if orphaned)
   ```

---

## Phase 2: Migration Verification

**Objective:** Confirm all functionality has migrated to HTTP.Core

### Verification Checklist:
- [ ] All provider modules use HTTP.Core
- [ ] StreamingCoordinator uses HTTP.Core
- [ ] EnhancedStreamingCoordinator uses HTTP.Core
- [ ] ModelFetcher uses HTTP.Core
- [ ] Error handling patterns match between implementations
- [ ] All HTTP operations have HTTP.Core equivalents

### Validation Script:
```bash
# Check provider usage
git grep -l "HTTP.Core" lib/ex_llm/providers/

# Verify no direct HTTPClient usage in providers
git grep "HTTPClient" lib/ex_llm/providers/ --include="*.ex"
```

---

## Phase 3: Test Transformation

**Objective:** Update tests to use HTTP.Core directly

### Test Files to Update:

1. **streaming_migration_test.exs**
   - Remove HTTPClient vs HTTP.Core comparison tests
   - Keep streaming validation tests using only HTTP.Core

2. **streaming_performance_test.exs**
   - Remove legacy_streaming benchmark
   - Keep performance tests for HTTP.Core only

3. **http_core_streaming_validation_test.exs**
   - Update to remove HTTPClient references
   - Ensure all validations use HTTP.Core

### Testing Strategy:
```bash
# Run after each file update
mix test <updated_test_file>

# Verify no test regression
mix test --failed
```

---

## Phase 4: Code Removal

**Objective:** Safely remove all legacy code

### Removal Order (Risk-Minimized):

1. **Test References First**
   - Remove from test files
   - Run `mix test` to ensure no breakage

2. **Documentation & Comments**
   - Update any code comments
   - Remove from documentation files

3. **Unused Modules**
   - Identify orphaned stream parsers
   - Remove if only used by HTTPClient

4. **Core Module Removal**
   - Remove `lib/ex_llm/providers/shared/http_client.ex`
   - Run `mix compile --warnings-as-errors`

### Safety Gates:
- Commit after each sub-phase
- Tag commits for easy rollback
- Run full test suite between removals

---

## Phase 5: Final Verification

**Objective:** Ensure complete removal with no regressions

### Final Checklist:
- [ ] `git grep HTTPClient` returns no results
- [ ] `mix compile --warnings-as-errors` succeeds
- [ ] `mix test` passes all tests
- [ ] `mix test --include integration` passes
- [ ] Documentation updated (CLAUDE.md, README.md)
- [ ] No orphaned modules remain

### Documentation Updates:
- Remove HTTPClient references from CLAUDE.md
- Update migration notes if any exist
- Add note about HTTP.Core being the standard

---

## Risk Mitigation

### Key Risks & Mitigations:

| Risk                    | Mitigation                                |
|-------------------------|-------------------------------------------|
| Hidden Dependencies     | Use git grep + compile checks             |
| Streaming Breakage      | Keep streaming tests, verify manually     |
| Provider Issues         | Test each provider individually           |
| Compilation Errors      | Feature branch + atomic commits           |

### Rollback Strategy:
- Each phase in separate commit
- Tag before major removals
- Keep branch until merged and stable

---

## Implementation Commands

### Quick Start:
```bash
# Create feature branch
git checkout -b remove-legacy-httpclient

# Run discovery
git grep -n "HTTPClient" | tee httpclient_references.txt

# Start with least risky changes
mix test test/ex_llm/providers/shared/streaming_migration_test.exs
```

### Verification Commands:
```bash
# After each change
mix compile --warnings-as-errors

# After each phase
mix test

# Before PR
mix test --include slow --include integration
mix format --check-formatted
mix credo
```

---

## PR Template

```markdown
## Remove Legacy HTTPClient Compatibility Layer

### Summary
Completes the HTTP client migration by removing the deprecated HTTPClient 
module and all associated legacy code.

### Changes
- Removed `HTTPClient` module and all references
- Updated tests to use HTTP.Core directly  
- Removed migration compatibility tests
- Cleaned up unused stream parser modules

### Testing
- [x] All unit tests pass
- [x] All integration tests pass
- [x] Manually tested streaming with each provider
- [x] No compilation warnings

### Migration Note
All functionality previously provided by HTTPClient is now handled by 
HTTP.Core with improved error handling and middleware support.
```

---

## Execution Timeline

While specific dates aren't set, the phases should be executed in order with verification between each:

1. **Phase 1**: Discovery & Assessment
2. **Phase 2**: Migration Verification  
3. **Phase 3**: Test Transformation
4. **Phase 4**: Code Removal
5. **Phase 5**: Final Verification

Each phase should be completed and verified before moving to the next.

---

## Success Criteria

The removal is considered complete when:
- All HTTPClient references are removed from the codebase
- All tests pass without any HTTPClient dependencies
- No compilation warnings related to the removal
- All streaming functionality works correctly with HTTP.Core
- Documentation reflects the current state

---

This plan ensures safe, systematic removal of the legacy HTTPClient layer while maintaining all functionality through the modern HTTP.Core implementation.