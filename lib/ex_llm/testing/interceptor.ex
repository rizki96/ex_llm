defmodule ExLLM.Testing.TestResponseInterceptor do
  @moduledoc """
  Automatically intercept and cache responses during tests.

  This module hooks into the HTTPClient request/response cycle to provide
  automatic cache key generation, rich metadata capture, and streaming
  response reassembly for the test caching system.
  """

  alias ExLLM.Infrastructure.Cache.Storage.TestCache
  alias ExLLM.Testing.TestCacheConfig
  alias ExLLM.Testing.TestCacheDetector
  alias ExLLM.Testing.TestCacheStrategy
  alias ExLLM.Testing.TestResponseMetadata

  @type intercept_result ::
          {:cached, any()}
          | {:proceed, map()}
          | {:error, term()}

  @doc """
  Intercept a request and check for cached response.
  """
  @spec intercept_request(String.t(), map(), list(), keyword()) :: intercept_result()
  def intercept_request(url, body, headers, opts) do
    request = %{
      url: url,
      body: body,
      headers: normalize_headers(headers),
      method: Keyword.get(opts, :method, "POST")
    }

    case TestCacheStrategy.execute(request, opts) do
      {:cached, response, _metadata} ->
        {:cached, response}

      {:proceed, request_metadata} ->
        {:proceed, request_metadata}
    end
  end

  @doc """
  Save response after successful request.
  """
  @spec save_response(map(), any(), map()) :: :ok | {:error, term()}
  def save_response(request_metadata, response_data, response_info \\ %{}) do
    case Map.get(request_metadata, :cache_key) do
      # No cache key, skip saving
      nil ->
        :ok

      cache_key ->
        metadata = build_response_metadata(request_metadata, response_data, response_info)
        TestCache.store(cache_key, response_data, metadata)
    end
  end

  @doc """
  Handle streaming response caching.
  """
  @spec handle_streaming_response(map(), pid()) :: {:ok, pid()} | {:error, term()}
  def handle_streaming_response(request_metadata, stream_pid) do
    case Map.get(request_metadata, :cache_key) do
      # No caching, return original stream
      nil ->
        {:ok, stream_pid}

      cache_key ->
        # Create a wrapper process that captures chunks and reassembles them
        wrapper_pid =
          spawn_link(fn ->
            stream_wrapper(stream_pid, cache_key, request_metadata, [])
          end)

        {:ok, wrapper_pid}
    end
  end

  @doc """
  Check if request should be intercepted for caching.
  """
  @spec should_intercept_request?() :: boolean()
  def should_intercept_request? do
    TestCacheDetector.should_cache_responses?()
  end

  @doc """
  Generate cache key from request parameters and test context.
  """
  @spec generate_cache_key(String.t(), map(), [any()]) :: String.t()
  def generate_cache_key(url, body, headers) do
    # Extract provider from URL
    provider = extract_provider_from_url(url)

    # Extract endpoint from URL
    endpoint = extract_endpoint_from_url(url)

    # Generate base cache key using test context
    base_key = TestCacheDetector.generate_cache_key(provider, endpoint)

    # Add request signature for uniqueness
    request_signature = generate_request_signature(body, headers)

    "#{base_key}/#{request_signature}"
  end

  @doc """
  Generate a unique signature for the request to differentiate similar requests.
  """
  @spec generate_request_signature(map(), [any()] | map()) :: String.t()
  def generate_request_signature(body, headers) do
    # Create a signature based on request content
    signature_data = %{
      body_hash: hash_request_body(body),
      content_type: get_header_value(headers, "content-type"),
      user_agent: get_header_value(headers, "user-agent")
    }

    signature_data
    |> Jason.encode!()
    |> then(fn data -> :crypto.hash(:sha256, data) end)
    |> Base.encode16(case: :lower)
    # Use first 12 characters
    |> String.slice(0..11)
  end

  @doc """
  Build comprehensive metadata for cached responses.
  """
  @spec build_response_metadata(map(), any(), map()) :: map()
  def build_response_metadata(request_metadata, response_data, response_info) do
    TestResponseMetadata.create_metadata(
      request_metadata,
      response_data,
      response_info
    )
  end

  @doc """
  Record cache hit for statistics.
  """
  @spec record_cache_hit(String.t(), map()) :: :ok
  def record_cache_hit(cache_key, _metadata) do
    # This could be enhanced to update cache statistics
    # For now, we'll just log the hit
    _config = TestCacheConfig.get_config()

    if Application.get_env(:ex_llm, :debug_test_cache, false) do
      IO.puts("Test cache HIT: #{cache_key}")
    end

    :ok
  end

  @doc """
  Record cache miss for statistics.
  """
  @spec record_cache_miss(String.t(), map()) :: :ok
  def record_cache_miss(cache_key, _metadata) do
    # This could be enhanced to update cache statistics
    # For now, we'll just log the miss
    if Application.get_env(:ex_llm, :debug_test_cache, false) do
      IO.puts("Test cache MISS: #{cache_key}")
    end

    :ok
  end

  # Private functions

  defp normalize_headers(headers) when is_list(headers) do
    headers
    |> Enum.map(fn
      {k, v} -> {to_string(k), to_string(v)}
      other -> other
    end)
    |> Map.new()
  end

  defp normalize_headers(headers), do: headers

  defp extract_provider_from_url(url) do
    cond do
      String.contains?(url, "api.anthropic.com") -> :anthropic
      String.contains?(url, "api.openai.com") -> :openai
      String.contains?(url, "generativelanguage.googleapis.com") -> :gemini
      String.contains?(url, "api.groq.com") -> :groq
      String.contains?(url, "openrouter.ai") -> :openrouter
      String.contains?(url, "localhost") or String.contains?(url, "127.0.0.1") -> :local
      true -> :unknown
    end
  end

  defp extract_endpoint_from_url(url) do
    uri = URI.parse(url)

    case uri.path do
      nil ->
        "unknown"

      path ->
        path
        |> String.trim_leading("/")
        |> String.replace("/", "_")
        |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
        |> String.replace(~r/_+/, "_")
        |> String.trim("_")
    end
  end

  defp hash_request_body(body) when is_map(body) do
    # Remove sensitive data before hashing
    sanitized_body = sanitize_request_body(body)

    sanitized_body
    |> Jason.encode!()
    |> then(fn data -> :crypto.hash(:sha256, data) end)
    |> Base.encode16(case: :lower)
    # Use first 16 characters
    |> String.slice(0..15)
  end

  defp hash_request_body(body) when is_binary(body) do
    body
    |> then(fn data -> :crypto.hash(:sha256, data) end)
    |> Base.encode16(case: :lower)
    |> String.slice(0..15)
  end

  defp hash_request_body(_body), do: "unknown"

  defp sanitize_request_body(body) when is_map(body) do
    # Remove or mask sensitive fields
    body
    |> Map.drop(["api_key", "authorization", "token"])
    |> Enum.map(fn {k, v} ->
      case String.downcase(to_string(k)) do
        key when key in ["password", "secret", "token", "key"] -> {k, "[REDACTED]"}
        _ -> {k, v}
      end
    end)
    |> Enum.into(%{})
  end

  defp get_header_value(headers, header_name) when is_list(headers) do
    headers
    |> Enum.find_value(fn
      {key, value} ->
        if String.downcase(to_string(key)) == String.downcase(header_name) do
          value
        end

      _ ->
        nil
    end)
  end

  defp get_header_value(headers, header_name) when is_map(headers) do
    headers
    |> Enum.find_value(fn {key, value} ->
      if String.downcase(to_string(key)) == String.downcase(header_name) do
        value
      end
    end)
  end

  defp get_header_value(_headers, _header_name), do: nil

  defp stream_wrapper(stream_pid, cache_key, request_metadata, accumulated_chunks) do
    receive do
      {:chunk, chunk} ->
        # Forward chunk to original consumer and accumulate for caching
        send(self(), {:chunk, chunk})
        stream_wrapper(stream_pid, cache_key, request_metadata, [chunk | accumulated_chunks])

      {:done, final_response} ->
        # Reassemble complete response from chunks
        complete_response =
          reassemble_streaming_response(
            Enum.reverse(accumulated_chunks),
            final_response
          )

        # Save complete response to cache
        response_metadata = %{
          streaming: true,
          chunk_count: length(accumulated_chunks),
          completed_at: DateTime.utc_now()
        }

        save_response(request_metadata, complete_response, response_metadata)

        # Forward completion signal
        send(self(), {:done, final_response})

      {:error, reason} ->
        # Save error response if configured to do so
        error_response = %{error: reason, type: "streaming_error"}

        response_metadata = %{
          streaming: true,
          error: true,
          chunk_count: length(accumulated_chunks),
          failed_at: DateTime.utc_now()
        }

        save_response(request_metadata, error_response, response_metadata)

        # Forward error
        send(self(), {:error, reason})

      other ->
        # Forward any other messages
        send(self(), other)
        stream_wrapper(stream_pid, cache_key, request_metadata, accumulated_chunks)
    end
  end

  defp reassemble_streaming_response(chunks, final_response) do
    # Combine all chunks into a complete response
    # This logic would depend on the specific streaming format used
    complete_content =
      chunks
      |> Enum.map(&extract_chunk_content/1)
      |> Enum.join()

    %{
      content: complete_content,
      chunks: chunks,
      final_response: final_response,
      reassembled_at: DateTime.utc_now()
    }
  end

  defp extract_chunk_content(chunk) when is_map(chunk) do
    Map.get(chunk, "content", Map.get(chunk, :content, ""))
  end

  defp extract_chunk_content(chunk) when is_binary(chunk), do: chunk
  defp extract_chunk_content(_chunk), do: ""
end
