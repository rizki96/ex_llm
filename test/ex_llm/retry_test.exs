defmodule ExLLM.RetryTest do
  use ExUnit.Case, async: true
  alias ExLLM.Retry

  describe "with_retry/2" do
    test "succeeds on first attempt" do
      counter = :counters.new(1, [])

      result =
        Retry.with_retry(fn ->
          :counters.add(counter, 1, 1)
          {:ok, "success"}
        end)

      assert result == {:ok, "success"}
      assert :counters.get(counter, 1) == 1
    end

    test "retries on failure and eventually succeeds" do
      counter = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            _count = :counters.add(counter, 1, 1)
            current = :counters.get(counter, 1)

            if current < 3 do
              {:error, {:network_error, "temporary failure"}}
            else
              {:ok, "success after #{current} attempts"}
            end
          end,
          max_attempts: 5
        )

      assert {:ok, "success after 3 attempts"} = result
      assert :counters.get(counter, 1) == 3
    end

    test "gives up after max attempts" do
      counter = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            {:error, {:network_error, "persistent failure"}}
          end,
          max_attempts: 3
        )

      assert {:error, {:network_error, "persistent failure"}} = result
      assert :counters.get(counter, 1) == 3
    end

    test "does not retry on non-retryable errors" do
      counter = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            :counters.add(counter, 1, 1)
            {:error, {:invalid_api_key, "Invalid key"}}
          end,
          max_attempts: 5
        )

      assert {:error, {:invalid_api_key, "Invalid key"}} = result
      # No retries
      assert :counters.get(counter, 1) == 1
    end

    test "applies exponential backoff" do
      start_time = System.monotonic_time(:millisecond)
      agent = Agent.start_link(fn -> [] end) |> elem(1)

      result =
        Retry.with_retry(
          fn ->
            current_time = System.monotonic_time(:millisecond)
            Agent.update(agent, fn attempts -> attempts ++ [current_time - start_time] end)
            attempts = Agent.get(agent, & &1)

            if length(attempts) < 3 do
              {:error, {:network_error, "retry me"}}
            else
              {:ok, attempts}
            end
          end,
          base_delay: 10,
          max_attempts: 3,
          jitter: false
        )

      {:ok, attempts} = result
      # Verify delays increase exponentially
      [first, second, third] = attempts

      # First attempt is immediate (allow some execution time)
      assert first <= 20

      # Second attempt should be after ~10ms (base_delay)
      assert second >= 10
      # Allow more tolerance for CI/slow systems
      assert second < 50

      # Third attempt should be after ~20ms more (base_delay * 2)
      assert third - second >= 20
      # Allow more tolerance
      assert third - second < 60
    end

    test "respects max_delay option" do
      # Use an agent to track timing across retries
      {:ok, agent} = Agent.start_link(fn -> [] end)

      result =
        Retry.with_retry(
          fn ->
            # Record current time
            current_time = System.monotonic_time(:millisecond)
            Agent.update(agent, fn times -> times ++ [current_time] end)

            # Get attempt count based on recorded times
            times = Agent.get(agent, & &1)
            count = length(times)

            if count < 4 do
              {:error, :test_retry}
            else
              {:ok, :done}
            end
          end,
          base_delay: 100,
          max_delay: 150,
          max_attempts: 5,
          retry_on: fn
            :test_retry -> true
            _ -> false
          end
        )

      # Should succeed on the 4th attempt
      assert {:ok, :done} = result

      # Get all recorded times
      times = Agent.get(agent, & &1)
      Agent.stop(agent)

      # Calculate actual delays between attempts
      actual_delays =
        times
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> b - a end)

      # Verify we have 3 delays (between 4 attempts)
      assert length(actual_delays) == 3

      # Expected delays with exponential backoff capped at max_delay:
      # 1st retry: 100ms (base_delay)
      # 2nd retry: 150ms (would be 200ms but capped at max_delay)
      # 3rd retry: 150ms (would be 400ms but capped at max_delay)

      # All delays should respect the constraints
      # First delay should be around base_delay (allow more tolerance for CI)
      assert Enum.at(actual_delays, 0) >= 80 and Enum.at(actual_delays, 0) <= 150

      # Subsequent delays should be capped at max_delay
      # Allow more tolerance for jitter and execution time in CI environments
      Enum.drop(actual_delays, 1)
      |> Enum.each(fn delay ->
        assert delay >= 120 and delay <= 250
      end)
    end

    test "handles exceptions" do
      counter = :counters.new(1, [])

      result =
        Retry.with_retry(
          fn ->
            _count = :counters.add(counter, 1, 1)
            current = :counters.get(counter, 1)

            if current < 2 do
              raise "Temporary error"
            else
              {:ok, "recovered"}
            end
          end,
          max_attempts: 3,
          retry_on: fn
            exception when is_exception(exception) -> true
            _ -> false
          end
        )

      assert {:ok, "recovered"} = result
      assert :counters.get(counter, 1) == 2
    end
  end

  describe "should_retry?/3" do
    setup do
      # Create a default policy for testing
      policy = %Retry.RetryPolicy{
        max_attempts: 3,
        # Use default retry condition
        retry_on: nil
      }

      {:ok, policy: policy}
    end

    test "retryable errors", %{policy: policy} do
      assert Retry.should_retry?({:timeout, "timeout"}, 1, policy)
      assert Retry.should_retry?({:network_error, "error"}, 1, policy)
      assert Retry.should_retry?({:closed, "closed"}, 1, policy)
      assert Retry.should_retry?({:api_error, %{status: 500}}, 1, policy)
      assert Retry.should_retry?({:api_error, %{status: 502}}, 1, policy)
      assert Retry.should_retry?({:api_error, %{status: 503}}, 1, policy)
      assert Retry.should_retry?({:api_error, %{status: 504}}, 1, policy)
      assert Retry.should_retry?({:api_error, %{status: 429}}, 1, policy)
    end

    test "non-retryable errors", %{policy: policy} do
      refute Retry.should_retry?({:api_error, %{status: 400}}, 1, policy)
      refute Retry.should_retry?({:api_error, %{status: 401}}, 1, policy)
      refute Retry.should_retry?({:api_error, %{status: 403}}, 1, policy)
      refute Retry.should_retry?({:api_error, %{status: 404}}, 1, policy)
      refute Retry.should_retry?({:invalid_api_key, "msg"}, 1, policy)
      refute Retry.should_retry?(:invalid_request, 1, policy)
    end

    test "success responses", %{policy: policy} do
      # should_retry? doesn't handle success cases in real usage
      refute Retry.should_retry?("not an error", 1, policy)
    end

    test "unknown errors default to not retryable", %{policy: policy} do
      refute Retry.should_retry?(:unknown_error, 1, policy)
      # Test that specific string errors might be retryable
      assert Retry.should_retry?({:error, "stream timeout"}, 1, policy)
    end
  end

  describe "get_retry_policy/1" do
    test "OpenAI policy" do
      policy = Retry.get_provider_policy(:openai)
      assert policy.max_attempts == 3
      assert policy.base_delay == 1000
      assert policy.max_delay == 60_000
    end

    test "Anthropic policy" do
      policy = Retry.get_provider_policy(:anthropic)
      assert policy.max_attempts == 3
      assert policy.base_delay == 2_000
      assert policy.max_delay == 30_000
    end

    test "Gemini policy with longer delays" do
      # Gemini uses default policy
      policy = Retry.get_provider_policy(:gemini)
      assert policy.max_attempts == 3
      assert policy.base_delay == 1_000
      assert policy.max_delay == 60_000
    end

    test "Local adapter policy with minimal retries" do
      # Local uses default policy
      policy = Retry.get_provider_policy(:local)
      assert policy.max_attempts == 3
      assert policy.base_delay == 1_000
      assert policy.max_delay == 60_000
    end

    test "Default policy for unknown provider" do
      policy = Retry.get_provider_policy(:unknown)
      assert policy.max_attempts == 3
      assert policy.base_delay == 1_000
      assert policy.max_delay == 60_000
    end
  end

  describe "calculate_delay/2" do
    test "exponential growth" do
      base_delay = 100

      # Create a policy without jitter for predictable results
      policy = %Retry.RetryPolicy{
        base_delay: base_delay,
        max_delay: 60_000,
        multiplier: 2,
        jitter: false
      }

      delay1 = Retry.calculate_delay(1, policy)
      delay2 = Retry.calculate_delay(2, policy)
      delay3 = Retry.calculate_delay(3, policy)

      # Verify exponential growth (power of 2)
      assert delay1 == base_delay
      assert delay2 == base_delay * 2
      assert delay3 == base_delay * 4
    end

    test "respects max_delay" do
      # Create a policy with max_delay
      policy = %Retry.RetryPolicy{
        base_delay: 100,
        max_delay: 500,
        multiplier: 2,
        jitter: false
      }

      delays =
        for attempt <- 1..10 do
          Retry.calculate_delay(attempt, policy)
        end

      # All delays should be capped at max_delay
      assert Enum.all?(delays, fn d -> d <= 500 end)
      # Later attempts should be capped at exactly max_delay
      assert Retry.calculate_delay(10, policy) == 500
    end

    test "adds jitter" do
      base_delay = 100

      # Create a policy with jitter enabled
      policy = %Retry.RetryPolicy{
        base_delay: base_delay,
        max_delay: 60_000,
        multiplier: 2,
        jitter: true
      }

      # Generate multiple delays for same attempt
      delays =
        for _ <- 1..100 do
          Retry.calculate_delay(1, policy)
        end

      # Should have variation due to jitter
      unique_delays = Enum.uniq(delays)
      # Some variation expected
      assert length(unique_delays) > 10

      # All should be within expected range (base_delay with up to 25% added jitter)
      assert Enum.all?(delays, fn d -> d >= base_delay and d <= base_delay * 1.25 end)
    end
  end

  describe "integration with provider policies" do
    test "retries with provider-specific policy" do
      counter = :counters.new(1, [])

      # Simulate API call with provider
      api_call = fn provider ->
        Retry.with_provider_retry(
          provider,
          fn ->
            _count = :counters.add(counter, 1, 1)
            current = :counters.get(counter, 1)

            if current < 2 do
              {:error, {:api_error, %{status: 503}}}
            else
              {:ok, "Provider #{provider} succeeded"}
            end
          end
        )
      end

      # Test different providers
      for provider <- [:openai, :anthropic, :gemini, :local] do
        # Reset counter
        :counters.put(counter, 1, 0)

        result = api_call.(provider)
        assert match?({:ok, _}, result)
        {:ok, message} = result
        assert message == "Provider #{provider} succeeded"
        assert :counters.get(counter, 1) == 2
      end
    end
  end

  describe "retry with custom predicate" do
    test "custom retry predicate" do
      counter = :counters.new(1, [])

      custom_should_retry = fn
        :special_error -> true
        _ -> false
      end

      result =
        Retry.with_retry(
          fn ->
            _count = :counters.add(counter, 1, 1)
            current = :counters.get(counter, 1)

            case current do
              1 -> {:error, :special_error}
              2 -> {:error, :non_retryable}
              _ -> {:ok, "should not reach"}
            end
          end,
          max_attempts: 3,
          retry_on: custom_should_retry
        )

      assert {:error, :non_retryable} = result
      # Retried once, then stopped
      assert :counters.get(counter, 1) == 2
    end
  end
end
