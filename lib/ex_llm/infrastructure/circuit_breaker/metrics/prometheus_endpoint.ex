defmodule ExLLM.Infrastructure.CircuitBreaker.Metrics.PrometheusEndpoint do
  @moduledoc """
  Prometheus metrics endpoint for circuit breaker monitoring.

  Provides HTTP endpoint for Prometheus to scrape circuit breaker metrics.
  Can be integrated with Phoenix applications or standalone HTTP servers.

  ## Phoenix Integration

      # In your router
      defmodule MyAppWeb.Router do
        use MyAppWeb, :router
        
        pipeline :metrics do
          plug :accepts, ["text"]
        end
        
        scope "/metrics" do
          pipe_through :metrics
          
          get "/circuit_breakers", ExLLM.CircuitBreaker.Metrics.PrometheusEndpoint, :metrics
        end
      end

  ## Standalone Usage

      # Start standalone HTTP server
      ExLLM.CircuitBreaker.Metrics.PrometheusEndpoint.start_server(port: 9090)

  ## Manual Export

      # Get metrics as text
      {:ok, metrics_text} = ExLLM.CircuitBreaker.Metrics.PrometheusEndpoint.export()
  """

  # Check if optional dependencies are available
  @plug_available Code.ensure_loaded?(Plug.Conn)
  @cowboy_available Code.ensure_loaded?(:cowboy)

  @doc """
  Export Prometheus metrics as text format.
  """
  def export do
    ExLLM.Infrastructure.CircuitBreaker.Metrics.export_prometheus()
  end

  @doc """
  Plug function for Phoenix/Cowboy integration.
  """
  def init(opts), do: opts

  if @plug_available do
    def call(conn, _opts) do
      case export() do
        {:ok, metrics_text} ->
          conn
          |> Plug.Conn.put_resp_content_type("text/plain; version=0.0.4; charset=utf-8")
          |> Plug.Conn.send_resp(200, metrics_text)

        {:error, :prometheus_not_enabled} ->
          conn
          |> Plug.Conn.send_resp(503, "Prometheus metrics not enabled")

        {:error, :prometheus_not_available} ->
          conn
          |> Plug.Conn.send_resp(503, "Prometheus library not available")

        {:error, reason} ->
          Logger.error("Failed to export Prometheus metrics: #{inspect(reason)}")

          conn
          |> Plug.Conn.send_resp(500, "Internal server error")
      end
    end
  else
    def call(_conn, _opts) do
      raise RuntimeError, "Plug dependency not available - cannot handle HTTP requests"
    end
  end

  @doc """
  Phoenix controller action for metrics endpoint.
  """
  if @plug_available do
    def metrics(conn, _params) do
      call(conn, [])
    end
  else
    def metrics(_conn, _params) do
      raise RuntimeError, "Plug dependency not available - cannot handle HTTP requests"
    end
  end

  @doc """
  Start standalone HTTP server for metrics endpoint.
  """
  if @cowboy_available do
    def start_server(opts \\ []) do
      port = Keyword.get(opts, :port, 9090)
      path = Keyword.get(opts, :path, "/metrics")

      Logger.info("Starting Prometheus metrics server on port #{port}#{path}")

      dispatch =
        :cowboy_router.compile([
          {:_, [{path, __MODULE__, []}]}
        ])

      case :cowboy.start_clear(
             :circuit_breaker_metrics_server,
             [{:port, port}],
             %{env: %{dispatch: dispatch}}
           ) do
        {:ok, pid} ->
          Logger.info("Prometheus metrics server started successfully")
          {:ok, pid}

        {:error, {:already_started, pid}} ->
          Logger.info("Prometheus metrics server already running")
          {:ok, pid}

        {:error, reason} ->
          Logger.error("Failed to start Prometheus metrics server: #{inspect(reason)}")
          {:error, reason}
      end
    end
  else
    def start_server(_opts \\ []) do
      {:error, :cowboy_not_available}
    end
  end

  @doc """
  Stop the standalone metrics server.
  """
  if @cowboy_available do
    def stop_server do
      case :cowboy.stop_listener(:circuit_breaker_metrics_server) do
        :ok ->
          Logger.info("Prometheus metrics server stopped")
          :ok

        {:error, :not_found} ->
          Logger.warning("Prometheus metrics server was not running")
          :ok

        {:error, reason} ->
          Logger.error("Failed to stop Prometheus metrics server: #{inspect(reason)}")
          {:error, reason}
      end
    end
  else
    def stop_server do
      {:error, :cowboy_not_available}
    end
  end
end
