defmodule ExLLM.Testing.OAuth2TestCase do
  @moduledoc """
  Shared OAuth2 test case module for Gemini OAuth2 API tests.

  This module provides common setup, teardown, and helper functions
  for OAuth2-based tests, reducing duplication across test files.
  """

  defmacro __using__(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 300_000)

    quote do
      use ExUnit.Case, async: false

      import ExLLM.Testing.TestCacheHelpers

      import ExLLM.Testing.TestHelpers,
        only: [assert_eventually: 2, wait_for_resource: 2, eventual_consistency_timeout: 0]

      @moduletag timeout: unquote(timeout)
      @moduletag :eventual_consistency

      # Always tag as OAuth2 - skipping will be handled at runtime
      @moduletag :oauth2

      # Global cleanup before any tests run
      setup_all do
        if Code.ensure_loaded?(ExLLM.Testing.GeminiOAuth2Helper) do
          try do
            if apply(ExLLM.Testing.GeminiOAuth2Helper, :oauth_available?, []) do
              IO.puts("Starting OAuth2 tests - performing aggressive cleanup...")
              apply(ExLLM.Testing.GeminiOAuth2Helper, :global_cleanup, [])
              Process.sleep(1000)
            end
          rescue
            _ -> :ok
          end
        end

        :ok
      end

      # Setup OAuth token for tests with automatic refresh
      setup context do
        setup_test_cache(context)

        on_exit(fn ->
          ExLLM.Testing.TestCacheDetector.clear_test_context()

          if Code.ensure_loaded?(ExLLM.Testing.GeminiOAuth2Helper) do
            try do
              if apply(ExLLM.Testing.GeminiOAuth2Helper, :oauth_available?, []) do
                apply(ExLLM.Testing.GeminiOAuth2Helper, :quick_cleanup, [])
              end
            rescue
              _ -> :ok
            end
          end
        end)

        # Use advanced setup with token refresh
        context = ExLLM.Testing.EnvHelper.setup_oauth(context)

        # Double-check we have a token (should be set by setup_oauth if available)
        if Map.has_key?(context, :oauth_token) do
          {:ok, context}
        else
          # Fallback to the original method if setup_oauth didn't work
          if Code.ensure_loaded?(ExLLM.Testing.GeminiOAuth2Helper) do
            try do
              case apply(ExLLM.Testing.GeminiOAuth2Helper, :get_valid_token, []) do
                {:ok, token} ->
                  {:ok, Map.put(context, :oauth_token, token)}

                _ ->
                  # This shouldn't happen if module is tagged to skip
                  {:ok, Map.put(context, :oauth_token, nil)}
              end
            rescue
              _ ->
                {:ok, Map.put(context, :oauth_token, nil)}
            end
          else
            {:ok, Map.put(context, :oauth_token, nil)}
          end
        end
      end

      # Helper function to match Gemini API errors
      def gemini_api_error?(result, expected_status) do
        case result do
          {:error, %{code: ^expected_status}} ->
            true

          {:error, %{status: ^expected_status}} ->
            true

          {:error, %{message: message}} when is_binary(message) ->
            String.contains?(message, "status: #{expected_status}") or
              String.contains?(message, "\"code\" => #{expected_status}")

          {:error, %{reason: :network_error, message: message}} when is_binary(message) ->
            String.contains?(message, "status: #{expected_status}") or
              String.contains?(message, "\"code\" => #{expected_status}")

          _ ->
            false
        end
      end

      # Helper function to check if error indicates resource not found
      def resource_not_found?(result) do
        gemini_api_error?(result, 404) or
          gemini_api_error?(result, 403) or
          (match?({:error, %{message: message}} when is_binary(message), result) and
             String.contains?(elem(result, 1).message, "may not exist"))
      end

      # Generate unique resource names for tests
      def unique_name(prefix) do
        "#{prefix}-#{System.unique_integer([:positive]) |> Integer.to_string() |> String.downcase()}"
      end
    end
  end
end
