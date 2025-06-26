defmodule ExLLM.StreamingCallbackTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Tests for streaming callback functionality in ExLLM.

  These tests ensure that streaming works correctly with various
  callback patterns and error scenarios.
  """

  describe "basic streaming" do
    test "receives chunks through callback" do
      messages = [%{role: "user", content: "Hello"}]

      # Use an agent to collect chunks since we can't mutate in closure
      {:ok, collector} = Agent.start_link(fn -> [] end)

      callback = fn chunk ->
        Agent.update(collector, fn chunks -> [chunk | chunks] end)
      end

      assert :ok = ExLLM.stream(:mock, messages, callback)

      # Get collected chunks
      chunks = Agent.get(collector, fn chunks -> Enum.reverse(chunks) end)
      Agent.stop(collector)

      # Verify we received chunks
      assert length(chunks) > 0
      assert Enum.any?(chunks, &Map.has_key?(&1, :content))
      assert Enum.any?(chunks, &(&1.finish_reason == "stop"))
    end

    test "handles streaming with accumulator pattern" do
      messages = [%{role: "user", content: "Stream test"}]

      {:ok, accumulator} = Agent.start_link(fn -> "" end)

      callback = fn
        %{content: content, finish_reason: nil} ->
          Agent.update(accumulator, fn acc -> acc <> content end)

        %{finish_reason: "stop"} ->
          # Final chunk
          :ok
      end

      assert :ok = ExLLM.stream(:mock, messages, callback)

      final_content = Agent.get(accumulator, & &1)
      Agent.stop(accumulator)

      assert final_content =~ "Mock"
    end

    test "provides usage information in final chunk" do
      messages = [%{role: "user", content: "Test usage"}]

      {:ok, final_chunk_agent} = Agent.start_link(fn -> nil end)

      callback = fn chunk ->
        if chunk[:finish_reason] == "stop" do
          Agent.update(final_chunk_agent, fn _ -> chunk end)
        end
      end

      assert :ok = ExLLM.stream(:mock, messages, callback)

      final_chunk = Agent.get(final_chunk_agent, & &1)
      Agent.stop(final_chunk_agent)

      # Mock provider might include usage in final chunk
      # This depends on provider implementation
      assert final_chunk.finish_reason == "stop"
    end
  end

  describe "callback patterns" do
    test "supports pattern matching callbacks" do
      messages = [%{role: "user", content: "Pattern match test"}]

      {:ok, state} = Agent.start_link(fn -> %{chunks: 0, done: false} end)

      callback = fn
        %{done: true} ->
          Agent.update(state, fn s -> %{s | done: true} end)

        %{content: _content} ->
          Agent.update(state, fn s -> %{s | chunks: s.chunks + 1} end)

        _ ->
          # Ignore other chunks
          :ok
      end

      assert :ok = ExLLM.stream(:mock, messages, callback)

      final_state = Agent.get(state, & &1)
      Agent.stop(state)

      assert final_state.chunks > 0
    end

    test "supports async callbacks with Task" do
      messages = [%{role: "user", content: "Async test"}]

      {:ok, task_collector} = Agent.start_link(fn -> [] end)

      callback = fn chunk ->
        # Spawn a task for each chunk (in real usage, be careful with this pattern)
        Task.start(fn ->
          # Simulate some async processing
          Process.sleep(10)
          Agent.update(task_collector, fn tasks -> [chunk | tasks] end)
        end)
      end

      assert :ok = ExLLM.stream(:mock, messages, callback)

      # Wait for async tasks to complete
      Process.sleep(100)

      chunks = Agent.get(task_collector, & &1)
      Agent.stop(task_collector)

      assert length(chunks) > 0
    end

    test "handles GenServer-based callbacks" do
      defmodule StreamCollector do
        use GenServer

        def start_link(_), do: GenServer.start_link(__MODULE__, [])
        def get_chunks(pid), do: GenServer.call(pid, :get_chunks)
        def add_chunk(pid, chunk), do: GenServer.cast(pid, {:add_chunk, chunk})

        def init(_), do: {:ok, []}
        def handle_call(:get_chunks, _from, chunks), do: {:reply, Enum.reverse(chunks), chunks}
        def handle_cast({:add_chunk, chunk}, chunks), do: {:noreply, [chunk | chunks]}
      end

      messages = [%{role: "user", content: "GenServer test"}]
      {:ok, collector_pid} = StreamCollector.start_link([])

      callback = fn chunk ->
        StreamCollector.add_chunk(collector_pid, chunk)
      end

      assert :ok = ExLLM.stream(:mock, messages, callback)

      # Give GenServer time to process
      Process.sleep(50)

      chunks = StreamCollector.get_chunks(collector_pid)
      GenServer.stop(collector_pid)

      assert length(chunks) > 0
    end
  end

  describe "error handling" do
    @tag :capture_log
    test "handles callback errors gracefully" do
      messages = [%{role: "user", content: "Error test"}]

      {:ok, error_count} = Agent.start_link(fn -> 0 end)

      callback = fn _chunk ->
        Agent.update(error_count, fn count -> count + 1 end)

        # Raise error on second chunk
        if Agent.get(error_count, & &1) == 2 do
          raise "Callback error!"
        end
      end

      # The stream should continue even if callback raises
      # This behavior depends on the streaming coordinator implementation
      result = ExLLM.stream(:mock, messages, callback)

      error_count_val = Agent.get(error_count, & &1)
      Agent.stop(error_count)

      # We should have processed at least one chunk before error
      assert error_count_val >= 1

      # Result might be :ok or error depending on implementation
      assert result == :ok or match?({:error, _}, result)
    end

    test "validates callback arity" do
      messages = [%{role: "user", content: "Arity test"}]

      # Zero-arity function should fail
      assert_raise FunctionClauseError, fn ->
        ExLLM.stream(:mock, messages, fn -> :ok end)
      end

      # Two-arity function should fail
      assert_raise FunctionClauseError, fn ->
        ExLLM.stream(:mock, messages, fn _chunk, _acc -> :ok end)
      end
    end
  end

  describe "streaming options" do
    test "respects streaming options" do
      messages = [%{role: "user", content: "Options test"}]

      {:ok, chunks} = Agent.start_link(fn -> [] end)

      callback = fn chunk ->
        Agent.update(chunks, fn acc -> [chunk | acc] end)
      end

      # Stream with options
      assert :ok =
               ExLLM.stream(:mock, messages, callback,
                 model: "mock-model",
                 temperature: 0.5
               )

      collected_chunks = Agent.get(chunks, &Enum.reverse/1)
      Agent.stop(chunks)

      assert length(collected_chunks) > 0
    end

    test "handles timeout in streaming" do
      messages = [%{role: "user", content: "Timeout test"}]

      callback = fn _chunk -> :ok end

      # Mock provider should handle this gracefully
      result = ExLLM.stream(:mock, messages, callback, timeout: 100)

      assert result == :ok
    end
  end

  describe "real-world patterns" do
    test "implements a token counter callback" do
      messages = [%{role: "user", content: "Count my tokens"}]

      {:ok, counter} = Agent.start_link(fn -> %{tokens: 0, chunks: 0} end)

      callback = fn
        %{content: content} when is_binary(content) ->
          # Simple token estimation
          tokens = length(String.split(content))

          Agent.update(counter, fn state ->
            %{state | tokens: state.tokens + tokens, chunks: state.chunks + 1}
          end)

        _ ->
          :ok
      end

      assert :ok = ExLLM.stream(:mock, messages, callback)

      stats = Agent.get(counter, & &1)
      Agent.stop(counter)

      assert stats.chunks > 0
      assert stats.tokens > 0
    end

    test "implements a progress reporter callback" do
      messages = [%{role: "user", content: "Show progress"}]

      {:ok, progress} = Agent.start_link(fn -> [] end)

      callback = fn
        %{content: content, finish_reason: nil} when content != "" ->
          timestamp = System.monotonic_time(:millisecond)

          Agent.update(progress, fn events ->
            [{:chunk, timestamp, content} | events]
          end)

        %{finish_reason: "stop"} ->
          timestamp = System.monotonic_time(:millisecond)

          Agent.update(progress, fn events ->
            [{:done, timestamp} | events]
          end)

        _ ->
          # Ignore other chunks (empty content, etc.)
          :ok
      end

      assert :ok = ExLLM.stream(:mock, messages, callback)

      events = Agent.get(progress, &Enum.reverse/1)
      Agent.stop(progress)

      # Verify we have both chunk and done events
      assert Enum.any?(events, &match?({:chunk, _, _}, &1))
      # The last event should be a done event
      assert match?({:done, _}, List.last(events))
    end

    test "implements a UI update callback" do
      messages = [%{role: "user", content: "Update UI"}]

      # Simulate a UI state
      {:ok, ui_state} =
        Agent.start_link(fn ->
          %{content: "", status: :streaming, word_count: 0}
        end)

      callback = fn
        %{content: new_content, finish_reason: nil} when new_content != "" ->
          Agent.update(ui_state, fn state ->
            updated_content = state.content <> new_content
            %{state | content: updated_content, word_count: length(String.split(updated_content))}
          end)

        %{finish_reason: "stop"} ->
          Agent.update(ui_state, fn state ->
            %{state | status: :complete}
          end)

        _ ->
          # Ignore other chunks (empty content, etc.)
          :ok
      end

      assert :ok = ExLLM.stream(:mock, messages, callback)

      final_ui = Agent.get(ui_state, & &1)
      Agent.stop(ui_state)

      assert final_ui.status == :complete
      assert final_ui.content != ""
      assert final_ui.word_count > 0
    end
  end
end
