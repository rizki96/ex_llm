#!/usr/bin/env elixir

# ExLLM Performance Benchmarking Script
#
# This script benchmarks various aspects of ExLLM pipeline performance
# and demonstrates the impact of optimization strategies.

Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

defmodule PerformanceBenchmark do
  @moduledoc """
  Comprehensive performance benchmarking for ExLLM pipelines.
  """

  alias ExLLM.Benchmark
  alias ExLLM.PipelineOptimizer

  def run_full_benchmark() do
    IO.puts("🚀 Starting ExLLM Performance Benchmark")
    IO.puts("======================================\n")

    # Test messages
    messages = [
      %{role: "system", content: "You are a helpful assistant."},
      %{role: "user", content: "Hello! How are you today?"}
    ]

    # 1. Basic chat performance
    IO.puts("📊 1. Basic Chat Performance")
    basic_results = benchmark_basic_chat(messages)
    print_benchmark_results("Basic Chat", basic_results)

    # 2. Pipeline overhead analysis
    IO.puts("\n📊 2. Pipeline Overhead Analysis")
    overhead_results = benchmark_pipeline_overhead()
    print_overhead_results(overhead_results)

    # 3. Builder API vs Direct API
    IO.puts("\n📊 3. Builder API vs Direct API Performance")
    builder_results = benchmark_builder_vs_direct(messages)
    print_comparison_results("Builder vs Direct", builder_results)

    # 4. Optimization strategies
    IO.puts("\n📊 4. Pipeline Optimization Impact")
    optimization_results = benchmark_optimizations(messages)
    print_optimization_results(optimization_results)

    # 5. Memory usage analysis
    IO.puts("\n📊 5. Memory Usage Analysis")
    memory_results = benchmark_memory_usage(messages)
    print_memory_results(memory_results)

    # 6. Concurrent performance
    IO.puts("\n📊 6. Concurrent Performance")
    concurrent_results = benchmark_concurrent_performance(messages)
    print_concurrent_results(concurrent_results)

    IO.puts("\n✅ Benchmark completed! Check results above.")
    generate_recommendations(basic_results, optimization_results, memory_results)
  end

  defp benchmark_basic_chat(messages) do
    Benchmark.run_chat_benchmark(:mock, messages, 
      iterations: 1000,
      warmup: 50,
      measure: [:time, :memory]
    )
  end

  defp benchmark_pipeline_overhead() do
    pipeline = ExLLM.Providers.get_pipeline(:mock, :chat)
    Benchmark.benchmark_plug_overhead(pipeline, iterations: 5000)
  end

  defp benchmark_builder_vs_direct(messages) do
    iterations = 500

    # Benchmark direct API
    direct_time = benchmark_function(fn ->
      ExLLM.chat(:mock, messages)
    end, iterations)

    # Benchmark builder API
    builder_time = benchmark_function(fn ->
      ExLLM.build(:mock, messages)
      |> ExLLM.with_model("test-model")
      |> ExLLM.execute()
    end, iterations)

    %{
      direct_api: %{mean_time: direct_time, iterations: iterations},
      builder_api: %{mean_time: builder_time, iterations: iterations},
      overhead_percent: ((builder_time - direct_time) / direct_time) * 100
    }
  end

  defp benchmark_optimizations(messages) do
    # Configure optimizer
    PipelineOptimizer.configure(
      enabled: true,
      strategies: [:reorder_plugs, :eliminate_dead_code, :fast_path]
    )

    pipeline = ExLLM.Providers.get_pipeline(:mock, :chat)
    
    results = PipelineOptimizer.benchmark_optimization(:mock, pipeline, messages,
      iterations: 500,
      strategies: [:reorder_plugs, :eliminate_dead_code]
    )

    # Disable optimizer for fair comparison
    PipelineOptimizer.configure(enabled: false)
    
    results
  end

  defp benchmark_memory_usage(messages) do
    # Test different scenarios
    scenarios = [
      {"Simple chat", fn -> ExLLM.chat(:mock, messages) end},
      {"Builder with cache", fn ->
        ExLLM.build(:mock, messages)
        |> ExLLM.with_cache(ttl: 3600)
        |> ExLLM.execute()
      end},
      {"Long conversation", fn ->
        long_messages = Enum.map(1..20, fn i ->
          %{role: if(rem(i, 2) == 0, do: "user", else: "assistant"), 
            content: "Message #{i}: " <> String.duplicate("word ", 50)}
        end)
        ExLLM.chat(:mock, long_messages)
      end}
    ]

    Enum.map(scenarios, fn {name, fun} ->
      result = Benchmark.profile_memory(fun)
      {name, result}
    end)
    |> Map.new()
  end

  defp benchmark_concurrent_performance(messages) do
    concurrency_levels = [1, 5, 10, 25, 50]
    
    Enum.map(concurrency_levels, fn concurrency ->
      result = benchmark_concurrent_requests(messages, concurrency, 100)
      {concurrency, result}
    end)
    |> Map.new()
  end

  defp benchmark_concurrent_requests(messages, concurrency, total_requests) do
    requests_per_task = div(total_requests, concurrency)
    
    {total_time, results} = :timer.tc(fn ->
      1..concurrency
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Enum.map(1..requests_per_task, fn _ ->
            {time, _result} = :timer.tc(fn ->
              ExLLM.chat(:mock, messages)
            end)
            time
          end)
        end)
      end)
      |> Enum.map(&Task.await(&1, 30_000))
      |> List.flatten()
    end)

    %{
      concurrency: concurrency,
      total_time: total_time,
      total_requests: length(results),
      average_request_time: Enum.sum(results) / length(results),
      requests_per_second: length(results) / (total_time / 1_000_000),
      throughput_improvement: length(results) / (total_time / 1_000_000) / concurrency
    }
  end

  defp benchmark_function(fun, iterations) do
    # Warmup
    Enum.each(1..10, fn _ -> fun.() end)
    
    # Benchmark
    {total_time, _} = :timer.tc(fn ->
      Enum.each(1..iterations, fn _ -> fun.() end)
    end)
    
    total_time / iterations
  end

  # Result printing functions

  defp print_benchmark_results(name, results) do
    stats = results.statistics
    IO.puts("#{name}:")
    IO.puts("  Mean: #{format_time(stats.mean)}")
    IO.puts("  P95:  #{format_time(stats.p95)}")
    IO.puts("  P99:  #{format_time(stats.p99)}")
    IO.puts("  Success Rate: #{Float.round(stats.success_rate * 100, 1)}%")
  end

  defp print_overhead_results(results) do
    IO.puts("Pipeline Overhead Analysis:")
    IO.puts("  Empty request: #{format_time(results.empty_request_time)}")
    IO.puts("  Full pipeline: #{format_time(results.full_pipeline_time)}")
    IO.puts("  Efficiency: #{Float.round(results.pipeline_efficiency * 100, 1)}%")
    
    if map_size(results.plug_times) > 0 do
      IO.puts("  Slowest plugs:")
      results.plug_times
      |> Enum.sort_by(fn {_plug, time} -> time end, :desc)
      |> Enum.take(3)
      |> Enum.each(fn {plug, time} ->
        plug_name = plug |> to_string() |> String.split(".") |> List.last()
        IO.puts("    #{plug_name}: #{format_time(time)}")
      end)
    end
  end

  defp print_comparison_results(name, results) do
    IO.puts("#{name}:")
    IO.puts("  Direct API: #{format_time(results.direct_api.mean_time)}")
    IO.puts("  Builder API: #{format_time(results.builder_api.mean_time)}")
    IO.puts("  Overhead: #{Float.round(results.overhead_percent, 1)}%")
  end

  defp print_optimization_results(results) do
    improvement = results.improvement
    IO.puts("Pipeline Optimization Results:")
    IO.puts("  Original: #{format_time(results.original.mean)}")
    IO.puts("  Optimized: #{format_time(results.optimized.mean)}")
    IO.puts("  Improvement: #{Float.round(improvement.time_improvement_percent, 1)}%")
    IO.puts("  Time saved: #{format_time(improvement.absolute_time_saved_microseconds)}")
    IO.puts("  Recommendation: #{results.recommendation}")
  end

  defp print_memory_results(results) do
    IO.puts("Memory Usage Analysis:")
    Enum.each(results, fn {scenario, result} ->
      memory_mb = result.memory_delta.total / (1024 * 1024)
      IO.puts("  #{scenario}:")
      IO.puts("    Execution time: #{format_time(result.execution_time_microseconds)}")
      IO.puts("    Memory delta: #{Float.round(memory_mb, 2)} MB")
    end)
  end

  defp print_concurrent_results(results) do
    IO.puts("Concurrent Performance:")
    Enum.each(results, fn {concurrency, result} ->
      IO.puts("  #{concurrency} concurrent:")
      IO.puts("    RPS: #{Float.round(result.requests_per_second, 1)}")
      IO.puts("    Avg time: #{format_time(result.average_request_time)}")
      IO.puts("    Efficiency: #{Float.round(result.throughput_improvement, 2)}x")
    end)
  end

  defp generate_recommendations(basic_results, optimization_results, memory_results) do
    IO.puts("\n🎯 Performance Recommendations:")
    
    # Basic performance
    mean_time_ms = basic_results.statistics.mean / 1000
    cond do
      mean_time_ms < 1 ->
        IO.puts("✅ Excellent baseline performance (< 1ms)")
      mean_time_ms < 5 ->
        IO.puts("✅ Good baseline performance (< 5ms)")
      true ->
        IO.puts("⚠️  Consider investigating performance bottlenecks (> 5ms)")
    end

    # Optimization impact
    if optimization_results.improvement.time_improvement_percent > 10 do
      IO.puts("✅ Pipeline optimizations show significant benefit - recommend enabling")
    else
      IO.puts("ℹ️  Pipeline optimizations show minor benefit - enable for critical paths only")
    end

    # Memory usage
    max_memory_mb = memory_results
                   |> Enum.map(fn {_name, result} -> result.memory_delta.total / (1024 * 1024) end)
                   |> Enum.max()
    
    if max_memory_mb > 10 do
      IO.puts("⚠️  High memory usage detected - consider memory optimizations")
    else
      IO.puts("✅ Memory usage looks reasonable")
    end

    IO.puts("\n📈 Next Steps:")
    IO.puts("1. Enable pipeline optimizations in production")
    IO.puts("2. Monitor performance metrics in your application")
    IO.puts("3. Consider custom plugs for application-specific optimizations")
    IO.puts("4. Run this benchmark periodically to track performance regression")
  end

  defp format_time(microseconds) when is_number(microseconds) do
    cond do
      microseconds < 1000 ->
        "#{Float.round(microseconds, 1)}μs"
      microseconds < 1_000_000 ->
        "#{Float.round(microseconds / 1000, 2)}ms"
      true ->
        "#{Float.round(microseconds / 1_000_000, 2)}s"
    end
  end
  defp format_time(_), do: "N/A"
end

# Run the benchmark
PerformanceBenchmark.run_full_benchmark()