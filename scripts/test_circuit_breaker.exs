#!/usr/bin/env elixir

# Run with: mix run scripts/test_circuit_breaker.exs

IO.puts("\n=== Testing Circuit Breaker Integration ===\n")

IO.puts("Test 1: Simple success")
result = ExLLM.Retry.with_circuit_breaker_retry(fn ->
  IO.puts("  Function called")
  {:ok, "success"}
end)
IO.puts("  Result: #{inspect(result)}")

IO.puts("\nTest 2: With retries")
attempt = :ets.new(:attempt, [:public])
:ets.insert(attempt, {:count, 0})

result = ExLLM.Retry.with_circuit_breaker_retry(fn ->
  [{:count, count}] = :ets.lookup(attempt, :count)
  :ets.insert(attempt, {:count, count + 1})
  IO.puts("  Attempt #{count + 1}")
  
  if count < 2 do
    {:error, {:network_error, "temporary"}}
  else
    {:ok, "success after retry"}
  end
end, retry: [base_delay: 10, max_attempts: 3])

IO.puts("  Result: #{inspect(result)}")
:ets.delete(attempt)

IO.puts("\nTest 3: Circuit opens after failures")
for i <- 1..3 do
  IO.puts("  Failure #{i}")
  ExLLM.Retry.with_circuit_breaker_retry(fn ->
    {:error, "persistent failure"}
  end, 
  circuit_name: "test_circuit",
  circuit_breaker: [failure_threshold: 3],
  retry: [max_attempts: 2, base_delay: 10])
end

result = ExLLM.Retry.with_circuit_breaker_retry(fn ->
  {:ok, "should not execute"}
end, circuit_name: "test_circuit")
IO.puts("  Circuit state result: #{inspect(result)}")

IO.puts("\nTest 4: Checking circuit breaker alone")
result = ExLLM.CircuitBreaker.call("direct_test", fn ->
  {:ok, "direct success"}
end)
IO.puts("  Direct circuit breaker result: #{inspect(result)}")

IO.puts("\nAll tests completed!")