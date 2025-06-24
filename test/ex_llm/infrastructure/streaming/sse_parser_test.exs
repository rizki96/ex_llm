defmodule ExLLM.Infrastructure.Streaming.SSEParserTest do
  use ExUnit.Case, async: true

  alias ExLLM.Infrastructure.Streaming.SSEParser

  describe "parse_chunk/2" do
    test "parses a single, simple event" do
      chunk = "data: hello\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_chunk(parser, chunk)
      assert events == [%{data: "hello"}]
    end

    test "parses a complete event with all fields" do
      chunk = "event: message\nid: 123\nretry: 5000\ndata: some data\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_chunk(parser, chunk)

      assert events == [
               %{
                 event: "message",
                 id: "123",
                 retry: 5000,
                 data: "some data"
               }
             ]
    end

    test "handles multi-line data" do
      chunk = "data: line 1\ndata: line 2\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_chunk(parser, chunk)
      assert events == [%{data: "line 1\nline 2"}]
    end

    test "handles multiple events in one chunk" do
      chunk = "data: event 1\n\n" <> "id: 1\ndata: event 2\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_chunk(parser, chunk)

      assert events == [
               %{data: "event 1"},
               %{id: "1", data: "event 2"}
             ]
    end

    test "handles partial chunks and buffering" do
      parser = SSEParser.new()

      # First chunk, incomplete
      chunk1 = "data: part 1"
      {events1, parser} = SSEParser.parse_chunk(parser, chunk1)
      assert events1 == []

      # Second chunk, completes the event
      chunk2 = " part 2\n\n"
      {events2, _parser} = SSEParser.parse_chunk(parser, chunk2)
      assert events2 == [%{data: "part 1 part 2"}]
    end

    test "handles partial chunks across multiple lines" do
      parser = SSEParser.new()

      {events, parser} = SSEParser.parse_chunk(parser, "data: line 1\nda")
      assert events == []

      {events, _parser} = SSEParser.parse_chunk(parser, "ta: line 2\n\n")
      assert events == [%{data: "line 1\nline 2"}]
    end

    test "ignores comment lines" do
      chunk = ":this is a comment\ndata: hello\n: another comment\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_chunk(parser, chunk)
      assert events == [%{data: "hello"}]
    end

    test "handles empty lines between events" do
      chunk = "data: event 1\n\n\ndata: event 2\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_chunk(parser, chunk)
      assert events == [%{data: "event 1"}, %{data: "event 2"}]
    end

    test "handles malformed lines gracefully" do
      chunk = "this is not valid\ndata: good data\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_chunk(parser, chunk)
      assert events == [%{data: "good data"}]
    end

    test "handles field with no value" do
      chunk = "data:\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_chunk(parser, chunk)
      assert events == [%{data: ""}]
    end

    test "strips one leading space from field value" do
      # A single leading space is stripped
      chunk = "data: value\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_chunk(parser, chunk)
      assert events == [%{data: "value"}]

      # Multiple leading spaces are also stripped
      chunk = "data:  value\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_chunk(parser, chunk)
      assert events == [%{data: "value"}]
    end
  end

  describe "flush/1" do
    test "flushes a pending event after it has been processed from the buffer" do
      parser = SSEParser.new()

      # An event must be terminated by a newline to be processed from the buffer
      # into a pending event. Then flush can dispatch it.
      {[], parser} = SSEParser.parse_chunk(parser, "data: final event\n")

      {events, _parser} = SSEParser.flush(parser)
      assert events == [%{data: "final event"}]
    end

    test "flushes a pending event even if buffer is empty" do
      parser = SSEParser.new()
      # Process a line, but not the final empty line
      {[], parser} = SSEParser.parse_chunk(parser, "data: pending\n")
      # The event is in `current_event`, not the buffer
      assert parser.buffer == ""
      {events, _parser} = SSEParser.flush(parser)
      assert events == [%{data: "pending"}]
    end

    test "returns empty list if nothing to flush" do
      parser = SSEParser.new()
      {events, _parser} = SSEParser.flush(parser)
      assert events == []
    end
  end

  describe "parse_data_events/2" do
    test "parses data and [DONE] marker" do
      chunk = "data: hello\n\n" <> "data: world\n\n" <> "data: [DONE]\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_data_events(parser, chunk)
      assert events == ["hello", "world", :done]
    end

    test "ignores events without data" do
      chunk = "id: 123\n\n" <> "data: hello\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_data_events(parser, chunk)
      assert events == ["hello"]
    end
  end

  describe "parse_json_events/2" do
    test "parses JSON data and [DONE] marker" do
      chunk =
        ~s(data: {"foo": "bar"}\n\n) <>
          ~s(data: {"baz": "qux"}\n\n) <> ~s(data: [DONE]\n\n)

      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_json_events(parser, chunk)

      assert events == [
               %{"foo" => "bar"},
               %{"baz" => "qux"},
               :done
             ]
    end

    test "handles multi-line JSON data" do
      chunk = ~s(data: {"foo":\ndata: "bar"}\n\n)
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_json_events(parser, chunk)
      assert events == [%{"foo" => "bar"}]
    end

    test "returns nil for invalid JSON" do
      chunk = "data: {invalid json}\n\n"
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_json_events(parser, chunk)
      assert events == []
    end

    test "ignores events without data" do
      chunk = "id: 123\n\n" <> ~s(data: {"foo": "bar"}\n\n)
      parser = SSEParser.new()
      {events, _parser} = SSEParser.parse_json_events(parser, chunk)
      assert events == [%{"foo" => "bar"}]
    end
  end

  describe "stream transformers" do
    test "stream_transformer works correctly" do
      chunks = ["data: event 1\n\n", "id: 1\ndata:", " event 2\n\n"]

      result =
        chunks
        |> Stream.transform(SSEParser.new(), SSEParser.stream_transformer())
        |> Enum.to_list()

      assert result == [
               %{data: "event 1"},
               %{id: "1", data: "event 2"}
             ]
    end

    test "data_stream_transformer works correctly" do
      chunks = ["data: hello\n\n", "data: world\n", "\ndata: [DONE]\n\n"]

      result =
        chunks
        |> Stream.transform(SSEParser.new(), SSEParser.data_stream_transformer())
        |> Enum.to_list()

      assert result == ["hello", "world", :done]
    end

    test "json_stream_transformer works correctly" do
      chunks = [
        ~s(data: {"foo": "bar"}\n\n),
        ~s(data: {"baz": "qux"}\n\n),
        ~s(data: [DONE]\n\n)
      ]

      result =
        chunks
        |> Stream.transform(SSEParser.new(), SSEParser.json_stream_transformer())
        |> Enum.to_list()

      assert result == [
               %{"foo" => "bar"},
               %{"baz" => "qux"},
               :done
             ]
    end

    test "json_stream_transformer handles partial JSON" do
      chunks = [
        ~s(data: {"foo":),
        ~s( "bar"}\n\n)
      ]

      result =
        chunks
        |> Stream.transform(SSEParser.new(), SSEParser.json_stream_transformer())
        |> Enum.to_list()

      assert result == [%{"foo" => "bar"}]
    end
  end
end
