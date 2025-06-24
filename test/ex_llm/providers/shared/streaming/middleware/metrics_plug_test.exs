defmodule ExLLM.Providers.Shared.Streaming.Middleware.MetricsPlugTest do
  use ExUnit.Case, async: true

  alias ExLLM.Providers.Shared.Streaming.Middleware.MetricsPlug
  alias ExLLM.Types.StreamChunk

  # Test helpers
  defmodule TestClient do
    @moduledoc false
    use Tesla

    plug(MetricsPlug)

    adapter(fn env ->
      case env.url do
        "/success" ->
          {:ok, %{env | status: 200, body: "ok"}}

        "/error" ->
          {:error, :connection_failed}

        "/streaming" ->
          # Simulate streaming by sending messages to the process
          if stream_context = env.opts[:stream_context] do
            send(self(), {:test_stream_chunk, stream_context.stream_id})
          end

          {:ok, %{env | status: 200, body: ""}}
      end
    end)
  end

  describe "non-streaming requests" do
    test "passes through when no stream context" do
      assert {:ok, response} = TestClient.get("/success")
      assert response.status == 200
      assert response.body == "ok"
    end

    test "passes through errors without metrics" do
      assert {:error, :connection_failed} = TestClient.get("/error")
    end
  end

  describe "metrics collection" do
    test "collects basic metrics for streaming request" do
      callback = fn chunk ->
        send(self(), {:chunk_received, chunk})
      end

      metrics_callback = fn metrics ->
        send(self(), {:metrics_received, metrics})
      end

      stream_context = %{
        stream_id: "test_stream_123",
        provider: :openai,
        callback: callback,
        parse_chunk_fn: &{:ok, &1},
        opts: []
      }

      opts = [
        stream_context: stream_context,
        callback: metrics_callback,
        enabled: true,
        # Disable periodic reporting for test
        interval: 0
      ]

      # Make streaming request
      {:ok, _response} = TestClient.get("/streaming", opts: opts)

      # Initialize metrics for testing
      MetricsPlug.initialize_metrics_for_test("test_stream_123", :openai)

      # Simulate chunk processing
      chunk1 = %StreamChunk{content: "Hello", finish_reason: nil}
      chunk2 = %StreamChunk{content: " world!", finish_reason: nil}
      chunk3 = %StreamChunk{content: "", finish_reason: "stop"}

      MetricsPlug.update_metrics_for_chunk("test_stream_123", chunk1, false)
      MetricsPlug.update_metrics_for_chunk("test_stream_123", chunk2, false)
      MetricsPlug.update_metrics_for_chunk("test_stream_123", chunk3, false)

      # Get final metrics
      state = :persistent_term.get({MetricsPlug, :metrics, "test_stream_123"}, nil)
      refute is_nil(state)

      assert state.stream_id == "test_stream_123"
      assert state.provider == :openai
      assert state.chunks_received == 3
      # "Hello" (5) + " world!" (7) + "" (0)
      assert state.bytes_received == 12
      assert state.status == :completed
      assert state.error_count == 0
    end

    test "tracks errors in metrics" do
      callback = fn _chunk -> :ok end

      stream_context = %{
        stream_id: "test_error_stream",
        provider: :anthropic,
        callback: callback,
        parse_chunk_fn: &{:ok, &1},
        opts: []
      }

      opts = [
        stream_context: stream_context,
        enabled: true,
        interval: 0
      ]

      # Simulate error chunk
      error_chunk = %StreamChunk{content: "Error occurred", finish_reason: "error"}

      # Initialize metrics for testing
      MetricsPlug.initialize_metrics_for_test("test_error_stream", :anthropic)

      # Process error chunk
      MetricsPlug.update_metrics_for_chunk("test_error_stream", error_chunk, false)

      state = :persistent_term.get({MetricsPlug, :metrics, "test_error_stream"}, nil)
      assert state.status == :error
      assert state.error_count == 1
    end

    test "calculates throughput metrics correctly" do
      callback = fn _chunk -> :ok end

      stream_context = %{
        stream_id: "test_throughput",
        provider: :groq,
        callback: callback,
        parse_chunk_fn: &{:ok, &1},
        opts: []
      }

      opts = [
        stream_context: stream_context,
        enabled: true,
        interval: 0
      ]

      # Initialize metrics for testing
      MetricsPlug.initialize_metrics_for_test("test_throughput", :groq)

      # Simulate multiple chunks
      for i <- 1..10 do
        chunk = %StreamChunk{content: String.duplicate("x", i * 10), finish_reason: nil}
        MetricsPlug.update_metrics_for_chunk("test_throughput", chunk, false)
      end

      state = :persistent_term.get({MetricsPlug, :metrics, "test_throughput"}, nil)

      # Total bytes: 10 + 20 + 30 + ... + 100 = 550
      assert state.bytes_received == 550
      assert state.chunks_received == 10
      assert length(state.chunk_sizes) == 10
    end

    test "includes raw chunks when configured" do
      callback = fn _chunk -> :ok end

      stream_context = %{
        stream_id: "test_raw_chunks",
        provider: :openai,
        callback: callback,
        parse_chunk_fn: &{:ok, &1},
        opts: []
      }

      opts = [
        stream_context: stream_context,
        enabled: true,
        include_raw_data: true,
        interval: 0
      ]

      # Initialize metrics with raw chunks array
      MetricsPlug.initialize_metrics_for_test("test_raw_chunks", :openai)

      # Add chunks
      chunk1 = %StreamChunk{content: "First", finish_reason: nil}
      chunk2 = %StreamChunk{content: "Second", finish_reason: nil}

      MetricsPlug.update_metrics_for_chunk("test_raw_chunks", chunk1, true)
      MetricsPlug.update_metrics_for_chunk("test_raw_chunks", chunk2, true)

      state = :persistent_term.get({MetricsPlug, :metrics, "test_raw_chunks"}, nil)

      assert length(state.raw_chunks) == 2
      # Newest first
      assert [^chunk2, ^chunk1] = state.raw_chunks
    end
  end

  describe "periodic reporting" do
    @tag :slow
    test "sends periodic metrics updates" do
      test_pid = self()

      callback = fn _chunk -> :ok end

      metrics_callback = fn metrics ->
        send(test_pid, {:periodic_metrics, metrics})
      end

      stream_context = %{
        stream_id: "test_periodic",
        provider: :openai,
        callback: callback,
        parse_chunk_fn: &{:ok, &1},
        opts: []
      }

      opts = [
        stream_context: stream_context,
        callback: metrics_callback,
        enabled: true,
        # 50ms for faster test
        interval: 50
      ]

      TestClient.get("/streaming", opts: opts)

      # Add some chunks
      for i <- 1..5 do
        chunk = %StreamChunk{content: "chunk#{i}", finish_reason: nil}
        MetricsPlug.update_metrics_for_chunk("test_periodic", chunk, false)
        Process.sleep(30)
      end

      # Should receive at least 2 periodic updates
      assert_receive {:periodic_metrics, metrics1}, 200
      assert metrics1.stream_id == "test_periodic"
      assert metrics1.status == :streaming

      assert_receive {:periodic_metrics, metrics2}, 200
      assert metrics2.chunks_received > metrics1.chunks_received
    end
  end

  describe "configuration" do
    test "metrics can be disabled entirely" do
      callback = fn _chunk -> :ok end

      stream_context = %{
        stream_id: "test_disabled",
        provider: :openai,
        callback: callback,
        parse_chunk_fn: &{:ok, &1},
        opts: []
      }

      opts = [
        stream_context: stream_context,
        # Disable metrics
        enabled: false
      ]

      TestClient.get("/streaming", opts: opts)

      # No metrics should be stored
      state = :persistent_term.get({MetricsPlug, :metrics, "test_disabled"}, nil)
      assert is_nil(state)
    end

    @tag :skip
    test "middleware options can be overridden at runtime" do
      # Create client with compile-time config
      defmodule ConfiguredClient do
        use Tesla

        plug(MetricsPlug, enabled: false, interval: 5000)

        adapter(fn env ->
          {:ok, %{env | status: 200, body: ""}}
        end)
      end

      callback = fn _chunk -> :ok end

      stream_context = %{
        stream_id: "test_override",
        provider: :openai,
        callback: callback,
        parse_chunk_fn: &{:ok, &1},
        opts: []
      }

      # Runtime options override compile-time config
      opts = [
        stream_context: stream_context,
        # Override to enable
        enabled: true,
        # Override interval
        interval: 100
      ]

      ConfiguredClient.get("/streaming", opts: opts)

      # Metrics should be collected despite compile-time disabled
      state = :persistent_term.get({MetricsPlug, :metrics, "test_override"}, nil)
      refute is_nil(state)
    end
  end

  describe "metrics report structure" do
    test "builds complete metrics report" do
      test_pid = self()

      callback = fn _chunk -> :ok end

      metrics_callback = fn metrics ->
        send(test_pid, {:final_metrics, metrics})
      end

      stream_context = %{
        stream_id: "test_report",
        provider: :gemini,
        callback: callback,
        parse_chunk_fn: &{:ok, &1},
        opts: []
      }

      opts = [
        stream_context: stream_context,
        callback: metrics_callback,
        enabled: true,
        interval: 0
      ]

      # Initialize metrics for testing
      MetricsPlug.initialize_metrics_for_test("test_report", :gemini)

      # Add chunks
      chunks = [
        %StreamChunk{content: "Hello", finish_reason: nil},
        %StreamChunk{content: " world", finish_reason: nil},
        %StreamChunk{content: "!", finish_reason: nil},
        %StreamChunk{content: "", finish_reason: "stop"}
      ]

      for chunk <- chunks do
        MetricsPlug.update_metrics_for_chunk("test_report", chunk, false)
      end

      # Manually finalize to get report
      MetricsPlug.finalize_metrics("test_report", {:ok, nil}, metrics_callback, nil)

      assert_receive {:final_metrics, metrics}, 1000

      # Verify report structure
      assert metrics.stream_id == "test_report"
      assert metrics.provider == :gemini
      assert metrics.chunks_received == 4
      # "Hello" + " world" + "!"
      assert metrics.bytes_received == 12
      assert metrics.status == :completed
      assert metrics.error_count == 0
      assert is_float(metrics.bytes_per_second)
      assert is_float(metrics.chunks_per_second)
      assert is_float(metrics.avg_chunk_size)
      # 12 bytes / 4 chunks
      assert metrics.avg_chunk_size == 3.0
      # Not included by default
      refute Map.has_key?(metrics, :raw_chunks)
    end
  end

  # Cleanup after each test
  setup do
    on_exit(fn ->
      # Clean up any persistent terms
      for {key, _value} <- :persistent_term.get() do
        case key do
          {MetricsPlug, :metrics, _stream_id} ->
            :persistent_term.erase(key)

          _ ->
            :ok
        end
      end
    end)
  end
end
