defmodule ExLLM.Plugs.BuildTeslaClient do
  @moduledoc """
  Builds a Tesla HTTP client configured for the specific provider.

  This plug creates a Tesla client with the appropriate middleware stack
  for making API calls to the LLM provider. The client is stored in
  `request.tesla_client` for use by subsequent plugs.

  ## Provider-Specific Configuration

  Each provider gets a customized Tesla client with:
  - Base URL for the provider's API
  - Authentication headers
  - Retry logic
  - Timeout settings
  - Circuit breaker integration
  - Telemetry and logging

  ## Examples

      plug ExLLM.Plugs.BuildTeslaClient
      
  After this plug runs, `request.tesla_client` will contain a configured
  Tesla client ready to make API calls.
  """

  use ExLLM.Plug
  require Logger

  @impl true
  def call(%Request{provider: provider, config: config} = request, _opts) do
    client = build_client(provider, config)
    %{request | tesla_client: client}
  end

  defp build_client(provider, config) do
    base_url = get_base_url(provider, config)

    middleware =
      [
        # Base URL for all requests
        {Tesla.Middleware.BaseUrl, base_url},

        # Headers including auth
        {Tesla.Middleware.Headers, build_headers(provider, config)},

        # Circuit breaker integration
        {ExLLM.Tesla.Middleware.CircuitBreaker, name: "#{provider}_circuit", provider: provider},

        # Retry with exponential backoff
        {Tesla.Middleware.Retry,
         delay: config[:retry_delay] || 1_000,
         max_retries: config[:retry_attempts] || 3,
         max_delay: config[:max_retry_delay] || 30_000,
         should_retry: &should_retry?/1,
         jitter_factor: 0.2},

        # Timeout
        {Tesla.Middleware.Timeout, timeout: config[:timeout] || 60_000},

        # Telemetry
        {ExLLM.Tesla.Middleware.Telemetry, metadata: %{provider: provider}},

        # Logging (only in dev/test)
        maybe_add_logger(config),

        # JSON encoding/decoding
        Tesla.Middleware.JSON,

        # Optional compression
        maybe_add_compression(provider, config)
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    Tesla.client(middleware)
  end

  defp get_base_url(:openai, config) do
    config[:base_url] || "https://api.openai.com/v1"
  end

  defp get_base_url(:anthropic, config) do
    config[:base_url] || "https://api.anthropic.com/v1"
  end

  defp get_base_url(:gemini, config) do
    config[:base_url] || "https://generativelanguage.googleapis.com/v1beta"
  end

  defp get_base_url(:groq, config) do
    config[:base_url] || "https://api.groq.com/openai/v1"
  end

  defp get_base_url(:mistral, config) do
    config[:base_url] || "https://api.mistral.ai/v1"
  end

  defp get_base_url(:openrouter, config) do
    config[:base_url] || "https://openrouter.ai/api/v1"
  end

  defp get_base_url(:perplexity, config) do
    config[:base_url] || "https://api.perplexity.ai"
  end

  defp get_base_url(:xai, config) do
    config[:base_url] || "https://api.x.ai/v1"
  end

  defp get_base_url(:ollama, config) do
    config[:base_url] || config[:ollama_url] || "http://localhost:11434/api"
  end

  defp get_base_url(:lmstudio, config) do
    config[:base_url] || config[:lmstudio_url] || "http://localhost:1234/v1"
  end

  defp get_base_url(_provider, config) do
    config[:base_url] || raise "No base URL configured for provider"
  end

  defp build_headers(:openai, config) do
    base_headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{config[:api_key]}"}
    ]

    # Add optional OpenAI-specific headers
    base_headers
    |> maybe_add_header("openai-organization", config[:organization])
    |> maybe_add_header("openai-project", config[:project])
  end

  defp build_headers(:anthropic, config) do
    [
      {"content-type", "application/json"},
      {"x-api-key", config[:api_key]},
      {"anthropic-version", config[:anthropic_version] || "2023-06-01"}
    ]
  end

  defp build_headers(:gemini, config) do
    # Gemini can use either API key in header or query param
    if config[:api_key] do
      [
        {"content-type", "application/json"},
        {"x-goog-api-key", config[:api_key]}
      ]
    else
      [{"content-type", "application/json"}]
    end
  end

  defp build_headers(:groq, config) do
    [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{config[:api_key]}"}
    ]
  end

  defp build_headers(:mistral, config) do
    [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{config[:api_key]}"}
    ]
  end

  defp build_headers(:openrouter, config) do
    headers = [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{config[:api_key]}"}
    ]

    # OpenRouter specific headers
    headers
    |> maybe_add_header("http-referer", config[:site_url])
    |> maybe_add_header("x-title", config[:app_name])
  end

  defp build_headers(:perplexity, config) do
    [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{config[:api_key]}"}
    ]
  end

  defp build_headers(:xai, config) do
    [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{config[:api_key]}"}
    ]
  end

  defp build_headers(:ollama, _config) do
    [{"content-type", "application/json"}]
  end

  defp build_headers(:lmstudio, _config) do
    [{"content-type", "application/json"}]
  end

  defp build_headers(_provider, config) do
    # Generic headers with optional auth
    headers = [{"content-type", "application/json"}]

    if config[:api_key] do
      headers ++ [{"authorization", "Bearer #{config[:api_key]}"}]
    else
      headers
    end
  end

  defp maybe_add_header(headers, _name, nil), do: headers

  defp maybe_add_header(headers, name, value) do
    headers ++ [{name, value}]
  end

  defp should_retry?({:ok, %{status: status}}) when status in [429, 500, 502, 503, 504] do
    true
  end

  defp should_retry?({:ok, %{status: 401}}) do
    # Don't retry auth errors
    false
  end

  defp should_retry?({:error, :timeout}) do
    true
  end

  defp should_retry?({:error, :closed}) do
    true
  end

  defp should_retry?({:error, :econnrefused}) do
    true
  end

  defp should_retry?({:error, _}) do
    # Retry other errors
    true
  end

  defp should_retry?(_) do
    false
  end

  defp maybe_add_logger(config) do
    if config[:debug] || Mix.env() in [:dev, :test] do
      Tesla.Middleware.Logger
    else
      nil
    end
  end

  defp maybe_add_compression(_provider, config) do
    if config[:compression] do
      {Tesla.Middleware.CompressRequest, format: :gzip}
    else
      nil
    end
  end
end
