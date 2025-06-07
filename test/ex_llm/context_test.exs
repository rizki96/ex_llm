defmodule ExLLM.ContextTest do
  use ExUnit.Case
  alias ExLLM.Context

  describe "truncate_messages/4" do
    test "returns messages unchanged when under token limit" do
      messages = [
        %{role: "system", content: "You are helpful"},
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]

      result =
        Context.truncate_messages(messages, :anthropic, "claude-3-5-sonnet-20241022",
          max_tokens: 1000
        )

      assert result == messages
    end

    test "truncates messages with sliding window strategy" do
      messages =
        for i <- 1..100 do
          %{
            role: "user",
            content:
              "Message #{i} " <>
                String.duplicate("with some longer content to use up tokens ", 20)
          }
        end

      result =
        Context.truncate_messages(messages, :openai, "gpt-3.5-turbo",
          max_tokens: 200,
          strategy: :sliding_window
        )

      assert length(result) < length(messages)
      # Sliding window keeps messages from the beginning
      assert List.first(result).content =~ "Message 1"
    end

    test "preserves system messages with smart strategy" do
      # Create many messages to force truncation
      system_msg = %{role: "system", content: "Important system prompt"}

      old_messages =
        for i <- 1..50 do
          %{role: "user", content: "Old message #{i} " <> String.duplicate("padding ", 20)}
        end

      recent_messages = [
        %{role: "user", content: "Recent message"},
        %{role: "assistant", content: "Recent response"}
      ]

      messages = [system_msg] ++ old_messages ++ recent_messages

      result =
        Context.truncate_messages(messages, :openai, "gpt-3.5-turbo",
          max_tokens: 100,
          strategy: :smart
        )

      assert Enum.any?(result, &(&1.role == "system"))
      # Smart strategy keeps recent messages after system message
      assert List.last(result).content == "Recent response"
    end

    test "respects preserve_messages option" do
      messages =
        for i <- 1..10 do
          %{role: "user", content: "Message #{i}"}
        end

      result =
        Context.truncate_messages(messages, :openai, "gpt-3.5-turbo", max_tokens: 50)

      # Should preserve recent messages
      assert length(result) >= 1
      assert List.last(result).content == "Message 10"
    end
  end

  describe "validate_context/4" do
    test "validates messages within model context window" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi!"}
      ]

      assert {:ok, tokens} =
               Context.validate_context(messages, "anthropic", "claude-3-5-sonnet-20241022")

      assert is_integer(tokens)
      assert tokens > 0
    end

    test "returns error for messages exceeding context window" do
      # Create very long message
      long_content = String.duplicate("word ", 50_000)
      messages = [%{role: "user", content: long_content}]

      assert {:error, _reason} =
               Context.validate_context(messages, "openai", "gpt-3.5-turbo")
    end

    test "uses custom max_tokens if provided" do
      # Create a message that will exceed context when combined with max_tokens
      messages = [
        %{role: "user", content: String.duplicate("word ", 4000)}
      ]

      assert {:error, _reason} =
               Context.validate_context(messages, "openai", "gpt-3.5-turbo", max_tokens: 16_000)
    end
  end

  describe "get_context_window/2" do
    test "returns correct window size for known models" do
      assert Context.get_context_window("anthropic", "claude-3-5-sonnet-20241022") == 200_000
      assert Context.get_context_window("anthropic", "claude-3-haiku-20240307") == 200_000
      assert Context.get_context_window("openai", "gpt-4o") == 128_000
      assert Context.get_context_window("openai", "gpt-3.5-turbo") == 16_385
    end

    test "raises for unknown models" do
      assert_raise RuntimeError, ~r/Unknown model/, fn ->
        Context.get_context_window("unknown", "model")
      end

      assert_raise RuntimeError, ~r/Unknown model/, fn ->
        Context.get_context_window("anthropic", "unknown-model")
      end
    end
  end

  describe "get_token_allocation/3" do
    test "calculates token allocation for model" do
      allocation = Context.get_token_allocation("anthropic", "claude-3-5-sonnet-20241022")

      assert allocation.system > 0
      assert allocation.conversation > 0
      assert allocation.response > 0
      assert allocation.total == 200_000
    end

    test "respects custom max_tokens" do
      allocation = Context.get_token_allocation("openai", "gpt-3.5-turbo", max_tokens: 2000)

      assert allocation.response == 2000
      assert allocation.total == 16_385
    end
  end

  describe "truncate_messages/4 with large messages" do
    test "removes messages from end when using sliding window" do
      messages =
        for i <- 1..50 do
          %{
            role: "user",
            content:
              "Message #{i} " <>
                String.duplicate(
                  "with lots of additional content to ensure we exceed token limits ",
                  50
                )
          }
        end

      result = Context.truncate_messages(messages, :openai, "gpt-3.5-turbo", max_tokens: 100)

      assert length(result) < length(messages)
      # Default strategy is sliding window which keeps early messages
      assert List.first(result).content =~ "Message 1"
    end

    test "handles messages when all fit" do
      messages = [
        %{role: "user", content: "short message"}
      ]

      result =
        Context.truncate_messages(messages, :anthropic, "claude-3-5-sonnet-20241022",
          max_tokens: 1000
        )

      assert length(result) == 1
      assert result == messages
    end
  end
end
