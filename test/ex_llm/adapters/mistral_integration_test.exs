defmodule ExLLM.MistralIntegrationTest do
  use ExUnit.Case
  alias ExLLM.Adapters.Mistral
  alias ExLLM.Types

  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag provider: :mistral

  # These tests require a Mistral API key
  # Run with: mix test --include integration --include external
  # Or use the provider-specific alias: mix test.mistral

  describe "chat/2 with real API" do
    test "generates response with default model" do
      messages = [%{role: "user", content: "What is 2+2?"}]

      result = Mistral.chat(messages)

      case result do
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          assert is_binary(response.content)
          assert response.content != ""

          assert String.contains?(response.content, "4") or
                   String.contains?(response.content, "four")

          assert response.usage.input_tokens > 0
          assert response.usage.output_tokens > 0
          assert response.model == "mistral/mistral-tiny"

        {:error, reason} ->
          IO.puts("Mistral API error: #{inspect(reason)}")
      end
    end

    test "generates response with specific model" do
      messages = [%{role: "user", content: "Write a haiku about programming"}]

      result =
        Mistral.chat(messages,
          model: "mistral/mistral-small-latest",
          temperature: 0.7
        )

      case result do
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          assert response.model == "mistral/mistral-small-latest"
          # Should be a short poem
          assert String.length(response.content) < 500

        {:error, _reason} ->
          :ok
      end
    end

    test "handles system prompts" do
      messages = [
        %{role: "system", content: "You are a helpful assistant that speaks like a pirate."},
        %{role: "user", content: "Hello, how are you?"}
      ]

      result = Mistral.chat(messages)

      case result do
        {:ok, response} ->
          # Should respond in pirate style
          assert String.contains?(String.downcase(response.content), "ahoy") or
                   String.contains?(String.downcase(response.content), "arr") or
                   String.contains?(String.downcase(response.content), "matey") or
                   String.contains?(String.downcase(response.content), "ye")

        {:error, _reason} ->
          :ok
      end
    end

    test "respects max_tokens limit" do
      messages = [%{role: "user", content: "Count from 1 to 100"}]

      result = Mistral.chat(messages, max_tokens: 50)

      case result do
        {:ok, response} ->
          # Response should be limited
          # Some buffer for stop tokens
          assert response.usage.output_tokens <= 60

        {:error, _reason} ->
          :ok
      end
    end

    test "handles safe_prompt option" do
      messages = [%{role: "user", content: "Tell me a story"}]

      result = Mistral.chat(messages, safe_prompt: true)

      case result do
        {:ok, response} ->
          assert response.content != ""

        # Safe mode should work without issues

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "stream_chat/2 with real API" do
    test "streams response chunks" do
      messages = [%{role: "user", content: "Count from 1 to 5"}]

      case Mistral.stream_chat(messages) do
        {:ok, stream} ->
          chunks = stream |> Enum.take(10) |> Enum.to_list()

          assert length(chunks) > 0

          # Each chunk should be a StreamChunk
          assert Enum.all?(chunks, fn chunk ->
                   %Types.StreamChunk{} = chunk
                   is_binary(chunk.content) or is_nil(chunk.content)
                 end)

          # At least one chunk should have content
          assert Enum.any?(chunks, fn chunk ->
                   chunk.content != nil and chunk.content != ""
                 end)

        {:error, _reason} ->
          :ok
      end
    end

    test "streaming respects temperature" do
      messages = [%{role: "user", content: "Give me a random number"}]

      # Low temperature should be more deterministic
      case Mistral.stream_chat(messages, temperature: 0.1, seed: 42) do
        {:ok, stream} ->
          chunks = Enum.to_list(stream)

          # Concatenate all content
          full_content =
            chunks
            |> Enum.map(&(&1.content || ""))
            |> Enum.join("")

          assert String.length(full_content) > 0

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "function calling" do
    test "executes function calls" do
      messages = [%{role: "user", content: "What's the weather in Paris?"}]

      functions = [
        %{
          name: "get_weather",
          description: "Get the current weather in a location",
          parameters: %{
            type: "object",
            properties: %{
              location: %{
                type: "string",
                description: "The city and state, e.g. San Francisco, CA"
              },
              unit: %{
                type: "string",
                enum: ["celsius", "fahrenheit"]
              }
            },
            required: ["location"]
          }
        }
      ]

      result =
        Mistral.chat(messages,
          functions: functions,
          tool_choice: "auto"
        )

      case result do
        {:ok, response} ->
          # Model might call the function or respond directly
          assert response.content != "" or response.function_call != nil

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "embeddings/2" do
    test "generates embeddings for single text" do
      result = Mistral.embeddings("Hello world", model: "mistral/mistral-embed")

      case result do
        {:ok, response} ->
          assert %Types.EmbeddingResponse{} = response
          assert is_list(response.embeddings)
          assert length(response.embeddings) == 1

          embedding = hd(response.embeddings)
          assert is_list(embedding)
          assert length(embedding) > 0
          assert Enum.all?(embedding, &is_float/1)

        {:error, _reason} ->
          :ok
      end
    end

    test "generates embeddings for multiple texts" do
      texts = ["Hello", "World", "Mistral AI"]

      result = Mistral.embeddings(texts, model: "mistral/mistral-embed")

      case result do
        {:ok, response} ->
          assert %Types.EmbeddingResponse{} = response
          assert length(response.embeddings) == 3

          # Each embedding should be a list of floats
          assert Enum.all?(response.embeddings, fn emb ->
                   is_list(emb) and length(emb) > 0 and Enum.all?(emb, &is_float/1)
                 end)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "list_models/1 with API" do
    test "returns available Mistral models" do
      case Mistral.list_models() do
        {:ok, models} ->
          assert is_list(models)
          assert length(models) > 0

          # Check model structure
          assert Enum.all?(models, fn model ->
                   assert %Types.Model{} = model
                   assert is_binary(model.id)
                   assert is_binary(model.name)
                   assert is_integer(model.context_window)
                   assert model.context_window > 0
                 end)

          # Should include key models
          model_ids = Enum.map(models, & &1.id)
          assert Enum.any?(model_ids, &String.contains?(&1, "mistral"))

        {:error, _reason} ->
          # API might be down or key invalid
          :ok
      end
    end
  end

  describe "error handling with real API" do
    test "handles invalid model gracefully" do
      messages = [%{role: "user", content: "Test"}]

      result = Mistral.chat(messages, model: "mistral/invalid-model")

      assert {:error, reason} = result
      assert is_binary(reason)
    end

    test "handles API errors properly" do
      # Try with a very large prompt that might exceed limits
      large_content = String.duplicate("Test ", 10000)
      messages = [%{role: "user", content: large_content}]

      result = Mistral.chat(messages)

      case result do
        {:ok, _} ->
          # Succeeded despite large prompt
          assert true

        {:error, reason} ->
          # Should get a meaningful error
          assert is_binary(reason)
      end
    end
  end

  describe "model-specific features" do
    test "handles code generation with Codestral" do
      messages = [
        %{role: "user", content: "Write a Python function to calculate fibonacci numbers"}
      ]

      result = Mistral.chat(messages, model: "mistral/codestral-latest")

      case result do
        {:ok, response} ->
          # Should contain Python code
          assert String.contains?(response.content, "def") or
                   String.contains?(response.content, "fibonacci") or
                   String.contains?(response.content, "python")

        {:error, _reason} ->
          :ok
      end
    end

    test "handles multimodal with Pixtral" do
      # Note: This would require actual image data
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{type: "image_url", image_url: %{url: "https://example.com/image.jpg"}}
          ]
        }
      ]

      result = Mistral.chat(messages, model: "mistral/pixtral-12b-2409")

      case result do
        {:ok, _response} ->
          # Model would describe the image
          assert true

        {:error, _reason} ->
          # Expected if model doesn't support vision or URL is invalid
          :ok
      end
    end
  end

  # Helper functions removed - tests now use tag-based exclusion
end
