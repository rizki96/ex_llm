if Code.ensure_loaded?(Telemetry.Metrics) do
  defmodule ExLLM.Infrastructure.Telemetry.Metrics do
    @moduledoc """
    Telemetry metrics definitions for ExLLM.

    This module provides metric definitions using the `telemetry_metrics` library.
    These can be used with various reporters like Prometheus, StatsD, or console output.

    ## Usage

    Add to your supervision tree with a reporter:

        children = [
          {Telemetry.Metrics.ConsoleReporter, metrics: ExLLM.Infrastructure.Telemetry.Metrics.metrics()},
          # or for Prometheus:
          # {TelemetryMetricsPrometheus, metrics: ExLLM.Infrastructure.Telemetry.Metrics.metrics()}
        ]

    ## Available Metrics

    - Request counts and durations
    - Token usage
    - Cost tracking
    - Cache hit rates
    - Error rates
    - Provider-specific metrics
    """

    import Telemetry.Metrics

    @doc """
    Returns the list of metrics definitions for ExLLM.

    These metrics cover all major operations and can be used with any
    telemetry_metrics reporter.
    """
    def metrics do
      [
        # Chat metrics
        counter("ex_llm.chat.requests.total",
          event_name: [:ex_llm, :chat, :stop],
          description: "Total number of chat requests",
          tags: [:provider, :model]
        ),
        summary("ex_llm.chat.duration.milliseconds",
          event_name: [:ex_llm, :chat, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          description: "Chat request duration",
          tags: [:provider, :model]
        ),
        counter("ex_llm.chat.errors.total",
          event_name: [:ex_llm, :chat, :exception],
          description: "Total number of chat errors",
          tags: [:provider, :model, :kind]
        ),

        # Token usage
        sum("ex_llm.tokens.input.total",
          event_name: [:ex_llm, :chat, :stop],
          measurement: fn _measurements, metadata ->
            Map.get(metadata, :input_tokens, 0)
          end,
          description: "Total input tokens used",
          tags: [:provider, :model]
        ),
        sum("ex_llm.tokens.output.total",
          event_name: [:ex_llm, :chat, :stop],
          measurement: fn _measurements, metadata ->
            Map.get(metadata, :output_tokens, 0)
          end,
          description: "Total output tokens used",
          tags: [:provider, :model]
        ),

        # Cost tracking
        sum("ex_llm.cost.cents.total",
          event_name: [:ex_llm, :cost, :calculated],
          measurement: :cost,
          description: "Total cost in cents",
          tags: [:provider, :model]
        ),
        counter("ex_llm.cost.threshold_exceeded.total",
          event_name: [:ex_llm, :cost, :threshold_exceeded],
          description: "Number of times cost threshold was exceeded"
        ),

        # Provider metrics
        counter("ex_llm.provider.requests.total",
          event_name: [:ex_llm, :provider, :request, :stop],
          description: "Total provider API requests",
          tags: [:provider]
        ),
        summary("ex_llm.provider.request.duration.milliseconds",
          event_name: [:ex_llm, :provider, :request, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          description: "Provider API request duration",
          tags: [:provider]
        ),
        counter("ex_llm.provider.errors.total",
          event_name: [:ex_llm, :provider, :request, :exception],
          description: "Total provider API errors",
          tags: [:provider, :kind]
        ),
        counter("ex_llm.provider.rate_limits.total",
          event_name: [:ex_llm, :provider, :rate_limit],
          description: "Rate limit hits",
          tags: [:provider]
        ),

        # Cache metrics
        counter("ex_llm.cache.hits.total",
          event_name: [:ex_llm, :cache, :hit],
          description: "Cache hits"
        ),
        counter("ex_llm.cache.misses.total",
          event_name: [:ex_llm, :cache, :miss],
          description: "Cache misses"
        ),
        counter("ex_llm.cache.puts.total",
          event_name: [:ex_llm, :cache, :put],
          description: "Cache puts"
        ),
        sum("ex_llm.cache.size.bytes",
          event_name: [:ex_llm, :cache, :put],
          measurement: :size_bytes,
          description: "Total bytes cached"
        ),

        # HTTP metrics
        counter("ex_llm.http.requests.total",
          event_name: [:ex_llm, :http, :request, :stop],
          description: "Total HTTP requests",
          tags: [:method, :status_class]
        ),
        summary("ex_llm.http.request.duration.milliseconds",
          event_name: [:ex_llm, :http, :request, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          description: "HTTP request duration",
          tags: [:method]
        ),

        # Streaming metrics
        counter("ex_llm.stream.started.total",
          event_name: [:ex_llm, :stream, :start],
          description: "Total streams started",
          tags: [:provider, :model]
        ),
        counter("ex_llm.stream.chunks.total",
          event_name: [:ex_llm, :stream, :chunk],
          description: "Total stream chunks received",
          tags: [:provider, :model]
        ),
        summary("ex_llm.stream.duration.milliseconds",
          event_name: [:ex_llm, :stream, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          description: "Stream duration",
          tags: [:provider, :model]
        ),

        # Session metrics
        counter("ex_llm.session.created.total",
          event_name: [:ex_llm, :session, :created],
          description: "Total sessions created",
          tags: [:backend]
        ),
        counter("ex_llm.session.messages.total",
          event_name: [:ex_llm, :session, :message_added],
          description: "Total messages added to sessions",
          tags: [:role]
        ),
        sum("ex_llm.session.tokens.input.total",
          event_name: [:ex_llm, :session, :token_usage_updated],
          measurement: :input_tokens_delta,
          description: "Total input tokens in sessions"
        ),
        sum("ex_llm.session.tokens.output.total",
          event_name: [:ex_llm, :session, :token_usage_updated],
          measurement: :output_tokens_delta,
          description: "Total output tokens in sessions"
        ),
        counter("ex_llm.session.cleared.total",
          event_name: [:ex_llm, :session, :cleared],
          description: "Total sessions cleared"
        ),
        counter("ex_llm.session.truncations.total",
          event_name: [:ex_llm, :session, :truncated],
          description: "Total session truncations"
        ),

        # Context metrics
        counter("ex_llm.context.window_exceeded.total",
          event_name: [:ex_llm, :context, :window_exceeded],
          description: "Context window exceeded events",
          tags: [:provider, :model]
        ),
        summary("ex_llm.context.truncation.duration.milliseconds",
          event_name: [:ex_llm, :context, :truncation, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          description: "Context truncation duration",
          tags: [:strategy]
        ),
        sum("ex_llm.context.messages.removed.total",
          event_name: [:ex_llm, :context, :truncation, :stop],
          measurement: :messages_removed,
          description: "Total messages removed by truncation",
          tags: [:strategy]
        ),
        sum("ex_llm.context.tokens.removed.total",
          event_name: [:ex_llm, :context, :truncation, :stop],
          measurement: :tokens_removed,
          description: "Total tokens removed by truncation",
          tags: [:strategy]
        ),

        # Embedding metrics
        counter("ex_llm.embedding.requests.total",
          event_name: [:ex_llm, :embedding, :stop],
          description: "Total embedding requests",
          tags: [:provider, :model]
        ),
        summary("ex_llm.embedding.duration.milliseconds",
          event_name: [:ex_llm, :embedding, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          description: "Embedding request duration",
          tags: [:provider, :model]
        )
      ]
    end

    @doc """
    Returns a subset of metrics suitable for development/debugging.
    """
    def basic_metrics do
      [
        counter("ex_llm.requests.total",
          event_name: [:ex_llm, :chat, :stop],
          description: "Total requests"
        ),
        summary("ex_llm.duration.milliseconds",
          event_name: [:ex_llm, :chat, :stop],
          measurement: :duration,
          unit: {:native, :millisecond},
          description: "Request duration"
        ),
        counter("ex_llm.errors.total",
          event_name: [:ex_llm, :chat, :exception],
          description: "Total errors"
        )
      ]
    end

    @doc """
    Returns cost-focused metrics.
    """
    def cost_metrics do
      [
        sum("ex_llm.cost.cents.total",
          event_name: [:ex_llm, :cost, :calculated],
          measurement: :cost,
          description: "Total cost in cents",
          tags: [:provider, :model]
        ),
        sum("ex_llm.tokens.total",
          event_name: [:ex_llm, :chat, :stop],
          measurement: fn _measurements, metadata ->
            Map.get(metadata, :total_tokens, 0)
          end,
          description: "Total tokens used",
          tags: [:provider, :model]
        ),
        last_value("ex_llm.cost.cents.last",
          event_name: [:ex_llm, :cost, :calculated],
          measurement: :cost,
          description: "Most recent cost",
          tags: [:provider, :model]
        )
      ]
    end

    @doc """
    Helper to calculate cache hit rate.

    This is a derived metric that reporters can use.
    """
    def cache_hit_rate do
      # This would be calculated by the reporter based on
      # cache.hits.total / (cache.hits.total + cache.misses.total)
      distribution("ex_llm.cache.hit_rate",
        event_name: [:ex_llm, :cache, :hit],
        measurement: fn _measurements, _metadata -> 1.0 end,
        description: "Cache hit rate"
      )
    end

    @doc """
    Add status class tag for HTTP metrics.

    Transforms status codes into classes (2xx, 3xx, 4xx, 5xx).
    """
    def add_http_status_class(metadata) do
      case Map.get(metadata, :status) do
        status when status >= 200 and status < 300 -> Map.put(metadata, :status_class, "2xx")
        status when status >= 300 and status < 400 -> Map.put(metadata, :status_class, "3xx")
        status when status >= 400 and status < 500 -> Map.put(metadata, :status_class, "4xx")
        status when status >= 500 -> Map.put(metadata, :status_class, "5xx")
        _ -> Map.put(metadata, :status_class, "unknown")
      end
    end
  end
else
  # Provide a stub module when telemetry_metrics is not available
  defmodule ExLLM.Infrastructure.Telemetry.Metrics do
    @moduledoc """
    Telemetry metrics definitions for ExLLM (Stub).

    This is a stub module that is loaded when telemetry_metrics is not available.
    To use the full metrics functionality, add {:telemetry_metrics, "~> 1.0"} to your dependencies.
    """

    def metrics do
      []
    end

    def basic_metrics do
      []
    end

    def cost_metrics do
      []
    end

    def cache_hit_rate do
      nil
    end

    def add_http_status_class(metadata) do
      metadata
    end
  end
end
