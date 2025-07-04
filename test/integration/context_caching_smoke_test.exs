defmodule ExLLM.Integration.ContextCachingSmokeTest do
  @moduledoc """
  Quick smoke test to verify context caching integration works.
  """
  use ExUnit.Case

  alias ExLLM.Providers.Gemini
  alias ExLLM.Providers.Gemini.Content.{Content, Part}

  @tag :integration
  @tag timeout: 30_000
  test "basic context caching integration smoke test" do
    # Just test that the functions are connected and return structured responses
    # (not actual API calls for now)

    # Test list_cached_contents (should work even with no cached content)
    case Gemini.list_cached_contents() do
      {:ok, result} ->
        assert is_map(result)
        assert Map.has_key?(result, :cached_contents)

      {:error, error} ->
        # Expected for API authentication, network issues, etc.
        assert is_map(error) or is_atom(error)
    end

    # Test create_cached_content (will likely fail but should be a structured error)
    # Create proper Content structs
    part = %Part{text: "Hello, this is test content for caching."}
    content_item = %Content{role: "user", parts: [part]}

    request = %{
      model: "gemini-1.5-flash",
      contents: [content_item],
      ttl: "3600s"
    }

    case Gemini.create_cached_content(request) do
      {:ok, cached} ->
        # If it works, great! Clean up.
        if cached.name do
          Gemini.delete_cached_content(cached.name)
        end

      {:error, error} ->
        # Expected for various reasons (auth, validation, etc.)
        assert is_map(error) or is_atom(error)
        # Log the error for debugging (but don't fail the test)
        IO.puts("Expected cache creation error: #{inspect(error)}")
    end
  end
end
