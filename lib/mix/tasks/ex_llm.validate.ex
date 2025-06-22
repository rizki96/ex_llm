defmodule Mix.Tasks.ExLlm.Validate do
  @moduledoc """
  Validates ExLLM configuration and reports issues.

  ## Available commands:

      mix ex_llm.validate                      # Run full validation
      mix ex_llm.validate --category=providers # Validate specific category
      mix ex_llm.validate --summary             # Show summary only
      mix ex_llm.validate --fix                # Show fix suggestions

  ## Categories:

  - `application_config` - Application-level configuration
  - `providers` - Provider configurations and API keys
  - `models` - Model configuration files and default models
  - `cache` - Cache configuration and disk paths
  - `dependencies` - Optional dependencies

  ## Examples:

      # Run full validation
      mix ex_llm.validate
      
      # Validate only providers
      mix ex_llm.validate --category=providers
      
      # Show summary with fix suggestions
      mix ex_llm.validate --summary --fix
      
      # Quiet mode (errors only)
      mix ex_llm.validate --quiet

  ## Exit codes:

  - 0: Validation passed or only warnings/info found
  - 1: Validation errors found
  - 2: Validation could not run (configuration issue)
  """

  use Mix.Task
  alias ExLLM.Infrastructure.StartupValidator

  @shortdoc "Validate ExLLM configuration"

  @switches [
    category: :string,
    summary: :boolean,
    fix: :boolean,
    quiet: :boolean,
    help: :boolean
  ]

  def run(args) do
    {opts, [], []} = OptionParser.parse(args, switches: @switches)

    cond do
      opts[:help] ->
        show_help()

      opts[:category] ->
        run_category_validation(opts[:category], opts)

      true ->
        run_full_validation(opts)
    end
  end

  defp run_full_validation(opts) do
    ensure_app_started()

    case StartupValidator.validate() do
      {:ok, results} ->
        if Keyword.get(opts, :summary, false) do
          show_summary(results, [])
        else
          show_success()
        end

        if Map.has_key?(results, :issues) do
          show_issues(results.issues, opts)
        end

        exit_code = if any_errors?(Map.get(results, :issues, [])), do: 1, else: 0
        if exit_code > 0, do: exit({:shutdown, exit_code})

      {:error, issues} ->
        unless Keyword.get(opts, :quiet, false) do
          show_failure()
          show_issues(issues, opts)
        end

        exit({:shutdown, 1})
    end
  end

  defp run_category_validation(category_name, opts) do
    ensure_app_started()

    case validate_category(category_name) do
      {:ok, results} ->
        handle_category_success(results, category_name, opts)

      {:error, issues} when is_list(issues) ->
        handle_validation_failure(issues, category_name, opts)

      {:error, message} when is_binary(message) ->
        handle_unknown_category(message)
    end
  end

  defp validate_category(category_name) do
    category = String.to_atom(category_name)

    case category do
      :application_config -> StartupValidator.validate_application_config()
      :providers -> StartupValidator.validate_providers()
      :models -> StartupValidator.validate_models()
      :cache -> StartupValidator.validate_cache()
      :dependencies -> StartupValidator.validate_dependencies()
      _ -> {:error, "Unknown category: #{category_name}"}
    end
  end

  defp handle_category_success(results, category_name, opts) do
    unless Keyword.get(opts, :quiet, false) do
      Mix.shell().info("✓ #{category_name} validation passed")

      if Keyword.get(opts, :summary, false) do
        category = String.to_atom(category_name)
        show_summary(%{category => results}, [])
      end
    end
  end

  defp handle_validation_failure(issues, category_name, opts) do
    unless Keyword.get(opts, :quiet, false) do
      Mix.shell().error("✗ #{category_name} validation failed")
      show_issues(issues, opts)
    end

    exit({:shutdown, 1})
  end

  defp handle_unknown_category(message) do
    Mix.shell().error("Error: #{message}")
    show_available_categories()
    exit({:shutdown, 2})
  end

  defp show_help do
    Mix.shell().info(@moduledoc)
  end

  defp show_success do
    Mix.shell().info("""
    ✓ ExLLM Configuration Validation Passed

    All configuration checks completed successfully.
    """)
  end

  defp show_failure do
    Mix.shell().error("""
    ✗ ExLLM Configuration Validation Failed

    Issues were found that require attention:
    """)
  end

  defp show_summary(results, issues) do
    Mix.shell().info("\n=== Validation Summary ===")

    if Map.has_key?(results, :validation_enabled) and not results.validation_enabled do
      Mix.shell().info("• Validation: Disabled")
    else
      Enum.each(results, fn
        {:issues, _} ->
          :skip

        {category, {:ok, data}} when is_map(data) ->
          show_category_summary(category, data)

        {category, {:error, _}} ->
          Mix.shell().error("• #{format_category(category)}: Failed")

        {category, data} when is_map(data) ->
          show_category_summary(category, data)
      end)
    end

    unless Enum.empty?(issues) do
      error_count = count_by_severity(issues, :error)
      warning_count = count_by_severity(issues, :warning)
      info_count = count_by_severity(issues, :info)

      Mix.shell().info("\n=== Issue Summary ===")
      if error_count > 0, do: Mix.shell().error("• Errors: #{error_count}")
      if warning_count > 0, do: Mix.shell().info("• Warnings: #{warning_count}")
      if info_count > 0, do: Mix.shell().info("• Info: #{info_count}")
    end

    Mix.shell().info("")
  end

  defp show_category_summary(:providers, %{configured_providers: providers}) do
    Mix.shell().info(
      "• Providers: #{length(providers)} configured (#{Enum.join(providers, ", ")})"
    )
  end

  defp show_category_summary(:models, %{providers_with_configs: providers}) do
    Mix.shell().info("• Models: #{length(providers)} provider configs found")
  end

  defp show_category_summary(:cache, %{cache_enabled: enabled}) do
    status = if enabled, do: "enabled", else: "disabled"
    Mix.shell().info("• Cache: #{status}")
  end

  defp show_category_summary(category, _data) do
    Mix.shell().info("• #{format_category(category)}: OK")
  end

  defp show_issues(issues, opts) do
    grouped = Enum.group_by(issues, & &1.severity)

    # Show errors first
    if Map.has_key?(grouped, :error) do
      Mix.shell().error("\n=== Errors ===")

      Enum.each(grouped.error, fn issue ->
        show_issue(issue, opts)
      end)
    end

    # Then warnings (unless quiet)
    if Map.has_key?(grouped, :warning) and not Keyword.get(opts, :quiet, false) do
      Mix.shell().info("\n=== Warnings ===")

      Enum.each(grouped.warning, fn issue ->
        show_issue(issue, opts)
      end)
    end

    # Then info (unless quiet)
    if Map.has_key?(grouped, :info) and not Keyword.get(opts, :quiet, false) do
      Mix.shell().info("\n=== Information ===")

      Enum.each(grouped.info, fn issue ->
        show_issue(issue, opts)
      end)
    end
  end

  defp show_issue(issue, opts) do
    icon =
      case issue.severity do
        :error -> "✗"
        :warning -> "⚠"
        :info -> "ℹ"
      end

    Mix.shell().info("#{icon} [#{issue.category}] #{issue.message}")

    if Keyword.get(opts, :fix, false) and Map.has_key?(issue.details, :suggestion) do
      Mix.shell().info("   💡 #{issue.details.suggestion}")
    end

    if not Keyword.get(opts, :summary, false) and map_size(issue.details) > 0 do
      details_to_show =
        issue.details
        |> Map.drop([:suggestion])
        |> Enum.reject(fn {_, v} -> is_nil(v) end)

      unless Enum.empty?(details_to_show) do
        Enum.each(details_to_show, fn {key, value} ->
          Mix.shell().info("     #{key}: #{format_detail_value(value)}")
        end)
      end
    end

    Mix.shell().info("")
  end

  defp format_detail_value(value) when is_list(value) do
    Enum.join(value, ", ")
  end

  defp format_detail_value(value) do
    inspect(value)
  end

  defp format_category(:application_config), do: "Application Config"
  defp format_category(category), do: String.capitalize(to_string(category))

  defp count_by_severity(issues, severity) do
    issues
    |> Enum.count(&(&1.severity == severity))
  end

  defp any_errors?(issues) do
    Enum.any?(issues, &(&1.severity == :error))
  end

  defp show_available_categories do
    Mix.shell().info("""

    Available categories:
    • application_config - Application-level configuration
    • providers          - Provider configurations and API keys
    • models             - Model configuration files and default models
    • cache              - Cache configuration and disk paths
    • dependencies       - Optional dependencies
    """)
  end

  defp ensure_app_started do
    {:ok, _} = Application.ensure_all_started(:ex_llm)
  end
end
