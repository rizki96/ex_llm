# Test Refactoring Example

This shows how to refactor tests from `@tag :skip` to meaningful tags.

## Example 1: Network Error Test

### Before:
```elixir
@tag :skip
test "returns error for network issues" do
  # Test network error handling
  # This test requires mocking the HTTP client
  assert {:error, %{reason: :network_error}} =
           Models.list_models(config_provider: network_error_provider())
end
```

### After:
```elixir
@tag :unit
@tag :requires_mock
@tag provider: :gemini
test "returns error for network issues" do
  # Test network error handling
  assert {:error, %{reason: :network_error}} =
           Models.list_models(config_provider: network_error_provider())
end
```

## Example 2: Integration Test

### Before:
```elixir
@tag :skip
test "fetches real models from Anthropic API" do
  # Requires API key
  {:ok, models} = Anthropic.list_models()
  assert length(models) > 0
end
```

### After:
```elixir
@tag :integration
@tag :external
@tag :live_api
@tag :requires_api_key
@tag provider: :anthropic
test "fetches real models from Anthropic API" do
  {:ok, models} = Anthropic.list_models()
  assert length(models) > 0
end
```

## Example 3: OAuth2 Test

### Before:
```elixir
@tag :skip
test "creates corpus with OAuth2" do
  # Needs OAuth token
  {:ok, corpus} = Corpus.create_corpus(%{display_name: "Test"})
  assert corpus.name
end
```

### After:
```elixir
@describetag :integration
@describetag :external
@describetag :requires_oauth
@describetag provider: :gemini

test "creates corpus with OAuth2", %{oauth_token: token} do
  {:ok, corpus} = Corpus.create_corpus(
    %{display_name: "Test"},
    oauth_token: token
  )
  assert corpus.name
end
```

## Example 4: Resource-Dependent Test

### Before:
```elixir
@tag :skip
test "uses tuned model for generation" do
  # Requires existing tuned model
  model = "tunedModels/my-model-123"
  {:ok, response} = Tuning.generate_content(model, request)
  assert response
end
```

### After:
```elixir
@tag :integration
@tag :external
@tag :requires_resource, requires_resource: :tuned_model
@tag :slow
@tag provider: :gemini
test "uses tuned model for generation" do
  model = System.get_env("TEST_TUNED_MODEL") || 
          raise "TEST_TUNED_MODEL env var required"
  
  {:ok, response} = Tuning.generate_content(model, request)
  assert response
end
```

## Example 5: Service-Dependent Test

### Before:
```elixir
@tag :skip
test "streams from local Ollama" do
  # Requires Ollama running
  {:ok, stream} = Ollama.stream_chat(messages)
  chunks = Enum.to_list(stream)
  assert length(chunks) > 0
end
```

### After:
```elixir
@tag :integration
@tag :requires_service, requires_service: :ollama
@tag :slow
@tag provider: :ollama
test "streams from local Ollama" do
  {:ok, stream} = Ollama.stream_chat(messages)
  chunks = Enum.to_list(stream)
  assert length(chunks) > 0
end
```

## Running Different Test Suites

With the new tagging system:

```bash
# Fast unit tests only (default)
mix test

# Include integration tests
mix test --include integration

# Run only Anthropic tests
mix test --only provider:anthropic

# Run all external API tests
mix test --only external

# Run everything except flaky tests
mix test.ci

# Run specific provider with API keys
ANTHROPIC_API_KEY=sk-xxx mix test --only provider:anthropic --include integration
```