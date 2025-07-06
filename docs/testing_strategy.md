# ExLLM Testing Strategy

## Overview

This document outlines a comprehensive testing strategy for ExLLM to address current challenges with integration testing, provider visibility, and test execution time. The strategy was developed through consensus between multiple AI models and represents industry best practices for SDK testing.

## Current Challenges

1. **Performance**: Integration tests take several minutes, exceeding development tool timeout limits
2. **Clarity**: Unclear which tests hit live APIs vs mocks/errors
3. **Visibility**: No easy way to see which providers pass/fail for specific functionality
4. **Reporting**: Linear test output doesn't show cross-provider comparisons

## Proposed Solution

### Core Components

1. **Test Tagging System**: Clear categorization using ExUnit tags
2. **Directory Structure**: Logical separation of test types
3. **Provider Capability Matrix**: Visual reporting of provider support
4. **Selective Execution**: Run specific test subsets quickly
5. **Response Capture**: Optional debugging with actual API responses

## Implementation Plan

### Phase 1: Test Organization (Days 1-2)

#### Tag Structure
```elixir
# Test type tags
@tag :unit                    # Pure logic tests, no external dependencies
@tag :integration            # All integration tests
@tag :live                   # Real API calls
@tag :mock                   # Mocked responses

# Capability tags
@tag capability: :chat       # Basic chat functionality
@tag capability: :streaming  # Streaming responses
@tag capability: :models     # Model listing
@tag capability: :functions  # Function calling
@tag capability: :vision     # Image processing
@tag capability: :tools      # Tool use

# Provider tags
@tag provider: :openai       # OpenAI-specific
@tag provider: :anthropic    # Anthropic-specific
@tag provider: :gemini       # Google Gemini
@tag provider: :groq         # Groq
@tag provider: :ollama       # Local Ollama
@tag provider: :mistral      # Mistral AI
```

#### Directory Structure
```
test/
├── unit/                    # Pure unit tests
│   ├── core/               # Core functionality
│   ├── utils/              # Utility functions
│   └── types/              # Type validation
├── integration/
│   ├── live/               # Real API calls
│   │   ├── providers/      # Provider-specific tests
│   │   └── capabilities/   # Capability-focused tests
│   └── mock/               # Mocked integration tests
│       ├── providers/      # Provider behavior mocks
│       └── error_cases/    # Error scenario testing
└── support/
    ├── matrix_reporter.ex   # Custom reporting
    ├── response_capture.ex  # Response debugging
    └── test_helpers.ex      # Common test utilities
```

### Phase 2: Mix Aliases & Configuration (Day 3)

#### Mix Aliases
```elixir
# mix.exs
def project do
  [
    # ... existing config ...
    aliases: [
      # Basic test categories
      "test.unit": "test --only unit",
      "test.mock": "test --only mock",
      "test.live": "test --only live --max-cases 4",
      
      # Provider-specific live tests
      "test.live.openai": "test --only live --only provider:openai",
      "test.live.anthropic": "test --only live --only provider:anthropic",
      "test.live.gemini": "test --only live --only provider:gemini",
      "test.live.groq": "test --only live --only provider:groq",
      "test.live.ollama": "test --only live --only provider:ollama",
      
      # Capability-specific tests
      "test.capability": &test_capability/1,
      
      # Quick smoke test
      "test.smoke": "test --only unit --only mock",
      
      # Full matrix report
      "test.matrix": ["test.live", "test.matrix.report"],
      
      # CI-specific aliases
      "test.ci.pr": "test --exclude live --exclude slow",
      "test.ci.nightly": "test --only live"
    ]
  ]
end

# Custom capability testing function
defp test_capability(args) do
  capability = List.first(args) || raise "Specify a capability"
  Mix.Task.run("test", ["--only", "capability:#{capability}"])
end
```

#### Test Configuration
```elixir
# config/test.exs
config :ex_llm, :test,
  # Parallel execution for live tests
  max_cases: System.schedulers_online() * 2,
  
  # Response capture
  capture_responses: System.get_env("CAPTURE_RESPONSES") == "true",
  capture_dir: "test/responses",
  
  # Timeout configurations
  live_test_timeout: 30_000,  # 30 seconds per live test
  mock_test_timeout: 5_000,   # 5 seconds per mock test
  
  # Rate limit protection
  rate_limit_delay: 1_000,    # 1 second between provider requests
  
  # Matrix reporter settings
  show_response_samples: System.get_env("SHOW_RESPONSES") == "true"
```

