defmodule ExLLM.ContextTest do
  use ExUnit.Case
  alias ExLLM.Context

  describe "prepare_messages/2" do
    test "returns messages unchanged when under token limit" do
      messages = [
        %{role: "system", content: "You are helpful"},
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]
      
      result = Context.prepare_messages(messages, max_tokens: 1000)
      assert result == messages
    end
    
    test "truncates messages with sliding window strategy" do
      messages = for i <- 1..20 do
        %{role: "user", content: "Message #{i} with some longer content to use up tokens"}
      end
      
      result = Context.prepare_messages(messages, max_tokens: 200, strategy: :sliding_window)
      assert length(result) < length(messages)
      assert List.last(result).content =~ "Message 20"
    end
    
    test "preserves system messages with smart strategy" do
      messages = [
        %{role: "system", content: "Important system prompt"},
        %{role: "user", content: "Old message"},
        %{role: "assistant", content: "Old response"},
        %{role: "user", content: "Recent message"},
        %{role: "assistant", content: "Recent response"}
      ]
      
      result = Context.prepare_messages(messages, 
        max_tokens: 100, 
        strategy: :smart,
        preserve_messages: 2
      )
      
      assert Enum.any?(result, &(&1.role == "system"))
      assert List.last(result).content == "Recent response"
    end
    
    test "respects preserve_messages option" do
      messages = for i <- 1..10 do
        %{role: "user", content: "Message #{i}"}
      end
      
      result = Context.prepare_messages(messages, 
        max_tokens: 50,
        preserve_messages: 3
      )
      
      # Should have at least 3 messages preserved
      assert length(result) >= 3
      assert List.last(result).content == "Message 10"
    end
  end
  
  describe "validate_context/2" do
    test "validates messages within model context window" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi!"}
      ]
      
      assert {:ok, tokens} = Context.validate_context(messages, 
        provider: "anthropic",
        model: "claude-3-5-sonnet-20241022"
      )
      assert is_integer(tokens)
      assert tokens > 0
    end
    
    test "returns error for messages exceeding context window" do
      # Create very long message
      long_content = String.duplicate("word ", 50_000)
      messages = [%{role: "user", content: long_content}]
      
      assert {:error, {:context_too_large, _}} = Context.validate_context(messages,
        provider: "openai",
        model: "gpt-3.5-turbo"
      )
    end
    
    test "uses custom max_tokens if provided" do
      messages = [
        %{role: "user", content: String.duplicate("word ", 100)}
      ]
      
      assert {:error, {:context_too_large, _}} = Context.validate_context(messages,
        max_tokens: 50
      )
    end
  end
  
  describe "context_window_size/2" do
    test "returns correct window size for known models" do
      assert Context.context_window_size("anthropic", "claude-3-5-sonnet-20241022") == 200_000
      assert Context.context_window_size("anthropic", "claude-3-haiku-20240307") == 200_000
      assert Context.context_window_size("openai", "gpt-4-turbo") == 128_000
      assert Context.context_window_size("openai", "gpt-3.5-turbo") == 16_385
    end
    
    test "returns nil for unknown models" do
      assert Context.context_window_size("unknown", "model") == nil
      assert Context.context_window_size("anthropic", "unknown-model") == nil
    end
  end
  
  describe "stats/1" do
    test "calculates message statistics" do
      messages = [
        %{role: "system", content: "System prompt"},
        %{role: "user", content: "User message"},
        %{role: "assistant", content: "Assistant response"},
        %{role: "user", content: "Another question"}
      ]
      
      stats = Context.stats(messages)
      
      assert stats.message_count == 4
      assert stats.total_tokens > 0
      assert stats.by_role["system"] == 1
      assert stats.by_role["user"] == 2
      assert stats.by_role["assistant"] == 1
      assert stats.avg_tokens_per_message > 0
    end
    
    test "handles empty messages" do
      stats = Context.stats([])
      
      assert stats.message_count == 0
      assert stats.total_tokens == 0
      assert stats.by_role == %{}
      assert stats.avg_tokens_per_message == 0
    end
  end
  
  describe "truncate_messages/2" do
    test "removes middle messages while preserving recent ones" do
      messages = for i <- 1..10 do
        %{role: "user", content: "Message #{i} " <> String.duplicate("with additional content ", 5)}
      end
      
      result = Context.truncate_messages(messages, max_tokens: 100)
      
      assert length(result) < length(messages)
      assert List.last(result).content =~ "Message 10"
    end
    
    test "handles single message that exceeds limit" do
      messages = [
        %{role: "user", content: String.duplicate("word ", 1000)}
      ]
      
      result = Context.truncate_messages(messages, max_tokens: 50)
      
      assert length(result) == 1
      assert String.length(result |> List.first() |> Map.get(:content)) < 
             String.length(messages |> List.first() |> Map.get(:content))
    end
  end
end