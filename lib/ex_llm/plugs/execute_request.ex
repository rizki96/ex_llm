defmodule ExLLM.Plugs.ExecuteRequest do
  @moduledoc """
  Executes the HTTP request to the LLM provider using the configured Tesla client.

  This plug expects:
  - `request.tesla_client` - A configured Tesla client (from BuildTeslaClient)
  - `request.provider_request` - The formatted request body (from provider-specific PrepareRequest)

  After execution, it sets:
  - `request.response` - The raw Tesla response
  - `request.state` - Updated to `:completed` or `:error`

  ## Options

    * `:endpoint` - Override the endpoint path (defaults to provider-specific)
    * `:method` - HTTP method (defaults to :post)
    
  ## Examples

      plug ExLLM.Plugs.ExecuteRequest
      
      # With custom endpoint
      plug ExLLM.Plugs.ExecuteRequest, endpoint: "/v1/completions"
  """

  use ExLLM.Plug
  require Logger

  @impl true
  def init(opts) do
    Keyword.validate!(opts, [:endpoint, :method])
  end

  @impl true
  def call(%Request{tesla_client: nil} = request, _opts) do
    request
    |> Request.halt_with_error(%{
      plug: __MODULE__,
      error: :missing_tesla_client,
      message: "Tesla client not configured. Did BuildTeslaClient run?"
    })
  end

  def call(%Request{provider_request: nil} = request, _opts) do
    request
    |> Request.halt_with_error(%{
      plug: __MODULE__,
      error: :missing_provider_request,
      message: "Provider request not prepared. Did PrepareRequest run?"
    })
  end

  def call(%Request{} = request, opts) do
    endpoint =
      opts[:endpoint] || request.assigns[:http_path] || get_provider_endpoint(request.provider)

    method = opts[:method] || request.assigns[:http_method] || :post

    # Log the request in debug mode
    if request.config[:debug] do
      Logger.debug("""
      ExLLM Request:
      Provider: #{request.provider}
      Endpoint: #{endpoint}
      Model: #{request.config[:model]}
      """)
    end

    # Update state to executing
    request = Request.put_state(request, :executing)

    # Make the request
    case make_request(request.tesla_client, method, endpoint, request.provider_request) do
      {:ok, %Tesla.Env{status: status} = env} when status in 200..299 ->
        # Success
        request
        |> Map.put(:response, env)
        |> Request.put_state(:completed)
        |> Request.put_metadata(:http_status, status)
        |> Request.put_metadata(:response_headers, env.headers)

      {:ok, %Tesla.Env{status: status, body: body} = env} ->
        # HTTP error
        error = build_http_error(status, body, request.provider)

        request
        |> Map.put(:response, env)
        |> Request.halt_with_error(error)
        |> Request.put_metadata(:http_status, status)

      {:error, reason} ->
        # Network or other error
        error = build_network_error(reason, request.provider)

        request
        |> Request.halt_with_error(error)

      %Tesla.Env{status: status} = env when status in 200..299 ->
        # Direct success response
        request
        |> Map.put(:response, env)
        |> Request.put_state(:completed)
        |> Request.put_metadata(:http_status, status)
        |> Request.put_metadata(:response_headers, env.headers)

      %Tesla.Env{status: status, body: body} = env ->
        # Direct HTTP error
        error = build_http_error(status, body, request.provider)

        request
        |> Map.put(:response, env)
        |> Request.halt_with_error(error)
        |> Request.put_metadata(:http_status, status)
    end
  end

  defp make_request(client, :post, endpoint, body) do
    Tesla.post(client, endpoint, body)
  end

  defp make_request(client, :get, endpoint, _body) do
    Tesla.get(client, endpoint)
  end

  defp make_request(client, :put, endpoint, body) do
    Tesla.put(client, endpoint, body)
  end

  defp make_request(client, :patch, endpoint, body) do
    Tesla.patch(client, endpoint, body)
  end

  defp make_request(client, :delete, endpoint, _body) do
    Tesla.delete(client, endpoint)
  end

  defp get_provider_endpoint(:openai), do: "/chat/completions"
  defp get_provider_endpoint(:anthropic), do: "/messages"
  defp get_provider_endpoint(:gemini), do: "/models/gemini-pro:generateContent"
  defp get_provider_endpoint(:groq), do: "/chat/completions"
  defp get_provider_endpoint(:mistral), do: "/chat/completions"
  defp get_provider_endpoint(:openrouter), do: "/chat/completions"
  defp get_provider_endpoint(:perplexity), do: "/chat/completions"
  defp get_provider_endpoint(:xai), do: "/chat/completions"
  defp get_provider_endpoint(:ollama), do: "/generate"
  defp get_provider_endpoint(:lmstudio), do: "/chat/completions"
  defp get_provider_endpoint(_), do: "/chat/completions"

  defp build_http_error(401, body, provider) do
    %{
      plug: __MODULE__,
      error: :unauthorized,
      message: "Authentication failed for #{provider}. Check your API key.",
      status: 401,
      body: body,
      provider: provider
    }
  end

  defp build_http_error(403, body, provider) do
    %{
      plug: __MODULE__,
      error: :forbidden,
      message: "Access forbidden for #{provider}. Check your permissions.",
      status: 403,
      body: body,
      provider: provider
    }
  end

  defp build_http_error(404, _body, provider) do
    %{
      plug: __MODULE__,
      error: :not_found,
      message: "Endpoint not found for #{provider}. The API may have changed.",
      status: 404,
      provider: provider
    }
  end

  defp build_http_error(429, body, provider) do
    # Try to extract retry-after header
    retry_after = extract_retry_after(body)

    %{
      plug: __MODULE__,
      error: :rate_limited,
      message: "Rate limit exceeded for #{provider}.",
      status: 429,
      body: body,
      provider: provider,
      retry_after: retry_after
    }
  end

  defp build_http_error(500, body, provider) do
    %{
      plug: __MODULE__,
      error: :server_error,
      message: "Internal server error from #{provider}.",
      status: 500,
      body: body,
      provider: provider
    }
  end

  defp build_http_error(status, body, provider) do
    %{
      plug: __MODULE__,
      error: :http_error,
      message: "HTTP error #{status} from #{provider}.",
      status: status,
      body: body,
      provider: provider
    }
  end

  defp build_network_error(:timeout, provider) do
    %{
      plug: __MODULE__,
      error: :timeout,
      message: "Request timeout for #{provider}.",
      provider: provider
    }
  end

  defp build_network_error(:econnrefused, provider) do
    %{
      plug: __MODULE__,
      error: :connection_refused,
      message: "Connection refused for #{provider}. Is the service running?",
      provider: provider
    }
  end

  defp build_network_error(%{reason: :circuit_open} = error, provider) do
    %{
      plug: __MODULE__,
      error: :circuit_open,
      message: error[:message] || "Circuit breaker open for #{provider}.",
      provider: provider,
      retry_after: error[:retry_after]
    }
  end

  defp build_network_error(reason, provider) do
    %{
      plug: __MODULE__,
      error: :network_error,
      message: "Network error for #{provider}: #{inspect(reason)}",
      reason: reason,
      provider: provider
    }
  end

  defp extract_retry_after(body) when is_map(body) do
    # Try common fields where retry-after might be
    body["retry_after"] || body["retryAfter"] || body["retry-after"] || nil
  end

  defp extract_retry_after(_), do: nil
end
