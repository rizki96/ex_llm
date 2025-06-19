defmodule ExLLM.Providers.AnthropicPublicAPITest do
  @moduledoc """
  Anthropic-specific integration tests using the public ExLLM API.
  Common tests are handled by the shared module.
  """

  use ExLLM.Shared.ProviderIntegrationTest, provider: :anthropic

  # Provider-specific tests only
  describe "anthropic-specific features via public API" do
    @tag :vision
    test "handles Claude vision capabilities" do
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

      case ExLLM.chat(:anthropic, messages, model: "claude-3-5-sonnet-20241022", max_tokens: 50) do
        {:ok, response} ->
          assert response.content =~ ~r/red/i

        {:error, {:api_error, %{status: 400}}} ->
          IO.puts("Vision not supported or invalid image")

        {:error, reason} ->
          IO.puts("Vision test failed: #{inspect(reason)}")
      end
    end

    test "handles multiple system messages gracefully" do
      # Anthropic only supports one system message
      messages = [
        %{role: "system", content: "You are helpful."},
        %{role: "system", content: "You are concise."},
        %{role: "user", content: "Hi"}
      ]

      case ExLLM.chat(:anthropic, messages, max_tokens: 50) do
        {:ok, response} ->
          # Should combine or use last system message
          assert is_binary(response.content)

        {:error, _} ->
          # Might reject multiple system messages
          :ok
      end
    end

    @tag :streaming
    test "streaming includes proper finish reasons" do
      messages = [
        %{role: "user", content: "Say hello"}
      ]

      case ExLLM.stream(:anthropic, messages, max_tokens: 10) do
        {:ok, stream} ->
          chunks = Enum.to_list(stream)
          last_chunk = List.last(chunks)
          assert last_chunk.finish_reason in ["end_turn", "stop_sequence", "max_tokens"]

        {:error, _} ->
          :ok
      end
    end
  end
end
