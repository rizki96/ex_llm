# ExLLM Release Checklist

This checklist ensures consistent and high-quality releases for ExLLM.

## Pre-Release Checklist

### 1. Code Quality ✓

- [ ] **Run all tests**
  ```bash
  mix test
  ```
  - [ ] All tests pass
  - [ ] No skipped tests without justification

- [ ] **Check code quality**
  ```bash
  mix format --check-formatted
  mix credo --strict
  mix compile --warnings-as-errors
  ```
  - [ ] No formatting issues
  - [ ] No Credo warnings
  - [ ] No compilation warnings

- [ ] **Run Dialyzer**
  ```bash
  mix dialyzer
  ```
  - [ ] Address any new warnings
  - [ ] Update .dialyzer_ignore.exs if needed

- [ ] **Security audit**
  ```bash
  mix deps.audit
  ```
  - [ ] No vulnerable dependencies

### 2. Documentation ✓

- [ ] **Update version numbers**
  - [ ] `mix.exs` - Update `@version`
  - [ ] `README.md` - Update version badge and installation instructions
  - [ ] `docs/QUICKSTART.md` - Update dependency version
  - [ ] `docs/USER_GUIDE.md` - Update dependency version
  - [ ] Check for any hardcoded version references

- [ ] **Update CHANGELOG.md**
  - [ ] Add new version section with date
  - [ ] Move items from `[Unreleased]` to new version
  - [ ] Categorize changes: Added, Changed, Fixed, Removed
  - [ ] Mark any breaking changes with **BREAKING:**
  - [ ] Add migration notes for breaking changes

- [ ] **Review and update docs**
  - [ ] API documentation is current
  - [ ] Examples work with new version
  - [ ] Migration guide updated (if needed)
  - [ ] New features are documented

- [ ] **Generate and review ExDoc**
  ```bash
  mix docs
  open doc/index.html
  ```
  - [ ] All modules have documentation
  - [ ] All public functions have @doc
  - [ ] @moduledoc explains purpose clearly
  - [ ] Examples are correct and helpful

### 3. Testing ✓

- [ ] **Run tests with all providers**
  ```bash
  # With API keys loaded
  source scripts/run_with_env.sh
  mix test --include integration
  ```

- [ ] **Test critical paths manually**
  - [ ] Basic chat with major providers (OpenAI, Anthropic, Gemini)
  - [ ] Streaming works correctly
  - [ ] Error handling behaves as expected
  - [ ] New features work as documented

- [ ] **Check backward compatibility**
  - [ ] Previous version's examples still work
  - [ ] No unexpected breaking changes
  - [ ] Deprecation warnings are clear

### 4. Dependencies ✓

- [ ] **Update dependencies**
  ```bash
  mix deps.update --all
  mix deps.compile
  ```
  - [ ] Test with updated dependencies
  - [ ] Lock file is committed

- [ ] **Check dependency constraints**
  - [ ] Version constraints in mix.exs are appropriate
  - [ ] No overly restrictive constraints
  - [ ] Compatible with latest Elixir/Erlang

## Release Process

### 1. Version Bump

- [ ] **Determine version number**
  - [ ] MAJOR: Breaking changes
  - [ ] MINOR: New features, backward compatible
  - [ ] PATCH: Bug fixes only
  - [ ] Follow Semantic Versioning

- [ ] **Create version commit**
  ```bash
  git add -A
  git commit -m "chore: bump version to X.Y.Z"
  ```

### 2. Git Tag

- [ ] **Create annotated tag**
  ```bash
  git tag -a vX.Y.Z -m "Release vX.Y.Z"
  ```

- [ ] **Push commits and tags**
  ```bash
  git push origin main
  git push origin vX.Y.Z
  ```

### 3. GitHub Release

- [ ] **Create GitHub release**
  - [ ] Go to Releases → New Release
  - [ ] Select the version tag
  - [ ] Title: `vX.Y.Z`
  - [ ] Copy CHANGELOG entries to description
  - [ ] Highlight major features/fixes
  - [ ] Add migration notes if applicable

### 4. Hex Package

- [ ] **Publish to Hex**
  ```bash
  mix hex.publish
  ```
  - [ ] Review package contents
  - [ ] Confirm version is correct
  - [ ] Enter Hex credentials

- [ ] **Verify publication**
  - [ ] Check https://hex.pm/packages/ex_llm
  - [ ] Documentation is generated
  - [ ] Installation instructions work

## Post-Release Checklist

### 1. Announcements

- [ ] **Update project references**
  - [ ] Update README with new version info
  - [ ] Update any example repositories
  - [ ] Update integration guides

- [ ] **Announce release** (if major/minor)
  - [ ] Twitter/X announcement
  - [ ] Elixir Forum post
  - [ ] Discord/Slack communities
  - [ ] Include highlights and thanks

### 2. Monitor

- [ ] **Watch for issues**
  - [ ] GitHub issues for problems
  - [ ] Hex.pm download stats
  - [ ] Community feedback

- [ ] **Be ready to patch**
  - [ ] Keep PR ready for hotfixes
  - [ ] Document any found issues

### 3. Planning

- [ ] **Update project boards**
  - [ ] Close completed milestone
  - [ ] Create next milestone
  - [ ] Move unfinished issues

- [ ] **Start CHANGELOG for next version**
  - [ ] Add `[Unreleased]` section
  - [ ] Begin tracking changes

## Emergency Procedures

### Reverting a Release

If critical issues are found:

1. **Revert on Hex** (within 24 hours)
   ```bash
   mix hex.publish revert X.Y.Z
   ```

2. **Communicate**
   - [ ] GitHub issue explaining the problem
   - [ ] Announcement in same channels
   - [ ] Clear timeline for fix

3. **Fix and Re-release**
   - [ ] Create patch version
   - [ ] Extra thorough testing
   - [ ] Clear communication about fix

### Hotfix Process

For critical security/bug fixes:

1. **Create hotfix branch**
   ```bash
   git checkout -b hotfix/X.Y.Z main
   ```

2. **Minimal changes only**
   - [ ] Fix the specific issue
   - [ ] Add regression test
   - [ ] Update CHANGELOG

3. **Fast-track release**
   - [ ] Abbreviated testing (focus on fix)
   - [ ] Immediate version bump
   - [ ] Priority announcement

## Automation Notes

Consider automating these checks with GitHub Actions:

```yaml
# .github/workflows/release.yml
name: Release Checklist
on:
  push:
    tags:
      - 'v*'

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
      - run: mix deps.get
      - run: mix format --check-formatted
      - run: mix credo --strict
      - run: mix compile --warnings-as-errors
      - run: mix test
      - run: mix docs
```

## Version History

- **v1.0.0-rc1** - First release candidate
  - Major architectural improvements
  - Module extraction
  - Provider delegation system
  - Zero breaking changes

---

Remember: Quality over speed. It's better to delay a release than to ship broken code.