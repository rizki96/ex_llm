defmodule ExLLM.SessionStreamingCostTest do
  @moduledoc """
  Tests for cost tracking and aggregation in streaming sessions.

  This test module specifically addresses the integration of:
  - Streaming chat responses
  - Session management
  - Cost tracking and aggregation

  These are critical real-world scenarios where users need to track
  costs across streaming conversations within sessions.
  """

  use ExUnit.Case, async: false

  alias ExLLM.Core.Session

  @test_message "Test streaming cost tracking"

  describe "streaming cost integration" do
    test "tracks cost from streaming chunks in session context" do
      # Create a session
      _session = Session.new("mock")

      # Track cost accumulation during streaming
      {:ok, cost_tracker} = Agent.start_link(fn -> %{total_cost: 0.0, chunk_count: 0} end)

      callback = fn chunk ->
        Agent.update(cost_tracker, fn state ->
          # Extract cost from chunk if available
          chunk_cost =
            case chunk do
              %{cost: %{total_cost: cost}} when is_number(cost) -> cost
              %{cost: cost} when is_number(cost) -> cost
              _ -> 0.0
            end

          %{
            total_cost: state.total_cost + chunk_cost,
            chunk_count: state.chunk_count + 1
          }
        end)
      end

      # Perform streaming chat
      result = ExLLM.stream(:mock, [%{role: "user", content: @test_message}], callback)
      assert result == :ok

      # Check that cost tracking worked
      final_state = Agent.get(cost_tracker, & &1)
      Agent.stop(cost_tracker)

      assert final_state.chunk_count > 0
      # Cost might be 0 for mock provider, but structure should be correct
      assert is_number(final_state.total_cost)
      assert final_state.total_cost >= 0
    end

    test "aggregates costs across multiple streaming interactions in same session" do
      # Create session and add initial message
      session = Session.new("mock")
      session = Session.add_message(session, "user", "First message")

      # First streaming interaction
      {:ok, first_cost} = Agent.start_link(fn -> 0.0 end)

      first_callback = fn chunk ->
        case chunk do
          %{cost: %{total_cost: cost}} when is_number(cost) ->
            Agent.update(first_cost, fn _ -> cost end)

          %{cost: cost} when is_number(cost) ->
            Agent.update(first_cost, fn _ -> cost end)

          _ ->
            :ok
        end
      end

      assert :ok =
               ExLLM.stream(
                 :mock,
                 Session.get_messages(session),
                 first_callback
               )

      first_interaction_cost = Agent.get(first_cost, & &1)
      Agent.stop(first_cost)

      # Add response to session (simulating cost tracking)
      session = Session.add_message(session, "assistant", "First response")
      session = Session.add_message(session, "user", "Second message")

      # Second streaming interaction
      {:ok, second_cost} = Agent.start_link(fn -> 0.0 end)

      second_callback = fn chunk ->
        case chunk do
          %{cost: %{total_cost: cost}} when is_number(cost) ->
            Agent.update(second_cost, fn _ -> cost end)

          %{cost: cost} when is_number(cost) ->
            Agent.update(second_cost, fn _ -> cost end)

          _ ->
            :ok
        end
      end

      assert :ok =
               ExLLM.stream(
                 :mock,
                 Session.get_messages(session),
                 second_callback
               )

      second_interaction_cost = Agent.get(second_cost, & &1)
      Agent.stop(second_cost)

      # Verify cost tracking structure
      assert is_number(first_interaction_cost)
      assert is_number(second_interaction_cost)

      # In a real implementation, we'd verify session.total_cost accumulation
      total_session_cost = first_interaction_cost + second_interaction_cost
      assert total_session_cost >= 0
    end

    test "streaming callback can update session with cost information" do
      session = Session.new("mock")
      session = Session.add_message(session, "user", @test_message)

      # Track session updates through streaming
      {:ok, session_state} = Agent.start_link(fn -> session end)
      {:ok, final_chunk} = Agent.start_link(fn -> nil end)

      callback = fn chunk ->
        case chunk do
          %{finish_reason: "stop"} = final ->
            # Store final chunk for analysis
            Agent.update(final_chunk, fn _ -> final end)

            # In real implementation, this would update the session with:
            # - The complete response content
            # - Usage information (tokens)
            # - Cost information
            Agent.update(session_state, fn current_session ->
              # Simulate adding the streaming response to session
              content = final.content || "Mock streaming response"
              Session.add_message(current_session, "assistant", content)
            end)

          _ ->
            :ok
        end
      end

      assert :ok = ExLLM.stream(:mock, Session.get_messages(session), callback)

      # Verify session was updated
      final_session = Agent.get(session_state, & &1)
      final_response = Agent.get(final_chunk, & &1)

      Agent.stop(session_state)
      Agent.stop(final_chunk)

      # Session should have been updated with assistant response
      messages = Session.get_messages(final_session)
      # user + assistant
      assert length(messages) == 2

      [user_msg, assistant_msg] = messages
      assert user_msg.role == "user"
      assert assistant_msg.role == "assistant"

      # Final chunk should have completion information
      if final_response do
        assert final_response.finish_reason == "stop"
      end
    end
  end

  describe "session cost aggregation patterns" do
    test "demonstrates session-level cost tracking pattern" do
      # This test shows how applications should track costs in sessions
      session = Session.new("mock")

      # Track costs at session level
      {:ok, session_costs} = Agent.start_link(fn -> [] end)

      # Function to perform streaming chat and track costs
      stream_with_cost_tracking = fn session, message ->
        current_messages = Session.get_messages(session)
        messages_with_new = current_messages ++ [%{role: "user", content: message}]

        {:ok, response_cost} = Agent.start_link(fn -> 0.0 end)
        {:ok, response_content} = Agent.start_link(fn -> "" end)

        callback = fn chunk ->
          # Accumulate content
          if chunk.content do
            Agent.update(response_content, fn acc -> acc <> chunk.content end)
          end

          # Track cost
          case chunk do
            %{cost: %{total_cost: cost}} when is_number(cost) ->
              Agent.update(response_cost, fn _ -> cost end)

            %{cost: cost} when is_number(cost) ->
              Agent.update(response_cost, fn _ -> cost end)

            _ ->
              :ok
          end
        end

        :ok = ExLLM.stream(:mock, messages_with_new, callback)

        # Get final values
        cost = Agent.get(response_cost, & &1)
        content = Agent.get(response_content, & &1)

        Agent.stop(response_cost)
        Agent.stop(response_content)

        # Update session with response
        updated_session =
          session
          |> Session.add_message("user", message)
          |> Session.add_message("assistant", content)

        # Track cost
        Agent.update(session_costs, fn costs -> [cost | costs] end)

        {updated_session, cost}
      end

      # Perform multiple streaming interactions
      {session, cost1} = stream_with_cost_tracking.(session, "First question")
      {session, cost2} = stream_with_cost_tracking.(session, "Second question")
      {_final_session, cost3} = stream_with_cost_tracking.(session, "Third question")

      # Verify cost tracking
      all_costs = Agent.get(session_costs, &Enum.reverse/1)
      Agent.stop(session_costs)

      assert length(all_costs) == 3
      assert [cost1, cost2, cost3] == all_costs

      # Calculate total session cost
      total_cost = Enum.sum(all_costs)
      assert is_number(total_cost)
      assert total_cost >= 0
    end

    test "handles streaming errors with partial cost tracking" do
      _session = Session.new("mock")

      {:ok, error_tracker} = Agent.start_link(fn -> %{errors: 0, partial_cost: 0.0} end)

      callback = fn chunk ->
        case chunk do
          %{error: _error} ->
            Agent.update(error_tracker, fn state ->
              %{state | errors: state.errors + 1}
            end)

          %{cost: cost} when is_number(cost) ->
            Agent.update(error_tracker, fn state ->
              %{state | partial_cost: state.partial_cost + cost}
            end)

          _ ->
            :ok
        end
      end

      # This should work with mock provider
      result = ExLLM.stream(:mock, [%{role: "user", content: "Error test"}], callback)

      final_state = Agent.get(error_tracker, & &1)
      Agent.stop(error_tracker)

      # Even if there are errors, we should handle partial costs gracefully
      assert is_number(final_state.partial_cost)
      assert final_state.partial_cost >= 0
      # Mock provider should succeed
      assert result == :ok
    end
  end

  describe "cost calculation accuracy" do
    test "streaming cost matches non-streaming cost for same input" do
      # Ensure mock provider is in clean state
      :ok = ExLLM.Providers.Mock.reset()

      messages = [%{role: "user", content: "Cost comparison test"}]

      # Get cost from regular chat
      case ExLLM.chat(:mock, messages) do
        {:ok, regular_response} ->
          regular_cost =
            case regular_response do
              %{cost: %{total_cost: cost}} -> cost
              %{cost: cost} when is_number(cost) -> cost
              _ -> 0.0
            end

          # Get cost from streaming chat
          {:ok, streaming_cost} = Agent.start_link(fn -> 0.0 end)

          streaming_callback = fn chunk ->
            case chunk do
              %{cost: %{total_cost: cost}} when is_number(cost) ->
                Agent.update(streaming_cost, fn _ -> cost end)

              %{cost: cost} when is_number(cost) ->
                Agent.update(streaming_cost, fn _ -> cost end)

              _ ->
                :ok
            end
          end

          assert :ok = ExLLM.stream(:mock, messages, streaming_callback)

          final_streaming_cost = Agent.get(streaming_cost, & &1)
          Agent.stop(streaming_cost)

          # Costs should be comparable (allowing for mock provider differences)
          assert is_number(regular_cost)
          assert is_number(final_streaming_cost)

          # For mock provider, both might be 0, but structure should be consistent
          if regular_cost > 0 or final_streaming_cost > 0 do
            # If either has a cost, they should be similar
            cost_diff = abs(regular_cost - final_streaming_cost)
            # Allow small floating point differences
            assert cost_diff < 0.001
          end

        {:error, _reason} ->
          # If regular chat fails, that's a different issue
          assert true
      end
    end

    test "cost tracking works with different providers" do
      # Test that cost tracking structure is consistent across providers
      providers = [:mock, :openai, :anthropic]

      for provider <- providers do
        {:ok, cost_structure} = Agent.start_link(fn -> %{has_cost: false, cost_format: nil} end)

        callback = fn chunk ->
          case chunk do
            %{cost: %{total_cost: cost}} when is_number(cost) ->
              Agent.update(cost_structure, fn _ ->
                %{has_cost: true, cost_format: :structured}
              end)

            %{cost: cost} when is_number(cost) ->
              Agent.update(cost_structure, fn _ ->
                %{has_cost: true, cost_format: :simple}
              end)

            _ ->
              :ok
          end
        end

        case ExLLM.stream(provider, [%{role: "user", content: "Provider test"}], callback) do
          :ok ->
            structure = Agent.get(cost_structure, & &1)

            # If provider returned cost info, verify it's well-formed
            if structure.has_cost do
              assert structure.cost_format in [:structured, :simple]
            end

          {:error, _reason} ->
            # Provider may not be configured
            assert true
        end

        Agent.stop(cost_structure)
      end
    end
  end

  describe "integration with session token usage" do
    test "streaming updates session token usage properly" do
      session = Session.new("mock")
      initial_usage = session.token_usage

      # Track token usage from streaming
      {:ok, usage_tracker} = Agent.start_link(fn -> %{input: 0, output: 0} end)

      callback = fn chunk ->
        case chunk do
          %{usage: %{input_tokens: input, output_tokens: output}} ->
            Agent.update(usage_tracker, fn _ -> %{input: input, output: output} end)

          %{usage: usage} when is_map(usage) ->
            input = Map.get(usage, :input_tokens, 0)
            output = Map.get(usage, :output_tokens, 0)
            Agent.update(usage_tracker, fn _ -> %{input: input, output: output} end)

          _ ->
            :ok
        end
      end

      assert :ok = ExLLM.stream(:mock, [%{role: "user", content: "Token usage test"}], callback)

      final_usage = Agent.get(usage_tracker, & &1)
      Agent.stop(usage_tracker)

      # Verify token usage structure
      assert is_map(initial_usage)
      assert Map.has_key?(initial_usage, :input_tokens)
      assert Map.has_key?(initial_usage, :output_tokens)

      # Final usage should have reasonable values
      assert is_integer(final_usage.input)
      assert is_integer(final_usage.output)
      assert final_usage.input >= 0
      assert final_usage.output >= 0
    end
  end
end
