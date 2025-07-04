defmodule ExLLM.Testing.IntegrationCase do
  @moduledoc """
  Base test case for ExLLM integration tests.

  Provides:
  - Automatic cost tracking
  - Test caching support
  - Rate limit handling
  - Lifecycle helpers
  - Provider availability checks
  """

  use ExUnit.CaseTemplate
  alias ExLLM.Testing.{CostTracker, Fixtures}

  using do
    quote do
      use ExUnit.Case, async: false
      import ExLLM.Testing.IntegrationCase
      import ExLLM.Testing.Fixtures

      @moduletag :integration

      setup context do
        # Start cost tracking for this test
        test_name = "#{context.module}.#{context.test}"
        max_cost = Map.get(context, :max_cost, 0.50)

        case CostTracker.check_test_budget(test_name, max_cost) do
          :ok ->
            :ok

          {:error, :budget_exceeded, cost} ->
            flunk("Test budget exceeded: $#{Float.round(cost, 2)} > $#{max_cost}")
        end

        # Ensure fixtures exist
        Fixtures.ensure_fixtures_exist()

        # Setup cleanup
        on_exit(fn ->
          ExLLM.Testing.IntegrationCase.cleanup_test_resources(context)
        end)

        {:ok, context}
      end
    end
  end

  # Helper Functions

  def skip_if_no_api_key(provider) do
    case provider_api_key(provider) do
      nil ->
        reason = "No API key for #{provider}"
        IO.puts("\n  Skipped: #{reason}")
        flunk(reason)

      _ ->
        :ok
    end
  end

  def with_provider(provider, fun) do
    skip_if_no_api_key(provider)
    fun.()
  end

  def assert_api_lifecycle(_resource_type, create_fn, get_fn, delete_fn) do
    # Create resource
    {:ok, resource} = create_fn.()
    assert resource.id

    # Verify it exists
    {:ok, fetched} = get_fn.(resource.id)
    assert fetched.id == resource.id

    # Delete it
    {:ok, _} = delete_fn.(resource.id)

    # Verify it's gone (should error)
    assert {:error, _} = get_fn.(resource.id)
  end

  def with_retry(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    delay = Keyword.get(opts, :delay, 1000)

    Enum.reduce_while(1..max_attempts, nil, fn attempt, _acc ->
      case fun.() do
        {:ok, result} ->
          {:halt, {:ok, result}}

        {:error, %{status: 429}} when attempt < max_attempts ->
          Process.sleep(delay * attempt)
          {:cont, nil}

        {:error, _} = error when attempt == max_attempts ->
          {:halt, error}

        {:error, _} ->
          Process.sleep(delay)
          {:cont, nil}
      end
    end)
  end

  def track_tokens(provider, model, input_tokens, output_tokens) do
    CostTracker.track_request(provider, model, input_tokens, :input)
    CostTracker.track_request(provider, model, output_tokens, :output)
  end

  def assert_eventually(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    _interval = Keyword.get(opts, :interval, 100)

    start_time = System.monotonic_time(:millisecond)

    result =
      Stream.repeatedly(fn ->
        case fun.() do
          true -> :ok
          false -> :retry
          {:ok, _} -> :ok
          _ -> :retry
        end
      end)
      |> Stream.take_while(fn result ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        result == :retry && elapsed < timeout
      end)
      |> Enum.to_list()
      |> List.last()

    if result != :ok do
      flunk("Assertion failed after #{timeout}ms")
    end
  end

  def unique_name(prefix) do
    "#{prefix}_#{Fixtures.unique_id()}"
  end

  def measure_performance(fun) do
    start_time = System.monotonic_time(:millisecond)
    result = fun.()
    end_time = System.monotonic_time(:millisecond)

    {result, end_time - start_time}
  end

  def assert_performance(fun, max_ms) do
    {result, duration} = measure_performance(fun)

    if duration > max_ms do
      flunk("Performance assertion failed: #{duration}ms > #{max_ms}ms")
    end

    result
  end

  # Private Functions

  def cleanup_test_resources(context) do
    # Clean up any resources tagged in context
    if context[:cleanup_assistant_id] do
      try do
        ExLLM.Providers.OpenAI.delete_assistant(context.cleanup_assistant_id)
      rescue
        _ -> :ok
      end
    end

    if context[:cleanup_file_id] do
      try do
        ExLLM.FileManager.delete_file(context[:cleanup_provider], context.cleanup_file_id)
      rescue
        _ -> :ok
      end
    end

    if context[:cleanup_cache_id] do
      try do
        # Note: Gemini cache cleanup requires caching API availability
        :ok
      rescue
        _ -> :ok
      end
    end
  end

  defp provider_api_key(provider) do
    case provider do
      :openai -> System.get_env("OPENAI_API_KEY")
      :anthropic -> System.get_env("ANTHROPIC_API_KEY")
      :gemini -> System.get_env("GEMINI_API_KEY")
      _ -> nil
    end
  end
end
