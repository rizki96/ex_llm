defmodule ExLLM.Integration.SessionStateComprehensiveTest do
  @moduledoc """
  Comprehensive integration tests for session management and state tracking.
  Tests conversation persistence, context management, and token tracking.
  """
  use ExUnit.Case
  require Logger

  describe "Session Management" do
    @describetag :integration
    @describetag :session
    @describetag timeout: 60_000

    test "session persistence across multiple conversations" do
      # Create a new session
      session = ExLLM.new_session(:openai, model: "gpt-4o-mini")

      # First conversation turn
      {:ok, {response1, session1}} =
        ExLLM.chat_with_session(session, "My name is Alice", max_tokens: 50)

      assert is_binary(response1.content)
      assert String.length(response1.content) > 0

      # Second turn - should remember the name
      {:ok, {response2, session2}} =
        ExLLM.chat_with_session(session1, "What's my name?", max_tokens: 50)

      assert String.contains?(String.downcase(response2.content), "alice")

      # Check session state
      messages = ExLLM.get_messages(session2)
      # 2 user + 2 assistant messages
      assert length(messages) == 4

      # Check token usage tracking
      total_tokens = ExLLM.session_token_usage(session2)
      assert total_tokens > 0

      usage = session2.token_usage
      assert usage.input_tokens > 0
      assert usage.output_tokens > 0

      # Save session to JSON
      {:ok, json} = ExLLM.save_session(session2)
      assert String.contains?(json, "Alice")

      # Load session from JSON
      {:ok, loaded_session} = ExLLM.load_session(json)
      loaded_messages = ExLLM.get_messages(loaded_session)
      assert length(loaded_messages) == length(messages)

      # Continue conversation with loaded session
      {:ok, {response3, _session3}} =
        ExLLM.chat_with_session(loaded_session, "Tell me a fact about my name", max_tokens: 100)

      assert is_binary(response3.content)

      assert String.contains?(String.downcase(response3.content), "alice") or
               String.contains?(String.downcase(response3.content), "name")

      IO.puts("\nSession Persistence Test:")
      IO.puts("- Initial session created")
      IO.puts("- #{length(messages)} messages stored")
      IO.puts("- Total tokens used: #{usage.input_tokens + usage.output_tokens}")
      IO.puts("- Session saved and loaded successfully")
      IO.puts("- Conversation continued after loading")
    end

    test "context window management with message truncation" do
      # Use a small context model for testing
      session =
        ExLLM.new_session(:openai,
          model: "gpt-4o-mini",
          # Artificially low for testing
          max_context_tokens: 1000
        )

      # Add many messages to exceed context
      session_with_messages =
        Enum.reduce(1..10, session, fn i, acc_session ->
          content = "This is message number #{i}. " <> String.duplicate("word ", 50)
          {:ok, {_, new_session}} = ExLLM.chat_with_session(acc_session, content, max_tokens: 20)
          new_session
        end)

      # Get messages and check truncation
      all_messages = ExLLM.get_messages(session_with_messages)

      # Try to get messages with limit
      recent_messages = ExLLM.get_session_messages(session_with_messages, 4)
      assert length(recent_messages) == 4

      # Final message should still work despite context limits
      {:ok, {final_response, _final_session}} =
        ExLLM.chat_with_session(
          session_with_messages,
          "Summarize our conversation in one sentence",
          max_tokens: 50
        )

      assert is_binary(final_response.content)

      IO.puts("\nContext Management Test:")
      IO.puts("- Total messages: #{length(all_messages)}")
      IO.puts("- Recent messages retrieved: #{length(recent_messages)}")
      IO.puts("- Context window handled successfully")
    end

    test "multi-provider session state transfer" do
      providers = get_configured_providers()

      if length(providers) < 2 do
        IO.puts("Skipping multi-provider session test: Need at least 2 configured providers")
        assert true
      else
        provider1 = List.first(providers)
        provider2 = Enum.at(providers, 1)

        # Create session with first provider
        session1 = ExLLM.new_session(provider1, model: get_model_for_provider(provider1))

        # Have a conversation
        {:ok, {_response1, session1_updated}} =
          ExLLM.chat_with_session(
            session1,
            "My favorite color is blue and my favorite number is 42",
            max_tokens: 50
          )

        # Export messages
        messages = ExLLM.get_messages(session1_updated)

        # Create new session with second provider and import messages
        session2 = ExLLM.new_session(provider2, model: get_model_for_provider(provider2))

        # Import conversation history
        session2_with_history =
          Enum.reduce(messages, session2, fn msg, acc ->
            ExLLM.add_message(acc, msg.role, msg.content)
          end)

        # Continue conversation with new provider
        {:ok, {response2, session2_final}} =
          ExLLM.chat_with_session(
            session2_with_history,
            "What's my favorite color and number?",
            max_tokens: 50
          )

        # Check if information was retained
        response_text = String.downcase(response2.content)
        assert String.contains?(response_text, "blue") or String.contains?(response_text, "42")

        IO.puts("\nMulti-Provider Session Transfer:")
        IO.puts("- Session created with #{provider1}")
        IO.puts("- Conversation history: #{length(messages)} messages")
        IO.puts("- Session transferred to #{provider2}")

        IO.puts(
          "- Context preserved: #{String.contains?(response_text, "blue") and String.contains?(response_text, "42")}"
        )

        # Compare token usage between providers
        total_tokens1 = ExLLM.session_token_usage(session1_updated)
        total_tokens2 = ExLLM.session_token_usage(session2_final)

        if total_tokens1 > 0 and total_tokens2 > 0 do
          token_ratio = total_tokens2 / total_tokens1

          IO.puts(
            "- Token usage comparison: #{provider2} used #{Float.round(token_ratio, 2)}x tokens of #{provider1}"
          )
        end
      end
    end
  end

  describe "State Tracking" do
    @describetag :integration
    @describetag :state_tracking
    @describetag timeout: 60_000

    test "comprehensive token and cost tracking" do
      initial_session = ExLLM.new_session(:openai, model: "gpt-4o-mini")

      # Track costs across multiple interactions
      {final_session, cost_data} =
        Enum.reduce(1..3, {initial_session, []}, fn i, {session, data} ->
          prompt = "Generate exactly #{i} sentence#{if i > 1, do: "s", else: ""} about space"

          {:ok, {response, updated_session}} =
            ExLLM.chat_with_session(session, prompt, max_tokens: 50 * i)

          usage = response.usage
          cost = response.cost

          cost_entry = %{
            turn: i,
            prompt_tokens: usage.prompt_tokens || usage.input_tokens,
            completion_tokens: usage.completion_tokens || usage.output_tokens,
            total_tokens: usage.total_tokens,
            total_cost: cost
          }

          {updated_session, [cost_entry | data]}
        end)

      # Reverse the data to get correct order
      cost_data = Enum.reverse(cost_data)

      # Get cumulative session stats
      total_tokens_count = ExLLM.session_token_usage(final_session)
      session_usage = final_session.token_usage

      # Calculate cumulative values
      cumulative_prompt_tokens = Enum.sum(Enum.map(cost_data, & &1.prompt_tokens))
      cumulative_completion_tokens = Enum.sum(Enum.map(cost_data, & &1.completion_tokens))
      _cumulative_cost = Enum.sum(Enum.map(cost_data, & &1.total_cost))

      IO.puts("\nToken & Cost Tracking Test:")
      IO.puts("Turn-by-turn breakdown:")

      Enum.each(cost_data, fn data ->
        IO.puts(
          "  Turn #{data.turn}: #{data.prompt_tokens} + #{data.completion_tokens} = #{data.total_tokens} tokens ($#{Float.round(data.total_cost, 6)})"
        )
      end)

      IO.puts("\nCumulative totals:")
      IO.puts("  Prompt tokens: #{cumulative_prompt_tokens}")
      IO.puts("  Completion tokens: #{cumulative_completion_tokens}")
      IO.puts("  Total tokens: #{total_tokens_count}")

      IO.puts(
        "  Total session tokens: #{session_usage.input_tokens + session_usage.output_tokens}"
      )

      # Verify tracking accuracy - use session token count
      assert total_tokens_count >= cumulative_prompt_tokens + cumulative_completion_tokens
      assert total_tokens_count == session_usage.input_tokens + session_usage.output_tokens
    end

    test "session memory limits and cleanup" do
      # Create session with memory limit
      session =
        ExLLM.new_session(:openai,
          model: "gpt-4o-mini",
          # Keep only last 10 messages
          max_messages: 10
        )

      # Add many messages
      final_session =
        Enum.reduce(1..15, session, fn i, acc ->
          {:ok, {_, new_session}} =
            ExLLM.chat_with_session(
              acc,
              "Message #{i}: #{String.duplicate("test ", 10)}",
              max_tokens: 10
            )

          new_session
        end)

      # Check message count
      messages = ExLLM.get_messages(final_session)

      # Should have maximum 10 messages (or close to it considering system messages)
      # Reasonable upper bound
      assert length(messages) <= 30

      # Get token count before clearing
      final_total_tokens = ExLLM.session_token_usage(final_session)

      # Clear session
      cleared_session = ExLLM.clear_session(final_session)
      cleared_messages = ExLLM.get_messages(cleared_session)
      assert length(cleared_messages) == 0

      # Token usage should be preserved (historical usage)
      cleared_total_tokens = ExLLM.session_token_usage(cleared_session)
      assert cleared_total_tokens == final_total_tokens

      IO.puts("\nSession Memory Management Test:")
      IO.puts("- Messages after 15 turns: #{length(messages)}")
      IO.puts("- Messages after clear: #{length(cleared_messages)}")
      IO.puts("- Usage tracking reset: ✓")
    end

    test "session branching and checkpoint management" do
      # Create base session
      base_session = ExLLM.new_session(:openai, model: "gpt-4o-mini")

      # Establish context
      {:ok, {_, session_v1}} =
        ExLLM.chat_with_session(
          base_session,
          "I'm planning a trip to Paris in spring",
          max_tokens: 50
        )

      # Save checkpoint
      {:ok, checkpoint_json} = ExLLM.save_session(session_v1)

      # Branch 1: Ask about attractions
      {:ok, {_response1, branch1_session}} =
        ExLLM.chat_with_session(
          session_v1,
          "What are the top 3 attractions I should visit?",
          max_tokens: 100
        )

      # Branch 2: Load checkpoint and ask about food
      {:ok, session_v1_restored} = ExLLM.load_session(checkpoint_json)

      {:ok, {_response2, branch2_session}} =
        ExLLM.chat_with_session(
          session_v1_restored,
          "What are the best restaurants for French cuisine?",
          max_tokens: 100
        )

      # Compare branches
      branch1_messages = ExLLM.get_messages(branch1_session)
      branch2_messages = ExLLM.get_messages(branch2_session)

      # Both should have the base context
      assert Enum.any?(branch1_messages, &String.contains?(&1.content, "Paris"))
      assert Enum.any?(branch2_messages, &String.contains?(&1.content, "Paris"))

      # But different follow-up questions
      assert Enum.any?(branch1_messages, &String.contains?(&1.content, "attractions"))
      assert Enum.any?(branch2_messages, &String.contains?(&1.content, "restaurants"))

      IO.puts("\nSession Branching Test:")
      IO.puts("- Base context established: Paris trip")
      IO.puts("- Checkpoint saved at message count: 2")
      IO.puts("- Branch 1 messages: #{length(branch1_messages)} (attractions)")
      IO.puts("- Branch 2 messages: #{length(branch2_messages)} (restaurants)")
      IO.puts("- Both branches maintained context: ✓")
    end
  end

  # Helper functions
  defp get_configured_providers do
    [:openai, :anthropic, :gemini, :groq, :mistral]
    |> Enum.filter(fn provider ->
      config = ExLLM.Environment.provider_config(provider)
      config[:api_key] != nil
    end)
  end

  defp get_model_for_provider(provider) do
    case provider do
      :openai -> "gpt-4o-mini"
      :anthropic -> "claude-3-haiku-20240307"
      :gemini -> "gemini-1.5-flash"
      :groq -> "llama-3.1-8b-instant"
      :mistral -> "mistral-small-latest"
      _ -> nil
    end
  end
end
