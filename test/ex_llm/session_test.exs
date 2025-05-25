defmodule ExLLM.SessionTest do
  use ExUnit.Case
  doctest ExLLM.Session

  alias ExLLM.Session

  test "creates a new session with default values" do
    session = Session.new()

    assert is_binary(session.id)
    assert session.llm_backend == nil
    assert session.messages == []
    assert session.context == %{}
    assert session.token_usage == %{input_tokens: 0, output_tokens: 0}
    assert %DateTime{} = session.created_at
    assert %DateTime{} = session.updated_at
  end

  test "creates a new session with backend and name" do
    session = Session.new("anthropic", name: "Test Chat")

    assert session.llm_backend == "anthropic"
    assert session.name == "Test Chat"
  end

  test "adds messages to session" do
    session = Session.new()
    session = Session.add_message(session, "user", "Hello!")
    session = Session.add_message(session, "assistant", "Hi there!")

    messages = Session.get_messages(session)
    assert length(messages) == 2
    assert Enum.at(messages, 0).role == "user"
    assert Enum.at(messages, 0).content == "Hello!"
    assert Enum.at(messages, 1).role == "assistant"
    assert Enum.at(messages, 1).content == "Hi there!"
  end

  test "limits messages when requested" do
    session = Session.new()
    session = Session.add_message(session, "user", "Message 1")
    session = Session.add_message(session, "assistant", "Message 2")
    session = Session.add_message(session, "user", "Message 3")

    limited = Session.get_messages(session, 2)
    assert length(limited) == 2
    assert Enum.at(limited, 0).content == "Message 2"
    assert Enum.at(limited, 1).content == "Message 3"
  end

  test "updates token usage" do
    session = Session.new()
    session = Session.update_token_usage(session, %{input_tokens: 10, output_tokens: 15})

    assert session.token_usage.input_tokens == 10
    assert session.token_usage.output_tokens == 15
    assert Session.total_tokens(session) == 25
  end

  test "accumulates token usage" do
    session = Session.new()
    session = Session.update_token_usage(session, %{input_tokens: 10, output_tokens: 15})
    session = Session.update_token_usage(session, %{input_tokens: 5, output_tokens: 10})

    assert session.token_usage.input_tokens == 15
    assert session.token_usage.output_tokens == 25
    assert Session.total_tokens(session) == 40
  end

  test "sets and updates context" do
    session = Session.new()
    session = Session.set_context(session, %{temperature: 0.7, max_tokens: 1000})

    assert session.context.temperature == 0.7
    assert session.context.max_tokens == 1000
  end

  test "clears messages" do
    session = Session.new()
    session = Session.add_message(session, "user", "Hello!")
    session = Session.clear_messages(session)

    assert Session.get_messages(session) == []
  end

  test "sets session name" do
    session = Session.new()
    session = Session.set_name(session, "Important Chat")

    assert session.name == "Important Chat"
  end

  test "serializes and deserializes session to/from JSON" do
    original_session = Session.new("anthropic", name: "Test Session")
    original_session = Session.add_message(original_session, "user", "Hello!")

    original_session =
      Session.update_token_usage(original_session, %{input_tokens: 10, output_tokens: 15})

    {:ok, json} = Session.to_json(original_session)
    {:ok, restored_session} = Session.from_json(json)

    assert restored_session.id == original_session.id
    assert restored_session.llm_backend == original_session.llm_backend
    assert restored_session.name == original_session.name
    assert length(restored_session.messages) == 1
    assert restored_session.token_usage == original_session.token_usage
  end

  test "handles invalid JSON gracefully" do
    assert {:error, _} = Session.from_json("invalid json")
  end
end
