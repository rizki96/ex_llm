defmodule ExLLM.Providers.Gemini.Base do
  @moduledoc """
  Base HTTP request functionality for Gemini API modules.
  """

  alias ExLLM.Providers.Shared.HTTP.Core

  @base_url "https://generativelanguage.googleapis.com/v1beta"
  @base_url_v1 "https://generativelanguage.googleapis.com/v1"

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
  Makes an HTTP request to the Gemini API (v1beta endpoint).
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

    # Use shared HTTP.Core for caching support
    case make_http_request(method, url, body, headers, opts) do
      {:error, reason} ->
        {:error, %{reason: :network_error, message: inspect(reason)}}

      {:ok, response_body} ->
        # Direct response body (successful request)
        {:ok, response_body}
    end
  end

  @doc """
  Makes an HTTP request to the Gemini API (v1 endpoint).
  """
  @spec request_v1(request_opts()) :: {:ok, map()} | {:error, map()}
  def request_v1(opts) do
    method = Keyword.fetch!(opts, :method)
    path = Keyword.fetch!(opts, :url)
    query = Keyword.get(opts, :query, %{})
    body = Keyword.get(opts, :body)

    # Support both API key and OAuth token
    {url, headers} =
      if oauth_token = opts[:oauth_token] do
        # OAuth2 authentication
        {build_url_v1(path, query), build_headers(oauth_token: oauth_token)}
      else
        # API key authentication
        api_key = Keyword.get(opts, :api_key)
        {build_url_v1(path, Map.put(query, "key", api_key)), build_headers()}
      end

    # Use shared HTTP.Core for caching support
    case make_http_request(method, url, body, headers, opts) do
      {:error, reason} ->
        {:error, %{reason: :network_error, message: inspect(reason)}}

      {:ok, response_body} ->
        # Direct response body (successful request)
        {:ok, response_body}
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
    {url, _headers} =
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

    # Use Core.stream for streaming requests
    case method do
      :post ->
        # Extract configuration from opts  
        api_key = get_api_key_from_opts(request_opts)
        oauth_token = get_oauth_token_from_opts(request_opts)
        timeout = Keyword.get(request_opts, :timeout, 300_000)

        # Create client with Gemini-specific configuration
        client_opts = [
          provider: :gemini,
          base_url: get_base_url_from_full_url(url)
        ]

        client_opts =
          cond do
            oauth_token -> Keyword.put(client_opts, :oauth_token, oauth_token)
            api_key -> Keyword.put(client_opts, :api_key, api_key)
            true -> client_opts
          end

        client = Core.client(client_opts)

        # Extract path from full URL
        path = get_path_from_url(url)

        # Use Core.stream for streaming
        Core.stream(client, path, body || %{}, callback, timeout: timeout)

      _ ->
        {:error, %{reason: :unsupported_method, message: "Streaming only supports POST requests"}}
    end
  end

  defp build_url(path, query_params) do
    query_string = URI.encode_query(query_params)
    "#{@base_url}#{path}?#{query_string}"
  end

  defp build_url_v1(path, query_params) do
    query_string = URI.encode_query(query_params)
    "#{@base_url_v1}#{path}?#{query_string}"
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

  # Helper function to route requests through Core HTTP client
  defp make_http_request(method, url, body, headers, opts) when method in [:post, :patch] do
    gemini_core_request(method, url, body, headers, opts)
  end

  defp make_http_request(:get, url, _body, headers, opts) do
    gemini_core_request(:get, url, nil, headers, opts)
  end

  defp make_http_request(:delete, url, _body, headers, opts) do
    gemini_core_request(:delete, url, %{}, headers, opts)
  end

  # Core HTTP client helper for Gemini API
  defp gemini_core_request(method, url, body, _headers, opts) do
    # Extract configuration from opts
    api_key = get_api_key_from_opts(opts)
    oauth_token = get_oauth_token_from_opts(opts)
    timeout = Keyword.get(opts, :timeout, 60_000)

    # Create client with Gemini-specific configuration  
    client_opts = [
      provider: :gemini,
      base_url: get_base_url_from_full_url(url)
    ]

    client_opts =
      cond do
        oauth_token -> Keyword.put(client_opts, :oauth_token, oauth_token)
        api_key -> Keyword.put(client_opts, :api_key, api_key)
        true -> client_opts
      end

    client = Core.client(client_opts)

    # Extract path from full URL
    path = get_path_from_url(url)

    # Execute request
    result =
      case method do
        :get -> Tesla.get(client, path, opts: [timeout: timeout])
        :post -> Tesla.post(client, path, body || %{}, opts: [timeout: timeout])
        :patch -> Tesla.patch(client, path, body || %{}, opts: [timeout: timeout])
        :delete -> Tesla.delete(client, path, opts: [timeout: timeout])
      end

    # Convert Tesla response to expected format
    case result do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        # Try to decode JSON if it's a string
        parsed_body =
          case body do
            body when is_binary(body) ->
              case Jason.decode(body) do
                {:ok, parsed} -> parsed
                {:error, _} -> body
              end

            body ->
              body
          end

        {:ok, parsed_body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper to extract API key from opts (could be in nested structure)
  defp get_api_key_from_opts(opts) do
    Keyword.get(opts, :api_key)
  end

  # Helper to extract OAuth token from opts  
  defp get_oauth_token_from_opts(opts) do
    Keyword.get(opts, :oauth_token)
  end

  # Helper to extract base URL from full URL
  defp get_base_url_from_full_url(url) do
    uri = URI.parse(url)

    "#{uri.scheme}://#{uri.host}#{if uri.port && uri.port not in [80, 443], do: ":#{uri.port}", else: ""}"
  end

  # Helper to extract path from full URL (preserving query params)
  defp get_path_from_url(url) do
    uri = URI.parse(url)
    path = uri.path || "/"
    if uri.query, do: "#{path}?#{uri.query}", else: path
  end
end
