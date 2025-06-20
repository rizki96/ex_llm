defmodule ExLLM.Benchmark do
  @moduledoc """
  Benchmarking utilities for ExLLM pipeline performance.

  This module provides tools to measure and optimize pipeline performance,
  helping identify bottlenecks and validate optimization strategies.

  ## Usage

      # Benchmark a simple chat operation
      ExLLM.Benchmark.run_chat_benchmark(:openai, messages)
      
      # Benchmark pipeline with different configurations
      ExLLM.Benchmark.compare_pipelines([
        {:baseline, ExLLM.Providers.get_pipeline(:openai, :chat)},
        {:optimized, optimized_pipeline()}
      ])
      
      # Profile memory usage
      ExLLM.Benchmark.profile_memory(fn ->
        ExLLM.chat(:openai, messages)
      end)
  """

  alias ExLLM.Pipeline
  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers
  alias ExLLM.Infrastructure.Logger

  @doc """
  Runs a comprehensive benchmark of chat operations.

  ## Options

    * `:iterations` - Number of iterations to run (default: 100)
    * `:warmup` - Number of warmup iterations (default: 10)
    * `:providers` - List of providers to test (default: [:mock])
    * `:measure` - What to measure (default: [:time, :memory])
    * `:concurrent` - Run concurrent tests (default: false)
    
  ## Examples

      # Basic benchmark
      ExLLM.Benchmark.run_chat_benchmark(:openai, messages)
      
      # Detailed benchmark with options
      ExLLM.Benchmark.run_chat_benchmark(:openai, messages,
        iterations: 1000,
        measure: [:time, :memory, :reductions],
        concurrent: true
      )
  """
  @spec run_chat_benchmark(atom(), list(map()), keyword()) :: map()
  def run_chat_benchmark(provider, messages, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 100)
    warmup = Keyword.get(opts, :warmup, 10)
    measure = Keyword.get(opts, :measure, [:time, :memory])
    concurrent = Keyword.get(opts, :concurrent, false)

    Logger.info("Starting chat benchmark for #{provider} with #{iterations} iterations")

    # Warmup
    warmup_results = run_iterations(provider, messages, warmup, false)
    Logger.debug("Warmup completed: #{inspect(warmup_results.summary)}")

    # Main benchmark
    results =
      if concurrent do
        run_concurrent_iterations(provider, messages, iterations, measure)
      else
        run_iterations(provider, messages, iterations, true, measure)
      end

    # Calculate statistics
    stats = calculate_statistics(results.measurements)

    report = %{
      provider: provider,
      iterations: iterations,
      concurrent: concurrent,
      measurements: measure,
      statistics: stats,
      summary: results.summary,
      raw_data: results.measurements
    }

    Logger.info("Benchmark completed: #{format_summary(stats)}")
    report
  end

  @doc """
  Compares performance of different pipeline configurations.

  ## Examples

      pipelines = [
        {:baseline, ExLLM.Providers.get_pipeline(:openai, :chat)},
        {:with_cache, add_cache_plug(baseline_pipeline)},
        {:optimized, optimized_pipeline()}
      ]
      
      results = ExLLM.Benchmark.compare_pipelines(pipelines, messages)
  """
  @spec compare_pipelines(list({atom(), Pipeline.pipeline()}), list(map()), keyword()) :: map()
  def compare_pipelines(pipeline_configs, messages, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 50)
    provider = Keyword.get(opts, :provider, :mock)

    Logger.info("Comparing #{length(pipeline_configs)} pipeline configurations")

    results =
      Enum.map(pipeline_configs, fn {name, pipeline} ->
        Logger.debug("Benchmarking pipeline: #{name}")

        measurements =
          Enum.map(1..iterations, fn _ ->
            measure_pipeline_execution(provider, messages, pipeline)
          end)

        stats = calculate_statistics(measurements)

        {name,
         %{
           pipeline_length: length(pipeline),
           statistics: stats,
           measurements: measurements
         }}
      end)
      |> Map.new()

    # Generate comparison report
    comparison = generate_comparison_report(results)

    %{
      configurations: results,
      comparison: comparison,
      winner: find_fastest_configuration(results)
    }
  end

  @doc """
  Profiles memory usage of a function.

  ## Examples

      ExLLM.Benchmark.profile_memory(fn ->
        ExLLM.build(:openai, messages)
        |> ExLLM.with_cache()
        |> ExLLM.execute()
      end)
  """
  @spec profile_memory(function()) :: map()
  def profile_memory(fun) when is_function(fun, 0) do
    # Start memory profiling
    :erlang.garbage_collect()
    initial_memory = :erlang.memory()

    # Measure execution
    {time, result} = :timer.tc(fun)

    # Final memory measurement
    :erlang.garbage_collect()
    final_memory = :erlang.memory()

    # Calculate memory delta
    memory_delta =
      Enum.map(initial_memory, fn {type, initial_bytes} ->
        final_bytes = Keyword.get(final_memory, type, 0)
        {type, final_bytes - initial_bytes}
      end)
      |> Map.new()

    %{
      execution_time_microseconds: time,
      result: result,
      memory_delta: memory_delta,
      peak_memory: calculate_peak_memory(initial_memory, final_memory)
    }
  end

  @doc """
  Benchmarks pipeline plug overhead.

  Measures the overhead of individual plugs and pipeline setup.
  """
  @spec benchmark_plug_overhead(Pipeline.pipeline(), keyword()) :: map()
  def benchmark_plug_overhead(pipeline, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 1000)

    # Benchmark empty request creation
    empty_request_time =
      benchmark_function(
        fn ->
          Request.new(:mock, [], %{})
        end,
        iterations
      )

    # Benchmark individual plugs
    request = Request.new(:mock, [%{role: "user", content: "test"}], %{})

    plug_times =
      Enum.map(pipeline, fn plug_spec ->
        {plug, opts} = normalize_plug_spec(plug_spec)

        time =
          benchmark_function(
            fn ->
              if function_exported?(plug, :call, 2) do
                plug.call(request, plug.init(opts))
              else
                request
              end
            end,
            iterations
          )

        {plug, time}
      end)
      |> Map.new()

    # Benchmark full pipeline
    full_pipeline_time =
      benchmark_function(
        fn ->
          Pipeline.run(request, pipeline)
        end,
        # Fewer iterations for full pipeline
        div(iterations, 10)
      )

    %{
      empty_request_time: empty_request_time,
      plug_times: plug_times,
      full_pipeline_time: full_pipeline_time,
      total_plug_overhead: Enum.sum(Map.values(plug_times)),
      pipeline_efficiency: calculate_efficiency(plug_times, full_pipeline_time)
    }
  end

  @doc """
  Stress tests the pipeline under high concurrent load.
  """
  @spec stress_test(atom(), list(map()), keyword()) :: map()
  def stress_test(provider, messages, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 100)
    duration_seconds = Keyword.get(opts, :duration, 30)
    ramp_up_seconds = Keyword.get(opts, :ramp_up, 5)

    Logger.info("Starting stress test: #{concurrency} concurrent, #{duration_seconds}s duration")

    # Start monitoring
    monitor_pid = start_monitoring()

    # Ramp up
    tasks = ramp_up_load(provider, messages, concurrency, ramp_up_seconds)

    # Sustained load
    :timer.sleep(duration_seconds * 1000)

    # Shutdown
    results = shutdown_load_test(tasks, monitor_pid)

    Logger.info(
      "Stress test completed: #{results.total_requests} requests, #{results.errors} errors"
    )

    results
  end

  ## Private Functions

  defp run_iterations(provider, messages, iterations, measure_detailed?, measures \\ [:time]) do
    measurements =
      Enum.map(1..iterations, fn _i ->
        if measure_detailed? do
          measure_detailed_execution(provider, messages, measures)
        else
          {time, _result} =
            :timer.tc(fn ->
              ExLLM.chat(provider, messages)
            end)

          %{time: time}
        end
      end)

    summary = %{
      total_time: Enum.sum(Enum.map(measurements, & &1.time)),
      average_time: Enum.sum(Enum.map(measurements, & &1.time)) / iterations,
      iterations: iterations
    }

    %{measurements: measurements, summary: summary}
  end

  defp run_concurrent_iterations(provider, messages, iterations, measures) do
    concurrency = min(iterations, System.schedulers_online() * 2)
    batch_size = div(iterations, concurrency)

    tasks =
      1..concurrency
      |> Enum.map(fn _ ->
        Task.async(fn ->
          run_iterations(provider, messages, batch_size, true, measures)
        end)
      end)

    results =
      tasks
      |> Enum.map(&Task.await(&1, 30_000))
      |> Enum.reduce(%{measurements: [], summary: %{}}, fn result, acc ->
        %{
          measurements: acc.measurements ++ result.measurements,
          summary: merge_summaries(acc.summary, result.summary)
        }
      end)

    %{results | summary: Map.put(results.summary, :concurrent, true)}
  end

  defp measure_detailed_execution(provider, messages, measures) do
    request = Request.new(provider, messages, %{})
    pipeline = Providers.get_pipeline(provider, :chat)

    initial_memory = if :memory in measures, do: :erlang.memory(:total), else: 0

    initial_reductions =
      if :reductions in measures, do: :erlang.process_info(self(), :reductions), else: {nil, 0}

    {time, result} =
      :timer.tc(fn ->
        Pipeline.run(request, pipeline)
      end)

    final_memory = if :memory in measures, do: :erlang.memory(:total), else: 0

    final_reductions =
      if :reductions in measures, do: :erlang.process_info(self(), :reductions), else: {nil, 0}

    measurement = %{time: time}

    measurement =
      if :memory in measures do
        Map.put(measurement, :memory_delta, final_memory - initial_memory)
      else
        measurement
      end

    measurement =
      if :reductions in measures do
        {_, initial_reds} = initial_reductions
        {_, final_reds} = final_reductions
        Map.put(measurement, :reductions, final_reds - initial_reds)
      else
        measurement
      end

    Map.put(measurement, :success, match?(%Request{state: :completed}, result))
  end

  defp measure_pipeline_execution(provider, messages, pipeline) do
    request = Request.new(provider, messages, %{})

    {time, result} =
      :timer.tc(fn ->
        Pipeline.run(request, pipeline)
      end)

    %{
      time: time,
      success: match?(%Request{state: :completed}, result),
      pipeline_length: length(pipeline)
    }
  end

  defp calculate_statistics(measurements) do
    times = Enum.map(measurements, & &1.time)
    sorted_times = Enum.sort(times)
    count = length(times)

    %{
      count: count,
      min: Enum.min(times),
      max: Enum.max(times),
      mean: Enum.sum(times) / count,
      median: calculate_median(sorted_times),
      p95: calculate_percentile(sorted_times, 0.95),
      p99: calculate_percentile(sorted_times, 0.99),
      std_dev: calculate_std_dev(times),
      success_rate: calculate_success_rate(measurements)
    }
  end

  defp calculate_median(sorted_list) do
    count = length(sorted_list)
    middle = div(count, 2)

    if rem(count, 2) == 0 do
      (Enum.at(sorted_list, middle - 1) + Enum.at(sorted_list, middle)) / 2
    else
      Enum.at(sorted_list, middle)
    end
  end

  defp calculate_percentile(sorted_list, percentile) do
    count = length(sorted_list)
    index = round(count * percentile) - 1
    index = max(0, min(index, count - 1))
    Enum.at(sorted_list, index)
  end

  defp calculate_std_dev(values) do
    mean = Enum.sum(values) / length(values)
    variance = Enum.sum(Enum.map(values, fn x -> :math.pow(x - mean, 2) end)) / length(values)
    :math.sqrt(variance)
  end

  defp calculate_success_rate(measurements) do
    successes = Enum.count(measurements, fn m -> Map.get(m, :success, true) end)
    successes / length(measurements)
  end

  defp generate_comparison_report(results) do
    baseline_name = results |> Map.keys() |> List.first()
    baseline_stats = get_in(results, [baseline_name, :statistics])

    Enum.map(results, fn {name, data} ->
      stats = data.statistics

      improvement =
        if name != baseline_name do
          calculate_improvement(baseline_stats.mean, stats.mean)
        else
          0.0
        end

      {name,
       %{
         mean_time: stats.mean,
         improvement_percent: improvement,
         relative_performance: stats.mean / baseline_stats.mean
       }}
    end)
    |> Map.new()
  end

  defp find_fastest_configuration(results) do
    results
    |> Enum.min_by(fn {_name, data} -> data.statistics.mean end)
    |> elem(0)
  end

  defp calculate_improvement(baseline, current) do
    (baseline - current) / baseline * 100
  end

  defp benchmark_function(fun, iterations) do
    # Warmup
    Enum.each(1..10, fn _ -> fun.() end)

    # Actual measurement
    {total_time, _} =
      :timer.tc(fn ->
        Enum.each(1..iterations, fn _ -> fun.() end)
      end)

    total_time / iterations
  end

  defp normalize_plug_spec(plug) when is_atom(plug), do: {plug, []}
  defp normalize_plug_spec({plug, opts}), do: {plug, opts}

  defp calculate_efficiency(plug_times, full_pipeline_time) do
    total_plug_time = Enum.sum(Map.values(plug_times))

    if full_pipeline_time > 0 do
      total_plug_time / full_pipeline_time
    else
      0.0
    end
  end

  defp calculate_peak_memory(initial, final) do
    Enum.map(final, fn {type, final_bytes} ->
      initial_bytes = Keyword.get(initial, type, 0)
      {type, max(initial_bytes, final_bytes)}
    end)
    |> Map.new()
  end

  defp format_summary(stats) do
    "mean: #{Float.round(stats.mean / 1000, 2)}ms, " <>
      "p95: #{Float.round(stats.p95 / 1000, 2)}ms, " <>
      "success: #{Float.round(stats.success_rate * 100, 1)}%"
  end

  defp merge_summaries(acc, new) when map_size(acc) == 0, do: new

  defp merge_summaries(acc, new) do
    %{
      total_time: acc.total_time + new.total_time,
      average_time: (acc.average_time + new.average_time) / 2,
      iterations: acc.iterations + new.iterations
    }
  end

  # Stress testing functions
  defp start_monitoring do
    spawn(fn -> monitor_loop(%{start_time: :os.system_time(:second), requests: 0, errors: 0}) end)
  end

  defp monitor_loop(state) do
    receive do
      {:request_completed} ->
        monitor_loop(%{state | requests: state.requests + 1})

      {:request_failed} ->
        monitor_loop(%{state | requests: state.requests + 1, errors: state.errors + 1})

      {:get_stats, from} ->
        send(from, state)
        monitor_loop(state)

      :stop ->
        state
    after
      1000 -> monitor_loop(state)
    end
  end

  defp ramp_up_load(provider, messages, target_concurrency, ramp_seconds) do
    # 10 steps per second
    step_size = target_concurrency / (ramp_seconds * 10)

    Enum.reduce(1..target_concurrency, [], fn i, tasks ->
      if rem(i, round(step_size)) == 0 do
        # 100ms between steps
        :timer.sleep(100)
      end

      task =
        Task.async(fn ->
          continuous_requests(provider, messages)
        end)

      [task | tasks]
    end)
  end

  defp continuous_requests(provider, messages) do
    try do
      case ExLLM.chat(provider, messages) do
        {:ok, _} -> send(:stress_monitor, {:request_completed})
        {:error, _} -> send(:stress_monitor, {:request_failed})
      end

      # Brief pause between requests
      :timer.sleep(100)
      continuous_requests(provider, messages)
    catch
      :exit, _ -> :stopped
    end
  end

  defp shutdown_load_test(tasks, monitor_pid) do
    # Stop all tasks
    Enum.each(tasks, fn task -> Task.shutdown(task, :brutal_kill) end)

    # Get final stats from monitor
    send(monitor_pid, {:get_stats, self()})

    receive do
      stats ->
        send(monitor_pid, :stop)

        %{
          total_requests: stats.requests,
          errors: stats.errors,
          duration: :os.system_time(:second) - stats.start_time,
          error_rate: if(stats.requests > 0, do: stats.errors / stats.requests, else: 0)
        }
    after
      1000 -> %{total_requests: 0, errors: 0, duration: 0, error_rate: 0}
    end
  end
end
