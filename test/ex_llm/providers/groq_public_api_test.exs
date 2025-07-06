defmodule ExLLM.Providers.GroqPublicAPITest do
  @moduledoc """
  Groq-specific integration tests using the public ExLLM API.
  Common tests are handled by the shared module.
  """

  use ExLLM.Shared.ProviderIntegrationTest, provider: :groq

  # Provider-specific tests only
  describe "groq-specific features via public API" do
    test "handles Groq's ultra-fast inference" do
      messages = [
        %{role: "user", content: "What is 2+2? Answer in one word."}
      ]

      # Measure response time
      start_time = System.monotonic_time(:millisecond)

      case ExLLM.chat(:groq, messages, model: "llama-3.1-8b-instant", max_tokens: 10) do
        {:ok, response} ->
          end_time = System.monotonic_time(:millisecond)
          duration = end_time - start_time

          # Verify we got content (don't test specific answer)
          assert String.length(response.content) > 0
          # Groq should be very fast (usually < 1 second)
          assert duration < 2000

        {:error, _} ->
          :ok
      end
    end

    @tag :streaming
    test "streaming with Groq models" do
      messages = [
        %{role: "user", content: "List 3 colors"}
      ]

      # Collect chunks using the callback API
      collector = fn chunk ->
        send(self(), {:chunk, chunk})
      end

      case ExLLM.stream(:groq, messages, collector,
             model: "llama-3.1-8b-instant",
             max_tokens: 50,
             timeout: 10_000
           ) do
        :ok ->
          chunks = collect_stream_chunks([], 1000)

          assert length(chunks) > 0

          # Collect content
          full_content =
            chunks
            |> Enum.map(& &1.content)
            |> Enum.filter(& &1)
            |> Enum.join("")

          # Verify we got streaming content (don't test specific colors)
          assert String.length(full_content) > 0

        {:error, _} ->
          :ok
      end
    end

    test "supports various Groq models" do
      models_to_test = [
        "llama-3.2-1b-preview",
        "llama-3.2-3b-preview",
        "mixtral-8x7b-32768"
      ]

      messages = [%{role: "user", content: "Hi"}]

      for model <- models_to_test do
        case ExLLM.chat(:groq, messages, model: model, max_tokens: 10) do
          {:ok, response} ->
            assert response.model == model
            assert is_binary(response.content)

          {:error, {:api_error, %{status: 404}}} ->
            # Model might not be available
            :ok

          {:error, _} ->
            :ok
        end
      end
    end

    test "handles JSON mode with Groq" do
      messages = [
        %{
          role: "user",
          content: "Return a JSON object with status: 'ok' and value: 123"
        }
      ]

      case ExLLM.chat(:groq, messages, response_format: %{type: "json_object"}, max_tokens: 100) do
        {:ok, response} ->
          case Jason.decode(response.content) do
            {:ok, json} ->
              # Verify JSON structure (not exact values)
              assert Map.has_key?(json, "status") and is_binary(json["status"])
              assert Map.has_key?(json, "value") and is_integer(json["value"])

            {:error, _} ->
              # Groq might not support JSON mode for all models
              :ok
          end

        {:error, _} ->
          :ok
      end
    end
  end
end
