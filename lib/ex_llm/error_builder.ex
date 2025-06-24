defmodule ExLLM.ErrorBuilder do
  @moduledoc """
  A centralized module for building consistent error structures for ExLLM.

  This module extracts error building patterns from plugs and providers to ensure
  uniform error handling across the library. It provides functions to create
  standardized error maps for various HTTP and network-related issues.
  """

  @typedoc "The provider atom, e.g., :openai, :anthropic."
  @type provider :: atom()

  @typedoc "The HTTP status code."
  @type status :: integer() | nil

  @typedoc "The HTTP response body."
  @type body :: any()

  @typedoc "The reason for a network error."
  @type reason :: atom() | term()

  @doc """
  Builds a generic HTTP error map based on the status code.

  It delegates to more specific error builders for common status codes like
  401, 403, 404, 429, and 500. For other status codes, it creates a
  generic `:http_error` map.
  """
  @spec http_error(status, body, provider) :: map()
  def http_error(401, body, provider) do
    %{
      error: :unauthorized,
      message: "Authentication failed for #{provider}. Check your API key.",
      status: 401,
      body: body,
      provider: provider
    }
  end

  def http_error(403, body, provider) do
    %{
      error: :forbidden,
      message: "Access forbidden for #{provider}. Check your permissions.",
      status: 403,
      body: body,
      provider: provider
    }
  end

  def http_error(404, _body, provider) do
    %{
      error: :not_found,
      message: "Endpoint not found for #{provider}. The API may have changed.",
      status: 404,
      provider: provider
    }
  end

  def http_error(429, body, provider) do
    rate_limit_error(body, provider)
  end

  def http_error(500, body, provider) do
    server_error(body, provider)
  end

  def http_error(nil, body, provider) do
    connection_error(body, provider)
  end

  def http_error(status, body, provider) do
    %{
      error: :http_error,
      message: "HTTP error #{status} from #{provider}.",
      status: status,
      body: body,
      provider: provider
    }
  end

  @doc """
  Builds a network error map based on the reason.

  Handles common network issues like timeouts, connection refused, and
  circuit breaker events.
  """
  @spec network_error(reason, provider) :: map()
  def network_error(:timeout, provider) do
    %{
      error: :timeout,
      message: "Request timeout for #{provider}.",
      provider: provider
    }
  end

  def network_error(:econnrefused, provider) do
    %{
      error: :connection_refused,
      message: "Connection refused for #{provider}. Is the service running?",
      provider: provider
    }
  end

  def network_error(%{reason: :circuit_open} = error, provider) do
    %{
      error: :circuit_open,
      message: error[:message] || "Circuit breaker open for #{provider}.",
      provider: provider,
      retry_after: error[:retry_after]
    }
  end

  def network_error(reason, provider) do
    %{
      error: :network_error,
      message: "Network error for #{provider}: #{inspect(reason)}",
      reason: reason,
      provider: provider
    }
  end

  @doc """
  Builds an authentication error map.

  This is a specific type of HTTP error (401).
  """
  @spec authentication_error(provider) :: map()
  def authentication_error(provider) do
    http_error(401, nil, provider)
  end

  @doc """
  Builds a rate limit error map.

  This is a specific type of HTTP error (429). It attempts to extract
  a `retry_after` value from the response body.
  """
  @spec rate_limit_error(body, provider) :: map()
  def rate_limit_error(body, provider) do
    retry_after = extract_retry_after(body)

    %{
      error: :rate_limited,
      message: "Rate limit exceeded for #{provider}.",
      status: 429,
      body: body,
      provider: provider,
      retry_after: retry_after
    }
  end

  @doc """
  Builds a server error map.

  This is a specific type of HTTP error (500).
  """
  @spec server_error(body, provider) :: map()
  def server_error(body, provider) do
    %{
      error: :server_error,
      message: "Internal server error from #{provider}.",
      status: 500,
      body: body,
      provider: provider
    }
  end

  @doc """
  Builds a connection error map.

  This is used when no HTTP status is received from the provider.
  """
  @spec connection_error(body, provider) :: map()
  def connection_error(body, provider) do
    %{
      error: :connection_error,
      message: "Connection error to #{provider}. No HTTP status received.",
      status: nil,
      body: body,
      provider: provider
    }
  end

  defp extract_retry_after(body) when is_map(body) do
    # Try common fields where retry-after might be
    body["retry_after"] || body["retryAfter"] || body["retry-after"] || nil
  end

  defp extract_retry_after(_), do: nil
end
