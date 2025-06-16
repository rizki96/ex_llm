defmodule ExLLM.CircuitBreaker.Metrics.StatsDReporter do
  @moduledoc """
  StatsD metrics reporter for circuit breakers.

  Provides enhanced StatsD integration with custom tags support,
  metric aggregation, and batch reporting capabilities.

  ## Features

  - **Custom Tags**: Support for DogStatsD-style tags
  - **Metric Aggregation**: Batch multiple metrics for efficiency
  - **Error Recovery**: Resilient to StatsD server unavailability
  - **Rate Limiting**: Configurable metric sampling

  ## Configuration

      config :ex_llm, :circuit_breaker_metrics,
        statsd: [
          host: "localhost",
          port: 8125,
          namespace: "ex_llm.circuit_breaker",
          tags: ["service:ex_llm", "version:1.0.0"],
          sample_rate: 1.0,
          batch_size: 10,
          flush_interval: 1000
        ]

  ## Usage

      # Start reporter
      ExLLM.CircuitBreaker.Metrics.StatsDReporter.start_link()
      
      # Report metrics
      ExLLM.CircuitBreaker.Metrics.StatsDReporter.counter("requests.total", 1, 
        tags: ["circuit:api_service", "result:success"])
      
      # Report with sampling
      ExLLM.CircuitBreaker.Metrics.StatsDReporter.gauge("health.score", 85,
        tags: ["circuit:api_service"], sample_rate: 0.1)
  """

  use GenServer
  require Logger

  @default_config %{
    host: "localhost",
    port: 8125,
    namespace: "ex_llm.circuit_breaker",
    tags: [],
    sample_rate: 1.0,
    batch_size: 10,
    flush_interval: 1000,
    max_retries: 3,
    retry_backoff: 1000
  }

  defstruct [
    :socket,
    :host,
    :port,
    :namespace,
    :global_tags,
    :sample_rate,
    :batch_size,
    :flush_interval,
    :max_retries,
    :retry_backoff,
    batch: [],
    retry_count: 0
  ]

  ## Public API

  @doc """
  Start the StatsD reporter.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Report a counter metric.
  """
  def counter(metric_name, value \\ 1, opts \\ []) do
    report_metric(:counter, metric_name, value, opts)
  end

  @doc """
  Report a gauge metric.
  """
  def gauge(metric_name, value, opts \\ []) do
    report_metric(:gauge, metric_name, value, opts)
  end

  @doc """
  Report a timing metric.
  """
  def timing(metric_name, value_ms, opts \\ []) do
    report_metric(:timing, metric_name, value_ms, opts)
  end

  @doc """
  Report a histogram metric.
  """
  def histogram(metric_name, value, opts \\ []) do
    report_metric(:histogram, metric_name, value, opts)
  end

  @doc """
  Report a set metric.
  """
  def set(metric_name, value, opts \\ []) do
    report_metric(:set, metric_name, value, opts)
  end

  @doc """
  Flush any pending metrics immediately.
  """
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @doc """
  Get current reporter status and statistics.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    config = build_config(opts)

    case open_socket(config) do
      {:ok, socket} ->
        state = %__MODULE__{
          socket: socket,
          host: config.host,
          port: config.port,
          namespace: config.namespace,
          global_tags: config.tags,
          sample_rate: config.sample_rate,
          batch_size: config.batch_size,
          flush_interval: config.flush_interval,
          max_retries: config.max_retries,
          retry_backoff: config.retry_backoff,
          batch: [],
          retry_count: 0
        }

        # Schedule periodic flush
        schedule_flush(state.flush_interval)

        Logger.info("StatsD reporter started on #{config.host}:#{config.port}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start StatsD reporter: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:report, metric_type, metric_name, value, opts}, _from, state) do
    sample_rate = Keyword.get(opts, :sample_rate, state.sample_rate)

    if should_sample?(sample_rate) do
      metric = build_metric(metric_type, metric_name, value, opts, state)
      new_batch = [metric | state.batch]

      if length(new_batch) >= state.batch_size do
        case send_batch(new_batch, state) do
          :ok ->
            {:reply, :ok, %{state | batch: [], retry_count: 0}}

          {:error, _reason} ->
            # Retry logic handled in send_batch
            {:reply, :ok, %{state | batch: new_batch}}
        end
      else
        {:reply, :ok, %{state | batch: new_batch}}
      end
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    case send_batch(state.batch, state) do
      :ok ->
        {:reply, :ok, %{state | batch: [], retry_count: 0}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      connected: state.socket != nil,
      host: state.host,
      port: state.port,
      namespace: state.namespace,
      batch_size: length(state.batch),
      retry_count: state.retry_count,
      global_tags: state.global_tags
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info(:flush, state) do
    new_state =
      if length(state.batch) > 0 do
        case send_batch(state.batch, state) do
          :ok ->
            %{state | batch: [], retry_count: 0}

          {:error, _reason} ->
            state
        end
      else
        state
      end

    # Schedule next flush
    schedule_flush(state.flush_interval)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:retry_connection, state) do
    case open_socket(state) do
      {:ok, socket} ->
        Logger.info("StatsD connection restored")
        {:noreply, %{state | socket: socket, retry_count: 0}}

      {:error, _reason} ->
        if state.retry_count < state.max_retries do
          schedule_retry(state.retry_backoff * (state.retry_count + 1))
          {:noreply, %{state | retry_count: state.retry_count + 1}}
        else
          Logger.error("StatsD connection failed after #{state.max_retries} retries")
          {:noreply, %{state | socket: nil}}
        end
    end
  end

  ## Private Implementation

  defp report_metric(metric_type, metric_name, value, opts) do
    try do
      GenServer.call(__MODULE__, {:report, metric_type, metric_name, value, opts}, 5000)
    catch
      :exit, {:timeout, _} ->
        Logger.warning("StatsD reporter timeout")
        :ok

      :exit, {:noproc, _} ->
        Logger.warning("StatsD reporter not running")
        :ok
    end
  end

  defp build_config(opts) do
    user_config =
      Application.get_env(:ex_llm, :circuit_breaker_metrics, [])
      |> Keyword.get(:statsd, [])
      |> Enum.into(%{})

    opts_config = Enum.into(opts, %{})

    Map.merge(@default_config, user_config)
    |> Map.merge(opts_config)
  end

  defp open_socket(config) do
    host = String.to_charlist(config.host)
    port = config.port

    case :gen_udp.open(0, [:binary, {:active, false}]) do
      {:ok, socket} ->
        # Test connectivity by sending a test metric
        test_metric = "#{config.namespace}.test:1|c"

        case :gen_udp.send(socket, host, port, test_metric) do
          :ok ->
            {:ok, socket}

          {:error, reason} ->
            :gen_udp.close(socket)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_metric(metric_type, metric_name, value, opts, state) do
    full_name = "#{state.namespace}.#{metric_name}"
    tags = combine_tags(state.global_tags, Keyword.get(opts, :tags, []))
    sample_rate = Keyword.get(opts, :sample_rate, state.sample_rate)

    metric_string =
      case metric_type do
        :counter -> "#{full_name}:#{value}|c"
        :gauge -> "#{full_name}:#{value}|g"
        :timing -> "#{full_name}:#{value}|ms"
        :histogram -> "#{full_name}:#{value}|h"
        :set -> "#{full_name}:#{value}|s"
      end

    # Add sampling rate if not 1.0
    metric_string =
      if sample_rate < 1.0 do
        "#{metric_string}|@#{sample_rate}"
      else
        metric_string
      end

    # Add tags if using DogStatsD format
    if length(tags) > 0 do
      tag_string = Enum.join(tags, ",")
      "#{metric_string}|##{tag_string}"
    else
      metric_string
    end
  end

  defp combine_tags(global_tags, local_tags) do
    (global_tags ++ local_tags)
    |> Enum.uniq()
  end

  defp send_batch([], _state), do: :ok

  defp send_batch(batch, state) do
    if state.socket do
      payload =
        batch
        |> Enum.reverse()
        |> Enum.join("\n")

      host = String.to_charlist(state.host)

      case :gen_udp.send(state.socket, host, state.port, payload) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to send StatsD metrics: #{inspect(reason)}")
          schedule_retry(state.retry_backoff)
          {:error, reason}
      end
    else
      Logger.warning("StatsD socket not available")
      {:error, :no_socket}
    end
  end

  defp should_sample?(1.0), do: true

  defp should_sample?(sample_rate) when sample_rate > 0 do
    :rand.uniform() <= sample_rate
  end

  defp should_sample?(_), do: false

  defp schedule_flush(interval) do
    Process.send_after(self(), :flush, interval)
  end

  defp schedule_retry(backoff) do
    Process.send_after(self(), :retry_connection, backoff)
  end
end
