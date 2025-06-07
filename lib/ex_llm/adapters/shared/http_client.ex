defmodule ExLLM.Adapters.Shared.HTTPClient do
  @moduledoc """
  Shared HTTP client utilities for ExLLM adapters.

  Provides common HTTP functionality including:
  - JSON API requests with proper headers
  - Server-Sent Events (SSE) streaming support
  - Standardized error handling
  - Response parsing utilities

  This module abstracts common HTTP patterns to reduce duplication
  across provider adapters.
  """

  alias ExLLM.Error
  alias ExLLM.Logger

  # 60 seconds
  @default_timeout 60_000
  # 5 minutes for streaming
  @stream_timeout 300_000

  @doc """
  Make a POST request with JSON body to an API endpoint.

  ## Options
  - `:timeout` - Request timeout in milliseconds (default: 60s)
  - `:recv_timeout` - Receive timeout for streaming (default: 5m)
  - `:stream` - Whether this is a streaming request

  ## Examples

      HTTPClient.post_json("https://api.example.com/v1/chat", 
        %{messages: messages},
        [{"Authorization", "Bearer sk-..."}],
        timeout: 30_000
      )
  """
  @spec post_json(String.t(), map(), list({String.t(), String.t()}), keyword()) ::
          {:ok, map()} | {:error, term()}
  def post_json(url, body, headers, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    method = Keyword.get(opts, :method, :post)
    provider = Keyword.get(opts, :provider, :unknown)

    headers = prepare_headers(headers)

    # Log request
    Logger.log_request(provider, url, body, headers)

    req_opts = [headers: headers, receive_timeout: timeout]

    start_time = System.monotonic_time(:millisecond)

    result =
      case method do
        :get -> Req.get(url, req_opts)
        :post -> Req.post(url, [json: body] ++ req_opts)
        :put -> Req.put(url, [json: body] ++ req_opts)
        :patch -> Req.patch(url, [json: body] ++ req_opts)
        :delete -> Req.delete(url, req_opts)
      end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        # Log successful response
        Logger.log_response(provider, %{status: status, body: response_body}, duration)
        # Req already decodes JSON
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        # Log error response
        Logger.error("API error response",
          provider: provider,
          status: status,
          body: response_body,
          duration_ms: duration
        )

        handle_error_response(status, response_body)

      {:error, reason} ->
        # Log connection error
        Logger.error("Connection error",
          provider: provider,
          error: reason,
          duration_ms: duration
        )

        Error.connection_error(reason)
    end
  end

  @doc """
  Make a streaming POST request using Req's into option.

  This is used by StreamingCoordinator for unified streaming.

  ## Examples

      HTTPClient.post_stream(url, body, [
        headers: headers,
        into: stream_collector_fn
      ])
  """
  @spec post_stream(String.t(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def post_stream(url, body, opts \\ []) do
    headers = Keyword.get(opts, :headers, []) |> prepare_headers()
    provider = Keyword.get(opts, :provider, :unknown)

    # Log streaming request
    Logger.log_stream_event(provider, :request_start, %{
      url: url,
      body_preview: inspect(body, limit: 100)
    })

    req_opts = [
      json: body,
      headers: headers,
      receive_timeout: Keyword.get(opts, :receive_timeout, @stream_timeout)
    ]

    # Add the into option if provided
    req_opts =
      case Keyword.get(opts, :into) do
        nil -> req_opts
        collector -> Keyword.put(req_opts, :into, collector)
      end

    case Req.post(url, req_opts) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        Logger.log_stream_event(provider, :response_ok, %{status: status})
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        Logger.log_stream_event(provider, :response_error, %{status: status, body: body})
        handle_error_response(status, body)

      {:error, reason} ->
        Logger.log_stream_event(provider, :connection_error, %{reason: inspect(reason)})
        {:error, Error.connection_error(reason)}
    end
  end

  @doc """
  Make a streaming POST request that returns Server-Sent Events.

  The callback function will be called for each chunk received.

  ## Examples

      HTTPClient.stream_request(url, body, headers, fn chunk ->
        # Process each SSE chunk
        IO.puts("Received: " <> chunk)
      end)
  """
  @spec stream_request(String.t(), map(), list({String.t(), String.t()}), function(), keyword()) ::
          {:ok, any()} | {:error, term()}
  def stream_request(url, body, headers, callback, opts \\ []) do
    timeout = Keyword.get(opts, :recv_timeout, @stream_timeout)
    parent = self()

    headers = prepare_headers(headers) ++ [{"Accept", "text/event-stream"}]

    # Start async task for streaming
    Task.start(fn ->
      case Req.post(url, json: body, headers: headers, receive_timeout: timeout, into: :self) do
        {:ok, response} ->
          if response.status in 200..299 do
            handle_req_stream_response(response, parent, callback, "", opts)
          else
            if error_handler = Keyword.get(opts, :on_error) do
              error_handler.(response.status, Jason.encode!(response.body))
            else
              send(parent, {:stream_error, Error.api_error(response.status, response.body)})
            end
          end

        {:error, reason} ->
          send(parent, {:stream_error, Error.connection_error(reason)})
      end
    end)

    # Return immediately
    {:ok, :streaming}
  end

  @doc """
  Parse Server-Sent Events from a data buffer.

  Returns parsed events and remaining buffer.

  ## Examples

      {events, new_buffer} = HTTPClient.parse_sse_chunks("data: {\"text\":\"Hi\"}\\n\\n", "")
  """
  @spec parse_sse_chunks(binary(), binary()) :: {list(map()), binary()}
  def parse_sse_chunks(data, buffer) do
    lines = String.split(buffer <> data, "\n")
    {complete_lines, [last_line]} = Enum.split(lines, -1)

    events =
      complete_lines
      |> Enum.chunk_by(&(&1 == ""))
      |> Enum.reject(&(&1 == [""]))
      |> Enum.map(&parse_sse_event/1)
      |> Enum.reject(&is_nil/1)

    {events, last_line}
  end

  @doc """
  Build a standardized User-Agent header for ExLLM.
  """
  @spec user_agent() :: {String.t(), String.t()}
  def user_agent do
    version = Application.spec(:ex_llm, :vsn) |> to_string()
    {"User-Agent", "ExLLM/#{version} (Elixir)"}
  end

  @doc """
  Prepare headers with common defaults.

  Adds Content-Type and User-Agent if not present.
  """
  @spec prepare_headers(list({String.t(), String.t()})) :: list({String.t(), String.t()})
  def prepare_headers(headers) do
    default_headers = [
      {"Content-Type", "application/json"},
      user_agent()
    ]

    # Merge with defaults, preferring provided headers
    Enum.reduce(default_headers, headers, fn {key, value}, acc ->
      if List.keyfind(acc, key, 0) do
        acc
      else
        [{key, value} | acc]
      end
    end)
  end

  @doc """
  Handle API error responses consistently.

  Attempts to parse error details from JSON responses.
  """
  @spec handle_api_error(integer(), String.t() | map()) :: {:error, term()}
  def handle_api_error(status, body) do
    # Handle both string and map bodies (Req might decode JSON automatically)
    parsed_body =
      case body do
        body when is_binary(body) ->
          case Jason.decode(body) do
            {:ok, decoded} -> decoded
            {:error, _} -> %{"error" => body}
          end

        body when is_map(body) ->
          body
      end

    case parsed_body do
      %{"error" => error} when is_map(error) ->
        handle_structured_error(status, error)

      %{"error" => message} when is_binary(message) ->
        categorize_error(status, message)

      %{"message" => message} ->
        categorize_error(status, message)

      _ ->
        Error.api_error(status, body)
    end
  end

  # Private functions

  defp handle_error_response(status, body) do
    handle_api_error(status, body)
  end

  defp handle_req_stream_response(response, parent, callback, buffer, opts) do
    %Req.Response.Async{ref: ref} = response.body
    provider = Keyword.get(opts, :provider, :unknown)

    receive do
      {^ref, {:data, data}} ->
        {events, new_buffer} = parse_sse_chunks(data, buffer)

        # Log chunk received if streaming logging is enabled
        if length(events) > 0 do
          Logger.log_stream_event(provider, :chunk_received, %{
            event_count: length(events),
            buffer_size: byte_size(new_buffer)
          })
        end

        Enum.each(events, fn event ->
          if event.data != "[DONE]" do
            callback.(event.data)
          end
        end)

        handle_req_stream_response(response, parent, callback, new_buffer, opts)

      {^ref, :done} ->
        Logger.log_stream_event(provider, :stream_complete, %{})
        send(parent, :stream_done)

      {^ref, {:error, reason}} ->
        Logger.log_stream_event(provider, :stream_error, %{reason: inspect(reason)})
        send(parent, {:stream_error, Error.connection_error(reason)})
    after
      Keyword.get(opts, :recv_timeout, @stream_timeout) ->
        Logger.log_stream_event(provider, :stream_timeout, %{timeout_ms: @stream_timeout})
        send(parent, {:stream_error, {:error, :timeout}})
    end
  end

  defp parse_sse_event(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          # SSE event keys are limited to: event, data, id, retry
          atom_key =
            case key do
              "event" -> :event
              "data" -> :data
              "id" -> :id
              "retry" -> :retry
              # Fallback for unknown keys
              _ -> String.to_atom(key)
            end

          Map.put(acc, atom_key, String.trim_leading(value))

        _ ->
          acc
      end
    end)
    |> case do
      %{data: _} = event -> event
      _ -> nil
    end
  end

  defp handle_structured_error(status, %{"type" => type} = error) do
    message = error["message"] || "Unknown error"

    case type do
      "authentication_error" -> Error.authentication_error(message)
      "rate_limit_error" -> Error.rate_limit_error(message)
      "invalid_request_error" -> Error.validation_error(:request, message)
      _ -> Error.api_error(status, error)
    end
  end

  defp handle_structured_error(status, error) do
    Error.api_error(status, error)
  end

  defp categorize_error(401, message), do: Error.authentication_error(message)
  defp categorize_error(429, message), do: Error.rate_limit_error(message)
  defp categorize_error(503, message), do: Error.service_unavailable(message)
  defp categorize_error(status, message), do: Error.api_error(status, message)
end
