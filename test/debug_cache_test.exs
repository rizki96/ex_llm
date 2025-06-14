defmodule DebugCacheTest do
  use ExUnit.Case
  import ExLLM.TestCacheHelpers

  @moduletag :integration

  setup context do
    IO.puts("\n=== Debug Cache Test Setup ===")
    IO.puts("Mix.env: #{Mix.env()}")

    # Get config
    config = ExLLM.TestCacheConfig.get_config()
    IO.puts("Config enabled: #{config.enabled}")
    IO.puts("Config auto_detect: #{config.auto_detect}")
    IO.puts("Config cache_integration_tests: #{config.cache_integration_tests}")

    # Enable cache
    enable_cache_debug()
    setup_test_cache(context)

    # Check detector
    IO.puts("should_cache_responses?: #{ExLLM.TestCacheDetector.should_cache_responses?()}")

    # Check context
    case ExLLM.TestCacheDetector.get_current_test_context() do
      {:ok, ctx} ->
        IO.puts("Test context found: #{inspect(ctx)}")

      :error ->
        IO.puts("No test context found")
    end

    on_exit(fn ->
      ExLLM.TestCacheDetector.clear_test_context()
    end)
  end

  test "debug cache detection" do
    IO.puts("\n=== Inside test ===")
    IO.puts("should_cache_responses?: #{ExLLM.TestCacheDetector.should_cache_responses?()}")

    # Try to make a call
    messages = [%{role: "user", content: "test"}]

    # Intercept directly
    request = %{
      url: "https://api.openai.com/v1/chat/completions",
      body: %{messages: messages},
      headers: [],
      method: "POST"
    }

    IO.puts("\nTrying cache strategy...")
    result = ExLLM.TestCacheStrategy.execute(request, [])
    IO.puts("Strategy result: #{inspect(result)}")

    assert true
  end
end
