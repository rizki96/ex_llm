defmodule ExLLM.StreamingTest do
  use ExUnit.Case, async: true

  alias ExLLM.Pipeline.Request
  alias ExLLM.Plugs

  describe "streaming functionality" do
    @tag :streaming
    test "stream/4 API with mock provider" do
      messages = [%{role: "user", content: "Hello, stream!"}]
      # Create a process to collect chunks
      collector = self()

      callback = fn chunk ->
        send(collector, {:chunk, chunk})
      end

      # Create a mock streaming pipeline
      pipeline = [
        Plugs.ValidateProvider,
        Plugs.FetchConfig,
        {MockStreamingPlug,
         chunks: [
           %{content: "Hello"},
           %{content: ", "},
           %{content: "world!"},
           %{done: true, usage: %{total_tokens: 10}}
         ]}
      ]

      request =
        Request.new(:mock, messages, %{stream: true, stream_callback: callback})

      _result = ExLLM.run(request, pipeline)

      # Wait for chunks to arrive
      Process.sleep(100)

      # Collect chunks with sufficient timeout for all 4 chunks
      # 4 chunks * 10ms delay + buffer = 100ms timeout
      chunks = collect_chunks(100)

      assert length(chunks) == 4
      assert Enum.at(chunks, 0).content == "Hello"
      assert Enum.at(chunks, 1).content == ", "
      assert Enum.at(chunks, 2).content == "world!"
      assert Enum.at(chunks, 3).done == true
    end

    @tag :streaming
    test "streaming with OpenAI-style SSE parsing" do
      parser = &ExLLM.Plugs.Providers.OpenAIParseStreamResponse.parse_sse_chunk/1

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

      assert is_pid(Map.get(result, :stream_coordinator))
      assert result.assigns.streaming_enabled == true
    end
  end

  defp collect_chunks(timeout \\ 1000) do
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
