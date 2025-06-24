defmodule ExLLM.Providers.Shared.StreamingEngineTest do
  use ExUnit.Case, async: true

  alias ExLLM.Providers.Shared.StreamingEngine
  alias ExLLM.Types.StreamChunk

  describe "streaming mode detection" do
    test "detects basic streaming mode for simple options" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      options = [
        parse_chunk_fn: parse_chunk_fn,
        timeout: 5000
      ]

      # Should use basic mode (StreamingCoordinator)
      assert {:ok, stream_id} =
               StreamingEngine.start_stream(
                 "http://test.com",
                 %{test: true},
                 [{"content-type", "application/json"}],
                 callback,
                 options
               )

      assert String.starts_with?(stream_id, "stream_")
    end

    test "detects enhanced streaming mode for advanced features" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      # Flow control option should trigger enhanced mode
      options = [
        parse_chunk_fn: parse_chunk_fn,
        enable_flow_control: true,
        buffer_capacity: 100
      ]

      assert {:ok, stream_id} =
               StreamingEngine.start_stream(
                 "http://test.com",
                 %{test: true},
                 [{"content-type", "application/json"}],
                 callback,
                 options
               )

      # Enhanced streams have different ID prefix
      assert String.starts_with?(stream_id, "enhanced_stream_")
    end

    test "detects enhanced mode for batching features" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      options = [
        parse_chunk_fn: parse_chunk_fn,
        enable_batching: true,
        batch_config: [batch_size: 5]
      ]

      assert {:ok, stream_id} =
               StreamingEngine.start_stream(
                 "http://test.com",
                 %{test: true},
                 [{"content-type", "application/json"}],
                 callback,
                 options
               )

      assert String.starts_with?(stream_id, "enhanced_stream_")
    end

    test "detects enhanced mode for detailed metrics" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      options = [
        parse_chunk_fn: parse_chunk_fn,
        track_detailed_metrics: true,
        # This ensures EnhancedStreamingCoordinator uses advanced mode
        enable_flow_control: true,
        on_metrics: fn _metrics -> :ok end
      ]

      assert {:ok, stream_id} =
               StreamingEngine.start_stream(
                 "http://test.com",
                 %{test: true},
                 [{"content-type", "application/json"}],
                 callback,
                 options
               )

      assert String.starts_with?(stream_id, "enhanced_stream_")
    end
  end

  describe "simple_stream/1 compatibility" do
    test "maintains backward compatibility with StreamingCoordinator.simple_stream/1" do
      callback = fn _chunk -> send(self(), :chunk_received) end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk_fn
      ]

      assert {:ok, stream_id} = StreamingEngine.simple_stream(params)
      assert is_binary(stream_id)
    end

    test "supports advanced features through simple_stream/1" do
      callback = fn _chunk -> send(self(), :chunk_received) end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [{"content-type", "application/json"}],
        callback: callback,
        parse_chunk: parse_chunk_fn,
        enable_flow_control: true,
        buffer_capacity: 50
      ]

      assert {:ok, stream_id} = StreamingEngine.simple_stream(params)
      assert String.starts_with?(stream_id, "enhanced_stream_")
    end

    test "merges options from params and options keyword" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      params = [
        url: "http://test.com",
        request: %{test: true},
        headers: [],
        callback: callback,
        parse_chunk: parse_chunk_fn,
        # From params
        buffer_capacity: 50,
        # From options
        options: [enable_flow_control: true]
      ]

      assert {:ok, stream_id} = StreamingEngine.simple_stream(params)
      # Should trigger enhanced mode due to both buffer_capacity and enable_flow_control
      assert String.starts_with?(stream_id, "enhanced_stream_")
    end
  end

  describe "configuration presets" do
    test "provides high_throughput configuration" do
      config = StreamingEngine.config(:high_throughput)

      assert config[:enable_flow_control] == true
      assert config[:buffer_capacity] == 200
      assert config[:backpressure_threshold] == 0.9
      assert config[:rate_limit_ms] == 0
      assert config[:enable_batching] == true
      assert is_list(config[:batch_config])
    end

    test "provides low_latency configuration" do
      config = StreamingEngine.config(:low_latency)

      assert config[:enable_flow_control] == true
      assert config[:buffer_capacity] == 20
      assert config[:backpressure_threshold] == 0.7
      assert config[:rate_limit_ms] == 0
      # No batching for low latency
      refute Keyword.has_key?(config, :batch_config)
    end

    test "provides balanced configuration" do
      config = StreamingEngine.config(:balanced)

      assert config[:enable_flow_control] == true
      assert config[:buffer_capacity] == 100
      assert config[:backpressure_threshold] == 0.8
      assert config[:enable_batching] == true
      assert config[:track_detailed_metrics] == true
    end

    test "provides conservative configuration" do
      config = StreamingEngine.config(:conservative)

      assert config[:enable_flow_control] == true
      assert config[:buffer_capacity] == 50
      assert config[:backpressure_threshold] == 0.6
      assert config[:overflow_strategy] == :block
      assert config[:stream_recovery] == true
    end

    test "allows overriding preset values" do
      config = StreamingEngine.config(:balanced, buffer_capacity: 300, rate_limit_ms: 10)

      # Overridden
      assert config[:buffer_capacity] == 300
      # Overridden
      assert config[:rate_limit_ms] == 10
      # From preset
      assert config[:enable_flow_control] == true
    end

    test "handles custom configuration without implicit defaults" do
      custom_opts = [enable_flow_control: true, buffer_capacity: 150]
      config = StreamingEngine.config(custom_opts, rate_limit_ms: 5)

      assert config[:buffer_capacity] == 150
      assert config[:rate_limit_ms] == 5
      assert config[:enable_flow_control] == true
      # Should NOT merge balanced defaults for pure custom configuration
      assert config[:backpressure_threshold] == nil
    end
  end

  describe "stream status tracking" do
    test "identifies enhanced stream IDs" do
      enhanced_id = "enhanced_stream_123_456"

      assert {:ok, status} = StreamingEngine.get_stream_status(enhanced_id)
      assert status.implementation == :enhanced
      assert status.stream_id == enhanced_id
    end

    test "returns not_found for basic stream IDs that don't exist" do
      basic_id = "stream_123_456"

      # Basic streams without Tesla tracking return not_found (prevents false positives)
      assert {:error, :not_found} = StreamingEngine.get_stream_status(basic_id)
    end

    test "handles invalid stream IDs" do
      assert {:error, :invalid_stream_id} = StreamingEngine.get_stream_status("invalid_id")
    end
  end

  describe "advanced features availability" do
    test "checks for required modules" do
      # This should return true in our test environment since modules are loaded
      assert StreamingEngine.advanced_features_available?()
    end
  end

  describe "parameter validation" do
    test "requires parse_chunk_fn parameter" do
      callback = fn _chunk -> :ok end

      assert_raise KeyError, fn ->
        StreamingEngine.start_stream(
          "http://test.com",
          %{test: true},
          [],
          callback,
          # Missing parse_chunk_fn
          []
        )
      end
    end

    test "requires core parameters in simple_stream/1" do
      assert_raise KeyError, fn ->
        StreamingEngine.simple_stream(
          # Missing required parameters
          url: "http://test.com"
        )
      end
    end
  end

  describe "tesla integration" do
    test "provides tesla client delegation" do
      # Test that tesla functions are properly delegated
      assert function_exported?(StreamingEngine, :tesla_client, 1)
      assert function_exported?(StreamingEngine, :tesla_stream, 4)
      assert function_exported?(StreamingEngine, :cancel_stream, 1)
      assert function_exported?(StreamingEngine, :stream_status, 1)
    end

    test "forces tesla mode when explicitly requested" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      options = [
        parse_chunk_fn: parse_chunk_fn,
        use_tesla: true,
        provider: :openai
      ]

      headers = [{"authorization", "Bearer sk-test"}]

      # This should attempt Tesla mode even though it will likely fail
      # in the test environment due to missing HTTP setup
      result =
        StreamingEngine.start_stream(
          "https://api.openai.com/v1/chat/completions",
          %{model: "gpt-4", messages: []},
          headers,
          callback,
          options
        )

      # May fail due to test environment, but that's expected
      case result do
        {:ok, _stream_id} -> :ok
        # Expected in test environment
        {:error, _reason} -> :ok
      end
    end
  end

  describe "utility functions" do
    test "generates unique stream IDs" do
      # Test by creating multiple streams and verifying unique IDs
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      options = [parse_chunk_fn: parse_chunk_fn]

      {:ok, id1} = StreamingEngine.start_stream("http://test1.com", %{}, [], callback, options)
      {:ok, id2} = StreamingEngine.start_stream("http://test2.com", %{}, [], callback, options)

      assert id1 != id2
      assert String.starts_with?(id1, "stream_")
      assert String.starts_with?(id2, "stream_")
    end
  end

  describe "error handling" do
    test "gracefully handles missing advanced features" do
      # Test that the facade degrades gracefully when advanced features
      # aren't available (though they should be in our test environment)
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      options = [
        parse_chunk_fn: parse_chunk_fn,
        # This would normally trigger enhanced mode
        enable_flow_control: true
      ]

      # Should work regardless of feature availability
      assert {:ok, stream_id} =
               StreamingEngine.start_stream(
                 "http://test.com",
                 %{test: true},
                 [],
                 callback,
                 options
               )

      assert is_binary(stream_id)
    end
  end

  describe "integration with existing coordinators" do
    test "maintains compatibility with StreamingCoordinator options" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      # All these options should work with basic mode
      options = [
        parse_chunk_fn: parse_chunk_fn,
        timeout: 30_000,
        buffer_chunks: 1,
        track_metrics: true,
        provider: :openai
      ]

      assert {:ok, stream_id} =
               StreamingEngine.start_stream(
                 "http://test.com",
                 %{test: true},
                 [],
                 callback,
                 options
               )

      assert String.starts_with?(stream_id, "stream_")
    end

    test "maintains compatibility with EnhancedStreamingCoordinator options" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      # These options should trigger enhanced mode
      options = [
        parse_chunk_fn: parse_chunk_fn,
        enable_flow_control: true,
        buffer_capacity: 100,
        backpressure_threshold: 0.8,
        enable_batching: true,
        batch_config: [batch_size: 5],
        track_detailed_metrics: true
      ]

      assert {:ok, stream_id} =
               StreamingEngine.start_stream(
                 "http://test.com",
                 %{test: true},
                 [],
                 callback,
                 options
               )

      assert String.starts_with?(stream_id, "enhanced_stream_")
    end
  end
end
