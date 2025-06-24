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
    # This would normally mock ExLLM.Providers.Shared.HTTPClient.stream_request/5
    # For now, we'll rely on the test interceptor
    :ok
  end

  defp mock_anthropic_stream_request do
    # This would normally mock for Anthropic format
    :ok
  end
end
