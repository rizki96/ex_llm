if Code.ensure_loaded?(OpenTelemetry) and Code.ensure_loaded?(OpenTelemetry.Tracer) do
  defmodule ExLLM.Infrastructure.Telemetry.OpenTelemetry do
    @moduledoc """
    OpenTelemetry integration for ExLLM.

    This module provides OpenTelemetry instrumentation for ExLLM operations,
    enabling distributed tracing across your application. It creates spans
    that properly propagate context across process boundaries.

    ## Installation

    Add OpenTelemetry dependencies to your `mix.exs`:

        {:opentelemetry_api, "~> 1.2"},
        {:opentelemetry, "~> 1.3"},
        {:opentelemetry_exporter, "~> 1.6"}

    ## Usage

    Replace direct ExLLM calls with the instrumented versions:

        # Instead of:
        ExLLM.chat(model: "gpt-4", messages: messages)
        
        # Use:
        ExLLM.Infrastructure.Telemetry.OpenTelemetry.chat(model: "gpt-4", messages: messages)

    ## Context Propagation

    This module handles context propagation across process boundaries,
    ensuring that async operations are properly traced.
    """

    @tracer :ex_llm

    @doc """
    Instrumented version of ExLLM.chat/3.

    Creates an OpenTelemetry span and ensures proper context propagation
    for any async operations.
    """
    def chat(model_or_config, messages, opts \\ []) do
      require OpenTelemetry.Tracer, as: Tracer

      attributes = build_attributes(:chat, model_or_config, opts)

      Tracer.with_span @tracer, "ex_llm.chat", %{attributes: attributes} do
        # Get current context for async propagation
        otel_ctx = OpenTelemetry.Ctx.get_current()

        # Add context to opts for internal propagation
        opts_with_ctx = Keyword.put(opts, :otel_ctx, otel_ctx)

        case ExLLM.chat(model_or_config, messages, opts_with_ctx) do
          {:ok, response} = result ->
            # Add response attributes to span
            set_response_attributes(response)
            result

          {:error, reason} = error ->
            # Record error on span
            Tracer.set_status(OpenTelemetry.status(:error, inspect(reason)))
            error
        end
      end
    end

    @doc """
    Instrumented version of ExLLM.stream_chat/3.

    Creates spans for streaming operations with proper chunk tracking.
    """
    def stream_chat(model_or_config, messages, opts \\ []) do
      require OpenTelemetry.Tracer, as: Tracer

      attributes = build_attributes(:stream, model_or_config, opts)

      Tracer.with_span @tracer, "ex_llm.stream", %{attributes: attributes} do
        otel_ctx = OpenTelemetry.Ctx.get_current()
        opts_with_ctx = Keyword.put(opts, :otel_ctx, otel_ctx)

        case ExLLM.stream_chat(model_or_config, messages, opts_with_ctx) do
          {:ok, stream} ->
            # Wrap the stream to track chunks
            wrapped_stream =
              Stream.transform(stream, 0, fn chunk, count ->
                Tracer.add_event("stream.chunk", %{"chunk_number" => count + 1})
                {[chunk], count + 1}
              end)

            {:ok, wrapped_stream}

          error ->
            Tracer.set_status(OpenTelemetry.status(:error, inspect(error)))
            error
        end
      end
    end

    @doc """
    Instrumented version of ExLLM.embed/3.
    """
    def embed(model_or_config, input, opts \\ []) do
      require OpenTelemetry.Tracer, as: Tracer

      attributes = build_attributes(:embed, model_or_config, opts)

      Tracer.with_span @tracer, "ex_llm.embed", %{attributes: attributes} do
        otel_ctx = OpenTelemetry.Ctx.get_current()
        opts_with_ctx = Keyword.put(opts, :otel_ctx, otel_ctx)

        case ExLLM.embed(model_or_config, input, opts_with_ctx) do
          {:ok, response} = result ->
            set_embedding_attributes(response)
            result

          error ->
            Tracer.set_status(OpenTelemetry.status(:error, inspect(error)))
            error
        end
      end
    end

    @doc """
    Wrap any ExLLM operation with OpenTelemetry tracing.

    ## Example

        with_span "custom_operation", %{custom: "attribute"} do
          # Your ExLLM operations here
        end
    """
    defmacro with_span(name, attributes \\ %{}, do: block) do
      quote do
        require OpenTelemetry.Tracer, as: Tracer

        Tracer.with_span unquote(@tracer), unquote(name), %{attributes: unquote(attributes)} do
          unquote(block)
        end
      end
    end

    @doc """
    Helper to propagate context in async operations.

    Use this when spawning tasks or processes that need to maintain
    the trace context.

    ## Example

        Task.async(fn ->
          ExLLM.Infrastructure.Telemetry.OpenTelemetry.with_context(ctx, fn ->
            # This will be part of the same trace
            ExLLM.chat(...)
          end)
        end)
    """
    def with_context(otel_ctx, fun) when is_function(fun, 0) do
      OpenTelemetry.Ctx.attach(otel_ctx)

      try do
        fun.()
      after
        OpenTelemetry.Ctx.detach(otel_ctx)
      end
    end

    @doc """
    Attach telemetry handlers that bridge to OpenTelemetry.

    This creates OpenTelemetry spans from ExLLM telemetry events.
    Note: This is less efficient than using the direct instrumentation
    functions above, but works with existing code.
    """
    def attach_telemetry_handlers do
      handlers = [
        {[:ex_llm, :chat, :start], &handle_start/4},
        {[:ex_llm, :chat, :stop], &handle_stop/4},
        {[:ex_llm, :chat, :exception], &handle_exception/4},
        {[:ex_llm, :provider, :request, :start], &handle_start/4},
        {[:ex_llm, :provider, :request, :stop], &handle_stop/4},
        {[:ex_llm, :provider, :request, :exception], &handle_exception/4}
      ]

      for {event, handler} <- handlers do
        :telemetry.attach(
          "otel-#{Enum.join(event, "-")}",
          event,
          handler,
          nil
        )
      end

      :ok
    end

    # Private functions

    defp build_attributes(operation, model_or_config, opts) do
      base = %{
        "llm.operation" => to_string(operation),
        "llm.stream" => Keyword.get(opts, :stream, false)
      }

      case ExLLM.Utils.build_config(model_or_config, opts) do
        {:ok, config} ->
          Map.merge(base, %{
            "llm.provider" => to_string(config.provider),
            "llm.model" => config.model,
            "llm.api_base" => config.api_base
          })

        _ ->
          base
      end
    end

    defp set_response_attributes(%{usage: usage} = response) when is_map(usage) do
      require OpenTelemetry.Tracer, as: Tracer

      Tracer.set_attributes(%{
        "llm.usage.input_tokens" => Map.get(usage, :input_tokens),
        "llm.usage.output_tokens" => Map.get(usage, :output_tokens),
        "llm.usage.total_tokens" => Map.get(usage, :total_tokens)
      })

      if cost = get_in(response, [:cost, :total_cents]) do
        Tracer.set_attribute("llm.cost.cents", cost)
      end
    end

    defp set_response_attributes(_), do: :ok

    defp set_embedding_attributes(%{usage: usage}) when is_map(usage) do
      require OpenTelemetry.Tracer, as: Tracer

      Tracer.set_attributes(%{
        "llm.usage.total_tokens" => Map.get(usage, :total_tokens)
      })
    end

    defp set_embedding_attributes(_), do: :ok

    # Telemetry event handlers for bridge mode

    defp handle_start(_event_name, _measurements, metadata, _config) do
      require OpenTelemetry.Tracer, as: Tracer

      span_name = build_span_name(_event_name)
      ctx = Tracer.start_span(span_name, %{attributes: metadata})

      # Store context in process dictionary for correlation
      Process.put({:otel_ctx, span_name}, ctx)
    end

    defp handle_stop(event_name, measurements, metadata, _config) do
      require OpenTelemetry.Tracer, as: Tracer

      span_name = build_span_name(event_name)

      if ctx = Process.delete({:otel_ctx, span_name}) do
        # Set final attributes
        attributes =
          Map.merge(metadata, %{
            "duration_ms" =>
              System.convert_time_unit(measurements.duration, :native, :millisecond)
          })

        Tracer.set_attributes(ctx, attributes)
        Tracer.end_span(ctx)
      end
    end

    defp handle_exception(event_name, measurements, metadata, _config) do
      require OpenTelemetry.Tracer, as: Tracer

      span_name = build_span_name(event_name)

      if ctx = Process.delete({:otel_ctx, span_name}) do
        Tracer.record_exception(ctx, metadata.reason, metadata.stacktrace)
        Tracer.set_status(ctx, OpenTelemetry.status(:error, inspect(metadata.reason)))
        Tracer.end_span(ctx)
      end
    end

    defp build_span_name(event_parts) do
      event_parts
      # Remove :start/:stop/:exception
      |> Enum.slice(0..-2)
      |> Enum.join(".")
    end
  end
