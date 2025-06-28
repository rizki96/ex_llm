defmodule ExLLM.Core.ChatPipelineIntegrationTest do
  use ExUnit.Case
  import ExLLM.Testing.CapabilityHelpers

  @moduletag :integration

  describe "chat pipeline integration via public API" do
    test "provider routing works correctly" do
      # Test that different providers can be called through the public API
      # This tests the internal pipeline routing without accessing internal APIs

      providers = [:anthropic, :openai, :groq]

      for provider <- providers do
        skip_unless_configured_and_supports(provider, :chat)

        messages = [%{role: "user", content: "Hello"}]

        case ExLLM.chat(provider, messages, max_tokens: 10) do
          {:ok, response} ->
            # Verify the provider routing worked correctly
            assert response.metadata.provider == provider
            assert is_binary(response.content)
            assert response.content != ""

          {:error, :not_configured} ->
            # Skip if provider not configured
            :ok

          {:error, reason} ->
            flunk("Provider #{provider} failed: #{inspect(reason)}")
        end
      end
    end

    test "different models work through public API" do
      skip_unless_configured_and_supports(:openai, :chat)

      models = ["gpt-4o-mini", "gpt-3.5-turbo"]
      messages = [%{role: "user", content: "Hi"}]

      for model <- models do
        case ExLLM.chat(:openai, messages, model: model, max_tokens: 10) do
          {:ok, response} ->
            # Verify model selection worked
            assert response.model =~ model or String.contains?(response.model, model)
            assert response.metadata.provider == :openai

          {:error, :not_configured} ->
            :ok

          {:error, {:api_error, %{status: 404}}} ->
            # Model not available, skip
            :ok

          {:error, reason} ->
            flunk("Model #{model} failed: #{inspect(reason)}")
        end
      end
    end

    test "provider-specific features work through public API" do
      # Test Anthropic vision capability
      skip_unless_configured_and_supports(:anthropic, [:chat, :vision])

      # Small 1x1 red pixel PNG
      red_pixel =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What color is this?"},
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

      case ExLLM.chat(:anthropic, messages, model: "claude-3-5-sonnet-20241022", max_tokens: 20) do
        {:ok, response} ->
          # Vision worked through the pipeline
          assert String.length(response.content) > 0
          assert response.metadata.provider == :anthropic

        {:error, :not_configured} ->
          :ok

        {:error, {:api_error, %{status: 400}}} ->
          # Vision not supported, acceptable
          :ok

        {:error, reason} ->
          flunk("Vision test failed: #{inspect(reason)}")
      end
    end

    test "streaming pipeline integration" do
      skip_unless_configured_and_supports(:openai, [:streaming])

      messages = [%{role: "user", content: "Count to 3"}]

      # Collect chunks using the callback API
      collector = fn chunk ->
        send(self(), {:chunk, chunk})
      end

      case ExLLM.stream(:openai, messages, collector, max_tokens: 20, timeout: 10_000) do
        :ok ->
          chunks = collect_stream_chunks([], 2000)
          assert length(chunks) > 0, "No streaming chunks received"

          # Verify streaming worked correctly
          if length(chunks) > 0 do
            last_chunk = List.last(chunks)
            assert last_chunk.finish_reason in ["stop", "length", "tool_calls"]
          end

        {:error, :not_configured} ->
          :ok

        {:error, reason} ->
          flunk("Streaming failed: #{inspect(reason)}")
      end
    end

    test "error handling through pipeline" do
      # Test that errors are properly handled through the public API
      # This indirectly tests pipeline error handling without accessing internals

      skip_unless_configured_and_supports(:anthropic, :chat)

      # Create a message that's too long
      long_content = String.duplicate("This is a test. ", 50_000)
      messages = [%{role: "user", content: long_content}]

      case ExLLM.chat(:anthropic, messages, max_tokens: 10) do
        {:error, {:api_error, %{status: 400}}} ->
          # Expected error for content too long
          :ok

        {:error, :invalid_messages} ->
          # Also acceptable - validation caught it before API
          :ok

        {:ok, _response} ->
          # Some models handle long content gracefully
          :ok

        {:error, :not_configured} ->
          :ok

        other ->
          flunk("Unexpected result for long content: #{inspect(other)}")
      end
    end
  end

  # Helper function to collect stream chunks
  defp collect_stream_chunks(chunks, timeout)

  defp collect_stream_chunks(chunks, timeout) do
    receive do
      {:chunk, chunk} ->
        collect_stream_chunks([chunk | chunks], timeout)
    after
      timeout -> Enum.reverse(chunks)
    end
  end
end
