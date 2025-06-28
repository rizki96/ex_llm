defmodule ExLLM.StreamingTest do
  use ExUnit.Case, async: true

  alias ExLLM.Pipeline.Request

  describe "streaming functionality" do
    @tag :streaming
    # @tag :skip
    test "stream/4 API with mock provider" do
      messages = [%{role: "user", content: "Hello, stream!"}]
      # Create a process to collect chunks
      collector = self()

      callback = fn chunk ->
        send(collector, {:chunk, chunk})
      end

      # Set up mock response in Application environment
      Application.put_env(:ex_llm, :mock_responses, %{
        stream: [
          %{content: "Hello", finish_reason: nil},
          %{content: ", ", finish_reason: nil},
          %{content: "world!", finish_reason: nil},
          %{content: "", finish_reason: "stop", done: true, usage: %{total_tokens: 10}}
        ]
      })

      # Clean up
      on_exit(fn -> Application.delete_env(:ex_llm, :mock_responses) end)

      # Use the high-level streaming API
      result = ExLLM.stream(:mock, messages, callback)

      # Wait for processing to complete
      Process.sleep(100)

      # Collect chunks with sufficient timeout for all 4 chunks
      # 4 chunks * 10ms delay + buffer = 100ms timeout
      chunks = collect_chunks(100)

      assert result == :ok
      # We should receive at least 4 chunks (may be more due to mock streaming behavior)
      assert length(chunks) >= 4
      
      # Find chunks with specific content (they may not be in exact order)
      content_chunks = Enum.filter(chunks, fn chunk -> chunk.content in ["Hello", ", ", "world!"] end)
      done_chunks = Enum.filter(chunks, fn chunk -> Map.get(chunk, :done) == true end)
      
      assert length(content_chunks) >= 3, "Expected at least 3 content chunks, got: #{inspect(chunks)}"
      assert length(done_chunks) >= 1, "Expected at least 1 done chunk, got: #{inspect(chunks)}"
    end

    @tag :streaming
    test "streaming with OpenAI-style SSE parsing" do
      parser = &ExLLM.Plugs.Providers.OpenAIParseStreamResponse.parse_sse_chunk(&1, :openai)

      # Test single chunk
      sse_data = """
      data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1234567890,"model":"gpt-3.5-turbo","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}
      """

      assert {:continue, [chunk]} = parser.(sse_data)
      assert chunk.content == "Hello"

      # Test completion
      done_data = "data: [DONE]"
      assert {:done, %{done: true}} = parser.(done_data)
    end

    @tag :streaming
    test "streaming with Anthropic event parsing" do
      parser = &ExLLM.Plugs.Providers.AnthropicParseStreamResponse.parse_anthropic_chunk/1

      # Test content delta
      anthropic_data = """
      event: content_block_delta
      data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}
      """

      assert {:continue, chunks} = parser.(anthropic_data)
      chunk = Enum.find(chunks, &Map.has_key?(&1, :content))
      assert chunk.content == "Hello"

      # Test completion
      done_data = "event: message_stop"
      assert {:done, %{done: true}} = parser.(done_data)
    end

    @tag :streaming
    test "stream coordinator manages chunks correctly" do
      messages = [%{role: "user", content: "Test"}]

      callback = fn chunk ->
        Process.put(:chunks, [chunk | Process.get(:chunks, [])])
      end

      # Ensure config has stream: true
      request = Request.new(:mock, messages, %{})
      # Manually set config to ensure stream is true
      request = %{request | config: %{stream: true, stream_callback: callback}}

      # Run coordinator plug
      result = ExLLM.Plugs.StreamCoordinator.call(request, [])

      assert is_pid(result.stream_pid)
      assert result.assigns.streaming_enabled == true
    end
  end

  defp collect_chunks(timeout) do
    collect_chunks([], timeout)
  end

  defp collect_chunks(acc, timeout) do
    receive do
      {:chunk, chunk} ->
        collect_chunks(acc ++ [chunk], timeout)
    after
      timeout ->
        acc
    end
  end
end

# Define the module outside the test module
defmodule MockStreamingPlug do
  use ExLLM.Plug

  @impl true
  def call(request, opts) do
    chunks = opts[:chunks] || []
    callback = request.config[:stream_callback]

    # Simulate streaming by sending chunks
    Task.start(fn ->
      Enum.each(chunks, fn chunk ->
        # Simulate network delay
        Process.sleep(10)
        callback.(chunk)
      end)
    end)

    request
    |> ExLLM.Pipeline.Request.put_state(:executing)
    |> ExLLM.Pipeline.Request.assign(:mock_streaming_started, true)
  end
end
