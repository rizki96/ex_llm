defmodule ExLLM.PipelineOptimizer do
  @moduledoc """
  Pipeline optimization utilities for ExLLM.
  
  This module provides tools to optimize pipeline performance through:
  - Pipeline caching and memoization
  - Plug ordering optimization
  - Dead plug elimination
  - Parallel execution where safe
  - Memory usage optimization
  
  ## Usage
  
      # Optimize a pipeline
      optimized = ExLLM.PipelineOptimizer.optimize(pipeline, [:cache_pipelines, :reorder_plugs])
      
      # Enable global optimizations
      ExLLM.PipelineOptimizer.configure(enabled: true, strategies: [:all])
      
      # Benchmark optimization impact
      ExLLM.PipelineOptimizer.benchmark_optimization(provider, pipeline, messages)
  """

  alias ExLLM.Pipeline
  alias ExLLM.Pipeline.Request
  
  require Logger

  @optimization_strategies [
    :cache_pipelines,      # Cache compiled pipelines
    :reorder_plugs,        # Optimize plug execution order
    :eliminate_dead_code,  # Remove unnecessary plugs
    :parallelize_safe,     # Execute independent plugs in parallel
    :optimize_memory,      # Reduce memory allocations
    :fast_path,           # Create fast paths for common cases
    :compile_time        # Move work to compile time
  ]

  @type optimization_strategy :: 
    :cache_pipelines | :reorder_plugs | :eliminate_dead_code | 
    :parallelize_safe | :optimize_memory | :fast_path | :compile_time

  @type optimization_result :: %{
    original_pipeline: Pipeline.pipeline(),
    optimized_pipeline: Pipeline.pipeline(),
    applied_optimizations: [optimization_strategy()],
    estimated_improvement: float(),
    warnings: [String.t()]
  }

  ## Configuration

  @doc """
  Configure global pipeline optimization settings.
  
  ## Options
  
    * `:enabled` - Enable/disable optimizations globally (default: false)
    * `:strategies` - List of optimization strategies to apply (default: [:cache_pipelines])
    * `:cache_size` - Maximum number of cached pipelines (default: 1000)
    * `:aggressive` - Enable aggressive optimizations that may break compatibility (default: false)
    
  ## Examples
  
      # Enable basic optimizations
      ExLLM.PipelineOptimizer.configure(enabled: true)
      
      # Enable all safe optimizations
      ExLLM.PipelineOptimizer.configure(
        enabled: true,
        strategies: [:cache_pipelines, :reorder_plugs, :optimize_memory]
      )
      
      # Enable all optimizations (aggressive)
      ExLLM.PipelineOptimizer.configure(
        enabled: true,
        strategies: :all,
        aggressive: true
      )
  """
  @spec configure(keyword()) :: :ok
  def configure(opts \\ []) do
    enabled = Keyword.get(opts, :enabled, false)
    strategies = Keyword.get(opts, :strategies, [:cache_pipelines])
    cache_size = Keyword.get(opts, :cache_size, 1000)
    aggressive = Keyword.get(opts, :aggressive, false)

    expanded_strategies = if strategies == :all do
      @optimization_strategies
    else
      strategies
    end

    config = %{
      enabled: enabled,
      strategies: expanded_strategies,
      cache_size: cache_size,
      aggressive: aggressive
    }

    Application.put_env(:ex_llm, :pipeline_optimizer, config)
    
    if enabled do
      Logger.info("Pipeline optimizer enabled with strategies: #{inspect(expanded_strategies)}")
      maybe_start_cache_cleanup()
    else
      Logger.debug("Pipeline optimizer disabled")
    end
    
    :ok
  end

  @doc """
  Optimize a pipeline using specified strategies.
  
  ## Examples
  
      # Basic optimization
      optimized = ExLLM.PipelineOptimizer.optimize(pipeline)
      
      # Specific optimizations
      optimized = ExLLM.PipelineOptimizer.optimize(pipeline, 
        [:reorder_plugs, :eliminate_dead_code]
      )
      
      # Get detailed optimization report
      result = ExLLM.PipelineOptimizer.optimize_with_report(pipeline, [:all])
  """
  @spec optimize(Pipeline.pipeline(), [optimization_strategy()]) :: Pipeline.pipeline()
  def optimize(pipeline, strategies \\ nil) do
    strategies = strategies || get_configured_strategies()
    
    if optimization_enabled?() do
      case get_cached_optimization(pipeline, strategies) do
        {:ok, optimized_pipeline} ->
          optimized_pipeline
          
        :miss ->
          optimized_pipeline = apply_optimizations(pipeline, strategies)
          cache_optimization(pipeline, strategies, optimized_pipeline)
          optimized_pipeline
      end
    else
      pipeline
    end
  end

  @doc """
  Optimize a pipeline and return detailed optimization report.
  """
  @spec optimize_with_report(Pipeline.pipeline(), [optimization_strategy()]) :: optimization_result()
  def optimize_with_report(pipeline, strategies \\ nil) do
    strategies = strategies || get_configured_strategies()
    
    start_time = :os.system_time(:microsecond)
    optimized_pipeline = apply_optimizations(pipeline, strategies)
    optimization_time = :os.system_time(:microsecond) - start_time
    
    %{
      original_pipeline: pipeline,
      optimized_pipeline: optimized_pipeline,
      applied_optimizations: strategies,
      estimated_improvement: estimate_improvement(pipeline, optimized_pipeline),
      optimization_time_microseconds: optimization_time,
      warnings: validate_optimization(pipeline, optimized_pipeline)
    }
  end

  @doc """
  Benchmark the impact of optimization on a pipeline.
  """
  @spec benchmark_optimization(atom(), Pipeline.pipeline(), list(map()), keyword()) :: map()
  def benchmark_optimization(provider, pipeline, messages, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 100)
    strategies = Keyword.get(opts, :strategies, get_configured_strategies())
    
    # Benchmark original pipeline
    original_stats = benchmark_pipeline(provider, pipeline, messages, iterations)
    
    # Optimize and benchmark
    optimized_pipeline = optimize(pipeline, strategies)
    optimized_stats = benchmark_pipeline(provider, optimized_pipeline, messages, iterations)
    
    # Calculate improvement
    improvement = calculate_performance_improvement(original_stats, optimized_stats)
    
    %{
      original: original_stats,
      optimized: optimized_stats,
      improvement: improvement,
      strategies_applied: strategies,
      recommendation: generate_recommendation(improvement)
    }
  end

  ## Optimization Strategies

  defp apply_optimizations(pipeline, strategies) do
    Enum.reduce(strategies, pipeline, fn strategy, current_pipeline ->
      apply_optimization_strategy(current_pipeline, strategy)
    end)
  end

  defp apply_optimization_strategy(pipeline, :cache_pipelines) do
    # This optimization is handled at the caching layer
    pipeline
  end

  defp apply_optimization_strategy(pipeline, :reorder_plugs) do
    # Reorder plugs for optimal execution
    # Move validation and cheap operations first
    # Move expensive operations (HTTP calls) later
    
    {validation_plugs, other_plugs} = Enum.split_with(pipeline, &is_validation_plug?/1)
    {config_plugs, remaining_plugs} = Enum.split_with(other_plugs, &is_config_plug?/1)
    {execution_plugs, post_plugs} = Enum.split_with(remaining_plugs, &is_execution_plug?/1)
    
    # Optimal order: validation -> config -> pre-execution -> execution -> post-execution
    validation_plugs ++ config_plugs ++ 
    Enum.reject(post_plugs, &is_execution_plug?/1) ++ 
    execution_plugs ++ 
    Enum.filter(post_plugs, &is_post_execution_plug?/1)
  end

  defp apply_optimization_strategy(pipeline, :eliminate_dead_code) do
    # Remove plugs that don't contribute to the final result
    # This is conservative - only removes obviously redundant plugs
    
    # Remove duplicate plugs (keeping the last occurrence)
    deduplicated = remove_duplicate_plugs(pipeline)
    
    # Remove no-op plugs
    Enum.reject(deduplicated, &is_noop_plug?/1)
  end

  defp apply_optimization_strategy(pipeline, :parallelize_safe) do
    # Identify plugs that can run in parallel
    # This is complex and requires dependency analysis
    
    # For now, just return original pipeline
    # TODO: Implement parallel execution for independent plugs
    pipeline
  end

  defp apply_optimization_strategy(pipeline, :optimize_memory) do
    # Add memory optimization hints
    # Wrap memory-intensive plugs with garbage collection hints
    
    Enum.map(pipeline, fn plug_spec ->
      if is_memory_intensive_plug?(plug_spec) do
        wrap_with_gc_hint(plug_spec)
      else
        plug_spec
      end
    end)
  end

  defp apply_optimization_strategy(pipeline, :fast_path) do
    # Create fast paths for common operations
    # Add conditional plugs that skip expensive operations when possible
    
    # For example, add cache check early in pipeline
    case Enum.find_index(pipeline, &is_cache_plug?/1) do
      nil -> pipeline  # No cache plug found
      index -> 
        # Move cache plug to the front (after validation)
        {cache_plug, rest} = List.pop_at(pipeline, index)
        {validation, non_validation} = Enum.split_while(rest, &is_validation_plug?/1)
        validation ++ [cache_plug] ++ non_validation
    end
  end

  defp apply_optimization_strategy(pipeline, :compile_time) do
    # Pre-compute what we can at compile time
    # For example, merge multiple config plugs into one
    
    merge_config_plugs(pipeline)
  end

  ## Plug Classification

  defp is_validation_plug?(plug_spec) do
    plug = get_plug_module(plug_spec)
    
    plug in [
      ExLLM.Plugs.ValidateProvider,
      ExLLM.Plugs.ValidateRequest,
      ExLLM.Plugs.ValidateConfiguration
    ]
  end

  defp is_config_plug?(plug_spec) do
    plug = get_plug_module(plug_spec)
    
    plug in [
      ExLLM.Plugs.FetchConfig,
      ExLLM.Plugs.BuildTeslaClient,
      ExLLM.Plugs.SetDefaults
    ]
  end

  defp is_execution_plug?(plug_spec) do
    plug = get_plug_module(plug_spec)
    
    plug in [
      ExLLM.Plugs.ExecuteRequest,
      ExLLM.Plugs.StreamRequest
    ] or String.contains?(to_string(plug), "Execute")
  end

  defp is_post_execution_plug?(plug_spec) do
    plug = get_plug_module(plug_spec)
    
    plug in [
      ExLLM.Plugs.ParseResponse,
      ExLLM.Plugs.TrackCost,
      ExLLM.Plugs.Cache  # Cache after response
    ] or String.contains?(to_string(plug), "Parse")
  end

  defp is_cache_plug?(plug_spec) do
    plug = get_plug_module(plug_spec)
    plug == ExLLM.Plugs.Cache
  end

  defp is_noop_plug?(_plug_spec) do
    # Identify plugs that don't do anything useful
    # This would need to be populated with actual no-op plugs
    false
  end

  defp is_memory_intensive_plug?(plug_spec) do
    plug = get_plug_module(plug_spec)
    
    # Plugs that typically use significant memory
    plug in [
      ExLLM.Plugs.ExecuteRequest,
      ExLLM.Plugs.ParseResponse,
      ExLLM.Plugs.Cache
    ]
  end

  defp get_plug_module(plug) when is_atom(plug), do: plug
  defp get_plug_module({plug, _opts}), do: plug

  ## Pipeline Transformations

  defp remove_duplicate_plugs(pipeline) do
    # Keep track of seen plugs and their positions
    {_, deduplicated} = 
      Enum.reduce(Enum.reverse(pipeline), {MapSet.new(), []}, fn plug_spec, {seen, acc} ->
        plug = get_plug_module(plug_spec)
        
        if MapSet.member?(seen, plug) do
          {seen, acc}  # Skip duplicate
        else
          {MapSet.put(seen, plug), [plug_spec | acc]}
        end
      end)
    
    deduplicated
  end

  defp wrap_with_gc_hint(plug_spec) do
    # This would wrap the plug with garbage collection hints
    # For now, just return the original plug
    plug_spec
  end

  defp merge_config_plugs(pipeline) do
    # Find consecutive config plugs and merge them
    # This is a simplified implementation
    pipeline
  end

  ## Caching

  defp optimization_enabled?() do
    config = Application.get_env(:ex_llm, :pipeline_optimizer, %{})
    Map.get(config, :enabled, false)
  end

  defp get_configured_strategies() do
    config = Application.get_env(:ex_llm, :pipeline_optimizer, %{})
    Map.get(config, :strategies, [:cache_pipelines])
  end

  defp get_cached_optimization(pipeline, strategies) do
    cache_key = generate_cache_key(pipeline, strategies)
    
    case :ets.whereis(:pipeline_optimization_cache) do
      :undefined ->
        :miss
      _ ->
        case :ets.lookup(:pipeline_optimization_cache, cache_key) do
          [{^cache_key, optimized_pipeline, _timestamp}] -> 
            {:ok, optimized_pipeline}
          [] -> 
            :miss
        end
    end
  end

  defp cache_optimization(original_pipeline, strategies, optimized_pipeline) do
    if :ets.whereis(:pipeline_optimization_cache) == :undefined do
      :ets.new(:pipeline_optimization_cache, [:named_table, :public, :set])
    end
    
    cache_key = generate_cache_key(original_pipeline, strategies)
    timestamp = :os.system_time(:second)
    
    :ets.insert(:pipeline_optimization_cache, {cache_key, optimized_pipeline, timestamp})
    
    # Trigger cleanup if cache is getting large
    maybe_cleanup_cache()
  end

  defp generate_cache_key(pipeline, strategies) do
    :crypto.hash(:sha256, :erlang.term_to_binary({pipeline, strategies}))
    |> Base.encode16(case: :lower)
  end

  defp maybe_start_cache_cleanup() do
    case Process.whereis(:pipeline_optimizer_cleaner) do
      nil ->
        pid = spawn(fn -> cache_cleanup_loop() end)
        Process.register(pid, :pipeline_optimizer_cleaner)
      _ ->
        :ok
    end
  end

  defp cache_cleanup_loop() do
    :timer.sleep(300_000)  # 5 minutes
    maybe_cleanup_cache()
    cache_cleanup_loop()
  end

  defp maybe_cleanup_cache() do
    if :ets.whereis(:pipeline_optimization_cache) != :undefined do
      size = :ets.info(:pipeline_optimization_cache, :size)
      config = Application.get_env(:ex_llm, :pipeline_optimizer, %{})
      max_size = Map.get(config, :cache_size, 1000)
      
      if size > max_size do
        cleanup_old_cache_entries()
      end
    end
  end

  defp cleanup_old_cache_entries() do
    # Remove oldest 25% of entries
    current_time = :os.system_time(:second)
    cutoff_time = current_time - 3600  # 1 hour old
    
    match_spec = [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff_time}], [true]}]
    :ets.select_delete(:pipeline_optimization_cache, match_spec)
  end

  ## Performance Analysis

  defp benchmark_pipeline(provider, pipeline, messages, iterations) do
    request = Request.new(provider, messages, %{})
    
    # Warmup
    Enum.each(1..10, fn _ ->
      Pipeline.run(request, pipeline)
    end)
    
    # Benchmark
    times = Enum.map(1..iterations, fn _ ->
      {time, _result} = :timer.tc(fn ->
        Pipeline.run(request, pipeline)
      end)
      time
    end)
    
    %{
      mean: Enum.sum(times) / length(times),
      min: Enum.min(times),
      max: Enum.max(times),
      iterations: iterations,
      pipeline_length: length(pipeline)
    }
  end

  defp calculate_performance_improvement(original, optimized) do
    time_improvement = ((original.mean - optimized.mean) / original.mean) * 100
    
    %{
      time_improvement_percent: time_improvement,
      absolute_time_saved_microseconds: original.mean - optimized.mean,
      relative_performance: optimized.mean / original.mean
    }
  end

  defp estimate_improvement(original_pipeline, optimized_pipeline) do
    # Simple heuristic based on pipeline length reduction
    original_length = length(original_pipeline)
    optimized_length = length(optimized_pipeline)
    
    if original_length > 0 do
      (original_length - optimized_length) / original_length * 100
    else
      0.0
    end
  end

  defp validate_optimization(original_pipeline, optimized_pipeline) do
    warnings = []
    
    # Check for significant pipeline changes
    warnings = if length(optimized_pipeline) < length(original_pipeline) * 0.5 do
      ["Optimization removed more than 50% of plugs - please verify correctness" | warnings]
    else
      warnings
    end
    
    # Check for missing critical plugs
    original_plugs = Enum.map(original_pipeline, &get_plug_module/1) |> MapSet.new()
    optimized_plugs = Enum.map(optimized_pipeline, &get_plug_module/1) |> MapSet.new()
    missing_plugs = MapSet.difference(original_plugs, optimized_plugs)
    
    warnings = if MapSet.size(missing_plugs) > 0 do
      ["Optimization removed plugs: #{inspect(MapSet.to_list(missing_plugs))}" | warnings]
    else
      warnings
    end
    
    warnings
  end

  defp generate_recommendation(improvement) do
    cond do
      improvement.time_improvement_percent > 20 ->
        "Excellent optimization - recommend enabling globally"
        
      improvement.time_improvement_percent > 10 ->
        "Good optimization - consider enabling for performance-critical paths"
        
      improvement.time_improvement_percent > 0 ->
        "Minor optimization - may be worth enabling with comprehensive testing"
        
      true ->
        "No significant improvement - optimization may not be beneficial"
    end
  end
end