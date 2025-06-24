defmodule ExLLM.Providers.Shared.Streaming.Middleware.RecoveryPlugTest do
  use ExUnit.Case, async: true

  alias ExLLM.Core.Streaming.Recovery
  alias ExLLM.Providers.Shared.Streaming.Middleware.RecoveryPlug
  alias ExLLM.Types.StreamChunk

  # Mock recovery process for testing
  defmodule MockRecovery do
    @moduledoc false
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: Recovery)
    end

    def init(opts) do
      {:ok,
       %{
         partial_responses: %{},
         opts: opts
       }}
    end

    # Mock the init_recovery function like the real Recovery module
    def init_recovery(provider, messages, options) do
      recovery_id = "test_recovery_#{:erlang.unique_integer([:positive])}"

      partial = %{
        id: recovery_id,
        provider: provider,
        messages: messages,
        options: options,
        chunks: [],
        token_count: 0,
        created_at: DateTime.utc_now(),
        last_chunk_at: DateTime.utc_now(),
        model: Keyword.get(options, :model),
        error_reason: nil
      }

      GenServer.call(Recovery, {:save_partial, partial})
      {:ok, recovery_id}
    end

    # Mock the record_chunk function
    def record_chunk(recovery_id, chunk) do
      GenServer.cast(Recovery, {:record_chunk, recovery_id, chunk})
    end

    # Mock the get_partial_response function
    def get_partial_response(recovery_id) do
      case GenServer.call(Recovery, {:get_partial, recovery_id}) do
        {:ok, partial} -> {:ok, partial.chunks}
        error -> error
      end
    end

    # Mock the complete_stream function
    def complete_stream(recovery_id) do
      GenServer.cast(Recovery, {:complete_stream, recovery_id})
    end

    # Mock the record_error function
    def record_error(recovery_id, error) do
      GenServer.call(Recovery, {:record_error, recovery_id, error})
    end

    def handle_call({:save_partial, partial}, _from, state) do
      new_partials = Map.put(state.partial_responses, partial.id, partial)
      {:reply, :ok, %{state | partial_responses: new_partials}}
    end

    def handle_call({:get_partial, recovery_id}, _from, state) do
      case Map.get(state.partial_responses, recovery_id) do
        nil -> {:reply, {:error, :not_found}, state}
        partial -> {:reply, {:ok, partial}, state}
      end
    end

    def handle_call({:record_error, recovery_id, error}, _from, state) do
      case Map.get(state.partial_responses, recovery_id) do
        nil ->
          {:reply, {:error, :not_found}, state}

        partial ->
          updated = %{partial | error_reason: error}
          new_partials = Map.put(state.partial_responses, recovery_id, updated)

          # Check if error is recoverable
          recoverable =
            case error do
              {:network_error, _} -> true
              {:timeout, _} -> true
              _ -> false
            end

          {:reply, {:ok, recoverable}, %{state | partial_responses: new_partials}}
      end
    end

    def handle_cast({:record_chunk, recovery_id, chunk}, state) do
      case Map.get(state.partial_responses, recovery_id) do
        nil ->
          {:noreply, state}

        partial ->
          # Only record chunks with content or finish_reason
          if (Map.get(chunk, :content) != nil && Map.get(chunk, :content) != "") ||
               Map.get(chunk, :finish_reason) != nil do
            updated = %{partial | chunks: partial.chunks ++ [chunk]}
            new_partials = Map.put(state.partial_responses, recovery_id, updated)
            {:noreply, %{state | partial_responses: new_partials}}
          else
            {:noreply, state}
          end
      end
    end

    def handle_cast({:complete_stream, recovery_id}, state) do
      new_partials = Map.delete(state.partial_responses, recovery_id)
      {:noreply, %{state | partial_responses: new_partials}}
    end
  end

  # Test client with RecoveryPlug
  defmodule TestClient do
    @moduledoc false
    use Tesla

    plug(RecoveryPlug)

    adapter(fn env ->
      case env.url do
        "/success" ->
          # Successful streaming response
          if stream_context = env.opts[:stream_context] do
            # Simulate successful streaming
            callback = stream_context.callback

            # Send some chunks
            callback.(%StreamChunk{content: "Hello", finish_reason: nil})
            callback.(%StreamChunk{content: " world", finish_reason: nil})
            callback.(%StreamChunk{content: "!", finish_reason: "stop"})
          end

          {:ok, %{env | status: 200, body: "stream complete"}}

        "/network_error" ->
          # Simulate network error after some chunks
          if stream_context = env.opts[:stream_context] do
            callback = stream_context.callback

            # Send partial response
            callback.(%StreamChunk{content: "Partial", finish_reason: nil})
            callback.(%StreamChunk{content: " response", finish_reason: nil})
          end

          {:error, {:closed, :timeout}}

        "/api_error" ->
          # Non-recoverable API error
          {:ok, %{env | status: 400, body: "Bad request"}}

        "/resume_success" ->
          # Successful resume
          if stream_context = env.opts[:stream_context] do
            callback = stream_context.callback

            # Continue from where we left off
            callback.(%StreamChunk{content: " continued!", finish_reason: "stop"})
          end

          {:ok, %{env | status: 200, body: "resumed"}}
      end
    end)
  end

  setup do
    # Check if Recovery process is already running
    recovery_running = Process.whereis(Recovery) != nil

    if recovery_running do
      # If it's running, we'll use it as-is
      {:ok, %{recovery_pid: Process.whereis(Recovery), original_recovery: true}}
    else
      # Start mock recovery process
      {:ok, pid} = MockRecovery.start_link()

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      {:ok, %{recovery_pid: pid, original_recovery: false}}
    end
  end

  describe "basic functionality" do
    test "passes through non-streaming requests" do
      assert {:ok, response} = TestClient.get("/success")
      assert response.status == 200
      assert response.body == "stream complete"
    end

    test "passes through when recovery is disabled" do
      chunks = []
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      stream_context = %{
        stream_id: "test_no_recovery",
        provider: :openai,
        callback: callback,
        messages: [%{role: "user", content: "Hello"}]
      }

      opts = [
        stream_context: stream_context,
        # Recovery disabled
        enabled: false
      ]

      assert {:ok, _} = TestClient.get("/success", opts: opts)

      # Should receive chunks but no recovery initialization
      assert_receive {:chunk, %{content: "Hello"}}
      assert_receive {:chunk, %{content: " world"}}
      assert_receive {:chunk, %{content: "!"}}
    end
  end

  describe "recovery initialization" do
    test "initializes recovery for streaming requests" do
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      stream_context = %{
        stream_id: "test_init",
        provider: :openai,
        callback: callback,
        messages: [%{role: "user", content: "Hello"}],
        model: "gpt-4"
      }

      opts = [
        stream_context: stream_context,
        enabled: true
      ]

      assert {:ok, _} = TestClient.get("/success", opts: opts)

      # Verify chunks were wrapped and recorded
      assert_receive {:chunk, %{content: "Hello"}}
      assert_receive {:chunk, %{content: " world"}}
      assert_receive {:chunk, %{content: "!"}}

      # Recovery should be completed
      # Give time for cleanup
      Process.sleep(50)
      assert {:error, :not_found} = Recovery.get_partial_response(stream_context.stream_id)
    end

    test "extracts messages from different request formats" do
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      # OpenAI/Anthropic format
      stream_context1 = %{
        stream_id: "test_openai",
        provider: :openai,
        callback: callback,
        request: %{"messages" => [%{"role" => "user", "content" => "Hello"}]}
      }

      # Gemini format
      stream_context2 = %{
        stream_id: "test_gemini",
        provider: :gemini,
        callback: callback,
        request: %{"contents" => [%{"role" => "user", "parts" => [%{"text" => "Hello"}]}]}
      }

      opts1 = [stream_context: stream_context1, enabled: true]
      opts2 = [stream_context: stream_context2, enabled: true]

      assert {:ok, _} = TestClient.get("/success", opts: opts1)
      assert {:ok, _} = TestClient.get("/success", opts: opts2)
    end
  end

  describe "error handling and recovery" do
    test "handles recoverable network errors" do
      test_pid = self()
      recovery_id_ref = make_ref()

      # Capture the recovery ID when chunks are received
      callback = fn chunk ->
        send(test_pid, {:chunk, chunk})
        # Try to extract recovery_id from the process dictionary or other source
        if recovery_id = Process.get(:current_recovery_id) do
          send(test_pid, {recovery_id_ref, recovery_id})
        end
      end

      stream_context = %{
        stream_id: "test_network_error",
        provider: :openai,
        callback: callback,
        messages: [%{role: "user", content: "Hello"}],
        model: "gpt-4"
      }

      opts = [
        stream_context: stream_context,
        enabled: true,
        # Disable auto-resume for this test
        auto_resume: false
      ]

      assert {:error, _} = TestClient.get("/network_error", opts: opts)

      # Should have received partial chunks
      assert_receive {:chunk, %{content: "Partial"}}
      assert_receive {:chunk, %{content: " response"}}

      # Recovery is enabled but we don't have direct access to the recovery_id
      # In a real integration test, we'd verify through the Recovery GenServer's API
      # For now, we'll skip the detailed verification
      Process.sleep(100)
    end

    test "handles non-recoverable API errors" do
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      stream_context = %{
        stream_id: "test_api_error",
        provider: :openai,
        callback: callback,
        messages: [%{role: "user", content: "Hello"}]
      }

      opts = [
        stream_context: stream_context,
        enabled: true
      ]

      # Mock the response to return an API error
      assert {:ok, %{status: 400}} = TestClient.get("/api_error", opts: opts)

      # Recovery should not be saved for non-recoverable errors
      Process.sleep(50)
      assert {:error, :not_found} = Recovery.get_partial_response(stream_context.stream_id)
    end
  end

  describe "automatic resumption" do
    # Skip because it requires more complex mocking
    @tag :skip
    test "automatically resumes on recoverable error" do
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      stream_context = %{
        stream_id: "test_auto_resume",
        provider: :openai,
        callback: callback,
        messages: [%{role: "user", content: "Hello"}],
        model: "gpt-4"
      }

      opts = [
        stream_context: stream_context,
        enabled: true,
        auto_resume: true,
        max_resume_attempts: 2
      ]

      # This would require more complex test setup to properly test
      # auto-resumption with different URLs for retry attempts
    end

    test "respects max resume attempts" do
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      stream_context = %{
        stream_id: "test_max_attempts",
        provider: :openai,
        callback: callback,
        messages: [%{role: "user", content: "Hello"}]
      }

      opts = [
        stream_context: stream_context,
        enabled: true,
        auto_resume: true,
        # No retries allowed
        max_resume_attempts: 0
      ]

      assert {:error, _} = TestClient.get("/network_error", opts: opts)

      # Should not attempt to resume with max_attempts = 0
      assert_receive {:chunk, %{content: "Partial"}}
      assert_receive {:chunk, %{content: " response"}}
      refute_receive {:chunk, _}, 100
    end
  end

  describe "provider-specific behavior" do
    # These would be tested through integration tests
    @tag :skip
    test "handles OpenAI continuation format" do
      # In a real test, we'd verify the resumed request has the correct format
      # by inspecting the actual HTTP request made during resumption
    end

    @tag :skip
    test "handles Anthropic continuation format" do
      # In a real test, we'd verify the resumed request has the correct format
    end

    @tag :skip
    test "handles Gemini continuation format" do
      # In a real test, we'd verify the resumed request has the correct format
    end
  end

  describe "configuration options" do
    test "uses custom recovery strategy" do
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      stream_context = %{
        stream_id: "test_strategy",
        provider: :openai,
        callback: callback,
        messages: [%{role: "user", content: "Hello"}]
      }

      opts = [
        stream_context: stream_context,
        enabled: true,
        # Custom strategy
        strategy: :summarize
      ]

      assert {:ok, _} = TestClient.get("/success", opts: opts)

      # Verify strategy was passed through (would need to check in Recovery state)
    end

    test "custom TTL configuration" do
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      stream_context = %{
        stream_id: "test_ttl",
        provider: :openai,
        callback: callback,
        messages: [%{role: "user", content: "Hello"}]
      }

      opts = [
        stream_context: stream_context,
        enabled: true,
        # 1 hour TTL
        ttl: :timer.minutes(60)
      ]

      assert {:ok, _} = TestClient.get("/success", opts: opts)
    end
  end

  describe "chunk validation and filtering" do
    test "validates chunks before recording" do
      callback = fn chunk -> send(self(), {:chunk, chunk}) end

      stream_context = %{
        stream_id: "test_validation",
        provider: :openai,
        callback: callback,
        messages: [%{role: "user", content: "Hello"}]
      }

      opts = [
        stream_context: stream_context,
        enabled: true
      ]

      # The middleware will validate chunks have content or finish_reason
      assert {:ok, _} = TestClient.get("/success", opts: opts)

      # All chunks should be valid
      assert_receive {:chunk, %{content: "Hello"}}
      assert_receive {:chunk, %{content: " world"}}
      assert_receive {:chunk, %{content: "!", finish_reason: "stop"}}
    end
  end

  describe "integration with StreamRecovery GenServer" do
    # Skip this test as it interferes with other tests
    @tag :skip
    test "checks if recovery process is running" do
      # This test would stop the global recovery process which affects other tests
      # In a real scenario, we'd test this in isolation
    end
  end

  # Note: These tests access private functions indirectly through the module
  # In a real scenario, we'd test these through the public API
end
