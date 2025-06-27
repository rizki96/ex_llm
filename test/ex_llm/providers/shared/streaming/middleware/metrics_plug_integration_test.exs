defmodule ExLLM.Providers.Shared.Streaming.Middleware.MetricsPlugIntegrationTest do
  use ExUnit.Case, async: true

  alias ExLLM.Providers.Shared.Streaming.Middleware.{MetricsPlug, StreamCollector}
  alias ExLLM.Types.StreamChunk

  @moduletag :integration

  describe "integration with streaming engine" do
    test "metrics are collected during actual streaming" do
      test_pid = self()

      # Initialize metrics state for testing
      stream_id = "test_integration_#{System.unique_integer()}"
      MetricsPlug.initialize_metrics_for_test(stream_id, :mock, false)

      # Create chunks to simulate
      chunks = [
        %StreamChunk{content: "Hello", finish_reason: nil},
        %StreamChunk{content: " streaming", finish_reason: nil},
        %StreamChunk{content: " world!", finish_reason: "stop"}
      ]

      # Set up callback
      callback = fn metrics ->
        send(test_pid, {:metrics, metrics})
      end

      # Simulate chunk processing
      Enum.each(chunks, fn chunk ->
        MetricsPlug.update_metrics_for_chunk(stream_id, chunk, false)
        Process.sleep(20)
      end)

      # Finalize metrics
      MetricsPlug.finalize_metrics(stream_id, {:ok, :completed}, callback, nil)

      # Collect metrics
      assert_receive {:metrics, final_metrics}, 1000

      # Verify metrics
      assert final_metrics.stream_id == stream_id
      assert final_metrics.provider == :mock
      assert final_metrics.chunks_received == 3
      assert final_metrics.bytes_received > 0
      assert final_metrics.status == :completed
      assert is_float(final_metrics.bytes_per_second)
      assert is_float(final_metrics.chunks_per_second)
    end

    test "metrics can be disabled without affecting streaming" do
      # This test can remain mostly the same as it doesn't rely on the streaming flow
      test_pid = self()

      # Create client with metrics disabled
      middleware = [
        {Tesla.Middleware.BaseUrl, "http://mock.test"},
        StreamCollector,
        {MetricsPlug, [enabled: false]}
      ]

      client =
        Tesla.client(middleware, fn env ->
          # Simulate successful response
          {:ok, %{env | status: 200, body: "ok"}}
        end)

      # Verify request succeeds without metrics
      stream_context = %{
        stream_id: "test_disabled",
        callback: fn chunk -> send(test_pid, {:chunk, chunk}) end,
        parse_chunk_fn: fn _ -> {:ok, :done} end,
        opts: []
      }

      assert {:ok, response} = Tesla.post(client, "/stream", "", stream_context: stream_context)
      assert response.status == 200

      # Verify no metrics were stored
      refute :persistent_term.get({MetricsPlug, :metrics, "test_disabled"}, nil)
    end

    test "error handling in metrics" do
      test_pid = self()

      # Initialize metrics for error case
      stream_id = "test_error"
      MetricsPlug.initialize_metrics_for_test(stream_id, :mock, false)

      # Set up error callback
      callback = fn metrics ->
        if metrics.status == :error do
          send(test_pid, {:error_metrics, metrics})
        end
      end

      # Simulate error
      MetricsPlug.finalize_metrics(stream_id, {:error, :connection_timeout}, callback, nil)

      # Should receive error metrics
      assert_receive {:error_metrics, metrics}, 1000
      assert metrics.status == :error
      assert metrics.last_error == :connection_timeout
      assert metrics.error_count >= 1
    end
  end

  # Cleanup after tests
  setup do
    on_exit(fn ->
      # Clean up any persistent terms from tests
      Enum.each(:persistent_term.get(), fn
        {{MetricsPlug, :metrics, _}, _} = entry ->
          :persistent_term.erase(elem(entry, 0))

        _ ->
          :ok
      end)
    end)
  end
end
