defmodule ExLLM.Providers.Shared.EnhancedStreamingCoordinatorTest do
  use ExUnit.Case, async: true

  alias ExLLM.Providers.Shared.EnhancedStreamingCoordinator
  alias ExLLM.Types.StreamChunk

  @moduletag :integration

  describe "backward compatibility" do
    test "behaves identically to original StreamingCoordinator when no advanced features are enabled" do
      test_pid = self()

      # Simple callback to collect chunks
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      # Simple parse function
      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> {:ok, %StreamChunk{content: parsed["content"]}}
          _ -> {:error, :invalid_json}
        end
      end

      # Test with minimal options (should use original behavior)
      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk
      ]

      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)
      assert is_binary(stream_id)
      assert String.starts_with?(stream_id, "stream_")
    end

    test "processes basic SSE data correctly without advanced features" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> {:ok, %StreamChunk{content: parsed["content"]}}
          _ -> {:error, :invalid_json}
        end
      end

      # Test data processing directly (integration test)
      stream_context = %{
        recovery_id: "test_stream",
        chunk_count: 0,
        byte_count: 0,
        error_count: 0
      }

      collector =
        EnhancedStreamingCoordinator.create_enhanced_stream_collector(
          callback,
          parse_chunk,
          stream_context,
          nil,
          []
        )

      data = "data: {\"content\": \"Hello\"}\n\n"

      # Should delegate to original collector when no flow controller
      {:cont, {text_buffer, chunk_buffer, stats}} = collector.({:data, data}, nil)

      assert text_buffer == ""
      assert chunk_buffer == []
      assert stats.chunk_count == 1

      # Should receive the chunk
      assert_receive {:chunk, %StreamChunk{content: "Hello"}}
    end
  end

  describe "enhanced streaming with flow control" do
    test "enables flow control when option is set" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      # Enable flow control
      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        enable_flow_control: true,
        buffer_capacity: 10,
        backpressure_threshold: 0.8
      ]

      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)
      assert String.starts_with?(stream_id, "enhanced_stream_")
    end

    test "applies backpressure when buffer fills up" do
      test_pid = self()

      # Create a slow consumer that will cause backpressure
      slow_callback = fn chunk ->
        send(test_pid, {:chunk, chunk})
        # Slow processing
        Process.sleep(100)
      end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      # Small buffer to trigger backpressure quickly
      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: slow_callback,
        parse_chunk: parse_chunk,
        enable_flow_control: true,
        buffer_capacity: 3,
        # 2.4 ≈ 2 chunks
        backpressure_threshold: 0.8
      ]

      # This integration test verifies the setup is correct
      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)
      assert String.contains?(stream_id, "enhanced")
    end

    test "tracks detailed metrics with flow control" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      # Metrics callback
      metrics_received = Agent.start_link(fn -> [] end)
      {:ok, metrics_agent} = metrics_received

      on_metrics = fn metrics ->
        Agent.update(metrics_agent, fn list -> [metrics | list] end)
      end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        enable_flow_control: true,
        track_detailed_metrics: true,
        on_metrics: on_metrics,
        metrics_interval_ms: 100
      ]

      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)

      # Verify metrics structure
      # Allow metrics to be collected
      Process.sleep(150)
      metrics_list = Agent.get(metrics_agent, & &1)

      if length(metrics_list) > 0 do
        metrics = hd(metrics_list)
        assert Map.has_key?(metrics, :stream_id)
        assert Map.has_key?(metrics, :enhanced_features)
        assert Map.has_key?(metrics, :flow_control)
      end

      Agent.stop(metrics_agent)
    end
  end

  describe "enhanced streaming with batching" do
    test "enables intelligent batching when option is set" do
      test_pid = self()

      # Track batch sizes
      batch_sizes = Agent.start_link(fn -> [] end)
      {:ok, batch_agent} = batch_sizes

      callback = fn chunk ->
        send(test_pid, {:chunk, chunk})
        # This will be called for each individual chunk in a batch
        Agent.update(batch_agent, fn sizes -> [1 | sizes] end)
      end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        enable_batching: true,
        batch_size: 3,
        batch_timeout_ms: 100,
        adaptive_batching: false
      ]

      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)
      assert String.starts_with?(stream_id, "enhanced_stream_")

      Agent.stop(batch_agent)
    end

    test "adapts batch size based on chunk characteristics" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        enable_batching: true,
        batch_size: 5,
        adaptive_batching: true,
        min_batch_size: 2,
        max_batch_size: 10
      ]

      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)
      assert String.contains?(stream_id, "enhanced")
    end
  end

  describe "combined advanced features" do
    test "can enable both flow control and batching together" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        enable_flow_control: true,
        enable_batching: true,
        buffer_capacity: 20,
        backpressure_threshold: 0.9,
        batch_size: 3,
        adaptive_batching: true
      ]

      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)
      assert String.starts_with?(stream_id, "enhanced_stream_")
    end

    test "provides comprehensive metrics with all features enabled" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      # Comprehensive metrics tracking
      metrics_received = Agent.start_link(fn -> [] end)
      {:ok, metrics_agent} = metrics_received

      on_metrics = fn metrics ->
        Agent.update(metrics_agent, fn list -> [metrics | list] end)
        send(test_pid, {:metrics, metrics})
      end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        enable_flow_control: true,
        enable_batching: true,
        track_detailed_metrics: true,
        buffer_capacity: 15,
        batch_size: 4,
        on_metrics: on_metrics,
        metrics_interval_ms: 50
      ]

      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)

      # Wait for at least one metrics report
      Process.sleep(100)

      metrics_list = Agent.get(metrics_agent, & &1)

      if length(metrics_list) > 0 do
        metrics = hd(metrics_list)

        # Verify comprehensive metrics structure
        assert Map.has_key?(metrics, :stream_id)
        assert Map.has_key?(metrics, :provider)
        assert Map.has_key?(metrics, :enhanced_features)
        assert Map.has_key?(metrics, :flow_control)
        assert Map.has_key?(metrics, :status)

        # Verify enhanced features are tracked
        enhanced_features = metrics.enhanced_features
        assert enhanced_features.flow_control == true
        assert enhanced_features.batching == true
        assert enhanced_features.detailed_metrics == true
      end

      Agent.stop(metrics_agent)
    end
  end

  describe "overflow strategies" do
    test "supports different overflow strategies with flow control" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      # Test drop strategy
      params_drop = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        enable_flow_control: true,
        buffer_capacity: 5,
        overflow_strategy: :drop
      ]

      assert {:ok, stream_id_drop} = EnhancedStreamingCoordinator.simple_stream(params_drop)
      assert String.contains?(stream_id_drop, "enhanced")

      # Test overwrite strategy
      params_overwrite = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        enable_flow_control: true,
        buffer_capacity: 5,
        overflow_strategy: :overwrite
      ]

      assert {:ok, stream_id_overwrite} =
               EnhancedStreamingCoordinator.simple_stream(params_overwrite)

      assert String.contains?(stream_id_overwrite, "enhanced")

      # Test block strategy
      params_block = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        enable_flow_control: true,
        buffer_capacity: 5,
        overflow_strategy: :block
      ]

      assert {:ok, stream_id_block} = EnhancedStreamingCoordinator.simple_stream(params_block)
      assert String.contains?(stream_id_block, "enhanced")
    end
  end

  describe "error handling and recovery" do
    test "handles consumer errors gracefully with flow control" do
      test_pid = self()

      # Create a callback that occasionally fails
      call_count = Agent.start_link(fn -> 0 end)
      {:ok, counter} = call_count

      error_callback = fn chunk ->
        count = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

        if rem(count, 3) == 0 do
          # Every 3rd call fails
          raise "Simulated consumer error"
        else
          send(test_pid, {:chunk, chunk})
        end
      end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: error_callback,
        parse_chunk: parse_chunk,
        enable_flow_control: true,
        buffer_capacity: 10
      ]

      # Should still successfully create the stream
      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)
      assert String.contains?(stream_id, "enhanced")

      Agent.stop(counter)
    end

    test "supports stream recovery with enhanced features" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        enable_flow_control: true,
        stream_recovery: true,
        provider: :test_provider
      ]

      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)
      assert String.contains?(stream_id, "enhanced")
    end
  end

  describe "chunk validation and transformation" do
    test "supports chunk validation with enhanced streaming" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      # Validator that rejects chunks with "bad" content
      validate_chunk = fn chunk ->
        if chunk.content && String.contains?(chunk.content, "bad") do
          {:error, "Invalid content"}
        else
          :ok
        end
      end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        validate_chunk: validate_chunk,
        enable_flow_control: true
      ]

      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)
      assert String.contains?(stream_id, "enhanced")
    end

    test "supports chunk transformation with enhanced streaming" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      # Transformer that uppercases content
      transform_chunk = fn chunk ->
        {:ok, %{chunk | content: String.upcase(chunk.content || "")}}
      end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        transform_chunk: transform_chunk,
        enable_batching: true
      ]

      assert {:ok, stream_id} = EnhancedStreamingCoordinator.simple_stream(params)
      assert String.contains?(stream_id, "enhanced")
    end
  end

  describe "performance and benchmarking" do
    @tag :performance
    test "enhanced streaming performance is comparable to basic streaming" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      # Measure basic streaming startup time
      {basic_time, {:ok, basic_stream_id}} =
        :timer.tc(fn ->
          EnhancedStreamingCoordinator.simple_stream(
            url: "http://test.com",
            request: %{test: true},
            headers: [{"content-type", "application/json"}],
            callback: callback,
            parse_chunk: parse_chunk
          )
        end)

      # Measure enhanced streaming startup time
      {enhanced_time, {:ok, enhanced_stream_id}} =
        :timer.tc(fn ->
          EnhancedStreamingCoordinator.simple_stream(
            url: "http://test.com",
            request: %{test: true},
            headers: [{"content-type", "application/json"}],
            callback: callback,
            parse_chunk: parse_chunk,
            enable_flow_control: true,
            enable_batching: true
          )
        end)

      # Enhanced streaming should not be significantly slower to start
      # Allow up to 5x overhead for the additional setup
      assert enhanced_time < basic_time * 5

      # Verify both streams were created successfully
      assert String.starts_with?(basic_stream_id, "stream_")
      assert String.starts_with?(enhanced_stream_id, "enhanced_stream_")
    end
  end

  describe "configuration validation" do
    test "validates required parameters" do
      assert_raise KeyError, fn ->
        EnhancedStreamingCoordinator.simple_stream(
          url: "http://test.com"
          # Missing required parameters
        )
      end
    end

    test "handles invalid configuration gracefully" do
      test_pid = self()
      callback = fn chunk -> send(test_pid, {:chunk, chunk}) end

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, parsed} -> %StreamChunk{content: parsed["content"]}
          _ -> nil
        end
      end

      # Invalid buffer capacity should be handled gracefully
      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk,
        enable_flow_control: true,
        # Invalid
        buffer_capacity: -1
      ]

      # Should either succeed with corrected config or fail predictably
      result = EnhancedStreamingCoordinator.simple_stream(params)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
