defmodule ExLLM.ContextIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  describe "chat/3 with context management" do
    setup do
      # Create many messages to test truncation
      messages = [
        %{role: "system", content: "You are a helpful assistant."}
      ]

      # Add many user/assistant pairs
      messages =
        Enum.reduce(1..50, messages, fn i, acc ->
          acc ++
            [
              %{
                role: "user",
                content:
                  "Question #{i}: " <>
                    String.duplicate(
                      "This is a much longer question to ensure we exceed the context window. ",
                      10
                    )
              },
              %{
                role: "assistant",
                content:
                  "Answer #{i}: " <>
                    String.duplicate(
                      "This is a much longer response to ensure we exceed the context window. ",
                      10
                    )
              }
            ]
        end)

      messages =
        messages ++
          [
            %{role: "user", content: "Final question: What's the weather?"}
          ]

      {:ok, messages: messages}
    end

    test "automatically truncates messages to fit context window", %{messages: messages} do
      # For this test, we'll use a model with a small context window
      # First verify the messages are too large
      total_tokens = ExLLM.estimate_tokens(messages)
      assert total_tokens > 1000

      # Use gpt-3.5-turbo with moderate max_tokens to force truncation
      prepared =
        ExLLM.prepare_messages(messages,
          provider: :openai,
          model: "gpt-3.5-turbo",
          # This leaves reasonable room for messages
          max_tokens: 8000,
          strategy: :sliding_window
        )

      # Should have fewer messages than original
      assert length(prepared) < length(messages)

      # Should have at least one message
      assert length(prepared) > 0

      # Sliding window keeps messages from the beginning
      if length(prepared) > 0 do
        assert List.first(prepared).role == "system"
      end
    end
  end

  describe "prepare_messages/2" do
    test "prepares messages with different strategies" do
      # Create messages that will definitely exceed context
      messages =
        for i <- 1..200 do
          # Each message should be ~100 tokens
          content =
            "Message #{i}: " <>
              String.duplicate("This is a longer message to ensure truncation happens. ", 10)

          %{role: "user", content: content}
        end

      # Test sliding window - use a model with smaller context window
      sliding =
        ExLLM.prepare_messages(messages,
          provider: :openai,
          model: "gpt-3.5-turbo",
          # Leave reasonable room for messages
          max_tokens: 2000,
          strategy: :sliding_window
        )

      assert length(sliding) < length(messages)
      # Check that we have at least one message
      assert length(sliding) > 0
      # Sliding window keeps messages (verify structure, not content)
      assert String.length(List.first(sliding).content) > 0

      # Test smart strategy
      messages_with_system =
        [
          %{role: "system", content: "System instructions"}
        ] ++ messages

      smart =
        ExLLM.prepare_messages(messages_with_system,
          provider: :openai,
          model: "gpt-3.5-turbo",
          # Force truncation
          max_tokens: 14_000,
          strategy: :smart
        )

      assert Enum.any?(smart, &(&1.role == "system"))
      assert length(smart) < length(messages_with_system)
    end
  end

  describe "validate_context/2" do
    test "validates context for different providers" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]

      # Test with Anthropic model
      assert {:ok, tokens} =
               ExLLM.validate_context(messages,
                 provider: "anthropic",
                 model: "claude-3-5-sonnet-20241022"
               )

      assert tokens < 200_000

      # Test with OpenAI model
      assert {:ok, tokens} =
               ExLLM.validate_context(messages,
                 provider: "openai",
                 model: "gpt-3.5-turbo"
               )

      assert tokens < 16_385
    end
  end

  describe "context_window_size/2" do
    test "returns correct sizes for known models" do
      assert ExLLM.context_window_size(:anthropic, "claude-3-5-sonnet-20241022") == 200_000
      assert ExLLM.context_window_size(:openai, "gpt-4o") == 128_000
      assert ExLLM.context_window_size(:openai, "gpt-3.5-turbo") == 16_385
    end
  end

  describe "context_stats/1" do
    test "provides useful statistics" do
      messages = [
        %{role: "system", content: "Be helpful"},
        %{role: "user", content: "What is Elixir?"},
        %{role: "assistant", content: "Elixir is a functional programming language."},
        %{role: "user", content: "Tell me more"},
        %{
          role: "assistant",
          content: "It runs on the Erlang VM and is great for concurrent applications."
        }
      ]

      stats = ExLLM.context_stats(messages)

      assert stats.message_count == 5
      assert stats.total_tokens > 0
      assert stats.by_role["system"] == 1
      assert stats.by_role["user"] == 2
      assert stats.by_role["assistant"] == 2
      assert stats.avg_tokens_per_message > 0
    end
  end
end
