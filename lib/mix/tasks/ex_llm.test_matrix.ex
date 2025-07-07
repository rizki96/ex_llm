defmodule Mix.Tasks.ExLlm.TestMatrix do
  @moduledoc """
  Runs tests across multiple providers to ensure consistency.

  This task allows you to run specific tests or test patterns across
  multiple providers to verify that functionality works consistently.

  ## Usage

      mix ex_llm.test_matrix [options]

  ## Options

    * `--providers` - Comma-separated list of providers to test
    * `--test` - Specific test file or pattern to run
    * `--only` - Run only tests matching this tag
    * `--exclude` - Exclude tests matching this tag
    * `--capability` - Test a specific capability across providers
    * `--parallel` - Run provider tests in parallel (default: false)
    * `--stop-on-failure` - Stop testing on first failure (default: false)
    * `--summary` - Show summary only (default: false)

  ## Examples

      # Run all tests for specific providers
      mix ex_llm.test_matrix --providers openai,anthropic,gemini

      # Run a specific test file across providers
      mix ex_llm.test_matrix --test test/ex_llm/chat_test.exs --providers openai,anthropic

      # Test a capability across all configured providers
      mix ex_llm.test_matrix --capability vision

      # Run tests with specific tags
      mix ex_llm.test_matrix --only integration --providers groq,mistral

      # Run in parallel with summary
      mix ex_llm.test_matrix --parallel --summary --providers all
  """

  use Mix.Task
  alias ExLLM.Capabilities

  @shortdoc "Run tests across multiple providers"

  @impl Mix.Task
  def run(args) do
    {opts, _} = parse_args(args)

    providers = get_providers(opts)
    test_config = build_test_config(opts)

    IO.puts("\n#{IO.ANSI.bright()}=== Cross-Provider Test Matrix ===#{IO.ANSI.reset()}\n")

    if opts[:summary] do
      IO.puts("Providers: #{Enum.join(providers, ", ")}")
      IO.puts("Test config: #{inspect(test_config)}\n")
    end

    results = run_matrix(providers, test_config, opts)

    print_results(results, opts)

    # Exit with error if any tests failed
    if Enum.any?(results, fn {_, result} -> result.status == :failed end) do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp parse_args(args) do
    OptionParser.parse!(args,
      strict: [
        providers: :string,
        test: :string,
        only: :string,
        exclude: :string,
        capability: :string,
        parallel: :boolean,
        stop_on_failure: :boolean,
        summary: :boolean
      ]
    )
  end

  defp get_providers(opts) do
    case opts[:providers] do
      nil ->
        # Default to all configured providers
        Capabilities.supported_providers()
        |> Enum.filter(&ExLLM.configured?/1)

      "all" ->
        # All supported providers
        Capabilities.supported_providers()

      providers_str ->
        # Parse comma-separated list
        providers_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_atom/1)
        |> Enum.filter(&provider_available?/1)
    end
    |> Enum.sort()
  end

  defp provider_available?(provider) do
    if ExLLM.configured?(provider) do
      true
    else
      IO.puts(
        "#{IO.ANSI.yellow()}Warning: Provider #{provider} is not configured#{IO.ANSI.reset()}"
      )

      false
    end
  end

  defp build_test_config(opts) do
    config = %{
      env: [{"MIX_ENV", "test"}]
    }

    # Build mix test command arguments
    args = []

    args = if opts[:test], do: args ++ [opts[:test]], else: args
    args = if opts[:only], do: args ++ ["--only", opts[:only]], else: args
    args = if opts[:exclude], do: args ++ ["--exclude", opts[:exclude]], else: args

    # Handle capability testing
    args =
      if opts[:capability] do
        args ++ ["--only", "capability:#{opts[:capability]}"]
      else
        args
      end

    Map.put(config, :args, args)
  end

  defp run_matrix(providers, test_config, opts) do
    if opts[:parallel] do
      run_parallel(providers, test_config, opts)
    else
      run_sequential(providers, test_config, opts)
    end
  end

  defp run_sequential(providers, test_config, opts) do
    Enum.reduce_while(providers, [], fn provider, acc ->
      result = run_provider_tests(provider, test_config, opts)

      if opts[:stop_on_failure] && result.status == :failed do
        {:halt, [{provider, result} | acc]}
      else
        {:cont, [{provider, result} | acc]}
      end
    end)
    |> Enum.reverse()
  end

  defp run_parallel(providers, test_config, opts) do
    providers
    |> Task.async_stream(
      fn provider -> {provider, run_provider_tests(provider, test_config, opts)} end,
      timeout: :timer.minutes(5),
      max_concurrency: System.schedulers_online()
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp run_provider_tests(provider, test_config, opts) do
    unless opts[:summary] do
      IO.puts("\n#{IO.ANSI.cyan()}Testing #{provider}...#{IO.ANSI.reset()}")
    end

    # Build the command with provider-specific tag
    args = ["--only", "provider:#{provider}" | test_config.args]
    cmd_args = ["test" | args]

    start_time = System.monotonic_time(:millisecond)

    # Run the tests
    {raw_output, exit_code} =
      System.cmd("mix", cmd_args,
        env: test_config.env,
        stderr_to_stdout: true
      )
    
    # Filter out telemetry warnings from output
    output = 
      raw_output
      |> String.split("\n")
      |> Enum.reject(&String.contains?(&1, "Failed to lookup telemetry handlers"))
      |> Enum.join("\n")

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    # Parse the output for test results
    {passed, failed, skipped} = parse_test_output(output)

    %{
      status: if(exit_code == 0, do: :passed, else: :failed),
      exit_code: exit_code,
      duration: duration,
      passed: passed,
      failed: failed,
      skipped: skipped,
      output: output
    }
  end

  defp parse_test_output(output) do
    # Look for ExUnit summary line
    case Regex.run(~r/(\d+) test[s]?, (\d+) failure[s]?(?:, (\d+) skipped)?/, output) do
      [_, total, failures, skipped] ->
        total_int = String.to_integer(total)
        failures_int = String.to_integer(failures)
        skipped_int = String.to_integer(skipped || "0")
        passed_int = total_int - failures_int - skipped_int

        {passed_int, failures_int, skipped_int}

      [_, total, failures] ->
        total_int = String.to_integer(total)
        failures_int = String.to_integer(failures)
        passed_int = total_int - failures_int

        {passed_int, failures_int, 0}

      _ ->
        # Couldn't parse, return defaults
        {0, 0, 0}
    end
  end

  defp print_results(results, opts) do
    IO.puts("\n#{IO.ANSI.bright()}=== Test Matrix Results ===#{IO.ANSI.reset()}\n")

    # Summary table
    IO.puts(
      String.pad_trailing("Provider", 15) <>
        String.pad_trailing("Status", 10) <>
        String.pad_trailing("Passed", 10) <>
        String.pad_trailing("Failed", 10) <>
        String.pad_trailing("Skipped", 10) <>
        "Duration"
    )

    IO.puts(String.duplicate("-", 70))

    {total_passed, total_failed, total_skipped, total_duration} =
      Enum.reduce(results, {0, 0, 0, 0}, fn {provider, result}, {tp, tf, ts, td} ->
        status_color = if result.status == :passed, do: IO.ANSI.green(), else: IO.ANSI.red()

        IO.puts(
          String.pad_trailing(to_string(provider), 15) <>
            status_color <>
            String.pad_trailing(to_string(result.status), 10) <>
            IO.ANSI.reset() <>
            String.pad_trailing(to_string(result.passed), 10) <>
            String.pad_trailing(to_string(result.failed), 10) <>
            String.pad_trailing(to_string(result.skipped), 10) <>
            "#{result.duration}ms"
        )

        {tp + result.passed, tf + result.failed, ts + result.skipped, td + result.duration}
      end)

    IO.puts(String.duplicate("-", 70))

    IO.puts(
      String.pad_trailing("TOTAL", 15) <>
        String.pad_trailing("", 10) <>
        String.pad_trailing(to_string(total_passed), 10) <>
        String.pad_trailing(to_string(total_failed), 10) <>
        String.pad_trailing(to_string(total_skipped), 10) <>
        "#{total_duration}ms"
    )

    # Print failed test details if not in summary mode
    unless opts[:summary] do
      failed_providers = Enum.filter(results, fn {_, result} -> result.status == :failed end)

      if length(failed_providers) > 0 do
        IO.puts("\n#{IO.ANSI.red()}Failed Providers:#{IO.ANSI.reset()}")

        Enum.each(failed_providers, fn {provider, result} ->
          IO.puts("\n#{IO.ANSI.yellow()}#{provider}:#{IO.ANSI.reset()}")
          # Extract failure details from output
          extract_failures(result.output)
          |> Enum.each(&IO.puts/1)
        end)
      end
    end

    # Overall summary
    IO.puts("\n#{IO.ANSI.bright()}Summary:#{IO.ANSI.reset()}")
    successful = Enum.count(results, fn {_, result} -> result.status == :passed end)
    IO.puts("#{successful}/#{length(results)} providers passed")

    if total_failed > 0 do
      IO.puts("#{IO.ANSI.red()}Total failures: #{total_failed}#{IO.ANSI.reset()}")
    end
  end

  defp extract_failures(output) do
    output
    |> String.split("\n")
    |> Enum.filter(fn line ->
      String.contains?(line, "Failure:") ||
        String.contains?(line, "** (") ||
        String.contains?(line, "test/")
    end)
    # Limit output
    |> Enum.take(10)
  end
end
