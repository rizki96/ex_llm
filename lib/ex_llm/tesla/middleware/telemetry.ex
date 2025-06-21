defmodule ExLLM.Tesla.Middleware.Telemetry do
  @moduledoc """
  Tesla middleware for emitting telemetry events.

  This middleware emits telemetry events for HTTP requests, allowing
  monitoring and observability of API calls.

  ## Events

  The following events are emitted:

    * `[:ex_llm, :http, :start]` - Request started
    * `[:ex_llm, :http, :stop]` - Request completed successfully
    * `[:ex_llm, :http, :error]` - Request failed
    
  ## Measurements

    * `:duration` - Time taken for the request in native units
    * `:request_size` - Size of request body in bytes
    * `:response_size` - Size of response body in bytes
    
  ## Metadata

    * `:provider` - The LLM provider
    * `:method` - HTTP method
    * `:url` - Request URL
    * `:status` - Response status code
    * `:error` - Error reason (for error events)
    
  ## Options

    * `:metadata` - Additional metadata to include in events
    
  ## Examples

      plug ExLLM.Tesla.Middleware.Telemetry,
        metadata: %{provider: :openai}
  """

  # @behaviour Tesla.Middleware  # Commented to avoid dialyzer callback_info_missing warnings

  # @impl Tesla.Middleware
  def call(env, next, opts) do
    start_time = System.monotonic_time()
    start_metadata = build_start_metadata(env, opts)

    # Emit start event
    :telemetry.execute(
      [:ex_llm, :http, :start],
      %{time: start_time},
      start_metadata
    )

    # Execute the request
    case Tesla.run(env, next) do
      {:ok, env} = result ->
        # Calculate measurements
        duration = System.monotonic_time() - start_time

        measurements = %{
          duration: duration,
          request_size: byte_size_of(env.body),
          response_size: byte_size_of(env.body)
        }

        # Build metadata
        stop_metadata =
          Map.merge(start_metadata, %{
            status: env.status,
            response_headers: env.headers
          })

        # Emit stop event
        :telemetry.execute(
          [:ex_llm, :http, :stop],
          measurements,
          stop_metadata
        )

        result

      {:error, reason} = error ->
        # Calculate duration
        duration = System.monotonic_time() - start_time

        # Build error metadata
        error_metadata =
          Map.merge(start_metadata, %{
            error: reason,
            error_type: classify_error(reason)
          })

        # Emit error event
        :telemetry.execute(
          [:ex_llm, :http, :error],
          %{duration: duration},
          error_metadata
        )

        error
    end
  end

  defp build_start_metadata(env, opts) do
    base_metadata = %{
      method: env.method,
      url: Tesla.build_url(env.url, env.query),
      path: env.url,
      query: env.query,
      request_headers: env.headers
    }

    # Merge with any metadata from options
    case opts[:metadata] do
      nil -> base_metadata
      metadata when is_map(metadata) -> Map.merge(base_metadata, metadata)
      _ -> base_metadata
    end
  end

  defp byte_size_of(nil), do: 0
  defp byte_size_of(body) when is_binary(body), do: byte_size(body)

  defp byte_size_of(body) do
    # For non-binary bodies, encode to JSON to get size
    case Jason.encode(body) do
      {:ok, json} -> byte_size(json)
      _ -> 0
    end
  end

  defp classify_error(:timeout), do: :timeout
  defp classify_error(:closed), do: :connection_closed
  defp classify_error(:econnrefused), do: :connection_refused
  defp classify_error({:tls_alert, _}), do: :tls_error
  defp classify_error(%{reason: :circuit_open}), do: :circuit_breaker
  defp classify_error(_), do: :other
end
