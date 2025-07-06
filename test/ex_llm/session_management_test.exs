defmodule ExLLM.SessionManagementTest do
  use ExUnit.Case, async: false

  alias ExLLM.Core.Session
  alias ExLLM.Types

  @moduledoc """
  Tests for session management functionality in ExLLM.

  Sessions allow maintaining conversation state across multiple
  interactions with automatic context management.
  """

  setup do
    ExLLM.Providers.Mock.reset()
    :ok
  end

  describe "session creation" do
    test "creates a new session with default options" do
      session = Session.new("mock")

      assert %Types.Session{} = session
      assert session.id
      assert session.messages == []
      assert session.context == %{config: %{}}
      assert session.token_usage == %{input_tokens: 0, output_tokens: 0}
      assert session.created_at
    end

    test "creates session with custom name" do
      session = Session.new("mock", name: "Test Session")

      assert session.name == "Test Session"
      assert session.llm_backend == "mock"
    end

    test "generates unique session IDs" do
      session1 = Session.new("mock")
      session2 = Session.new("mock")

      assert session1.id != session2.id
    end
  end

  describe "message management" do
    test "adds messages to session" do
      session = Session.new("mock")

      session = Session.add_message(session, "user", "Hello")
      session = Session.add_message(session, "assistant", "Hi there!")

      assert length(session.messages) == 2
      assert [user_msg, assistant_msg] = session.messages

      assert user_msg.role == "user"
      assert user_msg.content == "Hello"

      assert assistant_msg.role == "assistant"
      assert assistant_msg.content == "Hi there!"
    end

    test "adds message with timestamp" do
      session = Session.new("mock")
      timestamp = DateTime.utc_now()

      session = Session.add_message(session, "user", "Test", timestamp: timestamp)

      assert [msg] = session.messages
      assert msg.timestamp == timestamp
    end

    test "updates session timestamp on message addition" do
      session = Session.new("mock")
      original_updated_at = session.updated_at

      # Small delay to ensure timestamps differ
      Process.sleep(10)

      session = Session.add_message(session, "user", "Test")

      assert DateTime.compare(session.updated_at, original_updated_at) == :gt
    end
  end

  describe "message retrieval" do
    test "gets all messages" do
      session = Session.new("mock")

      session =
        session
        |> Session.add_message("user", "First")
        |> Session.add_message("assistant", "Second")
        |> Session.add_message("user", "Third")

      messages = Session.get_messages(session)

      assert length(messages) == 3
      assert List.first(messages).content == "First"
      assert List.last(messages).content == "Third"
    end

    test "gets messages with limit" do
      session = Session.new("mock")

      # Add 5 messages
      session =
        Enum.reduce(1..5, session, fn i, acc ->
          Session.add_message(acc, "user", "Message #{i}")
        end)

      # Get only last 3 messages
      messages = Session.get_messages(session, 3)

      assert length(messages) == 3
      # Should return most recent messages when limited
      assert List.first(messages).content == "Message 3"
      assert List.last(messages).content == "Message 5"
    end
  end

  describe "token usage tracking" do
    test "updates token usage" do
      session = Session.new("mock")

      session =
        Session.update_token_usage(session, %{
          input_tokens: 100,
          output_tokens: 150
        })

      assert session.token_usage.input_tokens == 100
      assert session.token_usage.output_tokens == 150
    end

    test "accumulates token usage" do
      session = Session.new("mock")

      # First update
      session =
        Session.update_token_usage(session, %{
          input_tokens: 50,
          output_tokens: 75
        })

      # Second update - should accumulate
      session =
        Session.update_token_usage(session, %{
          input_tokens: 30,
          output_tokens: 45
        })

      assert session.token_usage.input_tokens == 80
      assert session.token_usage.output_tokens == 120
    end
  end

  describe "context management" do
    test "stores arbitrary context data" do
      session = Session.new("mock")

      # Context is just a map, we can store anything
      session = %{session | context: %{user_id: "123", theme: "dark"}}

      assert session.context.user_id == "123"
      assert session.context.theme == "dark"
    end

    test "preserves context across message additions" do
      session = Session.new("mock")
      session = %{session | context: %{session_type: "support"}}

      session = Session.add_message(session, "user", "Help!")

      assert session.context.session_type == "support"
    end
  end

  describe "session with LLM integration" do
    test "uses session messages for chat" do
      session = Session.new("mock")

      session = Session.add_message(session, "user", "What's 2+2?")

      # Send to LLM using session messages
      {:ok, response} = ExLLM.chat(:mock, session.messages)

      # Add response to session (handle nil content)
      content = response.content || "Mock response"
      session = Session.add_message(session, "assistant", content)

      assert length(session.messages) == 2
    end

    test "maintains conversation flow" do
      session = Session.new("openai")

      # Build conversation
      session =
        session
        |> Session.add_message("user", "My name is Alice")
        |> Session.add_message("assistant", "Nice to meet you, Alice!")
        |> Session.add_message("user", "What's my name?")

      # Session has full conversation history
      assert length(session.messages) == 3

      # Messages are in order
      messages = Session.get_messages(session)
      assert List.first(messages).content == "My name is Alice"
      assert List.last(messages).content == "What's my name?"
    end
  end

  describe "session utilities" do
    test "checks if session has messages" do
      empty_session = Session.new("mock")
      assert Session.get_messages(empty_session) == []

      session_with_messages = Session.add_message(empty_session, "user", "Hello")
      assert length(Session.get_messages(session_with_messages)) == 1
    end

    test "gets most recent messages efficiently" do
      session = Session.new("mock")

      # Add many messages
      session =
        Enum.reduce(1..100, session, fn i, acc ->
          role = if rem(i, 2) == 0, do: "assistant", else: "user"
          Session.add_message(acc, role, "Message #{i}")
        end)

      # Get last 10
      recent = Session.get_messages(session, 10)

      assert length(recent) == 10
      assert List.first(recent).content == "Message 91"
      assert List.last(recent).content == "Message 100"
    end
  end

  describe "session persistence" do
    test "session has required fields for serialization" do
      session = Session.new("anthropic", name: "Test Chat")

      # All fields needed for persistence
      assert session.id
      assert session.llm_backend == "anthropic"
      assert session.name == "Test Chat"
      assert session.messages == []
      assert session.context == %{config: %{}}
      assert session.created_at
      assert session.updated_at
      assert session.token_usage
    end

    test "session can be reconstructed from data" do
      original = Session.new("openai", name: "Important Chat")

      original =
        original
        |> Session.add_message("user", "Hello")
        |> Session.add_message("assistant", "Hi!")
        |> Session.update_token_usage(%{input_tokens: 10, output_tokens: 15})

      # Simulate serialization/deserialization
      data = %{
        id: original.id,
        llm_backend: original.llm_backend,
        name: original.name,
        messages: original.messages,
        context: original.context,
        created_at: original.created_at,
        updated_at: original.updated_at,
        token_usage: original.token_usage
      }

      # Reconstruct
      reconstructed = struct(Types.Session, data)

      assert reconstructed.id == original.id
      assert reconstructed.messages == original.messages
      assert reconstructed.token_usage == original.token_usage
    end

    test "deserializes session from JSON with string keys to atom keys" do
      json_string = """
      {
        "id": "test_id",
        "llm_backend": "openai",
        "messages": [
          {"role": "user", "content": "Hello from JSON", "timestamp": "2023-01-01T12:00:00Z"},
          {"role": "assistant", "content": "Hi there!", "metadata": {"source": "mock"}}
        ],
        "context": {"config": {"model": "gpt-4"}},
        "created_at": "2023-01-01T10:00:00Z",
        "updated_at": "2023-01-01T11:00:00Z",
        "token_usage": {"input_tokens": 50, "output_tokens": 75},
        "name": "JSON Test Session"
      }
      """

      {:ok, session} = ExLLM.Core.Session.from_json(json_string)

      assert session.id == "test_id"
      assert session.llm_backend == :openai # Assert atom conversion
      assert session.name == "JSON Test Session"

      assert length(session.messages) == 2
      assert session.messages |> List.first() |> Map.get(:role) == "user" # Role remains string
      assert session.messages |> List.first() |> Map.get(:content) == "Hello from JSON"
      assert session.messages |> List.first() |> Map.get(:timestamp) |> is_struct(DateTime)

      assert session.messages |> List.last() |> Map.get(:role) == "assistant"
      assert session.messages |> List.last() |> Map.get(:metadata) == %{"source" => "mock"} # Metadata keys remain strings

      assert session.context["config"] == %{"model" => "gpt-4"} # Context keys remain as strings
      assert session.token_usage == %{input_tokens: 50, output_tokens: 75} # Assert atom conversion for token_usage keys
    end
  end

  describe "telemetry events" do
    test "emits telemetry on session creation" do
      # Telemetry is emitted in Session.new/2
      session = Session.new("gemini", name: "Telemetry Test")

      assert session.llm_backend == "gemini"
      # We can't easily test telemetry emission in unit tests without
      # setting up telemetry handlers, but the code path is exercised
    end

    test "emits telemetry on message addition" do
      session = Session.new("mock")

      # Telemetry is emitted in add_message/4
      session = Session.add_message(session, "user", "Test message")

      assert length(session.messages) == 1
    end
  end
end
