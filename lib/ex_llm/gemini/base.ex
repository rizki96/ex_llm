defmodule ExLLM.Gemini.Base do
  @moduledoc """
  Base HTTP request functionality for Gemini API modules.
  """

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

    req_opts = [headers: headers]
    req_opts = if body, do: [{:json, body} | req_opts], else: req_opts

    case apply(Req, method, [url | [req_opts]]) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error,
         %{status: status, message: extract_error_message(response_body), body: response_body}}

      {:error, reason} ->
        {:error, %{reason: :network_error, message: inspect(reason)}}
    end
  end

  @doc """
  Makes a streaming HTTP request to the Gemini API.
  """
  @spec stream_request(request_opts()) :: {:ok, Enumerable.t()} | {:error, map()}
  def stream_request(opts) do
    _method = Keyword.fetch!(opts, :method)
    path = Keyword.fetch!(opts, :url)
    api_key = Keyword.fetch!(opts, :api_key)
    query = Keyword.get(opts, :query, %{})
    _body = Keyword.get(opts, :body)

    _url = build_url(path, Map.merge(query, %{"key" => api_key, "alt" => "sse"}))
    _headers = build_headers()

    # For now, return not implemented
    # This would need proper SSE streaming implementation
    {:error, :not_implemented}
  end

  defp build_url(path, query_params) do
    query_string = URI.encode_query(query_params)
    "#{@base_url}#{path}?#{query_string}"
  end

  defp build_headers(opts \\ []) do
    base_headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    if oauth_token = opts[:oauth_token] do
      [{"Authorization", "Bearer #{oauth_token}"} | base_headers]
    else
      base_headers
    end
  end

  defp extract_error_message(%{"error" => %{"message" => message}}), do: message
  defp extract_error_message(_), do: "Unknown error"
end
