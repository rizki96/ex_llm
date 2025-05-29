defmodule ExLLM.ContextIntegrationTest do
  use ExUnit.Case

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
              %{role: "user", content: "Question #{i}: " <> String.duplicate("word ", 20)},
              %{role: "assistant", content: "Answer #{i}: " <> String.duplicate("response ", 20)}
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
      
      # Use gpt-3.5-turbo with small max_tokens to force truncation
      prepared =
        ExLLM.prepare_messages(messages,
          provider: :openai,
          model: "gpt-3.5-turbo",
          max_tokens: 15000,  # This leaves very little room for messages
          strategy: :sliding_window
        )

      # Should have fewer messages than original
      assert length(prepared) < length(messages)

      # Sliding window keeps messages from the beginning
      assert List.first(prepared).role == "system"
    end
  end

  describe "prepare_messages/2" do
    test "prepares messages with different strategies" do
      # Create messages that will definitely exceed context
      messages =
        for i <- 1..200 do
          %{role: "user", content: "Message #{i} " <> String.duplicate("with lots more content to force truncation ", 50)}
        end

      # Test sliding window - use a model with smaller context window
      sliding =
        ExLLM.prepare_messages(messages,
          provider: :openai,
          model: "gpt-3.5-turbo",
          max_tokens: 4000,  # Leave some room for response
          strategy: :sliding_window
        )

      assert length(sliding) < length(messages)
      # Check that we have at least one message
      assert length(sliding) > 0
      # Sliding window keeps early messages
      assert List.first(sliding).content =~ "Message 1"

      # Test smart strategy
      messages_with_system =
        [
          %{role: "system", content: "System instructions"}
        ] ++ messages

      smart =
        ExLLM.prepare_messages(messages_with_system,
          max_tokens: 200,
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
