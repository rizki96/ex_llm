defmodule ExLLM.SessionIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  describe "session integration with ExLLM" do
    test "creates session through ExLLM interface" do
      session = ExLLM.new_session(:anthropic, name: "Test Session")

      assert session.llm_backend == :anthropic
      assert session.name == "Test Session"
      assert session.messages == []
    end

    test "adds and retrieves messages through ExLLM interface" do
      session = ExLLM.new_session(:openai)
      session = ExLLM.add_session_message(session, "user", "Hello")
      session = ExLLM.add_session_message(session, "assistant", "Hi there!")

      messages = ExLLM.get_session_messages(session)
      assert length(messages) == 2

      last_2 = ExLLM.get_session_messages(session, 2)
      assert length(last_2) == 2
    end

    test "tracks token usage through ExLLM interface" do
      session = ExLLM.new_session(:anthropic)

      # Simulate token usage by performing an actual chat (using mock for consistency)
      # This tests the token tracking through the public API
      case ExLLM.chat_with_session(session, "Hello") do
        {:ok, {_response, updated_session}} ->
          # Token usage should be tracked through the chat operation
          assert ExLLM.session_token_usage(updated_session) > 0

        {:error, :not_configured} ->
          # Skip test if provider not configured
          :ok
      end
    end

    test "clears session through ExLLM interface" do
      session = ExLLM.new_session(:anthropic)
      session = ExLLM.add_session_message(session, "user", "Message 1")
      session = ExLLM.add_session_message(session, "assistant", "Response 1")

      session = ExLLM.clear_session(session)
      assert ExLLM.get_session_messages(session) == []
      # Metadata preserved
      assert session.llm_backend == :anthropic
    end

    test "saves and loads session through ExLLM interface" do
      session = ExLLM.new_session(:openai, name: "Persistent Session")
      session = ExLLM.add_session_message(session, "user", "Test message")

      {:ok, json} = ExLLM.save_session(session)
      {:ok, loaded_session} = ExLLM.load_session(json)

      assert loaded_session.id == session.id
      assert loaded_session.name == "Persistent Session"
      assert length(loaded_session.messages) == 1
    end
  end

  describe "chat_with_session" do
    @describetag :integration
    @moduletag :requires_api_key

    test "performs chat with session tracking" do
      # Use anthropic as it's commonly configured in tests
      session = ExLLM.new_session(:anthropic)

      case ExLLM.chat_with_session(session, "Say hello") do
        {:ok, {response, updated_session}} ->
          # Check response (verify we got content, don't test specific answer)
          assert String.length(response.content) > 0

          # Check session was updated
          messages = ExLLM.get_session_messages(updated_session)
          assert length(messages) == 2
          assert Enum.at(messages, 0).role == "user"
          assert Enum.at(messages, 0).content == "Say hello"
          assert Enum.at(messages, 1).role == "assistant"
          assert Enum.at(messages, 1).content == response.content

          # Check token usage was tracked if available
          if response.usage do
            assert ExLLM.session_token_usage(updated_session) > 0
          end

        {:error, :not_configured} ->
          # Skip test if not configured
          :ok

        {:error, reason} ->
          flunk("Chat failed: #{inspect(reason)}")
      end
    end

    test "maintains conversation context across multiple chats" do
      session = ExLLM.new_session(:anthropic)

      # First interaction
      case ExLLM.chat_with_session(session, "Remember that my favorite color is blue") do
        {:ok, {_, session}} ->
          # Second interaction
          case ExLLM.chat_with_session(session, "What did I just tell you?") do
            {:ok, {response, final_session}} ->
              # Verify we got a response (don't test if model remembers specific details)
              assert String.length(response.content) > 0
              assert length(ExLLM.get_session_messages(final_session)) == 4

            {:error, :not_configured} ->
              :ok

            {:error, reason} ->
              flunk("Second chat failed: #{inspect(reason)}")
          end

        {:error, :not_configured} ->
          :ok

        {:error, reason} ->
          flunk("First chat failed: #{inspect(reason)}")
      end
    end
  end
end
