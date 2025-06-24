defmodule ExLLM.Plugs.TelemetryMiddlewareTest do
  use ExUnit.Case, async: true

  alias ExLLM.Pipeline.Request
  alias ExLLM.Plugs.TelemetryMiddleware

  defmodule TestPlug do
    use ExLLM.Plug

    def call(request, _opts) do
      Request.assign(request, :plug_executed, true)
    end
  end

  defmodule ErrorPlug do
    use ExLLM.Plug

    def call(_request, _opts) do
      raise "boom"
    end
  end

  setup do
    # Setup a telemetry handler to capture events
    event_name = [:ex_llm, :test, :execution]

    :telemetry.attach_many(
      "test-handler-#{inspect(self())}",
      [
        event_name ++ [:start],
        event_name ++ [:stop],
        event_name ++ [:exception]
      ],
      &ExLLM.Plugs.TelemetryMiddlewareTest.handle_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach("test-handler-#{inspect(self())}") end)

    %{event_name: event_name}
  end

  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end

  test "executes inner pipeline and emits start/stop events", %{event_name: event_name} do
    request = Request.new(:openai, [], %{model: "gpt-4", stream: true})

    opts = %{
      pipeline: [{TestPlug, []}],
      event_name: event_name
    }

    result = TelemetryMiddleware.call(request, TelemetryMiddleware.init(opts))

    assert result.assigns.plug_executed == true

    # Assert start event
    assert_receive {:telemetry_event, start_event, _, start_meta}
    assert start_event == event_name ++ [:start]
    assert start_meta.provider == :openai
    assert start_meta.model == "gpt-4"
    assert start_meta.stream == true

    # Assert stop event
    assert_receive {:telemetry_event, stop_event, measurements, stop_meta}
    assert stop_event == event_name ++ [:stop]
    assert is_integer(measurements.duration)
    # Stop metadata includes duration_ms, while start metadata includes system_time
    assert stop_meta.provider == start_meta.provider
    assert stop_meta.model == start_meta.model
    assert stop_meta.stream == start_meta.stream
    assert Map.has_key?(stop_meta, :duration_ms)
  end

  test "emits exception event on pipeline failure", %{event_name: event_name} do
    request = Request.new(:openai, [])

    opts = %{
      pipeline: [{ErrorPlug, []}],
      event_name: event_name
    }

    assert_raise RuntimeError, "boom", fn ->
      TelemetryMiddleware.call(request, TelemetryMiddleware.init(opts))
    end

    # Assert start event
    assert_receive {:telemetry_event, start_event, _, _}
    assert start_event == event_name ++ [:start]

    # Assert exception event
    assert_receive {:telemetry_event, exception_event, measurements, exception_meta}
    assert exception_event == event_name ++ [:exception]
    assert is_integer(measurements.duration)
    assert exception_meta.kind == :error
    assert exception_meta.reason.__struct__ == RuntimeError
    assert exception_meta.reason.message == "boom"
    assert is_list(exception_meta.stacktrace)
  end

  test "builds metadata correctly" do
    request =
      Request.new(:openai, [], %{
        model: "gpt-4",
        stream: true,
        response_model: "Some.Model",
        retry: false,
        cache: true
      })

    metadata = TelemetryMiddleware.build_metadata(request)

    assert metadata == %{
             provider: :openai,
             model: "gpt-4",
             stream: true,
             structured_output: true,
             retry_enabled: false,
             cache_enabled: true
           }
  end

  describe "init/1" do
    test "raises ArgumentError if :pipeline is missing" do
      assert_raise ArgumentError, ~r/the :pipeline option is required/, fn ->
        TelemetryMiddleware.init([])
      end
    end

    test "raises ArgumentError if :pipeline is not a list" do
      assert_raise ArgumentError, ~r/the :pipeline option must be a list/, fn ->
        TelemetryMiddleware.init(pipeline: :not_a_list)
      end
    end

    test "raises ArgumentError if :event_name is not a list of atoms" do
      assert_raise ArgumentError, ~r/the :event_name option must be a list of atoms/, fn ->
        TelemetryMiddleware.init(pipeline: [], event_name: "not_a_list")
      end
    end
  end
end
