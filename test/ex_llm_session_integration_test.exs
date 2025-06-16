defmodule ExLLM.SessionIntegrationTest do
  use ExUnit.Case

  describe "session integration with ExLLM" do
    test "creates session through ExLLM interface" do
      session = ExLLM.new_session(:anthropic, name: "Test Session")

      assert session.llm_backend == "anthropic"
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

      session =
        ExLLM.Session.update_token_usage(session, %{input_tokens: 100, output_tokens: 200})

      assert ExLLM.session_token_usage(session) == 300
    end

    test "clears session through ExLLM interface" do
      session = ExLLM.new_session(:anthropic)
      session = ExLLM.add_session_message(session, "user", "Message 1")
      session = ExLLM.add_session_message(session, "assistant", "Response 1")

      session = ExLLM.clear_session(session)
      assert ExLLM.get_session_messages(session) == []
      # Metadata preserved
      assert session.llm_backend == "anthropic"
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

    setup do
      # Set up mock responses for session tests
      ExLLM.Providers.Mock.start_link()

      ExLLM.Providers.Mock.set_response_handler(fn messages, _options ->
        last_message = List.last(messages)
        content = last_message.content || last_message[:content] || last_message["content"]

        response_content =
          cond do
            String.contains?(content, "2+2") -> "4"
            String.contains?(content, "my name") -> "Hello Alice! Nice to meet you."
            String.contains?(content, "What is my name") -> "Your name is Alice."
            true -> "I understand."
          end

        %{
          content: response_content,
          model: "mock-model",
          usage: %{input_tokens: 10, output_tokens: 5}
        }
      end)

      :ok
    end

    test "performs chat with session tracking" do
      session = ExLLM.new_session(:mock)

      case ExLLM.chat_with_session(session, "What is 2+2?") do
        {:ok, {response, updated_session}} ->
          # Check response
          assert response.content =~ ~r/4|four/i

          # Check session was updated
          messages = ExLLM.get_session_messages(updated_session)
          assert length(messages) == 2
          assert Enum.at(messages, 0).role == "user"
          assert Enum.at(messages, 0).content == "What is 2+2?"
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
      session = ExLLM.new_session(:mock)

      # First interaction
      case ExLLM.chat_with_session(session, "My name is Alice") do
        {:ok, {_, session}} ->
          # Second interaction
          case ExLLM.chat_with_session(session, "What is my name?") do
            {:ok, {response, final_session}} ->
              assert response.content =~ ~r/Alice/i
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
