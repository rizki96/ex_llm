defmodule ExLLM.TestResultAggregator do
  @moduledoc """
  Aggregates test results by provider and capability to enhance the capability matrix.

  This module analyzes ExUnit test results to determine which provider/capability
  combinations are actually working based on test execution.
  """

  @doc """
  Aggregate test results from ExUnit.

  Returns a map of provider -> capability -> test_status
  """
  def aggregate_results do
    # Get test results from ExUnit if available
    # For now, always returns empty map as test result integration is not implemented
    %{}
  end

  @doc """
  Get test status for a specific provider and capability.

  Returns one of:
  - `:passed` - All tests passed
  - `:failed` - Some tests failed
  - `:skipped` - Tests were skipped
  - `:not_tested` - No tests found
  """
  def get_test_status(provider, capability) do
    results = aggregate_results()

    case get_in(results, [provider, capability]) do
      nil -> :not_tested
      status -> status
    end
  end

  @doc """
  Generate a test summary report.
  """
  def generate_summary do
    results = aggregate_results()

    providers = results |> Map.keys() |> Enum.sort()

    summary =
      for provider <- providers do
        capabilities = Map.get(results, provider, %{})

        stats = %{
          passed: count_by_status(capabilities, :passed),
          failed: count_by_status(capabilities, :failed),
          skipped: count_by_status(capabilities, :skipped),
          total: map_size(capabilities)
        }

        {provider, stats}
      end

    %{
      providers: summary,
      total_providers: length(providers),
      timestamp: DateTime.utc_now()
    }
  end

  # Private functions

  defp count_by_status(capabilities, status) do
    capabilities
    |> Map.values()
    |> Enum.count(&(&1 == status))
  end

  @doc """
  Parse test output from a file or string.

  This can be used to analyze test results from CI/CD pipelines.
  """
  def parse_test_output(output) when is_binary(output) do
    # Parse test output to extract results
    lines = String.split(output, "\n")

    results =
      lines
      |> Enum.reduce(%{state: :searching, results: []}, fn line, acc ->
        parse_test_line(line, acc)
      end)
      |> Map.get(:results)

    # Convert to provider/capability map
    Enum.reduce(results, %{}, fn {provider, capability, status}, acc ->
      put_in(acc, [Access.key(provider, %{}), capability], status)
    end)
  end

  defp parse_test_line(line, acc) do
    cond do
      # Look for test results with provider tags
      Regex.match?(~r/\d+ tests?, \d+ failures?/, line) ->
        # Extract test summary
        acc

      # Look for individual test results
      String.contains?(line, "test") && String.contains?(line, "(") ->
        # Try to extract provider and test info
        # For now, just return acc as extract_from_test_line always returns nil
        acc

      true ->
        acc
    end
  end
end
