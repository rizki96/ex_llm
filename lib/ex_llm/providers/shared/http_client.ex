defmodule ExLLM.Providers.Shared.HTTPClient do
  @moduledoc """
  Legacy HTTP client facade for ExLLM adapters.

  This module now serves as a facade over the new Tesla middleware-based
  HTTP architecture while maintaining backward compatibility.

  All functionality has been decomposed into focused modules:
  - HTTP.Core - Tesla client and middleware management
  - HTTP.Authentication - Provider-specific auth headers
  - HTTP.Cache - Response caching with TTL
  - HTTP.ErrorHandling - Retry logic and error mapping
  - HTTP.Multipart - File upload handling
  - HTTP.TestSupport - Test utilities and mocking

  ## Migration Notice

  New code should use the HTTP.Core module directly for better composability.
  This facade will be deprecated in a future version.
  """

  alias ExLLM.Providers.Shared.HTTP
  alias ExLLM.Testing.TestResponseInterceptor

  # Default timeouts
  @default_timeout 60_000
  @stream_timeout 300_000

  @doc """
  Make a POST request with JSON body to an API endpoint.

  ## Options
  - `:timeout` - Request timeout in milliseconds (default: 60s)
  - `:provider` - Provider atom for auth and error handling
  - `:api_key` - API key for authentication
  - `:cache_enabled` - Enable response caching
  - `:retry_enabled` - Enable retry logic
  """
  @spec post_json(String.t(), map(), list({String.t(), String.t()}), keyword()) ::
          {:ok, map()} | {:error, term()}
  def post_json(url, body, headers, opts \\ []) do
    # Check test interceptor first for backward compatibility
    if should_use_test_interceptor?() do
      handle_intercepted_post(url, body, headers, opts)
    else
      execute_post_request(url, body, headers, opts)
    end
  end

  defp handle_intercepted_post(url, body, headers, opts) do
    case TestResponseInterceptor.intercept_request(url, body, headers, opts) do
      {:cached, cached_response} ->
        cached_response

      {:proceed, _request_metadata} ->
        execute_post_request(url, body, headers, opts)
    end
  end

  @doc """
  Make a GET request to an API endpoint.
  """
  @spec get(String.t(), list({String.t(), String.t()}), keyword()) ::
          {:ok, Tesla.Env.t()} | {:error, term()}
  def get(url, headers, opts \\ []) do
    # Check if test caching is enabled via configuration
    if should_use_test_interceptor?() do
      handle_intercepted_get(url, headers, opts)
    else
      do_get_request(url, headers, opts)
    end
  end

  defp handle_intercepted_get(url, headers, opts) do
    case TestResponseInterceptor.intercept_request(url, %{}, headers, opts) do
      {:cached, cached_response} ->
        cached_response

      {:proceed, _request_metadata} ->
        do_get_request(url, headers, opts)
    end
  end

  defp do_get_request(url, headers, opts) do
    case execute_get_request(url, headers, opts) do
      {:ok, response_map} ->
        # Convert back to Tesla.Env format for compatibility
        body_content =
          case response_map[:body] do
            body when is_binary(body) -> body
            body when is_map(body) -> Jason.encode!(body)
            _ -> ""
          end

        tesla_env = %Tesla.Env{
          status: response_map[:status] || 200,
          headers: response_map[:headers] || [],
          body: body_content,
          method: :get,
          url: url
        }

        {:ok, tesla_env}

      error ->
        error
    end
  end

  @doc """
  Make a streaming POST request with Server-Sent Events.

  ## Deprecation Notice

  This function now serves as a compatibility shim. New code should use 
  `ExLLM.Providers.Shared.HTTP.Core.stream/5` directly for better composability
  and performance.

  ### Migration Example

      # Old approach
      HTTPClient.post_stream(url, body, 
        headers: headers,
        into: callback,
        timeout: 60_000
      )
      
      # New approach
      client = HTTP.Core.client(
        provider: :openai,
        api_key: api_key,
        base_url: base_url
      )
      HTTP.Core.stream(client, path, body, callback,
        headers: headers,
        timeout: 60_000
      )
  """
  @deprecated "Use ExLLM.Providers.Shared.HTTP.Core.stream/5 instead"
  @spec post_stream(String.t(), map(), keyword()) :: {:ok, any()} | {:error, term()}
  def post_stream(url, body, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    callback = Keyword.get(opts, :into)
    parse_chunk = Keyword.get(opts, :parse_chunk, &default_parse_chunk/1)

    # Extract base URL and path from the request URL to prevent double /v1 issues
    {base_url, path} = extract_base_url_and_path(url)

    # Build client options with the extracted or provided base URL
    client_opts = build_client_opts(opts, base_url)
    client = HTTP.Core.client(client_opts)

    HTTP.Core.stream(client, path, body, callback,
      headers: headers,
      parse_chunk: parse_chunk,
      timeout: Keyword.get(opts, :timeout, @stream_timeout)
    )
  end

  @doc """
  Upload a multipart file.
  """
  @spec post_multipart(String.t(), list(), keyword()) :: {:ok, any()} | {:error, term()}
  def post_multipart(url, multipart_data, opts \\ []) do
    # Extract base URL and path from the request URL to prevent double /v1 issues
    {base_url, path} = extract_base_url_and_path(url)

    # Build client options with the extracted or provided base URL
    # Disable JSON middleware for multipart uploads
    client_opts = build_client_opts(opts, base_url) ++ [json_enabled: false]
    client = HTTP.Core.client(client_opts)
    headers = normalize_headers(Keyword.get(opts, :headers, []))

    case HTTP.Core.upload(client, path, multipart_data, headers: headers) do
      {:ok, %Tesla.Env{status: status, headers: resp_headers, body: resp_body}} ->
        response = %{
          status: status,
          headers: resp_headers,
          # Don't parse multipart responses - they may already be parsed
          body: resp_body
        }

        {:ok, response}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Make a POST request (legacy compatibility).
  """
  @spec post(String.t(), term(), keyword()) :: {:ok, Tesla.Env.t()} | {:error, term()}
  def post(url, body, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])

    case post_json(url, body, headers, opts) do
      {:ok, response_map} ->
        # Convert back to Tesla.Env format for compatibility
        body_content =
          case response_map[:body] do
            body when is_binary(body) -> body
            body when is_map(body) -> Jason.encode!(body)
            _ -> ""
          end

        tesla_env = %Tesla.Env{
          status: response_map[:status] || 200,
          headers: response_map[:headers] || [],
          body: body_content,
          method: :post,
          url: url
        }

        {:ok, tesla_env}

      error ->
        error
    end
  end

  # Private helper functions

  defp execute_post_request(url, body, headers, opts) do
    # Extract base URL and path from the request URL to prevent double /v1 issues
    {base_url, path} = extract_base_url_and_path(url)

    # Build client options with the extracted or provided base URL
    client_opts = build_client_opts(opts, base_url)
    client = HTTP.Core.client(client_opts)

    # Merge additional headers
    additional_headers = normalize_headers(headers)

    case Tesla.post(client, path, body, headers: additional_headers) do
      {:ok, %Tesla.Env{status: status, headers: resp_headers, body: resp_body}} ->
        response = %{
          status: status,
          headers: resp_headers,
          body: parse_response_body(resp_body)
        }

        {:ok, response}

      {:error, error} ->
        # The error from ErrorHandling middleware is already a map with :type field
        # Just wrap it in an error tuple for backward compatibility
        require Logger
        Logger.debug("HTTPClient.post error: #{inspect(error)}")
        {:error, error}
    end
  end

  defp execute_get_request(url, headers, opts) do
    # Extract base URL and path from the request URL to prevent double /v1 issues
    {base_url, path} = extract_base_url_and_path(url)

    # Build client options with the extracted or provided base URL
    client_opts = build_client_opts(opts, base_url)
    client = HTTP.Core.client(client_opts)
    additional_headers = normalize_headers(headers)

    case Tesla.get(client, path, headers: additional_headers) do
      {:ok, %Tesla.Env{status: status, headers: resp_headers, body: resp_body}} ->
        response = %{
          status: status,
          headers: resp_headers,
          body: parse_response_body(resp_body)
        }

        {:ok, response}

      {:error, _} = error ->
        error
    end
  end

  defp build_client_opts(opts, base_url) do
    [
      provider: Keyword.get(opts, :provider, :openai),
      api_key: Keyword.get(opts, :api_key),
      base_url: base_url || extract_base_url_from_opts(opts),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      cache_enabled: Keyword.get(opts, :cache_enabled, false),
      retry_enabled: Keyword.get(opts, :retry_enabled, true),
      max_retries: Keyword.get(opts, :max_retries, 3)
    ]
  end

  defp extract_base_url_from_opts(opts) do
    # Try to extract base URL from provider or use explicit base_url
    case Keyword.get(opts, :base_url) do
      nil ->
        provider = Keyword.get(opts, :provider, :openai)
        get_default_base_url(provider)

      base_url ->
        base_url
    end
  end

  defp get_default_base_url(provider) do
    case provider do
      :openai -> "https://api.openai.com/v1"
      :anthropic -> "https://api.anthropic.com"
      :groq -> "https://api.groq.com/openai/v1"
      :gemini -> "https://generativelanguage.googleapis.com/v1beta"
      :ollama -> "http://localhost:11434/api"
      :lmstudio -> "http://localhost:1234/v1"
      :mistral -> "https://api.mistral.ai/v1"
      :openrouter -> "https://openrouter.ai/api/v1"
      :perplexity -> "https://api.perplexity.ai"
      :xai -> "https://api.x.ai/v1"
      # Default fallback
      _ -> "https://api.openai.com/v1"
    end
  end

  defp extract_base_url_and_path(url) do
    uri = URI.parse(url)

    # Check if this is an absolute URL (has scheme and host)
    if uri.scheme && uri.host do
      # Extract base URL (scheme + host + port)
      port_part =
        if uri.port && uri.port != URI.default_port(uri.scheme) do
          ":#{uri.port}"
        else
          ""
        end

      base_url = "#{uri.scheme}://#{uri.host}#{port_part}"
      path = uri.path || "/"

      # Include query if present
      path_with_query =
        if uri.query do
          "#{path}?#{uri.query}"
        else
          path
        end

      {base_url, path_with_query}
    else
      # Relative URL - return nil for base_url and the original URL as path
      {nil, url}
    end
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      {key, value} -> {to_string(key), to_string(value)}
      header -> header
    end)
  end

  defp normalize_headers(headers) when is_map(headers) do
    Enum.map(headers, fn {key, value} ->
      {to_string(key), to_string(value)}
    end)
  end

  defp parse_response_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parsed
      {:error, _} -> body
    end
  end

  defp parse_response_body(body), do: body

  defp default_parse_chunk(data) do
    case Jason.decode(data) do
      {:ok, parsed} ->
        content = get_in(parsed, ["choices", Access.at(0), "delta", "content"]) || ""
        finish_reason = get_in(parsed, ["choices", Access.at(0), "finish_reason"])

        chunk = %ExLLM.Types.StreamChunk{
          content: content,
          finish_reason: finish_reason
        }

        {:ok, chunk}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  # Missing compatibility functions

  @doc """
  Make a GET request with JSON response parsing.
  """
  @spec get_json(String.t(), list({String.t(), String.t()}), keyword()) ::
          {:ok, any()} | {:error, term()}
  def get_json(url, headers, opts \\ []) do
    case get(url, headers, opts) do
      {:ok, %Tesla.Env{body: body}} ->
        # Body is already parsed by execute_get_request
        {:ok, body}

      error ->
        error
    end
  end

  @doc """
  Make a streaming request with callback support.
  """
  @spec stream_request(String.t(), map(), list({String.t(), String.t()}), function(), keyword()) ::
          {:ok, :streaming} | {:error, term()}
  def stream_request(url, body, headers, callback, opts \\ []) do
    case post_stream(url, body, Keyword.merge(opts, headers: headers, into: callback)) do
      {:ok, _response} -> {:ok, :streaming}
      {:error, _} = error -> error
    end
  end

  @doc """
  Make a DELETE request with JSON response parsing.
  """
  @spec delete_json(String.t(), list({String.t(), String.t()}), keyword()) ::
          {:ok, any()} | {:error, term()}
  def delete_json(url, headers, opts \\ []) do
    # Extract base URL and path from the request URL to prevent double /v1 issues
    {base_url, path} = extract_base_url_and_path(url)

    # Build client options with the extracted or provided base URL
    client_opts = build_client_opts(opts, base_url)
    client = HTTP.Core.client(client_opts)
    additional_headers = normalize_headers(headers)

    case Tesla.delete(client, path, headers: additional_headers) do
      {:ok, %Tesla.Env{body: resp_body}} ->
        # Return just the parsed body like get_json does
        {:ok, parse_response_body(resp_body)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get binary content from a URL.
  """
  @spec get_binary(String.t(), list({String.t(), String.t()}), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def get_binary(url, headers, opts \\ []) do
    # Extract base URL and path from the request URL to prevent double /v1 issues
    {base_url, path} = extract_base_url_and_path(url)

    # Build client options with the extracted or provided base URL
    client_opts = build_client_opts(opts, base_url)
    client = HTTP.Core.client(client_opts)
    additional_headers = normalize_headers(headers)

    case Tesla.get(client, path, headers: additional_headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status} = response} ->
        {:error, %{status_code: status, response: response}}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Build provider-specific headers.
  """
  @spec build_provider_headers(atom(), keyword()) :: list({String.t(), String.t()})
  def build_provider_headers(provider, opts \\ []) do
    case provider do
      :gemini ->
        api_key = Keyword.get(opts, :api_key)

        if api_key do
          [
            {"x-goog-api-client", "ex_llm/1.0.0"},
            {"authorization", "Bearer #{api_key}"}
          ]
        else
          [{"x-goog-api-client", "ex_llm/1.0.0"}]
        end

      :anthropic ->
        api_key = Keyword.get(opts, :api_key)

        if api_key do
          [
            {"x-api-key", api_key},
            {"anthropic-version", "2023-06-01"},
            {"anthropic-beta", "messages-2023-12-15"}
          ]
        else
          []
        end

      :openai ->
        api_key = Keyword.get(opts, :api_key)

        if api_key do
          [{"authorization", "Bearer #{api_key}"}]
        else
          []
        end

      _ ->
        api_key = Keyword.get(opts, :api_key)

        if api_key do
          [{"authorization", "Bearer #{api_key}"}]
        else
          []
        end
    end
  end

  @doc """
  Post multipart data with 4-argument signature for compatibility.
  """
  @spec post_multipart(String.t(), list(), list({String.t(), String.t()}), keyword()) ::
          {:ok, map()} | {:error, term()}
  def post_multipart(url, multipart_data, headers, opts) do
    # Merge headers into opts for the 3-argument version
    merged_opts = Keyword.merge(opts, headers: headers)
    post_multipart(url, multipart_data, merged_opts)
  end

  # Legacy function compatibility (deprecated)

  @doc false
  @deprecated "Use HTTP.Core.client/1 directly"
  def prepare_headers(headers), do: normalize_headers(headers)

  @doc false
  @deprecated "Use HTTP.ErrorHandling middleware"
  def handle_response(%{status: status} = response) when status >= 200 and status < 300 do
    {:ok, response}
  end

  def handle_response(%{status: status} = response) do
    {:error, %{status_code: status, response: response}}
  end

  @doc false
  @deprecated "Use HTTP.TestSupport.mock_response/2"
  def build_mock_response(content, opts \\ []) do
    HTTP.TestSupport.mock_chat_response(content, opts)
  end

  # Check if test interceptor should be used based on configuration
  defp should_use_test_interceptor? do
    Application.get_env(:ex_llm, :test_cache_enabled, false) &&
      Application.get_env(:ex_llm, :env, :prod) == :test
  end
end
