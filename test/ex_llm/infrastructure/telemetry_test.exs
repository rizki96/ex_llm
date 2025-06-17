defmodule ExLLM.Infrastructure.TelemetryTest do
  use ExUnit.Case, async: true

  @moduletag :unit
  @moduletag :fast

  describe "telemetry events" do
    setup do
      handler_ref = make_ref()

      # Capture all events including test events
      events =
        ExLLM.Infrastructure.Telemetry.events() ++
          [
            [:test, :operation, :start],
            [:test, :operation, :stop],
            [:test, :failing, :start],
            [:test, :failing, :exception],
            [:test, :enriched, :start],
            [:test, :enriched, :stop],
            [:test, :with_cost, :start],
            [:test, :with_cost, :stop]
          ]

      test_pid = self()

      :telemetry.attach_many(
        handler_ref,
        events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach(handler_ref)
      end)

      {:ok, handler_ref: handler_ref}
    end

    test "span/3 emits start, stop, and measurements" do
      result =
        ExLLM.Infrastructure.Telemetry.span([:test, :operation], %{test: true}, fn ->
          Process.sleep(10)
          {:ok, "result"}
        end)

      assert result == {:ok, "result"}

      # Should receive start event
      assert_receive {:telemetry_event, [:test, :operation, :start], %{system_time: _},
                      %{test: true}}

      # Should receive stop event with duration
      assert_receive {:telemetry_event, [:test, :operation, :stop], %{duration: duration},
                      metadata}

      assert duration > 0
      assert metadata.test == true
      assert metadata.duration_ms > 0
    end

    test "span/3 emits exception event on error" do
      assert_raise RuntimeError, "test error", fn ->
        ExLLM.Infrastructure.Telemetry.span([:test, :failing], %{}, fn ->
          raise "test error"
        end)
      end

      assert_receive {:telemetry_event, [:test, :failing, :start], _, _}

      assert_receive {:telemetry_event, [:test, :failing, :exception], %{duration: _},
                      %{kind: :error, reason: %RuntimeError{message: "test error"}}}
    end

    test "cache event helpers" do
      ExLLM.Infrastructure.Telemetry.emit_cache_hit("test-key")
      assert_receive {:telemetry_event, [:ex_llm, :cache, :hit], %{}, %{key: "test-key"}}

      ExLLM.Infrastructure.Telemetry.emit_cache_miss("test-key")
      assert_receive {:telemetry_event, [:ex_llm, :cache, :miss], %{}, %{key: "test-key"}}

      ExLLM.Infrastructure.Telemetry.emit_cache_put("test-key", 1024)

      assert_receive {:telemetry_event, [:ex_llm, :cache, :put], %{size_bytes: 1024},
                      %{key: "test-key"}}
    end

    test "cost event helpers" do
      ExLLM.Infrastructure.Telemetry.emit_cost_calculated(:openai, "gpt-4", 150)

      assert_receive {:telemetry_event, [:ex_llm, :cost, :calculated], %{cost: 150},
                      %{provider: :openai, model: "gpt-4"}}

      ExLLM.Infrastructure.Telemetry.emit_cost_threshold_exceeded(500, 300)

      assert_receive {:telemetry_event, [:ex_llm, :cost, :threshold_exceeded],
                      %{cost: 500, threshold: 300}, %{exceeded_by: 200}}
    end

    test "stream event helpers" do
      ExLLM.Infrastructure.Telemetry.emit_stream_start(:anthropic, "claude-3")

      assert_receive {:telemetry_event, [:ex_llm, :stream, :start], %{system_time: _},
                      %{provider: :anthropic, model: "claude-3"}}

      ExLLM.Infrastructure.Telemetry.emit_stream_chunk(:anthropic, "claude-3", 128)

      assert_receive {:telemetry_event, [:ex_llm, :stream, :chunk], %{size: 128},
                      %{provider: :anthropic, model: "claude-3"}}

      ExLLM.Infrastructure.Telemetry.emit_stream_complete(:anthropic, "claude-3", 10, 5000)

      assert_receive {:telemetry_event, [:ex_llm, :stream, :stop], %{duration: 5000, chunks: 10},
                      %{provider: :anthropic, model: "claude-3"}}
    end

    test "metadata enrichment" do
      _result =
        ExLLM.Infrastructure.Telemetry.span([:test, :enriched], %{base: "value"}, fn ->
          {:ok, %{usage: %{input_tokens: 100, output_tokens: 50, total_tokens: 150}}}
        end)

      assert_receive {:telemetry_event, [:test, :enriched, :stop], _, metadata}
      assert metadata.base == "value"
      assert metadata.input_tokens == 100
      assert metadata.output_tokens == 50
      assert metadata.total_tokens == 150
    end

    test "cost metadata enrichment" do
      _result =
        ExLLM.Infrastructure.Telemetry.span([:test, :with_cost], %{}, fn ->
          {:ok, %{cost: %{total_cents: 25}}}
        end)

      assert_receive {:telemetry_event, [:test, :with_cost, :stop], _, metadata}
      assert metadata.cost_cents == 25
    end
  end

  describe "default logger" do
    test "attach and detach default logger" do
      # Should not raise
      ExLLM.Infrastructure.Telemetry.attach_default_logger(:debug)

      # Should log events
      ExLLM.Infrastructure.Telemetry.emit_cache_hit("test")

      # Should detach without error
      ExLLM.Infrastructure.Telemetry.detach_default_logger()
    end
  end

  describe "all defined events" do
    test "returns comprehensive event list" do
      events = ExLLM.Infrastructure.Telemetry.events()

      # Check major event categories are present
      assert Enum.any?(events, &match?([:ex_llm, :chat | _], &1))
      assert Enum.any?(events, &match?([:ex_llm, :stream | _], &1))
      assert Enum.any?(events, &match?([:ex_llm, :cache | _], &1))
      assert Enum.any?(events, &match?([:ex_llm, :provider | _], &1))
      assert Enum.any?(events, &match?([:ex_llm, :session | _], &1))
      assert Enum.any?(events, &match?([:ex_llm, :context | _], &1))
      assert Enum.any?(events, &match?([:ex_llm, :cost | _], &1))
      assert Enum.any?(events, &match?([:ex_llm, :http | _], &1))
      assert Enum.any?(events, &match?([:ex_llm, :embedding | _], &1))
    end
  end
end
