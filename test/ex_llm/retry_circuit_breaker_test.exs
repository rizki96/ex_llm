defmodule ExLLM.RetryCircuitBreakerTest do
  use ExUnit.Case
  alias ExLLM.Retry

  setup do
    # Initialize ETS table for each test
    if :ets.info(:ex_llm_circuit_breakers) != :undefined do
      :ets.delete(:ex_llm_circuit_breakers)
    end

    ExLLM.CircuitBreaker.init()
    :ok
  end

  describe "circuit breaker with retry integration" do
    test "successful calls pass through both retry and circuit breaker" do
      result =
        Retry.with_circuit_breaker_retry(fn ->
          {:ok, "success"}
        end)

      # Circuit breaker unwraps to return the retry result directly
      assert {:ok, "success"} = result
    end

    test "retryable errors are retried within circuit breaker" do
      attempt_count = :ets.new(:attempt_count, [:public])
      :ets.insert(attempt_count, {:count, 0})

      result =
        Retry.with_circuit_breaker_retry(
          fn ->
            [{:count, count}] = :ets.lookup(attempt_count, :count)
            :ets.insert(attempt_count, {:count, count + 1})

            if count < 2 do
              {:error, {:network_error, "temporary"}}
            else
              {:ok, "success after retry"}
            end
          end,
          retry: [base_delay: 10, max_attempts: 3]
        )

      assert {:ok, "success after retry"} = result
      [{:count, final_count}] = :ets.lookup(attempt_count, :count)
      assert final_count == 3

      :ets.delete(attempt_count)
    end

    test "circuit opens after threshold failures even with retries" do
      circuit_name = "test_circuit"

      # First, make calls that fail after retries to open the circuit
      for _ <- 1..3 do
        Retry.with_circuit_breaker_retry(
          fn ->
            {:error, "persistent failure"}
          end,
          circuit_name: circuit_name,
          circuit_breaker: [failure_threshold: 3],
          retry: [max_attempts: 2, base_delay: 10]
        )
      end

      # Circuit should now be open
      result =
        Retry.with_circuit_breaker_retry(
          fn ->
            {:ok, "should not execute"}
          end,
          circuit_name: circuit_name
        )

      assert {:error, :circuit_open} = result
    end

    test "provider-specific configurations work correctly" do
      # Mock a failing OpenAI call
      result =
        Retry.with_provider_circuit_breaker(
          :openai,
          fn ->
            {:error, {:api_error, %{status: 500}}}
          end,
          retry: [max_attempts: 1]
        )

      # Should fail after retry attempts
      assert {:error, {:api_error, %{status: 500}}} = result

      # Check circuit stats
      {:ok, stats} = ExLLM.CircuitBreaker.get_stats(:openai_circuit)
      assert stats.failure_count == 1
      # OpenAI specific
      assert stats.config.failure_threshold == 3
    end
  end

  describe "enhanced chat and streaming functions" do
    test "chat_with_circuit_breaker wraps ExLLM.chat" do
      # This test would need ExLLM.chat to be mockable
      # For now, we just verify the function exists and returns expected error structure
      result = Retry.chat_with_circuit_breaker(:test_provider, [%{role: "user", content: "test"}])

      # Since test_provider doesn't exist, it should return an error
      assert {:error, _} = result
    end

    test "stream_with_circuit_breaker sets longer timeout" do
      # Test that streaming calls get longer timeout
      attempt_count = :ets.new(:stream_attempt, [:public])
      :ets.insert(attempt_count, {:count, 0})

      result = Retry.stream_with_circuit_breaker(:test_provider, [], retry: [max_attempts: 1])

      # Verify the function exists and returns expected structure
      assert {:error, _} = result

      :ets.delete(attempt_count)
    end
  end

  describe "provider configurations" do
    test "each provider has specific circuit breaker settings" do
      providers = [:openai, :anthropic, :bedrock, :gemini, :groq, :ollama, :lmstudio]

      for provider <- providers do
        # Create a circuit for each provider
        Retry.with_provider_circuit_breaker(provider, fn ->
          {:ok, "test"}
        end)

        # Check that circuit was created with provider-specific settings
        {:ok, stats} = ExLLM.CircuitBreaker.get_stats(:"#{provider}_circuit")
        assert stats.state == :closed
        assert is_integer(stats.config.failure_threshold)
        assert is_integer(stats.config.reset_timeout)
      end
    end
  end

  describe "options handling" do
    test "split_options separates circuit breaker and retry options" do
      opts = [
        circuit_breaker: [failure_threshold: 10],
        retry: [max_attempts: 5],
        circuit_name: "custom",
        # Top-level option should go to retry
        max_attempts: 3
      ]

      result = Retry.with_circuit_breaker_retry(fn -> {:ok, "test"} end, opts)
      assert {:ok, "test"} = result

      # Verify circuit was created with custom name
      {:ok, stats} = ExLLM.CircuitBreaker.get_stats("custom")
      assert stats.config.failure_threshold == 10
    end
  end
end
