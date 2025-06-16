#!/usr/bin/env elixir

# Debug retry with circuit breaker

# Start the application to ensure ETS table is initialized
Application.ensure_all_started(:ex_llm)

IO.puts("\n=== Test 1: Simple success ===")

result =
  ExLLM.Retry.with_circuit_breaker_retry(fn ->
    IO.puts("Function called")
    {:ok, "success"}
  end)

IO.puts("Result: #{inspect(result)}")

IO.puts("\n=== Test 2: With retries ===")
attempt = :ets.new(:attempt, [:public])
:ets.insert(attempt, {:count, 0})

result =
  ExLLM.Retry.with_circuit_breaker_retry(
    fn ->
      [{:count, count}] = :ets.lookup(attempt, :count)
      :ets.insert(attempt, {:count, count + 1})
      IO.puts("Attempt #{count + 1}")

      if count < 2 do
        {:error, {:network_error, "temporary"}}
      else
        {:ok, "success after retry"}
      end
    end,
    retry: [base_delay: 10, max_attempts: 3]
  )

IO.puts("Result: #{inspect(result)}")
:ets.delete(attempt)
