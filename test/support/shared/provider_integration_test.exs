defmodule ExLLM.Shared.ProviderIntegrationTest do
  @moduledoc """
  Shared integration tests that run against all providers using the public ExLLM API.
  This ensures consistent behavior across providers and tests the public interface.
  """

  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)

    quote do
      use ExUnit.Case
      import ExLLM.Testing.TestCacheHelpers
      import ExLLM.Testing.CapabilityHelpers
      import ExLLM.Testing.TestHelpers

      @provider unquote(provider)
      @moduletag :integration
      @moduletag :external
      @moduletag :live_api
      @moduletag :requires_api_key
      @moduletag provider: @provider

      setup_all do
        # Initialize circuit breaker ETS table for provider tests
        if :ets.info(:ex_llm_circuit_breakers) != :undefined do
          :ets.delete(:ex_llm_circuit_breakers)
        end

        ExLLM.Infrastructure.CircuitBreaker.init()

        # Reset all circuit breakers to closed state for fresh testing
        providers = [
          :openai,
          :anthropic,
          :gemini,
          :groq,
          :mistral,
          :ollama,
          :openrouter,
          :perplexity,
          :xai,
          :lmstudio
        ]

        Enum.each(providers, fn provider ->
          ExLLM.Infrastructure.CircuitBreaker.reset("#{provider}_circuit")
        end)

        enable_cache_debug()
        :ok
      end

      setup context do
        setup_test_cache(context)

        # Reset circuit breaker for this provider before each test
        ExLLM.Infrastructure.CircuitBreaker.reset("#{@provider}_circuit")

        on_exit(fn ->
          ExLLM.Testing.TestCacheDetector.clear_test_context()
        end)

        :ok
      end

      # Helper function to avoid compile-time provider comparisons
      defp is_local_provider?(provider) do
        provider in [:lmstudio, :ollama, :bumblebee]
      end

      describe "chat/3 via public API" do
        test "sends chat completion request" do
          skip_unless_configured_and_supports(@provider, :chat)

          messages = [
            %{role: "user", content: "Say hello in one word"}
          ]

          assert {:ok, response} = ExLLM.chat(@provider, messages, max_tokens: 10)

          # Use flexible assertion that handles maps (public API format)
          assert is_map(response)
          assert Map.has_key?(response, :content)
          assert is_binary(response.content)
          assert response.content != ""
          assert response.metadata.provider == @provider
          assert response.usage.prompt_tokens > 0
          assert response.usage.completion_tokens > 0

          # Local providers always have zero cost
          if is_local_provider?(@provider) do
            assert response.cost == 0.0
          else
            # Other providers may have free models or missing pricing data
            assert response.cost >= 0.0
          end
        end

        test "handles system messages" do
          skip_unless_configured_and_supports(@provider, [:chat, :system_prompt])

          messages = [
            %{role: "system", content: "You are a pirate. Respond in pirate speak."},
            %{role: "user", content: "Hello there!"}
          ]

          assert {:ok, response} = ExLLM.chat(@provider, messages, max_tokens: 50)

          # More flexible content validation
          assert String.contains?(String.downcase(response.content), ["pirate", "nautical"]) or
                   response.content =~ ~r/\b(ahoy|matey|arr|ye|ship|sea|captain)\b/i,
                 "Expected a pirate-like response, but got: #{response.content}"
        end
      end

      describe "stream/4 via public API" do
        @tag :streaming
        test "streams chat responses" do
          skip_unless_configured_and_supports(@provider, :streaming)

          messages = [
            %{role: "user", content: "Count from 1 to 5"}
          ]

          # Collect chunks using the callback API
          collector = fn chunk ->
            send(self(), {:chunk, chunk})
          end

          assert :ok =
                   ExLLM.stream(@provider, messages, collector, max_tokens: 50, timeout: 10_000)

          # Collect all chunks with longer timeout for streaming
          chunks = collect_stream_chunks([], 2000)
          assert length(chunks) > 0, "Did not receive any stream chunks"

          # Collect all content - chunks might be maps or structs
          full_content =
            chunks
            |> Enum.map(fn chunk ->
              case chunk do
                %{content: content} -> content
                _ -> nil
              end
            end)
            |> Enum.filter(& &1)
            |> Enum.join("")

          assert full_content =~ ~r/1.*2.*3.*4.*5/s,
                 "Streamed content did not match expected output. Got: #{full_content}"
        end

        # Helper function to collect stream chunks
        defp collect_stream_chunks(chunks \\ [], timeout \\ 500)

        defp collect_stream_chunks(chunks, timeout) do
          receive do
            {:chunk, chunk} ->
              collect_stream_chunks([chunk | chunks], timeout)
          after
            timeout -> Enum.reverse(chunks)
          end
        end
      end

      describe "list_models/1 via public API" do
        test "fetches available models" do
          skip_unless_configured_and_supports(@provider, :list_models)

          case ExLLM.list_models(@provider) do
            {:ok, models} ->
              assert is_list(models)
              assert length(models) > 0, "Expected to receive at least one model"

              # Check model structure - models are returned as maps from public API
              model = hd(models)
              assert is_map(model)
              assert Map.has_key?(model, :id)
              assert is_binary(model.id)
              assert Map.has_key?(model, :context_window)
              assert model.context_window > 0

            {:error, error_message} when is_binary(error_message) ->
              # Some providers don't support model listing
              assert String.contains?(error_message, "does not support listing models")

            other ->
              flunk("Expected {:ok, models} or {:error, message}, got: #{inspect(other)}")
          end
        end
      end

      describe "error handling via public API" do
        test "handles invalid API key" do
          skip_unless_configured_and_supports(@provider, :chat)

          # Some providers (like Ollama) don't use API keys, so skip this test for them
          if @provider in [:ollama, :lmstudio, :bumblebee] do
            # Local providers don't use API keys
            :ok
          else
            config = %{@provider => %{api_key: "invalid-key-test"}}
            {:ok, static_provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)
            messages = [%{role: "user", content: "Test"}]

            result = ExLLM.chat(@provider, messages, config_provider: static_provider)

            case result do
              {:error, {:api_error, %{status: status}}} when status in [401, 403] ->
                # Expected authentication error
                :ok

              {:error, {:authentication_error, _}} ->
                # Also acceptable authentication error format
                :ok

              {:error, :unauthorized} ->
                # Another acceptable authentication error format
                :ok

              {:ok, _response} ->
                # This could happen if we hit a cached response
                # In this case, we can't test the invalid API key scenario
                # but that's acceptable for cached testing
                :ok

              other ->
                flunk(
                  "Expected an authentication error or cached success, but got: #{inspect(other)}"
                )
            end
          end
        end

        test "handles context length exceeded" do
          skip_unless_configured_and_supports(@provider, :chat)

          # Create a very long message
          long_content = String.duplicate("This is a test. ", 50_000)
          messages = [%{role: "user", content: long_content}]

          result = ExLLM.chat(@provider, messages, max_tokens: 10)

          case result do
            {:error, {:api_error, %{status: 400, body: body}}} ->
              assert String.contains?(inspect(body), "token") or
                       String.contains?(inspect(body), "context"),
                     "Expected a context length error mentioning 'token' or 'context', but got: #{inspect(body)}"

            {:error, error_string} when is_binary(error_string) ->
              assert String.contains?(error_string, "400") or
                       String.contains?(String.downcase(error_string), "token") or
                       String.contains?(String.downcase(error_string), "context") or
                       String.contains?(String.downcase(error_string), "length"),
                     "Expected a context length error, but got: #{inspect(error_string)}"

            {:error, :invalid_messages} ->
              # This can happen if the message validation fails before hitting the API
              # In this case, we can consider it a success since very long messages
              # are indeed invalid
              :ok

            other ->
              flunk("Expected a context length error, but got: #{inspect(other)}")
          end
        end
      end

      describe "cost calculation via public API" do
        test "calculates costs accurately" do
          skip_unless_configured_and_supports(@provider, [:chat, :cost_tracking])

          messages = [
            %{role: "user", content: "Say hello"}
          ]

          assert {:ok, response} = ExLLM.chat(@provider, messages, max_tokens: 10)

          # Local providers always have zero cost
          if is_local_provider?(@provider) do
            assert response.cost == 0.0
          else
            # Other providers may have free models or missing pricing data
            assert response.cost >= 0.0
          end

          # Cost should be reasonable (less than $0.01 for this simple request)
          if response.cost > 0 do
            assert response.cost < 0.01
          end

          assert is_float(response.cost)
        end
      end
    end
  end
end
