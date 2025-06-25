defmodule ExLLM.Providers.Shared.Streaming.Middleware.MetricsPlugIntegrationTest do
  use ExUnit.Case, async: true

  alias ExLLM.Providers.Shared.Streaming.Middleware.{MetricsPlug, StreamCollector}
  alias ExLLM.Types.StreamChunk

  @moduletag :integration

  describe "integration with streaming engine" do
    test "metrics are collected during actual streaming" do
      test_pid = self()
      metrics_received = []

      # Create a mock HTTP adapter that simulates streaming
      defmodule MockStreamingAdapter do
        def call(env, _opts) do
          # Send streaming data to the collector
          stream_context = env.opts[:stream_context]

          if stream_context do
            # Simulate streaming chunks
            Task.start(fn ->
              Process.sleep(10)

              # Simulate SSE data
              chunks = [
                "data: {\"chunk\": \"Hello\"}\n\n",
                "data: {\"chunk\": \" streaming\"}\n\n",
                "data: {\"chunk\": \" world!\"}\n\n",
                "data: [DONE]\n\n"
              ]

              Enum.each(chunks, fn chunk ->
                # The StreamCollector middleware will process these
                send(self(), {:hackney_response, make_ref(), {:data, chunk}})
                Process.sleep(20)
              end)

              send(self(), {:hackney_response, make_ref(), :done})
            end)
          end

          {:ok, %{env | status: 200, body: ""}}
        end
      end

      # Create a custom client with our mock adapter
      middleware = [
        {Tesla.Middleware.BaseUrl, "http://mock.test"},
        {Tesla.Middleware.Headers, [{"authorization", "Bearer mock"}]},
        {Tesla.Middleware.JSON, engine: Jason},
        StreamCollector,
        {MetricsPlug,
         [
           enabled: true,
           callback: fn metrics ->
             send(test_pid, {:metrics, metrics})
           end,
           # Fast interval for testing
           interval: 50
         ]}
      ]

      _client = Tesla.client(middleware, {MockStreamingAdapter, []})

      # Simple chunk parser
      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, %{"chunk" => content}} ->
            {:ok, %StreamChunk{content: content, finish_reason: nil}}

          _ ->
            {:ok, :done}
        end
      end

      # Callback to collect chunks
      _chunks_received = []

      callback = fn chunk ->
        send(test_pid, {:chunk, chunk})
      end

      # Create stream context
      stream_context = %{
        stream_id: "test_integration_#{System.unique_integer()}",
        provider: :mock,
        callback: callback,
        parse_chunk_fn: parse_chunk,
        opts: []
      }

      # Execute streaming request
      env = %Tesla.Env{
        method: :post,
        url: "/stream",
        body: %{},
        opts: [stream_context: stream_context]
      }

      {:ok, _response} =
        Tesla.run(env, [{fn env, next -> MockStreamingAdapter.call(env, next) end, nil}])

      # Collect metrics updates
      collect_metrics = fn collect_metrics, acc, timeout ->
        receive do
          {:metrics, metrics} ->
            collect_metrics.(collect_metrics, [metrics | acc], timeout)

          {:chunk, _chunk} ->
            collect_metrics.(collect_metrics, acc, timeout)
        after
          timeout -> Enum.reverse(acc)
        end
      end

      metrics_list = collect_metrics.(collect_metrics, [], 500)

      # Verify we received metrics
      assert length(metrics_list) > 0

      # Check the final metrics
      final_metrics = List.last(metrics_list)
      assert final_metrics.stream_id =~ "test_integration_"
      assert final_metrics.provider == :mock
      assert final_metrics.chunks_received > 0
      assert final_metrics.bytes_received > 0
      assert final_metrics.status in [:streaming, :completed]
      assert is_float(final_metrics.bytes_per_second)
      assert is_float(final_metrics.chunks_per_second)
    end

    test "metrics can be disabled without affecting streaming" do
      test_pid = self()

      # Create client with metrics disabled
      middleware = [
        {Tesla.Middleware.BaseUrl, "http://mock.test"},
        StreamCollector,
        {MetricsPlug, [enabled: false]}
      ]

      _client =
        Tesla.client(middleware, fn env, _opts ->
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

      env = %Tesla.Env{
        method: :post,
        url: "/stream",
        opts: [stream_context: stream_context]
      }

      assert {:ok, response} = Tesla.run(env, [])
      assert response.status == 200

      # Verify no metrics were stored
      refute :persistent_term.get({MetricsPlug, :metrics, "test_disabled"}, nil)
    end

    test "error handling in metrics" do
      test_pid = self()
      _error_metrics = nil

      # Client that will error
      middleware = [
        StreamCollector,
        {MetricsPlug,
         [
           enabled: true,
           callback: fn metrics ->
             if metrics.status == :error do
               send(test_pid, {:error_metrics, metrics})
             end
           end
         ]}
      ]

      _client =
        Tesla.client(middleware, fn _env, _opts ->
          {:error, :connection_timeout}
        end)

      stream_context = %{
        stream_id: "test_error",
        callback: fn _chunk -> :ok end,
        parse_chunk_fn: fn _ -> {:ok, :done} end,
        opts: []
      }

      env = %Tesla.Env{
        method: :post,
        url: "/stream",
        opts: [stream_context: stream_context]
      }

      assert {:error, :connection_timeout} = Tesla.run(env, [])

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
