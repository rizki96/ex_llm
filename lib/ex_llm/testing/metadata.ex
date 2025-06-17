defmodule ExLLM.Testing.TestResponseMetadata do
  @moduledoc false

  @type response_metadata :: %{
          # Request Information
          provider: String.t(),
          endpoint: String.t(),
          method: String.t(),
          request_body: map(),
          request_headers: list(),
          request_size: non_neg_integer(),

          # Response Information
          response_body: any(),
          response_headers: list(),
          status_code: non_neg_integer() | nil,
          response_time_ms: non_neg_integer(),
          response_size: non_neg_integer(),

          # Test Context
          test_module: String.t() | nil,
          test_name: String.t() | nil,
          test_tags: [atom()],
          test_pid: String.t() | nil,

          # Caching Information
          cached_at: DateTime.t(),
          cache_version: String.t(),
          api_version: String.t() | nil,

          # Usage Tracking
          usage: map() | nil,
          cost: map() | nil,

          # Additional metadata
          streaming: boolean(),
          error: boolean(),
          retry_attempt: non_neg_integer() | nil
        }

  @cache_version "1.0"

  @doc """
  Create comprehensive metadata for a cached response.
  """
  @spec create_metadata(map(), any(), map()) :: response_metadata()
  def create_metadata(request_metadata, response_data, response_info \\ %{}) do
    %{
      # Request Information
      provider: extract_provider(request_metadata),
      endpoint: extract_endpoint(request_metadata),
      method: Map.get(request_metadata, :method, "POST"),
      request_body: sanitize_request_body(Map.get(request_metadata, :body, %{})),
      request_headers: sanitize_headers(Map.get(request_metadata, :headers, [])),
      request_size: Map.get(request_metadata, :body_size, 0),

      # Response Information
      response_body: response_data,
      response_headers: Map.get(response_info, :headers, []),
      status_code: Map.get(response_info, :status_code),
      response_time_ms: calculate_response_time(request_metadata, response_info),
      response_size: calculate_response_size(response_data),

      # Test Context
      test_module: extract_test_module(request_metadata),
      test_name: extract_test_name(request_metadata),
      test_tags: extract_test_tags(request_metadata),
      test_pid: extract_test_pid(request_metadata),

      # Caching Information
      cached_at: DateTime.utc_now(),
      cache_version: @cache_version,
      api_version: extract_api_version(request_metadata, response_info),

      # Usage Tracking
      usage: extract_usage_info(response_data),
      cost: extract_cost_info(response_data),

      # Additional metadata
      streaming: Map.get(response_info, :streaming, false),
      error: is_error_response?(response_data),
      retry_attempt: Map.get(response_info, :retry_attempt)
    }
  end

  @doc """
  Extract minimal metadata for cache key generation.
  """
  @spec create_cache_key_metadata(map()) :: map()
  def create_cache_key_metadata(request_metadata) do
    %{
      provider: extract_provider(request_metadata),
      endpoint: extract_endpoint(request_metadata),
      method: Map.get(request_metadata, :method, "POST"),
      test_context: Map.get(request_metadata, :test_context, %{}),
      body_signature: generate_body_signature(Map.get(request_metadata, :body, %{}))
    }
  end

  @doc """
  Update metadata with additional information.
  """
  @spec update_metadata(response_metadata(), map()) :: response_metadata()
  def update_metadata(metadata, updates) do
    Map.merge(metadata, updates)
  end

  @doc """
  Sanitize metadata for storage (remove sensitive information).
  """
  @spec sanitize_for_storage(response_metadata()) :: response_metadata()
  def sanitize_for_storage(metadata) do
    metadata
    |> sanitize_request_data()
    |> sanitize_response_data()
    |> sanitize_test_context()
  end

  @doc """
  Extract timing information from metadata.
  """
  @spec extract_timing_info(response_metadata()) :: map()
  def extract_timing_info(metadata) do
    %{
      response_time_ms: metadata.response_time_ms,
      cached_at: metadata.cached_at,
      streaming: metadata.streaming
    }
  end

  @doc """
  Extract cost information from metadata.
  """
  @spec extract_cost_summary(response_metadata()) :: map()
  def extract_cost_summary(metadata) do
    case metadata.cost do
      nil ->
        %{total: 0, input: 0, output: 0}

      cost when is_map(cost) ->
        %{
          total: Map.get(cost, :total, Map.get(cost, "total", 0)),
          input: Map.get(cost, :input, Map.get(cost, "input", 0)),
          output: Map.get(cost, :output, Map.get(cost, "output", 0))
        }

      _ ->
        %{total: 0, input: 0, output: 0}
    end
  end

  @doc """
  Check if metadata indicates a successful response.
  """
  @spec successful_response?(response_metadata()) :: boolean()
  def successful_response?(metadata) do
    not metadata.error and
      (is_nil(metadata.status_code) or metadata.status_code in 200..299)
  end

  # Private functions

  defp extract_provider(request_metadata) do
    case Map.get(request_metadata, :url) do
      nil ->
        "unknown"

      url when is_binary(url) ->
        cond do
          String.contains?(url, "api.anthropic.com") -> "anthropic"
          String.contains?(url, "api.openai.com") -> "openai"
          String.contains?(url, "generativelanguage.googleapis.com") -> "gemini"
          String.contains?(url, "api.groq.com") -> "groq"
          String.contains?(url, "openrouter.ai") -> "openrouter"
          String.contains?(url, "localhost") or String.contains?(url, "127.0.0.1") -> "local"
          true -> "unknown"
        end

      _ ->
        "unknown"
    end
  end

  defp extract_endpoint(request_metadata) do
    case Map.get(request_metadata, :url) do
      nil ->
        "unknown"

      url when is_binary(url) ->
        uri = URI.parse(url)

        case uri.path do
          nil ->
            "unknown"

          path ->
            path
            |> String.trim_leading("/")
            |> String.replace("/", "_")
        end

      _ ->
        "unknown"
    end
  end

  defp extract_test_module(request_metadata) do
    case Map.get(request_metadata, :test_context) do
      %{module: module} -> to_string(module)
      nil -> nil
      _ -> nil
    end
  end

  defp extract_test_name(request_metadata) do
    case Map.get(request_metadata, :test_context) do
      %{test_name: name} -> name
      nil -> nil
      _ -> nil
    end
  end

  defp extract_test_tags(request_metadata) do
    case Map.get(request_metadata, :test_context) do
      %{tags: tags} -> tags
      nil -> []
      _ -> []
    end
  end

  defp extract_test_pid(request_metadata) do
    case Map.get(request_metadata, :test_context) do
      %{pid: pid} -> inspect(pid)
      nil -> nil
      _ -> nil
    end
  end

  defp extract_api_version(request_metadata, response_info) do
    # Check response headers first
    response_version =
      response_info
      |> Map.get(:headers, [])
      |> find_version_header()

    case response_version do
      nil ->
        # Fall back to request headers
        request_metadata
        |> Map.get(:headers, [])
        |> find_version_header()

      version ->
        version
    end
  end

  defp find_version_header(headers) do
    headers
    |> Enum.find_value(fn
      {key, value} when key in ["api-version", "x-api-version", "anthropic-version"] -> value
      _ -> nil
    end)
  end

  defp calculate_response_time(request_metadata, response_info) do
    case {Map.get(request_metadata, :requested_at), Map.get(response_info, :completed_at)} do
      {%DateTime{} = start_time, %DateTime{} = end_time} ->
        DateTime.diff(end_time, start_time, :millisecond)

      _ ->
        Map.get(response_info, :response_time_ms, 0)
    end
  end

  defp calculate_response_size(response_data) do
    case response_data do
      data when is_binary(data) ->
        byte_size(data)

      data when is_map(data) ->
        case Jason.encode(data) do
          {:ok, json} -> byte_size(json)
          {:error, _} -> 0
        end

      _ ->
        0
    end
  end

  defp extract_usage_info(response_data) when is_map(response_data) do
    # Look for usage information in common locations
    usage =
      response_data
      |> Map.get("usage", response_data |> Map.get(:usage))

    case usage do
      nil -> nil
      usage_map when is_map(usage_map) -> usage_map
      _ -> nil
    end
  end

  defp extract_usage_info(_response_data), do: nil

  defp extract_cost_info(response_data) when is_map(response_data) do
    # Look for cost information (might be added by ExLLM)
    cost =
      response_data
      |> Map.get("cost", response_data |> Map.get(:cost))

    case cost do
      nil -> nil
      cost_map when is_map(cost_map) -> cost_map
      _ -> nil
    end
  end

  defp extract_cost_info(_response_data), do: nil

  defp is_error_response?(response_data) when is_map(response_data) do
    has_error =
      Map.has_key?(response_data, "error") or
        Map.has_key?(response_data, :error) or
        Map.get(response_data, "status") == "error" or
        Map.get(response_data, :status) == :error

    has_error
  end

  defp is_error_response?(_response_data), do: false

  defp generate_body_signature(body) when is_map(body) do
    # Create a signature that ignores sensitive fields but captures structure
    sanitized_body = sanitize_request_body(body)

    case Jason.encode(sanitized_body) do
      {:ok, json} ->
        :crypto.hash(:sha256, json)
        |> Base.encode16(case: :lower)
        |> String.slice(0..15)

      {:error, _} ->
        "unknown"
    end
  end

  defp generate_body_signature(_body), do: "unknown"

  defp sanitize_request_body(body) when is_map(body) do
    # Remove sensitive fields but keep structure for caching
    sensitive_keys = ["api_key", "authorization", "token", "password", "secret"]

    body
    |> Map.drop(sensitive_keys)
    |> Enum.map(fn {k, v} ->
      key_str = String.downcase(to_string(k))

      if key_str in sensitive_keys do
        {k, "[REDACTED]"}
      else
        {k, sanitize_nested_value(v)}
      end
    end)
    |> Enum.into(%{})
  end

  defp sanitize_request_body(body), do: body

  defp sanitize_nested_value(value) when is_map(value) do
    sanitize_request_body(value)
  end

  defp sanitize_nested_value(value) when is_list(value) do
    Enum.map(value, &sanitize_nested_value/1)
  end

  defp sanitize_nested_value(value), do: value

  defp sanitize_headers(headers) when is_list(headers) do
    headers
    |> Enum.map(fn
      {key, _value} when key in ["authorization", "x-api-key", "anthropic-api-key"] ->
        {to_string(key), "[REDACTED]"}

      {key, value} ->
        {to_string(key), to_string(value)}

      other ->
        other
    end)
    |> Map.new()
  end

  defp sanitize_headers(headers) when is_map(headers) do
    headers
    |> Enum.map(fn
      {key, _value} when key in ["authorization", "x-api-key", "anthropic-api-key"] ->
        {to_string(key), "[REDACTED]"}

      {key, value} ->
        {to_string(key), to_string(value)}
    end)
    |> Map.new()
  end

  defp sanitize_headers(_headers), do: %{}

  defp sanitize_request_data(metadata) do
    %{
      metadata
      | request_body: sanitize_request_body(metadata.request_body),
        request_headers: sanitize_headers(metadata.request_headers)
    }
  end

  defp sanitize_response_data(metadata) do
    # Could implement response data sanitization if needed
    metadata
  end

  defp sanitize_test_context(metadata) do
    # Remove PID and other process-specific information
    %{metadata | test_pid: nil}
  end
end