else
  # Provide a stub module when OpenTelemetry is not available
  defmodule ExLLM.Infrastructure.Telemetry.OpenTelemetry do
    @moduledoc """
    OpenTelemetry integration for ExLLM (Stub).

    This is a stub module that is loaded when OpenTelemetry is not available.
    To use the full OpenTelemetry functionality, add the required dependencies to your mix.exs:

        {:opentelemetry_api, "~> 1.2"},
        {:opentelemetry, "~> 1.3"},
        {:opentelemetry_exporter, "~> 1.6"}
    """

    def chat(model_or_config, messages, opts \\ []) do
      ExLLM.chat(model_or_config, messages, opts)
    end

    def stream_chat(model_or_config, messages, opts \\ []) do
      # Convert to new stream API - needs a callback
      callback = opts[:stream_callback] || fn _chunk -> :ok end
      opts_list = Keyword.put(opts, :stream, true)
      ExLLM.stream(model_or_config, messages, callback, opts_list)
    end

    def embed(model_or_config, input, opts \\ []) do
      ExLLM.embeddings(model_or_config, input, opts)
    end

    def with_context(_otel_ctx, fun) when is_function(fun, 0) do
      fun.()
    end

    def attach_telemetry_handlers do
      :ok
    end

    defmacro with_span(_name, _attributes \\ %{}, do: block) do
      quote do
        unquote(block)
      end
    end
  end
end
