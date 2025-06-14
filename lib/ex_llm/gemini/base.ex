defmodule ExLLM.Gemini.Base do
  @moduledoc """
  Base HTTP request functionality for Gemini API modules.
  """

  alias ExLLM.Adapters.Shared.HTTPClient

  @base_url "https://generativelanguage.googleapis.com/v1beta"

  @type request_opts :: [
          method: :get | :post | :patch | :delete,
          url: String.t(),
          body: map() | nil,
          query: map(),
          api_key: String.t(),
          oauth_token: String.t(),
          opts: Keyword.t()
        ]

  @doc """
  Makes an HTTP request to the Gemini API.
  """
  @spec request(request_opts()) :: {:ok, map()} | {:error, map()}
  def request(opts) do
    method = Keyword.fetch!(opts, :method)
    path = Keyword.fetch!(opts, :url)
    query = Keyword.get(opts, :query, %{})
    body = Keyword.get(opts, :body)

    # Support both API key and OAuth token
    {url, headers} =
      if oauth_token = opts[:oauth_token] do
        # OAuth2 authentication
        {build_url(path, query), build_headers(oauth_token: oauth_token)}
      else
        # API key authentication
        api_key = Keyword.get(opts, :api_key)
        {build_url(path, Map.put(query, "key", api_key)), build_headers()}
      end

    # Use shared HTTPClient for caching support
    case make_http_request(method, url, body, headers, opts) do
      {:ok, response_body} when is_map(response_body) ->
        # Direct response body (successful request)
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        # HTTPClient wrapped response format
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        # HTTPClient wrapped error format
        {:error,
         %{status: status, message: extract_error_message(response_body), body: response_body}}

      {:error, reason} ->
        {:error, %{reason: :network_error, message: inspect(reason)}}
    end
  end

  @doc """
  Makes a streaming HTTP request to the Gemini API.
  Returns a function that takes a callback and streams responses.
  """
  @spec stream_request(request_opts(), function()) :: {:ok, any()} | {:error, map()}
  def stream_request(opts, callback) do
    method = Keyword.fetch!(opts, :method)
    path = Keyword.fetch!(opts, :url)
    body = Keyword.get(opts, :body)
    query = Keyword.get(opts, :query, %{})
    request_opts = Keyword.get(opts, :opts, [])

    # Support both API key and OAuth token
    {url, headers} =
      if oauth_token = opts[:oauth_token] do
        # OAuth2 authentication with SSE
        {build_url(path, Map.put(query, "alt", "sse")),
         build_headers(oauth_token: oauth_token, streaming: true)}
      else
        # API key authentication with SSE
        api_key = Keyword.get(opts, :api_key)

        {build_url(path, Map.merge(query, %{"key" => api_key, "alt" => "sse"})),
         build_headers(streaming: true)}
      end

    # Use HTTPClient for streaming with proper caching support
    case method do
      :post ->
        HTTPClient.stream_request(
          url,
          body || %{},
          headers,
          callback,
          [provider: :gemini] ++ request_opts
        )

      _ ->
        {:error, %{reason: :unsupported_method, message: "Streaming only supports POST requests"}}
    end
  end

  defp build_url(path, query_params) do
    query_string = URI.encode_query(query_params)
    "#{@base_url}#{path}?#{query_string}"
  end

  defp build_headers(opts \\ []) do
    base_headers = [
      {"Content-Type", "application/json"},
      {"Accept", if(opts[:streaming], do: "text/event-stream", else: "application/json")}
    ]

    if oauth_token = opts[:oauth_token] do
      [{"Authorization", "Bearer #{oauth_token}"} | base_headers]
    else
      base_headers
    end
  end

  defp extract_error_message(%{"error" => %{"message" => message}}), do: message
  defp extract_error_message(_), do: "Unknown error"

  # Helper function to route requests through shared HTTPClient for caching
  defp make_http_request(method, url, body, headers, opts) when method in [:post, :patch] do
    # For POST/PATCH with body, use post_json
    HTTPClient.post_json(url, body || %{}, headers, [method: method, provider: :gemini] ++ opts)
  end

  defp make_http_request(:get, url, _body, headers, opts) do
    # Use HTTPClient.get_json for caching support
    HTTPClient.get_json(url, headers, [provider: :gemini] ++ opts)
  end

  defp make_http_request(:delete, url, _body, headers, opts) do
    # Use HTTPClient.post_json with DELETE method for caching support
    HTTPClient.post_json(url, %{}, headers, [method: :delete, provider: :gemini] ++ opts)
  end
end
