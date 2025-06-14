# ExLLM Test Tagging Strategy

This document outlines the test tagging strategy for the ExLLM project, moving away from generic `@tag :skip` to more meaningful and actionable tags.

## Philosophy

Tests should never be permanently skipped. Instead, they should be tagged based on their **requirements** and **characteristics**, allowing for dynamic execution based on the current environment and context.

## Tag Categories

### 1. Test Type/Scope

- `@tag :unit` - Pure unit tests with no external dependencies (implicit default)
- `@tag :integration` - Tests that interact with external services or cross process boundaries
- `@tag :contract` - Tests that verify API contracts with providers

### 2. Requirements (Replaces @tag :skip)

- `@tag :requires_api_key` - Requires valid API key(s) to run
- `@tag :requires_oauth` - Requires OAuth2 tokens or authentication
- `@tag :requires_env` - Requires specific environment variables
- `@tag :requires_resource` - Requires pre-existing resources (specify in tag value)
  - Example: `@tag requires_resource: :tuned_model`
  - Example: `@tag requires_resource: :corpus`
- `@tag :requires_service` - Requires specific service to be running
  - Example: `@tag requires_service: :ollama`
  - Example: `@tag requires_service: :lmstudio`

### 3. Performance Characteristics

- `@tag :slow` - Tests that take more than 5 seconds
- `@tag :very_slow` - Tests that take more than 30 seconds
- `@tag :benchmark` - Performance benchmark tests

### 4. Network/External Dependencies

- `@tag :external` - Makes external network calls
- `@tag :live_api` - Calls real API endpoints (not mocked)
- `@tag :quota_sensitive` - Consumes API quota/credits

### 5. Stability/Lifecycle

- `@tag :wip` - Work in progress, known to be broken
- `@tag :flaky` - Known intermittent failures
- `@tag :experimental` - Testing experimental features
- `@tag :beta` - Testing beta features

### 6. Provider-Specific

- `@tag provider: :anthropic`
- `@tag provider: :openai`
- `@tag provider: :gemini`
- `@tag provider: :ollama`
- etc.

## Implementation

### 1. Custom Test Case Module

Create `test/support/ex_llm_case.ex`:

```elixir
defmodule ExLLM.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import ExLLM.Case
      import ExLLM.TestHelpers
    end
  end

  setup %{tags: tags} = context do
    cond do
      # Check API key requirements
      tags[:requires_api_key] ->
        check_api_key_requirement(tags)
      
      # Check OAuth requirements
      tags[:requires_oauth] ->
        check_oauth_requirement(tags)
      
      # Check service requirements
      tags[:requires_service] ->
        check_service_requirement(tags)
      
      # Check resource requirements
      tags[:requires_resource] ->
        check_resource_requirement(tags)
      
      # Check environment requirements
      tags[:requires_env] ->
        check_env_requirement(tags)
      
      true ->
        :ok
    end
  end

  defp check_api_key_requirement(tags) do
    provider = tags[:provider] || infer_provider_from_module()
    
    case provider do
      :anthropic ->
        if System.get_env("ANTHROPIC_API_KEY") do
          :ok
        else
          {:skip, "Test requires ANTHROPIC_API_KEY environment variable"}
        end
      
      :openai ->
        if System.get_env("OPENAI_API_KEY") do
          :ok
        else
          {:skip, "Test requires OPENAI_API_KEY environment variable"}
        end
      
      # ... other providers
      
      _ ->
        {:skip, "Test requires API key for #{provider}"}
    end
  end

  defp check_oauth_requirement(tags) do
    if ExLLM.Test.GeminiOAuth2Helper.oauth_available?() do
      case ExLLM.Test.GeminiOAuth2Helper.get_valid_token() do
        {:ok, token} -> {:ok, oauth_token: token}
        _ -> {:skip, "Test requires valid OAuth2 token"}
      end
    else
      {:skip, "Test requires OAuth2 authentication - run: elixir scripts/setup_oauth2.exs"}
    end
  end

  defp check_service_requirement(tags) do
    service = tags[:requires_service]
    
    case service do
      :ollama ->
        if ExLLM.Adapters.Ollama.configured?() do
          :ok
        else
          {:skip, "Test requires Ollama service to be running"}
        end
      
      :lmstudio ->
        if ExLLM.Adapters.LMStudio.configured?() do
          :ok
        else
          {:skip, "Test requires LM Studio to be running"}
        end
      
      _ ->
        {:skip, "Test requires #{service} service"}
    end
  end

  defp check_resource_requirement(tags) do
    resource = tags[:requires_resource]
    
    case resource do
      :tuned_model ->
        if System.get_env("TEST_TUNED_MODEL") do
          :ok
        else
          {:skip, "Test requires a tuned model - set TEST_TUNED_MODEL env var"}
        end
      
      :corpus ->
        {:skip, "Test requires pre-existing corpus"}
      
      _ ->
        {:skip, "Test requires resource: #{resource}"}
    end
  end

  defp check_env_requirement(tags) do
    env_vars = List.wrap(tags[:requires_env])
    missing = Enum.filter(env_vars, &(System.get_env(&1) == nil))
    
    if Enum.empty?(missing) do
      :ok
    else
      {:skip, "Test requires environment variables: #{Enum.join(missing, ", ")}"}
    end
  end
end
```