### Phase 3: Matrix Reporter (Days 4-5)

```elixir
defmodule ExLLM.Testing.MatrixReporter do
  @moduledoc """
  Generates a provider capability matrix from test results
  """
  
  @capabilities [:chat, :streaming, :models, :functions, :vision, :tools]
  @providers [:openai, :anthropic, :gemini, :groq, :ollama, :mistral, :xai, :perplexity]
  
  def generate_report(test_results) do
    matrix = build_matrix(test_results)
    
    # Console output
    print_console_matrix(matrix)
    
    # Markdown file output
    save_markdown_report(matrix)
    
    # JSON output for CI
    save_json_report(matrix)
    
    # Optional response samples
    if show_responses?() do
      print_sample_responses(test_results)
    end
  end
  
  defp print_console_matrix(matrix) do
    IO.puts("\n#{IO.ANSI.bright()}=== Provider Capability Matrix ===#{IO.ANSI.reset()}\n")
    
    # Header row
    IO.write(String.pad_trailing("Capability", 15))
    Enum.each(@providers, &IO.write(String.pad_trailing("#{&1}", 12)))
    IO.puts("\n" <> String.duplicate("-", 15 + length(@providers) * 12))
    
    # Data rows
    Enum.each(@capabilities, fn cap ->
      IO.write(String.pad_trailing("#{cap}", 15))
      Enum.each(@providers, fn provider ->
        status = matrix[{provider, cap}]
        {symbol, color} = format_status(status)
        IO.write(color <> String.pad_trailing(symbol, 12) <> IO.ANSI.reset())
      end)
      IO.puts("")
    end)
    
    # Legend
    IO.puts("\n#{IO.ANSI.light_black()}Legend: ✅ Pass | ❌ Fail | ⏭️ Skip | ❓ Unknown#{IO.ANSI.reset()}")
  end
  
  defp format_status(status) do
    case status do
      :pass -> {"✅", IO.ANSI.green()}
      :fail -> {"❌", IO.ANSI.red()}
      :skip -> {"⏭️", IO.ANSI.yellow()}
      _     -> {"❓", IO.ANSI.light_black()}
    end
  end
  
  defp save_markdown_report(matrix) do
    content = """
    # Provider Capability Matrix
    
    Generated: #{DateTime.utc_now() |> DateTime.to_string()}
    
    | Capability | #{Enum.map_join(@providers, " | ", &"#{&1}")} |
    |------------|#{String.duplicate("------|", length(@providers))}
    #{generate_markdown_rows(matrix)}
    
    ## Legend
    - ✅ Fully supported and tested
    - ❌ Not working or failing tests
    - ⏭️ Skipped (no API key or disabled)
    - ❓ Unknown or not tested
    """
    
    File.write!("test/reports/capability_matrix.md", content)
  end
end
```

### Phase 4: Response Capture System

```elixir
defmodule ExLLM.Testing.ResponseCapture do
  @moduledoc """
  Captures actual API responses for debugging and analysis
  """
  
  def capture(provider, capability, request, response, metadata \\ %{}) do
    if capture_enabled?() do
      data = %{
        timestamp: DateTime.utc_now(),
        provider: provider,
        capability: capability,
        request: sanitize_request(request),
        response: response,
        metadata: Map.merge(metadata, %{
          duration_ms: metadata[:duration_ms],
          tokens_used: metadata[:tokens_used],
          cost: metadata[:cost]
        })
      }
      
      save_capture(provider, capability, data)
    end
  end
  
  defp sanitize_request(request) do
    # Remove API keys and sensitive data
    request
    |> Map.drop([:api_key, :authorization])
    |> Map.update(:headers, [], &sanitize_headers/1)
  end
  
  defp save_capture(provider, capability, data) do
    dir = "test/responses/#{Date.utc_today()}"
    File.mkdir_p!(dir)
    
    filename = "#{dir}/#{provider}_#{capability}_#{timestamp()}.json"
    File.write!(filename, Jason.encode!(data, pretty: true))
    
    # Also append to daily summary
    append_to_summary(provider, capability, data)
  end
end
```

