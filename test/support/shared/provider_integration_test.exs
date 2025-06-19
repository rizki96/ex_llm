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

      @provider unquote(provider)
      @moduletag :integration
      @moduletag :external
      @moduletag :live_api
      @moduletag :requires_api_key
      @moduletag provider: @provider

      setup_all do
        enable_cache_debug()
        :ok
      end

      setup context do
        setup_test_cache(context)

        on_exit(fn ->
          ExLLM.Testing.TestCacheDetector.clear_test_context()
        end)

        :ok
      end

      describe "chat/3 via public API" do
        test "sends chat completion request" do
          messages = [
            %{role: "user", content: "Say hello in one word"}
          ]

          case ExLLM.chat(@provider, messages, max_tokens: 10) do
            {:ok, response} ->
              assert %ExLLM.Types.LLMResponse{} = response
              assert is_binary(response.content)
              assert response.content != ""
              assert response.provider == @provider
              assert response.usage.input_tokens > 0
              assert response.usage.output_tokens > 0
              assert response.cost > 0

            {:error, reason} ->
              IO.puts("Chat failed for #{@provider}: #{inspect(reason)}")
          end
        end

        test "handles system messages" do
          messages = [
            %{role: "system", content: "You are a pirate. Respond in pirate speak."},
            %{role: "user", content: "Hello there!"}
          ]

          case ExLLM.chat(@provider, messages, max_tokens: 50) do
            {:ok, response} ->
              # Should respond in pirate speak
              assert response.content =~ ~r/(ahoy|matey|arr|ye)/i

            {:error, _} ->
              :ok
          end
        end

        test "respects temperature setting" do
          messages = [
            %{role: "user", content: "Generate a random number between 1 and 10"}
          ]

          # Low temperature should give more consistent results
          results =
            for _ <- 1..3 do
              case ExLLM.chat(@provider, messages, temperature: 0.0, max_tokens: 10) do
                {:ok, response} -> response.content
                _ -> nil
              end
            end

          # Filter out nils
          valid_results = Enum.filter(results, & &1)

          if length(valid_results) >= 2 do
            # With temperature 0, results should be very similar
            [first | rest] = valid_results

            assert Enum.all?(rest, fn r ->
                     String.jaro_distance(first, r) > 0.8
                   end)
          end
        end
      end

      describe "stream/3 via public API" do
        @tag :streaming
        test "streams chat responses" do
          messages = [
            %{role: "user", content: "Count from 1 to 5"}
          ]

          case ExLLM.stream(@provider, messages, max_tokens: 50) do
            {:ok, stream} ->
              chunks = stream |> Enum.to_list()
              assert length(chunks) > 0

              # Collect all content
              full_content =
                chunks
                |> Enum.map(& &1.content)
                |> Enum.filter(& &1)
                |> Enum.join("")

              assert full_content =~ ~r/1.*2.*3.*4.*5/s

            {:error, reason} ->
              IO.puts("Stream failed for #{@provider}: #{inspect(reason)}")
          end
        end
      end

      describe "list_models/1 via public API" do
        test "fetches available models" do
          case ExLLM.list_models(@provider) do
            {:ok, models} ->
              assert is_list(models)
              assert length(models) > 0

              # Check model structure
              model = hd(models)
              assert %ExLLM.Types.Model{} = model
              assert is_binary(model.id)
              assert model.context_window > 0

            {:error, reason} ->
              IO.puts("Model listing failed for #{@provider}: #{inspect(reason)}")
          end
        end
      end

      describe "error handling via public API" do
        test "handles invalid API key" do
          config = %{@provider => %{api_key: "invalid-key-test"}}
          {:ok, provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)
          messages = [%{role: "user", content: "Test"}]

          case ExLLM.chat(@provider, messages, config_provider: provider) do
            {:error, {:api_error, %{status: status}}} when status in [401, 403] ->
              # Expected unauthorized error
              :ok

            {:error, _} ->
              # Other errors also acceptable
              :ok

            {:ok, _} ->
              flunk("Should have failed with invalid API key")
          end
        end

        test "handles context length exceeded" do
          # Create a very long message
          long_content = String.duplicate("This is a test. ", 50_000)
          messages = [%{role: "user", content: long_content}]

          case ExLLM.chat(@provider, messages, max_tokens: 10) do
            {:error, {:api_error, %{status: 400, body: body}}} ->
              # Should mention context length or tokens
              assert String.contains?(inspect(body), "token") ||
                       String.contains?(inspect(body), "context")

            {:error, _} ->
              :ok

            {:ok, _} ->
              flunk("Should have failed with context length error")
          end
        end
      end

      describe "cost calculation via public API" do
        test "calculates costs accurately" do
          messages = [
            %{role: "user", content: "Say hello"}
          ]

          case ExLLM.chat(@provider, messages, max_tokens: 10) do
            {:ok, response} ->
              assert response.cost > 0
              assert is_float(response.cost)
              # Cost should be reasonable (less than $0.01 for this simple request)
              assert response.cost < 0.01

            {:error, _} ->
              :ok
          end
        end
      end
    end
  end
end
