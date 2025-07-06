defmodule ExLLM.Providers.Shared.HTTP.ResponseCapture do
  @moduledoc """
  Tesla middleware for capturing API responses.
  
  This middleware intercepts responses and captures them using the
  ResponseCapture module when enabled via environment variables.
  """
  
  @behaviour Tesla.Middleware
  
  alias ExLLM.ResponseCapture
  
  @impl Tesla.Middleware
  def call(env, next, opts) do
    start_time = System.monotonic_time(:millisecond)
    
    # Call the next middleware
    case Tesla.run(env, next) do
      {:ok, response} = result ->
        if ResponseCapture.enabled?() do
          capture_response(env, response, start_time, opts)
        end
        result
        
      error ->
        error
    end
  end
  
  defp capture_response(env, response, start_time, opts) do
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    provider = Keyword.get(opts, :provider, :unknown)
    endpoint = extract_endpoint(env.url)
    
    metadata = %{
      response_time_ms: duration,
      status_code: response.status,
      headers: response.headers,
      method: env.method,
      full_url: env.url
    }
    
    # Extract cost if available from response headers or body
    metadata = 
      case extract_cost(response) do
        nil -> metadata
        cost -> Map.put(metadata, :cost, cost)
      end
    
    # Use Task to avoid blocking the response
    Task.start(fn ->
      ResponseCapture.capture_response(
        provider,
        endpoint,
        env.body,
        response.body,
        metadata
      )
    end)
  end
  
  defp extract_endpoint(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{path: path} when is_binary(path) -> path
      _ -> "unknown"
    end
  end
  
  defp extract_endpoint(_), do: "unknown"
  
  defp extract_cost(response) do
    # Try to extract cost from response body if it's a map
    case response.body do
      %{"usage" => usage} when is_map(usage) ->
        # For now, return nil - cost calculation would need pricing data
        nil
        
      _ ->
        nil
    end
  end
end