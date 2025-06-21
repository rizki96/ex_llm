defmodule ExLLM.Plugs.ParallelExecutor do
  @moduledoc """
  Executes multiple independent plugs in parallel for improved performance.

  This plug is used by the PipelineOptimizer to run non-dependent plugs
  concurrently, reducing overall pipeline execution time.

  ## Options

    * `:plugs` - List of plug specifications to execute in parallel
    * `:timeout` - Maximum time to wait for all plugs (default: 5000ms)
    * `:ordered` - Whether to preserve plug execution order in results (default: true)

  ## Example

      pipeline = [
        ExLLM.Plugs.ValidateProvider,
        {ExLLM.Plugs.ParallelExecutor, plugs: [
          ExLLM.Plugs.ValidateRequest,
          ExLLM.Plugs.ValidateConfiguration
        ]},
        ExLLM.Plugs.ExecuteRequest
      ]
  """

  @behaviour ExLLM.Plug

  alias ExLLM.Infrastructure.Logger

  @default_timeout 5_000

  @impl true
  def init(opts), do: opts

  @impl true
  def call(request, opts) do
    plugs = Keyword.get(opts, :plugs, [])
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    ordered = Keyword.get(opts, :ordered, true)

    if plugs == [] do
      # No plugs to execute
      {:ok, request}
    else
      execute_parallel(request, plugs, timeout, ordered)
    end
  end

  defp execute_parallel(request, plugs, timeout, ordered) do
    # Start telemetry span
    start_time = System.monotonic_time()

    # Spawn tasks for each plug
    tasks =
      Enum.map(plugs, fn plug_spec ->
        Task.async(fn ->
          {plug_spec, execute_plug(plug_spec, request)}
        end)
      end)

    # Wait for all tasks with timeout
    case Task.yield_many(tasks, timeout) do
      results when length(results) == length(tasks) ->
        # All tasks completed
        process_results(request, results, plugs, ordered, start_time)

      partial_results ->
        # Some tasks timed out
        handle_timeout(request, partial_results, tasks)
    end
  end

  defp execute_plug(plug_spec, request) do
    {plug, opts} = normalize_plug_spec(plug_spec)

    try do
      case plug.call(request, opts) do
        {:ok, updated_request} ->
          {:ok, updated_request}

        {:error, _} = error ->
          error

        # Handle non-standard returns
        other ->
          Logger.warning("Plug #{inspect(plug)} returned non-standard result: #{inspect(other)}")
          {:error, {:invalid_plug_result, other}}
      end
    rescue
      e ->
        Logger.error("Plug #{inspect(plug)} raised exception: #{inspect(e)}")
        {:error, {:plug_exception, e}}
    end
  end

  defp normalize_plug_spec(plug) when is_atom(plug), do: {plug, []}
  defp normalize_plug_spec({plug, opts}), do: {plug, opts}

  defp process_results(request, task_results, original_plugs, ordered, start_time) do
    # Extract results from tasks
    results =
      Enum.map(task_results, fn {_task, result} ->
        case result do
          {:ok, {plug_spec, plug_result}} ->
            {plug_spec, plug_result}

          {:exit, reason} ->
            {nil, {:error, {:task_exit, reason}}}

          nil ->
            # This shouldn't happen with yield_many when all complete
            {nil, {:error, :task_timeout}}
        end
      end)

    # Check for any errors
    errors =
      results
      |> Enum.filter(fn {_, result} -> match?({:error, _}, result) end)
      |> Enum.map(fn {plug_spec, error} -> {plug_spec, error} end)

    if errors != [] do
      # Return first error
      {_plug_spec, error} = hd(errors)
      error
    else
      # Merge all successful results
      merged_request = merge_results(request, results, original_plugs, ordered)

      # Emit telemetry
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:ex_llm, :plug, :parallel_executor],
        %{duration: duration, plug_count: length(original_plugs)},
        %{ordered: ordered}
      )

      {:ok, merged_request}
    end
  end

  defp merge_results(request, results, original_plugs, ordered) do
    if ordered do
      # Preserve original plug order
      ordered_results =
        original_plugs
        |> Enum.map(fn plug_spec ->
          Enum.find(results, fn {result_plug, _} ->
            result_plug == plug_spec
          end)
        end)
        |> Enum.reject(&is_nil/1)

      apply_results_sequentially(request, ordered_results)
    else
      # Apply in completion order
      apply_results_sequentially(request, results)
    end
  end

  defp apply_results_sequentially(request, results) do
    Enum.reduce(results, request, fn {_plug_spec, {:ok, updated_request}}, acc ->
      # Merge the changes from each plug
      # This is a simple deep merge - may need refinement based on actual usage
      deep_merge(acc, updated_request)
    end)
  end

  defp deep_merge(map1, map2) when is_map(map1) and is_map(map2) do
    Map.merge(map1, map2, fn _key, v1, v2 ->
      deep_merge(v1, v2)
    end)
  end

  defp deep_merge(_v1, v2), do: v2

  defp handle_timeout(_request, partial_results, tasks) do
    # Kill any remaining tasks
    Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))

    # Count how many timed out
    timed_out =
      Enum.count(partial_results, fn {_task, result} ->
        result == nil
      end)

    Logger.error("ParallelExecutor timeout: #{timed_out} plugs failed to complete")

    {:error, {:parallel_execution_timeout, timed_out}}
  end
end
