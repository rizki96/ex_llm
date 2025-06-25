defmodule ExLLM.Core.StreamingPipelineTest do
  use ExUnit.Case, async: true

  alias ExLLM.Core.Chat
  alias ExLLM.Types

  describe "streaming with pipeline system" do
    @tag :streaming
    test "OpenAI provider streams through pipeline" do
      messages = [%{role: "user", content: "Count to 3"}]

      # Mock the HTTPClient to return controlled chunks
      mock_stream_request()

      assert {:ok, stream} = Chat.stream_chat(:openai, messages)

      # Collect chunks
      chunks = Enum.to_list(stream)

      assert length(chunks) > 0
      assert %Types.StreamChunk{} = List.first(chunks)

      # Verify we get content and finish
      content_chunks = Enum.filter(chunks, & &1.content)
      assert length(content_chunks) > 0

      finish_chunk = Enum.find(chunks, & &1.finish_reason)
      assert finish_chunk
      assert finish_chunk.finish_reason == "stop"
    end

    @tag :streaming
    test "Anthropic provider streams through pipeline" do
      messages = [%{role: "user", content: "Say hello"}]

      # Mock the HTTPClient to return Anthropic-style chunks
      mock_anthropic_stream_request()

      assert {:ok, stream} = Chat.stream_chat(:anthropic, messages)

      # Collect chunks
      chunks = Enum.to_list(stream)

      assert length(chunks) > 0
      assert %Types.StreamChunk{} = List.first(chunks)
    end
  end

  defp mock_stream_request do
    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        if String.contains?(url, "chat/completions") do
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "text/event-stream"}],
            body: """
            data: {"choices":[{"delta":{"content":"1"}}],"id":"1"}

            data: {"choices":[{"delta":{"content":"2"}}],"id":"1"}

            data: {"choices":[{"delta":{"content":"3"}}],"id":"1"}

            data: {"choices":[{"delta":{},"finish_reason":"stop"}],"id":"1"}

            data: [DONE]

            """
          }
        else
          %Tesla.Env{status: 404, body: "Not Found"}
        end
    end)
  end

  defp mock_anthropic_stream_request do
    Tesla.Mock.mock(fn
      %{method: :post, url: url} ->
        if String.contains?(url, "messages") do
          %Tesla.Env{
            status: 200,
            headers: [{"content-type", "text/event-stream"}],
            body: """
            data: {"type":"content_block_delta","delta":{"text":"Hello"},"index":0}

            data: {"type":"content_block_delta","delta":{"text":" there"},"index":0}

            data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

            data: {"type":"message_stop"}

            """
          }
        else
          %Tesla.Env{status: 404, body: "Not Found"}
        end
    end)
  end
end
