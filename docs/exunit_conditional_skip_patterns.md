# ExUnit Conditional Test Skipping Patterns

ExUnit does not support returning `{:skip, reason}` from `setup` callbacks. This document outlines the recommended patterns for conditionally skipping tests.

## Problem

When you try to skip a test from a setup callback:

```elixir
setup do
  if some_condition do
    {:skip, "Condition not met"}  # This doesn't work!
  else
    :ok
  end
end
```

You'll get an error because ExUnit doesn't recognize `{:skip, reason}` as a valid return value from setup callbacks.

## Solutions

### 1. Module-Level Conditional Skip (Recommended)

Skip an entire test module based on compile-time conditions:

```elixir
defmodule MyTest do
  use ExUnit.Case
  
  # Check condition at compile time
  if not System.get_env("API_KEY") do
    @moduletag :skip
  end
  
  test "requires API key" do
    # All tests in this module will be skipped if no API key
  end
end
```

### 2. Tag-Based Exclusion

Use tags and configure ExUnit to exclude them:

```elixir
# In your test module
defmodule MyTest do
  use ExUnit.Case
  
  @tag :requires_api_key
  test "api test" do
    # test implementation
  end
end

# In test_helper.exs
if not System.get_env("API_KEY") do
  ExUnit.configure(exclude: [:requires_api_key])
end
```

### 3. Conditional Test Definition

Define tests conditionally at compile time:

```elixir
defmodule MyTest do
  use ExUnit.Case
  
  if System.get_env("FEATURE_ENABLED") do
    test "feature test" do
      assert true
    end
  end
end
```

### 4. Runtime Checks in Tests

Handle conditions within the test itself:

```elixir
test "conditional test" do
  case System.get_env("API_KEY") do
    nil ->
      IO.puts("Skipping: API key not available")
      # Note: This shows as "passed" not "skipped"
    key ->
      # Your actual test logic
      assert is_binary(key)
  end
end
```

### 5. Custom Skip Macro

Create a macro for cleaner conditional tests:

```elixir
defmodule TestMacros do
  defmacro test_with_env(name, env_var, do: block) do
    quote do
      if System.get_env(unquote(env_var)) do
        test unquote(name), do: unquote(block)
      else
        @tag :skip
        test unquote(name) do
          flunk("Missing environment variable: #{unquote(env_var)}")
        end
      end
    end
  end
end

# Usage
import TestMacros

test_with_env "oauth test", "OAUTH_TOKEN" do
  token = System.get_env("OAUTH_TOKEN")
  assert is_binary(token)
end
```

### 6. Setup Context Pattern

Pass skip information through context:

```elixir
setup do
  if oauth_available?() do
    {:ok, oauth_token: get_token()}
  else
    {:ok, skip_oauth: true}
  end
end

test "oauth test", context do
  if context[:skip_oauth] do
    IO.puts("OAuth not available - skipping test logic")
  else
    # Your test logic
    assert context.oauth_token
  end
end
```

## Real-World Example: OAuth2 Tests

Here's how we handle OAuth2 token availability in the ExLLM project:

```elixir
defmodule ExLLM.Adapters.Gemini.OAuth2APIsTest do
  use ExUnit.Case, async: false
  
  alias ExLLM.Test.GeminiOAuth2Helper
  
  # Skip entire module if OAuth2 is not available
  if not GeminiOAuth2Helper.oauth_available?() do
    @moduletag :skip
  else
    @moduletag :oauth2
  end
  
  setup do
    # Get OAuth token if available
    case GeminiOAuth2Helper.get_valid_token() do
      {:ok, token} ->
        {:ok, oauth_token: token}
      _ ->
        {:ok, oauth_token: nil}
    end
  end
  
  test "oauth api test", %{oauth_token: token} do
    # Token will be nil if module wasn't skipped but token unavailable
    assert is_binary(token)
    # Your test logic here
  end
end
```

## Best Practices

1. **Prefer compile-time decisions**: Use module attributes like `@moduletag :skip` when possible
2. **Use ExUnit.configure for runtime exclusions**: Good for environment-based skipping
3. **Document skip conditions**: Make it clear why tests might be skipped
4. **Provide setup instructions**: Tell users how to enable skipped tests
5. **Consider CI/CD**: Ensure critical tests aren't accidentally skipped in CI

## Common Pitfalls

1. **Don't return `{:skip, reason}` from setup**: It's not supported
2. **Runtime checks show as "passed"**: Tests that skip internally still count as passed
3. **Compile-time checks are cached**: Changes to environment variables may require recompilation
4. **Tag inheritance**: `@moduletag` affects all tests in the module, including those in `describe` blocks