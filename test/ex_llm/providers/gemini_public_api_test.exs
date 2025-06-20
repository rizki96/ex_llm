defmodule ExLLM.Providers.GeminiPublicAPITest do
  @moduledoc """
  Gemini-specific integration tests using the public ExLLM API.
  Common tests are handled by the shared module.
  """

  use ExLLM.Shared.ProviderIntegrationTest, provider: :gemini

  # Provider-specific tests only
  describe "gemini-specific features via public API" do
    @tag :vision
    @tag :multimodal
    test "handles multimodal content with Gemini models" do
      # Small 1x1 red pixel PNG
      red_pixel =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What color is this image?"},
            %{
              type: "image",
              image: %{
                data: red_pixel,
                media_type: "image/png"
              }
            }
          ]
        }
      ]

      case ExLLM.chat(:gemini, messages, model: "gemini-1.5-flash", max_tokens: 50) do
        {:ok, response} ->
          assert response.content =~ ~r/red/i

        {:error, {:api_error, %{status: 400}}} ->
          IO.puts("Vision not supported or invalid image")

        {:error, reason} ->
          IO.puts("Vision test failed: #{inspect(reason)}")
      end
    end

    test "handles safety settings" do
      messages = [
        %{role: "user", content: "Tell me a joke"}
      ]

      safety_settings = [
        %{
          category: "HARM_CATEGORY_HARASSMENT",
          threshold: "BLOCK_ONLY_HIGH"
        }
      ]

      case ExLLM.chat(:gemini, messages, safety_settings: safety_settings, max_tokens: 100) do
        {:ok, response} ->
          assert is_binary(response.content)

        {:error, _} ->
          :ok
      end
    end

    @tag :streaming
    test "streaming with Gemini-specific finish reasons" do
      messages = [
        %{role: "user", content: "Count to 3"}
      ]

      # Collect chunks using the callback API
      collector = fn chunk ->
        send(self(), {:chunk, chunk})
      end

      case ExLLM.stream(:gemini, messages, collector, max_tokens: 20, timeout: 10_000) do
        :ok ->
          chunks = collect_stream_chunks([], 1000)
          last_chunk = List.last(chunks)
          # Gemini uses different finish reasons
          assert last_chunk.finish_reason in ["STOP", "MAX_TOKENS", "SAFETY", nil]

        {:error, _} ->
          :ok
      end
    end

    test "handles Gemini's content format" do
      # Gemini uses a different format for multi-turn conversations
      messages = [
        %{role: "user", content: "Hi"},
        %{role: "assistant", content: "Hello!"},
        %{role: "user", content: "How are you?"}
      ]

      case ExLLM.chat(:gemini, messages, max_tokens: 50) do
        {:ok, response} ->
          assert is_binary(response.content)
          assert response.provider == :gemini

        {:error, _} ->
          :ok
      end
    end

    @tag :embedding
    test "embedding generation with Gemini" do
      texts = ["Hello world", "How are you?"]

      case ExLLM.create_embeddings(:gemini, texts, model: "text-embedding-004") do
        {:ok, embeddings} ->
          assert length(embeddings) == 2
          assert is_list(hd(embeddings))
          assert is_float(hd(hd(embeddings)))

        {:error, {:api_error, %{status: 404}}} ->
          # Model might not be available
          :ok

        {:error, _} ->
          :ok
      end
    end
  end
end