### 2. Test Helper Configuration

Update `test/test_helper.exs`:

```elixir
ExUnit.start()

# Configure default exclusions for fast local development
ExUnit.configure(exclude: [
  # Exclude by default to speed up local development
  integration: true,
  external: true,
  slow: true,
  very_slow: true,
  quota_sensitive: true,
  flaky: true,
  wip: true,
  
  # Include by default (override previous exclusions)
  unit: false
])

# Load support files
Code.require_file("test/support/ex_llm_case.ex")
```

### 3. Mix Aliases

Add to `mix.exs`:

```elixir
defp aliases do
  [
    # Fast local development tests
    "test.fast": ["test --exclude integration --exclude external --exclude slow"],
    
    # Unit tests only
    "test.unit": ["test --only unit"],
    
    # Integration tests (requires API keys)
    "test.integration": ["test --only integration"],
    
    # Provider-specific tests
    "test.anthropic": ["test --only provider:anthropic"],
    "test.openai": ["test --only provider:openai"],
    "test.gemini": ["test --only provider:gemini"],
    
    # CI configurations
    "test.ci": ["test --exclude wip --exclude flaky --exclude quota_sensitive"],
    "test.ci.full": ["test --exclude wip --exclude flaky"],
    
    # All tests including slow ones
    "test.all": ["test --include slow --include very_slow --include integration --include external"],
    
    # Experimental/beta features
    "test.experimental": ["test --only experimental --only beta"]
  ]
end
```

## Migration Plan

### Phase 1: Infrastructure (Week 1)
1. Create `ExLLM.Case` module
2. Update `test_helper.exs` with exclusions
3. Add mix aliases
4. Test the setup with a few pilot tests

### Phase 2: Tag Audit (Week 2)
1. Create spreadsheet of all 138 `@tag :skip` tests
2. Categorize each by actual requirement
3. Group by migration difficulty

### Phase 3: Migration (Weeks 3-4)
1. Start with `requires_api_key` tests (easiest)
2. Move to `requires_oauth` tests
3. Handle `requires_resource` tests
4. Address remaining edge cases

### Phase 4: Documentation (Week 5)
1. Update CONTRIBUTING.md
2. Update README test section
3. Create developer onboarding guide
4. Document CI/CD setup

## Example Migration

### Before:
```elixir
defmodule ExLLM.Adapters.AnthropicIntegrationTest do
  use ExUnit.Case
  
  @tag :skip
  test "creates chat completion" do
    # test implementation
  end
end
```

### After:
```elixir
defmodule ExLLM.Adapters.AnthropicIntegrationTest do
  use ExLLM.Case, async: false
  
  @tag :integration
  @tag :external
  @tag :live_api
  @tag :requires_api_key
  @tag provider: :anthropic
  test "creates chat completion" do
    # test implementation
  end
end
```

## Benefits

1. **Clarity**: Tags explain WHY a test has special requirements
2. **Flexibility**: Run different test suites based on context
3. **CI/CD Optimization**: Fast feedback loops with targeted test runs
4. **Developer Experience**: Clear skip messages when requirements aren't met
5. **No Dead Tests**: Every test is runnable given the right conditions

## Future Enhancements

1. **Automatic API Key Detection**: Detect which providers have keys available
2. **Cost Tracking**: Track API costs during test runs
3. **Parallel Test Execution**: Use tags to identify parallelizable tests
4. **Test Impact Analysis**: Use tags to run only affected tests based on changes