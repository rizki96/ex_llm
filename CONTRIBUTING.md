# Contributing to ExLLM

Thank you for your interest in contributing to ExLLM! This document provides guidelines for contributing to the project.

## Getting Started

1. **Fork the repository** and clone your fork locally
2. **Install dependencies**: `mix deps.get`
3. **Run the tests**: `mix test` to ensure everything works
4. **Create a feature branch**: `git checkout -b feature/your-feature-name`

## Development Setup

### Prerequisites
- Elixir 1.14+
- Erlang/OTP 25+

### Running Tests
```bash
# Run all tests
mix test

# Run specific test categories
mix test.unit           # Unit tests only
mix test.integration    # Integration tests (requires API keys)
mix test.fast          # Fast tests (excludes integration/external)

# Run provider-specific tests
mix test.anthropic
mix test.openai
mix test.gemini
```

### Code Quality
```bash
# Format code
mix format

# Run linter
mix credo

# Run type checker
mix dialyzer
```

## Contribution Guidelines

### Code Style
- Follow existing code patterns and conventions
- Use `mix format` to ensure consistent formatting
- Add typespecs for public functions
- Write comprehensive documentation
- Follow the `ExLLM.function_name(provider, ...args)` pattern for new unified API functions

### Testing
- Write tests for all new functionality
- Ensure tests pass without requiring API keys (use mocks/fixtures)
- Add integration tests when appropriate (tagged with `@tag :live_api`)
- Target 90%+ test coverage for new code

### Documentation
- Update relevant documentation when adding features
- Add examples to function documentation
- Update CHANGELOG.md following [Keep a Changelog](https://keepachangelog.com/) format

### Commit Messages
Follow [Conventional Commits](https://conventionalcommits.org/):
```
feat(provider): add support for new model
fix(streaming): resolve connection timeout issue
docs(api): update unified API examples
```

## Adding New Providers

1. **Create provider module** in `lib/ex_llm/providers/`
2. **Implement the ExLLM.Adapter behavior**
3. **Add configuration** in `config/models/provider.yml`
4. **Update capabilities registry** in `lib/ex_llm/api/capabilities.ex`
5. **Add tests** following existing provider test patterns
6. **Update documentation** with provider-specific details

## Pull Request Process

1. **Ensure all tests pass**: `mix test`
2. **Run code quality checks**: `mix credo && mix dialyzer`
3. **Update documentation** as needed
4. **Add changelog entry** for user-facing changes
5. **Create pull request** with clear description of changes
6. **Respond to review feedback** promptly

### Pull Request Requirements
- [ ] Tests pass locally
- [ ] Code follows style guidelines
- [ ] Documentation updated
- [ ] Changelog updated (for user-facing changes)
- [ ] Dialyzer passes without new errors

## Issue Reporting

When reporting issues:
- Use the appropriate issue template
- Provide clear reproduction steps
- Include relevant version information
- Add provider and model details if applicable

## Questions?

- Open a GitHub Discussion for general questions
- Check existing issues before creating new ones
- Join our community discussions for help

Thank you for contributing to ExLLM! 🚀