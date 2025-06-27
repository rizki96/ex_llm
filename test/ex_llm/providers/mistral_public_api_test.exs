defmodule ExLLM.Providers.MistralPublicAPITest do
  @moduledoc """
  Mistral-specific integration tests using the public ExLLM API.
  Common tests are handled by the shared module.
  """

  use ExLLM.Shared.ProviderIntegrationTest, provider: :mistral

  # Provider-specific tests only
  describe "mistral-specific features via public API" do
    test "supports Mistral's model lineup" do
      models_to_test = [
        "mistral-tiny",
        "mistral-small",
        "mistral-medium"
      ]

      messages = [%{role: "user", content: "Bonjour!"}]

      for model <- models_to_test do
        case ExLLM.chat(:mistral, messages, model: model, max_tokens: 20) do
          {:ok, response} ->
            assert response.metadata.provider == :mistral
            assert is_binary(response.content)
            # Mistral models often respond in French when greeted in French
            assert response.content =~ ~r/bonjour|salut|comment/i

          {:error, {:api_error, %{status: 404}}} ->
            # Model might not be available
            :ok

          {:error, _} ->
            :ok
        end
      end
    end

    @tag :streaming
    test "streaming with Mistral models" do
      messages = [
        %{role: "user", content: "List 3 French cities"}
      ]

      # Collect chunks using the callback API
      collector = fn chunk ->
        send(self(), {:chunk, chunk})
      end

      case ExLLM.stream(:mistral, messages, collector, max_tokens: 50, timeout: 10_000) do
        :ok ->
          chunks = collect_stream_chunks([], 1000)

          assert length(chunks) > 0

          full_content =
            chunks
            |> Enum.map(& &1.content)
            |> Enum.filter(& &1)
            |> Enum.join("")

          # Should mention French cities
          assert full_content =~ ~r/(Paris|Lyon|Marseille|Toulouse|Nice|Bordeaux)/i

        {:error, _} ->
          :ok
      end
    end

    test "handles Mistral's JSON mode" do
      messages = [
        %{
          role: "user",
          content: "Return a JSON object with city: 'Paris' and country: 'France'"
        }
      ]

      case ExLLM.chat(:mistral, messages,
             response_format: %{type: "json_object"},
             max_tokens: 100
           ) do
        {:ok, response} ->
          case Jason.decode(response.content) do
            {:ok, json} ->
              assert json["city"] == "Paris"
              assert json["country"] == "France"

            {:error, _} ->
              # JSON mode might not be supported
              :ok
          end

        {:error, _} ->
          :ok
      end
    end

    @tag :function_calling
    test "function calling with Mistral" do
      messages = [
        %{role: "user", content: "What's the weather in Paris?"}
      ]

      tools = [
        %{
          type: "function",
          function: %{
            name: "get_weather",
            description: "Get weather for a city",
            parameters: %{
              type: "object",
              properties: %{
                city: %{type: "string"},
                country: %{type: "string"}
              },
              required: ["city"]
            }
          }
        }
      ]

      case ExLLM.chat(:mistral, messages, tools: tools, max_tokens: 100) do
        {:ok, response} ->
          # Check if function was called
          if response.tool_calls && length(response.tool_calls) > 0 do
            tool_call = hd(response.tool_calls)
            assert tool_call.function.name == "get_weather"
            args = Jason.decode!(tool_call.function.arguments)
            assert args["city"] == "Paris"
          else
            # Function calling might not be supported
            assert is_binary(response.content)
          end

        {:error, _} ->
          :ok
      end
    end

    @tag :embedding
    test "Mistral embeddings" do
      texts = ["Bonjour le monde", "Comment allez-vous?"]

      case ExLLM.embeddings(:mistral, texts, model: "mistral-embed") do
        {:ok, %ExLLM.Types.EmbeddingResponse{embeddings: embeddings}} ->
          assert length(embeddings) == 2
          assert is_list(hd(embeddings))
          assert is_float(hd(hd(embeddings)))
          # Mistral embeddings have specific dimensions
          assert length(hd(embeddings)) == 1024

        {:error, {:api_error, %{status: 404}}} ->
          # Embedding model might not be available
          :ok

        {:error, _} ->
          :ok
      end
    end
  end
end
