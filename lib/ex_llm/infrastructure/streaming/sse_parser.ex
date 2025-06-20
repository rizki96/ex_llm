defmodule ExLLM.Infrastructure.Streaming.SSEParser do
  @moduledoc """
  Server-Sent Events (SSE) parser for streaming responses.
  
  This module handles parsing of SSE formatted data streams from various LLM providers.
  SSE is a standard for server-to-client streaming of text data using HTTP.
  
  ## SSE Format
  
  SSE messages follow this format:
  ```
  data: {"content": "Hello"}
  
  data: {"content": " world"}
  
  data: [DONE]
  
  ```
  
  Each field starts with a field name, followed by a colon, optionally followed by a space,
  followed by the field value, and terminated by a newline.
  
  ## Features
  
  - Handles partial chunks and buffering
  - Supports multi-line data fields
  - Ignores comment lines (starting with :)
  - Handles keep-alive messages
  - Provider-specific parsing for different formats
  
  ## Usage
  
      parser = SSEParser.new()
      
      # Process chunks as they arrive
      {events, parser} = SSEParser.parse_chunk(parser, "data: {\"content\": \"Hello\"}\n\n")
      
      # Get any remaining buffered data
      {final_events, _parser} = SSEParser.flush(parser)
  """
  
  require Logger
  
  @type t :: %__MODULE__{
    buffer: binary(),
    current_event: map(),
    provider: atom() | nil
  }
  
  @type sse_event :: %{
    event: String.t() | nil,
    data: String.t() | nil,
    id: String.t() | nil,
    retry: integer() | nil
  }
  
  defstruct buffer: "", current_event: %{}, provider: nil
  
  @doc """
  Creates a new SSE parser instance.
  
  ## Options
    * `:provider` - The LLM provider (for provider-specific parsing)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      provider: Keyword.get(opts, :provider)
    }
  end
  
  @doc """
  Parses a chunk of SSE data.
  
  Returns a tuple of parsed events and the updated parser state.
  Events are returned as a list of maps with SSE fields.
  """
  @spec parse_chunk(t(), binary()) :: {[sse_event()], t()}
  def parse_chunk(%__MODULE__{} = parser, chunk) when is_binary(chunk) do
    # Add chunk to buffer
    buffer = parser.buffer <> chunk
    
    # Process complete lines
    {events, remaining_buffer, current_event} = process_buffer(buffer, parser.current_event, [])
    
    # Update parser state
    updated_parser = %{parser | buffer: remaining_buffer, current_event: current_event}
    
    {events, updated_parser}
  end
  
  @doc """
  Flushes any remaining buffered data.
  
  Call this when the stream ends to ensure all data is processed.
  """
  @spec flush(t()) :: {[sse_event()], t()}
  def flush(%__MODULE__{} = parser) do
    # Process any remaining buffer as a complete line
    if parser.buffer != "" do
      # Add a newline to ensure the last line is processed
      parse_chunk(parser, "\n")
    else
      # Check if there's a pending event
      if map_size(parser.current_event) > 0 do
        {[parser.current_event], %{parser | current_event: %{}}}
      else
        {[], parser}
      end
    end
  end
  
  @doc """
  Parses SSE events and extracts the JSON data payload.
  
  This is a convenience function that parses SSE events and decodes
  the JSON data field for providers that send JSON in SSE format.
  """
  @spec parse_json_events(t(), binary()) :: {[map()], t()}
  def parse_json_events(%__MODULE__{} = parser, chunk) do
    {events, updated_parser} = parse_chunk(parser, chunk)
    
    json_events = 
      events
      |> Enum.map(&extract_json_data/1)
      |> Enum.reject(&is_nil/1)
    
    {json_events, updated_parser}
  end
  
  # Private functions
  
  defp process_buffer(buffer, current_event, events) do
    case String.split(buffer, "\n", parts: 2) do
      [line, rest] ->
        # Process this line
        {updated_event, maybe_complete_event} = process_line(line, current_event)
        
        # Add complete event if we have one
        events = 
          case maybe_complete_event do
            nil -> events
            event -> events ++ [event]
          end
        
        # Continue processing the rest
        process_buffer(rest, updated_event, events)
        
      [remaining] ->
        # No more complete lines
        {events, remaining, current_event}
    end
  end
  
  defp process_line("", current_event) do
    # Empty line signals end of event
    if map_size(current_event) > 0 do
      {%{}, current_event}
    else
      {current_event, nil}
    end
  end
  
  defp process_line(":" <> _comment, current_event) do
    # Comment line, ignore
    {current_event, nil}
  end
  
  defp process_line(line, current_event) do
    case parse_field(line) do
      {field, value} ->
        # Add field to current event
        updated_event = add_field_to_event(current_event, field, value)
        {updated_event, nil}
        
      nil ->
        # Invalid line format, ignore
        Logger.debug("SSEParser: Ignoring invalid line: #{inspect(line)}")
        {current_event, nil}
    end
  end
  
  defp parse_field(line) do
    case String.split(line, ":", parts: 2) do
      [field, value] ->
        # Remove optional leading space from value
        value = String.trim_leading(value, " ")
        {field, value}
        
      _ ->
        nil
    end
  end
  
  defp add_field_to_event(event, field, value) do
    case field do
      "event" ->
        Map.put(event, :event, value)
        
      "data" ->
        # Data fields can be concatenated
        current_data = Map.get(event, :data, "")
        separator = if current_data == "", do: "", else: "\n"
        Map.put(event, :data, current_data <> separator <> value)
        
      "id" ->
        Map.put(event, :id, value)
        
      "retry" ->
        case Integer.parse(value) do
          {retry, ""} -> Map.put(event, :retry, retry)
          _ -> event
        end
        
      _ ->
        # Unknown field, ignore
        event
    end
  end
  
  defp extract_json_data(event) do
    case Map.get(event, :data) do
      nil ->
        nil
        
      "[DONE]" ->
        %{done: true}
        
      data ->
        case Jason.decode(data) do
          {:ok, json} ->
            json
            
          {:error, reason} ->
            Logger.debug("SSEParser: Failed to decode JSON: #{inspect(reason)}, data: #{inspect(data)}")
            nil
        end
    end
  end
  
  @doc """
  Creates a streaming transformer that parses SSE chunks into events.
  
  This can be used with Stream.transform to convert a stream of raw
  chunks into a stream of parsed SSE events.
  
  ## Example
  
      raw_stream
      |> Stream.transform(
        SSEParser.new(),
        SSEParser.stream_transformer()
      )
  """
  @spec stream_transformer() :: (binary(), t() -> {[sse_event()], t()})
  def stream_transformer() do
    fn
      chunk, parser ->
        parse_chunk(parser, chunk)
    end
  end
  
  @doc """
  Creates a streaming transformer that parses SSE chunks and extracts JSON data.
  
  This combines SSE parsing with JSON decoding for providers that send
  JSON data in SSE format.
  """
  @spec json_stream_transformer() :: (binary(), t() -> {[map()], t()})
  def json_stream_transformer() do
    fn
      chunk, parser ->
        parse_json_events(parser, chunk)
    end
  end
end
