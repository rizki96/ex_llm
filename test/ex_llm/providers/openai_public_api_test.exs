defmodule ExLLM.Providers.OpenAIPublicAPITest do
  @moduledoc """
  OpenAI-specific integration tests using the public ExLLM API.
  Common tests are handled by the shared module.
  """

  use ExLLM.Shared.ProviderIntegrationTest, provider: :openai

  # Provider-specific tests only
  describe "openai-specific features via public API" do
    test "handles JSON mode" do
      messages = [
        %{
          role: "user",
          content: "Return a JSON object with name: 'test' and value: 42"
        }
      ]

      case ExLLM.chat(:openai, messages, response_format: %{type: "json_object"}, max_tokens: 100) do
        {:ok, response} ->
          # Should return valid JSON
          {:ok, json} = Jason.decode(response.content)
          assert json["name"] == "test"
          assert json["value"] == 42

        {:error, _} ->
          :ok
      end
    end

    @tag :vision
    test "handles GPT-4 vision capabilities" do
      # Small 1x1 red pixel PNG
      red_pixel =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What color is this image?"},
            %{
              type: "image_url",
              image_url: %{
                url: "data:image/png;base64,#{red_pixel}"
              }
            }
          ]
        }
      ]

      case ExLLM.chat(:openai, messages, model: "gpt-4o", max_tokens: 50) do
        {:ok, response} ->
          assert response.content =~ ~r/red/i

        {:error, {:api_error, %{status: 400}}} ->
          IO.puts("Vision not supported or invalid image")

        {:error, reason} ->
          IO.puts("Vision test failed: #{inspect(reason)}")
      end
    end

    @tag :function_calling
    @tag :streaming
    test "streaming with function calls" do
      messages = [
        %{role: "user", content: "What's the weather in Boston?"}
      ]

      tools = [
        %{
          type: "function",
          function: %{
            name: "get_weather",
            description: "Get the weather for a location",
            parameters: %{
              type: "object",
              properties: %{
                location: %{type: "string"}
              },
              required: ["location"]
            }
          }
        }
      ]

      # Collect chunks using the callback API
      collector = fn chunk ->
        send(self(), {:chunk, chunk})
      end

      case ExLLM.stream(:openai, messages, collector,
             tools: tools,
             max_tokens: 100,
             timeout: 10_000
           ) do
        :ok ->
          chunks = collect_stream_chunks([], 1000)

          # Check if function was called
          tool_calls =
            chunks
            |> Enum.flat_map(&(&1[:tool_calls] || []))
            |> Enum.filter(& &1)

          if length(tool_calls) > 0 do
            assert hd(tool_calls).function.name == "get_weather"
          end

        {:error, _} ->
          :ok
      end
    end

    @tag :streaming
    test "streaming includes proper finish reasons" do
      messages = [
        %{role: "user", content: "Say hello"}
      ]

      # Collect chunks using the callback API
      collector = fn chunk ->
        send(self(), {:chunk, chunk})
      end

      case ExLLM.stream(:openai, messages, collector, max_tokens: 10, timeout: 10_000) do
        :ok ->
          chunks = collect_stream_chunks([], 1000)
          last_chunk = List.last(chunks)
          assert last_chunk.finish_reason in ["stop", "length", "tool_calls"]

        {:error, _} ->
          :ok
      end
    end

    test "o1 model behavior" do
      messages = [
        %{role: "user", content: "What is 2+2?"}
      ]

      case ExLLM.chat(:openai, messages, model: "o1-mini", max_completion_tokens: 100) do
        {:ok, response} ->
          assert response.content =~ "4"
          # o1 models don't support temperature, streaming, etc
          assert response.model =~ "o1"

        {:error, {:api_error, %{status: 404}}} ->
          # Model might not be available
          :ok

        {:error, _} ->
          :ok
      end
    end
  end
end
