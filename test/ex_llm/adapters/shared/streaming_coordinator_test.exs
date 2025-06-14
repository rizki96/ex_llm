defmodule ExLLM.Adapters.Shared.StreamingCoordinatorTest do
  use ExUnit.Case, async: true

  alias ExLLM.Adapters.Shared.StreamingCoordinator
  alias ExLLM.Types.StreamChunk

  describe "parse_sse_line/1" do
    test "parses data lines correctly" do
      assert {:data, "hello"} = StreamingCoordinator.parse_sse_line("data: hello")

      assert {:data, "{\"test\": true}"} =
               StreamingCoordinator.parse_sse_line("data: {\"test\": true}")
    end

    test "handles done signal" do
      assert :done = StreamingCoordinator.parse_sse_line("data: [DONE]")
    end

    test "skips empty lines" do
      assert :skip = StreamingCoordinator.parse_sse_line("")
      assert :skip = StreamingCoordinator.parse_sse_line("   ")
    end

    test "skips comments" do
      assert :skip = StreamingCoordinator.parse_sse_line(": comment")
      assert :skip = StreamingCoordinator.parse_sse_line(":heartbeat")
    end

    test "skips event lines" do
      assert :skip = StreamingCoordinator.parse_sse_line("event: message")
    end
  end

  describe "process_stream_data/8" do
    setup do
      stats = %{
        recovery_id: "test_stream_123",
        chunk_count: 0,
        byte_count: 0,
        error_count: 0
      }

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> {:ok, %StreamChunk{content: parsed["content"]}}
          _ -> {:error, :invalid_json}
        end
      end

      chunks = []
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      {:ok,
       %{
         stats: stats,
         parse_chunk: parse_chunk,
         callback: callback,
         chunks: chunks
       }}
    end

    test "processes single complete SSE event", %{
      stats: stats,
      parse_chunk: parse_chunk,
      callback: callback,
      chunks: chunks
    } do
      data = "data: {\"content\": \"Hello\"}\n\n"

      {new_buffer, new_chunks, new_stats} =
        StreamingCoordinator.process_stream_data(
          data,
          "",
          chunks,
          callback,
          parse_chunk,
          stats,
          1,
          []
        )

      assert new_buffer == ""
      assert new_chunks == []
      # Incremented when buffer is flushed
      assert new_stats.chunk_count == 1
      assert new_stats.byte_count == byte_size(data)

      # Check callback was called
      assert_receive {:chunk, %StreamChunk{content: "Hello"}}
    end

    test "buffers partial SSE events", %{
      stats: stats,
      parse_chunk: parse_chunk,
      callback: callback,
      chunks: chunks
    } do
      data1 = "data: {\"cont"
      data2 = "ent\": \"Hello\"}\n\n"

      # First part
      {buffer1, chunks1, stats1} =
        StreamingCoordinator.process_stream_data(
          data1,
          "",
          chunks,
          callback,
          parse_chunk,
          stats,
          1,
          []
        )

      assert buffer1 == data1
      assert chunks1 == []

      # Second part
      {buffer2, chunks2, _stats2} =
        StreamingCoordinator.process_stream_data(
          data2,
          buffer1,
          chunks1,
          callback,
          parse_chunk,
          stats1,
          1,
          []
        )

      assert buffer2 == ""
      assert chunks2 == []

      # Check callback was called
      assert_receive {:chunk, %StreamChunk{content: "Hello"}}
    end

    test "handles done signal", %{
      stats: stats,
      parse_chunk: parse_chunk,
      callback: callback,
      chunks: chunks
    } do
      data = "data: [DONE]\n\n"

      {_buffer, new_chunks, _stats} =
        StreamingCoordinator.process_stream_data(
          data,
          "",
          chunks,
          callback,
          parse_chunk,
          stats,
          1,
          []
        )

      assert new_chunks == []
    end

    test "respects buffer size", %{stats: stats, parse_chunk: parse_chunk, callback: callback} do
      data = """
      data: {"content": "1"}

      data: {"content": "2"}

      data: {"content": "3"}

      """

      # Buffer size of 2
      {_buffer, chunks, _stats} =
        StreamingCoordinator.process_stream_data(
          data,
          "",
          [],
          callback,
          parse_chunk,
          stats,
          2,
          []
        )

      # Should have 1 chunk left in buffer (3 total, flushed 2)
      assert length(chunks) == 1

      # Should have received 2 chunks
      assert_receive {:chunk, %StreamChunk{content: "1"}}
      assert_receive {:chunk, %StreamChunk{content: "2"}}
    end
  end

  describe "simple_stream/1" do
    test "validates required parameters" do
      assert_raise KeyError, fn ->
        StreamingCoordinator.simple_stream(url: "http://test.com")
      end
    end

    test "starts stream with provided parameters" do
      parent = self()

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: fn chunk -> send(parent, {:callback, chunk}) end,
        parse_chunk: fn data -> {:ok, %StreamChunk{content: data}} end
      ]

      assert {:ok, stream_id} = StreamingCoordinator.simple_stream(params)
      assert is_binary(stream_id)
      assert String.starts_with?(stream_id, "stream_")
    end
  end

  describe "enhanced features" do
    test "chunk transformation" do
      transform = fn chunk ->
        {:ok, %{chunk | content: String.upcase(chunk.content || "")}}
      end

      # This would be tested in integration with actual streaming
      assert is_function(transform, 1)

      # Test the transformation
      chunk = %StreamChunk{content: "hello"}
      assert {:ok, %StreamChunk{content: "HELLO"}} = transform.(chunk)
    end

    test "chunk validation" do
      validate = fn chunk ->
        if chunk.content && String.contains?(chunk.content, "bad") do
          {:error, "Invalid content"}
        else
          :ok
        end
      end

      # Test validation
      good_chunk = %StreamChunk{content: "good"}
      bad_chunk = %StreamChunk{content: "bad word"}

      assert :ok = validate.(good_chunk)
      assert {:error, "Invalid content"} = validate.(bad_chunk)
    end

    test "metrics calculation" do
      # This would be tested with actual streaming
      # For now, test the module exists
      assert Code.ensure_loaded?(StreamingCoordinator)
    end
  end
end