### Phase 5: CI/CD Configuration

```yaml
# .github/workflows/test.yml
name: Test Suite

on:
  push:
    branches: [main]
  pull_request:
  schedule:
    - cron: '0 2 * * *'  # Nightly at 2 AM UTC
  workflow_dispatch:
    inputs:
      provider:
        description: 'Specific provider to test'
        required: false
        type: choice
        options:
          - all
          - openai
          - anthropic
          - gemini
          - groq
          - ollama

jobs:
  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.17'
          otp-version: '26'
      - run: mix deps.get
      - run: mix test.unit
      - uses: actions/upload-artifact@v3
        if: failure()
        with:
          name: unit-test-logs
          path: _build/test/logs

  integration-mocked:
    name: Integration Tests (Mocked)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.17'
          otp-version: '26'
      - run: mix deps.get
      - run: mix test.mock
      
  integration-live:
    name: Integration Tests (Live)
    runs-on: ubuntu-latest
    if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'
    strategy:
      fail-fast: false
      matrix:
        provider: [openai, anthropic, gemini, groq, ollama]
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.17'
          otp-version: '26'
      - run: mix deps.get
      - name: Run Provider Tests
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GOOGLE_API_KEY: ${{ secrets.GOOGLE_API_KEY }}
          GROQ_API_KEY: ${{ secrets.GROQ_API_KEY }}
        run: |
          if [ "${{ github.event.inputs.provider }}" = "all" ] || [ "${{ github.event.inputs.provider }}" = "${{ matrix.provider }}" ]; then
            mix test.live.${{ matrix.provider }}
          fi
      - run: mix test.matrix.report
      - uses: actions/upload-artifact@v3
        with:
          name: capability-matrix-${{ matrix.provider }}
          path: test/reports/capability_matrix.md
```

## Usage Examples

### Developer Workflow

```bash
# Quick unit tests during development
mix test.unit

# Test specific capability across all providers
mix test.capability chat

# Test specific provider
mix test.live.openai

# Run smoke tests before commit
mix test.smoke

# Generate full capability matrix
mix test.matrix

# Debug with response capture
CAPTURE_RESPONSES=true mix test.live.anthropic
```

### CI Workflow

```bash
# PR validation (fast)
mix test.ci.pr

# Nightly full validation
mix test.ci.nightly

# Generate and publish matrix
mix test.matrix
```

## Migration Path

### Week 1: Foundation
1. Tag all existing tests
2. Create directory structure
3. Implement basic mix aliases

### Week 2: Reporting
1. Implement matrix reporter
2. Add response capture
3. Update CI configuration

### Week 3: Optimization
1. Add parallel execution
2. Implement rate limiting
3. Add retry logic

### Week 4: Polish
1. Documentation
2. Contributor guide
3. Performance tuning

## Best Practices

### Writing Tests

1. **Always tag appropriately**
   ```elixir
   @tag :live
   @tag provider: :openai
   @tag capability: :streaming
   test "OpenAI streaming chat" do
     # test implementation
   end
   ```

2. **Use consistent naming**
   ```elixir
   # Good
   test "provider can list available models"
   test "provider handles streaming responses"
   
   # Bad
   test "test models"
   test "streaming"
   ```

3. **Capture meaningful data**
   ```elixir
   response = ExLLM.chat(messages, model: "gpt-4")
   
   ResponseCapture.capture(
     :openai,
     :chat,
     %{messages: messages, model: "gpt-4"},
     response,
     %{duration_ms: duration}
   )
   ```

### Maintaining Tests

1. **Regular cleanup**: Remove obsolete tests
2. **Update tags**: When capabilities change
3. **Monitor flaky tests**: Add to quarantine if needed
4. **Review matrix**: Ensure accuracy monthly

## Metrics & Monitoring

### Key Metrics
- Test execution time by category
- Provider success rates
- Capability coverage percentage
- Flaky test frequency

### Dashboards
- GitHub Actions summary
- Capability matrix trends
- Cost per test run
- API error rates

## Future Enhancements

1. **Record/Playback System**: Cache expensive API calls
2. **Contract Testing**: Provider API compatibility
3. **Performance Benchmarks**: Track response times
4. **Cost Optimization**: Minimize API usage
5. **Automated Alerts**: Provider degradation detection