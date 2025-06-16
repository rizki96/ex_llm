#!/usr/bin/env elixir

# Circuit Breaker Demo
# Run with: mix run scripts/demo_circuit_breaker.exs

IO.puts("""
====================================
   ExLLM Circuit Breaker Demo
====================================
""")

IO.puts("\n1. Basic Circuit Breaker Protection")
IO.puts("   Simulating intermittent service failures...")

# Simulate a flaky service
service_state = :ets.new(:service_state, [:public])
:ets.insert(service_state, {:state, :healthy})
:ets.insert(service_state, {:call_count, 0})

simulate_service = fn ->
  [{:call_count, count}] = :ets.lookup(service_state, :call_count)
  [{:state, state}] = :ets.lookup(service_state, :state)
  :ets.insert(service_state, {:call_count, count + 1})
  
  # Service fails on calls 3-8
  if count >= 3 and count <= 8 do
    {:error, :service_unavailable}
  else
    {:ok, "Response #{count + 1}"}
  end
end

# Make calls through circuit breaker
for i <- 1..12 do
  result = ExLLM.CircuitBreaker.call("demo_service", simulate_service,
    failure_threshold: 3,
    reset_timeout: 1000
  )
  
  case result do
    {:ok, response} ->
      IO.puts("   Call #{i}: ✅ #{response}")
    {:error, :circuit_open} ->
      IO.puts("   Call #{i}: 🚫 Circuit OPEN - fail fast")
    {:error, reason} ->
      IO.puts("   Call #{i}: ❌ Failed: #{inspect(reason)}")
  end
  
  # Short delay between calls
  Process.sleep(200)
end

IO.puts("\n2. Circuit Breaker with Retry Integration")
IO.puts("   Combining retry logic with circuit protection...")

# Reset service
:ets.insert(service_state, {:call_count, 0})

# Service that needs retries
flaky_service = fn ->
  [{:call_count, count}] = :ets.lookup(service_state, :call_count)
  :ets.insert(service_state, {:call_count, count + 1})
  
  # Fail first 2 attempts, succeed on 3rd
  if rem(count, 3) < 2 do
    {:error, {:network_error, "Temporary failure"}}
  else
    {:ok, "Success after #{div(count, 3) + 1} retry cycles"}
  end
end

# Make calls with retry and circuit breaker
for i <- 1..5 do
  IO.puts("\n   Request #{i}:")
  
  result = ExLLM.Retry.with_circuit_breaker_retry(
    flaky_service,
    circuit_name: "retry_demo",
    circuit_breaker: [failure_threshold: 3, reset_timeout: 2000],
    retry: [max_attempts: 3, base_delay: 100]
  )
  
  case result do
    {:ok, response} ->
      IO.puts("   ✅ #{response}")
    {:error, :circuit_open} ->
      IO.puts("   🚫 Circuit breaker OPEN - request rejected")
    {:error, reason} ->
      IO.puts("   ❌ Failed after retries: #{inspect(reason)}")
  end
end

IO.puts("\n3. Provider-Specific Circuit Breakers")
IO.puts("   Different providers have different reliability patterns...")

# Simulate provider behaviors
simulate_provider = fn provider ->
  case provider do
    :openai -> 
      # OpenAI: Rate limit sensitive
      if :rand.uniform() > 0.7 do
        {:error, {:api_error, %{status: 429, message: "Rate limit exceeded"}}}
      else
        {:ok, "GPT-4 response"}
      end
      
    :anthropic ->
      # Anthropic: Occasionally overloaded
      if :rand.uniform() > 0.8 do
        {:error, {:api_error, %{status: 529, message: "Overloaded"}}}
      else
        {:ok, "Claude response"}
      end
      
    :groq ->
      # Groq: Fast but stricter limits
      if :rand.uniform() > 0.6 do
        {:error, {:api_error, %{status: 429, message: "Too many requests"}}}
      else
        {:ok, "Llama response (fast!)"}
      end
  end
end

providers = [:openai, :anthropic, :groq]

for provider <- providers do
  IO.puts("\n   Testing #{provider}:")
  
  # Make 10 calls to each provider
  success_count = 0
  circuit_open_count = 0
  
  for _ <- 1..10 do
    result = ExLLM.Retry.with_provider_circuit_breaker(
      provider,
      fn -> simulate_provider.(provider) end,
      retry: [max_attempts: 2, base_delay: 50]
    )
    
    case result do
      {:ok, _} -> success_count = success_count + 1
      {:error, :circuit_open} -> circuit_open_count = circuit_open_count + 1
      _ -> :ok
    end
    
    Process.sleep(10)
  end
  
  {:ok, stats} = ExLLM.CircuitBreaker.get_stats(:"#{provider}_circuit")
  
  IO.puts("   Results: #{success_count}/10 successful, Circuit opened #{circuit_open_count} times")
  IO.puts("   Circuit state: #{stats.state}, Failures: #{stats.failure_count}")
end

IO.puts("\n4. Circuit Breaker Statistics")
IO.puts("   Real-time monitoring of circuit states...")

# Get all circuit statistics
circuits = ["demo_service", "retry_demo", :openai_circuit, :anthropic_circuit, :groq_circuit]

IO.puts("\n   Circuit Status Summary:")
IO.puts("   " <> String.duplicate("─", 60))
IO.puts("   Circuit              State      Failures  Last Failure")
IO.puts("   " <> String.duplicate("─", 60))

for circuit <- circuits do
  case ExLLM.CircuitBreaker.get_stats(circuit) do
    {:ok, stats} ->
      state_icon = case stats.state do
        :closed -> "🟢"
        :open -> "🔴"
        :half_open -> "🟡"
      end
      
      last_failure = if stats.last_failure_time do
        "#{div(System.monotonic_time(:millisecond) - stats.last_failure_time, 1000)}s ago"
      else
        "Never"
      end
      
      circuit_name = circuit |> to_string() |> String.pad_trailing(20)
      state = "#{state_icon} #{stats.state}" |> String.pad_trailing(12)
      failures = stats.failure_count |> to_string() |> String.pad_trailing(9)
      
      IO.puts("   #{circuit_name}#{state}#{failures}#{last_failure}")
    {:error, :circuit_not_found} ->
      :ok
  end
end

IO.puts("   " <> String.duplicate("─", 60))

IO.puts("""

====================================
Demo Complete!

The circuit breaker pattern helps:
✅ Prevent cascading failures
✅ Fail fast when services are down  
✅ Automatically recover when healthy
✅ Reduce load on struggling services

Combined with retry logic, it provides
robust fault tolerance for LLM APIs.
====================================
""")

:ets.delete(service_state)