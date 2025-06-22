defmodule ExLLM.Infrastructure.StartupValidator do
  @moduledoc """
  Validates ExLLM configuration during application startup.

  This module performs comprehensive validation of the ExLLM configuration
  to catch configuration issues early and provide helpful error messages.

  ## What it validates

  - Application configuration structure and values
  - Provider configurations and model files
  - Cache configuration and directory permissions
  - Circuit breaker configurations
  - Logger configuration
  - Required dependencies for optional features

  ## Configuration

  Startup validation can be controlled via application environment:

      config :ex_llm,
        startup_validation: %{
          enabled: true,              # Enable/disable startup validation
          fail_on_error: false,       # Whether to halt startup on validation errors
          log_level: :warn,           # Log level for validation results
          validate_providers: true,   # Validate provider configurations
          validate_models: true,      # Validate model configuration files
          validate_cache: true,       # Validate cache configuration
          validate_dependencies: true # Check optional dependencies
        }

  ## Examples

      # Validate configuration manually
      case ExLLM.Infrastructure.StartupValidator.validate() do
        {:ok, results} ->
          # Configuration is valid
          :ok
        {:error, issues} ->
          # Handle configuration issues
          Logger.error("Configuration issues found")
      end

      # Check specific validation categories
      {:ok, _} = ExLLM.Infrastructure.StartupValidator.validate_providers()
      {:ok, _} = ExLLM.Infrastructure.StartupValidator.validate_cache()
  """

  require Logger
  alias ExLLM.Infrastructure.{Config.ModelConfig, Logger}

  @type validation_result :: {:ok, map()} | {:error, [validation_issue()]}
  @type validation_issue :: %{
          category: atom(),
          severity: :error | :warning | :info,
          message: String.t(),
          details: map()
        }

  @default_config %{
    enabled: true,
    fail_on_error: false,
    log_level: :warn,
    validate_providers: true,
    validate_models: true,
    validate_cache: true,
    validate_dependencies: true
  }

  @doc """
  Performs comprehensive startup validation.

  Returns `{:ok, results}` if validation passes or `{:error, issues}` if problems are found.
  """
  @spec validate() :: validation_result()
  def validate do
    config = get_validation_config()

    if config.enabled do
      Logger.info("Starting ExLLM configuration validation...")

      validation_steps = [
        {:application_config, &validate_application_config/0},
        {:providers, config.validate_providers && (&validate_providers/0)},
        {:models, config.validate_models && (&validate_models/0)},
        {:cache, config.validate_cache && (&validate_cache/0)},
        {:dependencies, config.validate_dependencies && (&validate_dependencies/0)}
      ]

      results =
        validation_steps
        |> Enum.filter(fn {_, validator} -> validator end)
        |> Enum.map(fn {category, validator} ->
          Logger.debug("Validating #{category}...")
          {category, validator.()}
        end)
        |> Map.new()

      # Collect all issues
      all_issues =
        results
        |> Map.values()
        |> Enum.flat_map(fn
          {:ok, _} -> []
          {:error, issues} -> issues
        end)

      # Log results
      log_validation_results(all_issues, config.log_level)

      # Check if we should fail startup
      has_errors = Enum.any?(all_issues, &(&1.severity == :error))

      cond do
        has_errors and config.fail_on_error ->
          {:error, all_issues}

        Enum.empty?(all_issues) ->
          Logger.info("✓ ExLLM configuration validation passed")
          {:ok, results}

        true ->
          Logger.warning("⚠ ExLLM configuration validation completed with issues")
          {:ok, Map.put(results, :issues, all_issues)}
      end
    else
      Logger.debug("ExLLM startup validation disabled")
      {:ok, %{validation_enabled: false}}
    end
  end

  @doc """
  Validates application-level configuration.
  """
  @spec validate_application_config() :: validation_result()
  def validate_application_config do
    issues = []

    # Validate log level
    issues =
      case Application.get_env(:ex_llm, :log_level) do
        level when level in [:debug, :info, :warn, :warning, :error, :none] ->
          issues

        invalid_level ->
          [
            %{
              category: :application_config,
              severity: :warning,
              message: "Invalid log_level: #{inspect(invalid_level)}",
              details: %{
                current_value: invalid_level,
                valid_values: [:debug, :info, :warn, :warning, :error, :none]
              }
            }
            | issues
          ]
      end

    # Validate log components
    issues =
      case Application.get_env(:ex_llm, :log_components) do
        components when is_map(components) ->
          invalid_keys =
            Map.keys(components)
            |> Enum.reject(
              &(&1 in [:requests, :responses, :streaming, :retries, :cache, :models])
            )

          if Enum.empty?(invalid_keys) do
            issues
          else
            [
              %{
                category: :application_config,
                severity: :warning,
                message: "Unknown log_components keys: #{inspect(invalid_keys)}",
                details: %{
                  invalid_keys: invalid_keys,
                  valid_keys: [:requests, :responses, :streaming, :retries, :cache, :models]
                }
              }
              | issues
            ]
          end

        nil ->
          issues

        invalid ->
          [
            %{
              category: :application_config,
              severity: :warning,
              message: "log_components must be a map, got: #{inspect(invalid)}",
              details: %{current_value: invalid}
            }
            | issues
          ]
      end

    case issues do
      [] -> {:ok, %{}}
      issues -> {:error, issues}
    end
  end

  @doc """
  Validates provider configurations.
  """
  @spec validate_providers() :: validation_result()
  def validate_providers do
    issues = []

    # Check if any providers have API keys configured
    configured_providers =
      [:openai, :anthropic, :gemini, :groq, :mistral, :openrouter, :perplexity, :xai]
      |> Enum.filter(&provider_has_api_key?/1)

    issues =
      if Enum.empty?(configured_providers) do
        [
          %{
            category: :providers,
            severity: :info,
            message: "No remote providers configured with API keys",
            details: %{
              suggestion: "Set environment variables like OPENAI_API_KEY to configure providers"
            }
          }
          | issues
        ]
      else
        issues
      end

    # Validate individual provider configurations
    provider_issues =
      configured_providers
      |> Enum.flat_map(&validate_single_provider/1)

    case issues ++ provider_issues do
      [] -> {:ok, %{configured_providers: configured_providers}}
      all_issues -> {:error, all_issues}
    end
  end

  @doc """
  Validates model configuration files.
  """
  @spec validate_models() :: validation_result()
  def validate_models do
    issues = []

    # Check for missing model configuration files
    config_dir = ModelConfig.config_dir()

    providers_with_configs =
      if File.dir?(config_dir) do
        config_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".yml"))
        |> Enum.map(&(&1 |> String.replace(".yml", "") |> String.to_atom()))
      else
        []
      end

    expected_providers = [:openai, :anthropic, :gemini, :groq, :mistral, :openrouter, :perplexity]

    missing_configs =
      expected_providers
      |> Enum.reject(&(&1 in providers_with_configs))

    issues =
      if Enum.empty?(missing_configs) do
        issues
      else
        [
          %{
            category: :models,
            severity: :warning,
            message:
              "Missing model configuration files for providers: #{inspect(missing_configs)}",
            details: %{
              missing_providers: missing_configs,
              expected_location: "config/models/"
            }
          }
          | issues
        ]
      end

    # Validate each provider has a default model
    model_validation_issues =
      providers_with_configs
      |> Enum.flat_map(&validate_provider_models/1)

    case issues ++ model_validation_issues do
      [] -> {:ok, %{providers_with_configs: providers_with_configs}}
      all_issues -> {:error, all_issues}
    end
  end

  @doc """
  Validates cache configuration.
  """
  @spec validate_cache() :: validation_result()
  def validate_cache do
    issues = []

    cache_enabled = Application.get_env(:ex_llm, :cache_enabled, false)

    issues =
      if cache_enabled do
        # Validate cache strategy
        issues =
          case Application.get_env(:ex_llm, :cache_strategy) do
            nil ->
              [
                %{
                  category: :cache,
                  severity: :error,
                  message: "cache_enabled is true but cache_strategy is not configured",
                  details: %{}
                }
                | issues
              ]

            strategy ->
              if Code.ensure_loaded?(strategy) do
                issues
              else
                [
                  %{
                    category: :cache,
                    severity: :error,
                    message: "Cache strategy module not available: #{strategy}",
                    details: %{strategy: strategy}
                  }
                  | issues
                ]
              end
          end

        # Validate disk cache settings
        persist_disk = Application.get_env(:ex_llm, :cache_persist_disk, false)

        if persist_disk do
          cache_path = Application.get_env(:ex_llm, :cache_disk_path, "~/.cache/ex_llm_cache")
          expanded_path = Path.expand(cache_path)

          parent_dir = Path.dirname(expanded_path)

          cond do
            not File.dir?(parent_dir) ->
              [
                %{
                  category: :cache,
                  severity: :warning,
                  message: "Cache directory parent does not exist: #{parent_dir}",
                  details: %{
                    path: parent_dir,
                    suggestion: "Create directory or update cache_disk_path"
                  }
                }
                | issues
              ]

            File.exists?(expanded_path) and not File.dir?(expanded_path) ->
              [
                %{
                  category: :cache,
                  severity: :error,
                  message: "Cache path exists but is not a directory: #{expanded_path}",
                  details: %{path: expanded_path}
                }
                | issues
              ]

            true ->
              issues
          end
        else
          issues
        end
      else
        issues
      end

    case issues do
      [] -> {:ok, %{cache_enabled: cache_enabled}}
      issues -> {:error, issues}
    end
  end

  @doc """
  Validates optional dependencies.
  """
  @spec validate_dependencies() :: validation_result()
  def validate_dependencies do
    issues = []

    # Check Bumblebee for local models
    issues =
      if Code.ensure_loaded?(Bumblebee) do
        issues
      else
        [
          %{
            category: :dependencies,
            severity: :info,
            message: "Bumblebee not available - local model inference disabled",
            details: %{
              suggestion: "Add {:bumblebee, \"~> 0.4.0\"} to deps to enable local models"
            }
          }
          | issues
        ]
      end

    # Check Jason for JSON handling
    issues =
      if Code.ensure_loaded?(Jason) do
        issues
      else
        [
          %{
            category: :dependencies,
            severity: :error,
            message: "Jason not available - JSON encoding/decoding will fail",
            details: %{
              suggestion: "Add {:jason, \"~> 1.4\"} to deps"
            }
          }
          | issues
        ]
      end

    case issues do
      [] -> {:ok, %{}}
      issues -> {:error, issues}
    end
  end

  @doc """
  Run validation during application startup.

  This is called automatically by the Application module.
  """
  @spec run_startup_validation() :: :ok | {:error, [validation_issue()]}
  def run_startup_validation do
    case validate() do
      {:ok, _results} ->
        :ok

      {:error, issues} ->
        config = get_validation_config()

        if config.fail_on_error do
          Logger.error("ExLLM startup validation failed, halting application startup")
          {:error, issues}
        else
          Logger.warning("ExLLM startup validation found issues but continuing startup")
          :ok
        end
    end
  end

  # Private functions

  defp get_validation_config do
    config = Application.get_env(:ex_llm, :startup_validation, %{})
    Map.merge(@default_config, config)
  end

  defp provider_has_api_key?(provider) do
    env_var = get_env_var_name(provider)
    api_key = System.get_env(env_var)
    api_key != nil and api_key != ""
  end

  defp validate_single_provider(provider) do
    issues = []

    # Check if provider module exists
    provider_module = get_provider_module(provider)

    issues =
      if Code.ensure_loaded?(provider_module) do
        issues
      else
        [
          %{
            category: :providers,
            severity: :warning,
            message: "Provider module not available: #{provider_module}",
            details: %{provider: provider, module: provider_module}
          }
          | issues
        ]
      end

    # Validate API key format for specific providers
    case provider do
      :openai ->
        validate_openai_api_key(issues)

      :anthropic ->
        validate_anthropic_api_key(issues)

      _ ->
        issues
    end
  end

  defp validate_openai_api_key(issues) do
    case System.get_env("OPENAI_API_KEY") do
      nil ->
        issues

      key ->
        if String.starts_with?(key, "sk-") and String.length(key) > 20 do
          issues
        else
          [
            %{
              category: :providers,
              severity: :warning,
              message: "OpenAI API key format appears invalid",
              details: %{
                expected_prefix: "sk-",
                current_length: String.length(key),
                suggestion: "Verify API key from OpenAI dashboard"
              }
            }
            | issues
          ]
        end
    end
  end

  defp validate_anthropic_api_key(issues) do
    case System.get_env("ANTHROPIC_API_KEY") do
      nil ->
        issues

      key ->
        if String.starts_with?(key, "sk-ant-") and String.length(key) > 30 do
          issues
        else
          [
            %{
              category: :providers,
              severity: :warning,
              message: "Anthropic API key format appears invalid",
              details: %{
                expected_prefix: "sk-ant-",
                current_length: String.length(key),
                suggestion: "Verify API key from Anthropic console"
              }
            }
            | issues
          ]
        end
    end
  end

  defp validate_provider_models(provider) do
    case ModelConfig.get_default_model(provider) do
      {:ok, _model} ->
        []

      {:error, :missing_default_model_key} ->
        [
          %{
            category: :models,
            severity: :warning,
            message: "No default_model configured for #{provider}",
            details: %{
              provider: provider,
              config_file: "config/models/#{provider}.yml",
              suggestion: "Add 'default_model: model_name' to the configuration file"
            }
          }
        ]

      {:error, :config_file_not_found} ->
        [
          %{
            category: :models,
            severity: :warning,
            message: "Model configuration file not found for #{provider}",
            details: %{
              provider: provider,
              expected_file: "config/models/#{provider}.yml"
            }
          }
        ]
    end
  end

  defp log_validation_results(issues, log_level) do
    if Enum.empty?(issues) do
      log_success_message(log_level)
    else
      grouped_issues = Enum.group_by(issues, & &1.severity)
      error_count = length(Map.get(grouped_issues, :error, []))
      warning_count = length(Map.get(grouped_issues, :warning, []))
      info_count = length(Map.get(grouped_issues, :info, []))

      summary = format_validation_summary(error_count, warning_count, info_count)
      log_summary_by_level(summary, log_level, error_count, warning_count, info_count)

      Enum.each(issues, &log_individual_issue/1)
    end
  end

  defp log_success_message(log_level) do
    if log_level in [:debug, :info] do
      Logger.info("ExLLM configuration validation: ✓ All checks passed")
    end
  end

  defp format_validation_summary(error_count, warning_count, info_count) do
    "ExLLM validation: #{error_count} errors, #{warning_count} warnings, #{info_count} info"
  end

  defp log_summary_by_level(summary, log_level, error_count, warning_count, info_count) do
    case log_level do
      :error ->
        if error_count > 0, do: Logger.error(summary)

      :warn ->
        cond do
          error_count > 0 -> Logger.error(summary)
          warning_count > 0 -> Logger.warning(summary)
          true -> :ok
        end

      _ ->
        cond do
          error_count > 0 -> Logger.error(summary)
          warning_count > 0 -> Logger.warning(summary)
          info_count > 0 -> Logger.info(summary)
          true -> :ok
        end
    end
  end

  defp log_individual_issue(issue) do
    Logger.log(issue.severity, "[#{issue.category}] #{issue.message}")
  end

  defp get_env_var_name(:openai), do: "OPENAI_API_KEY"
  defp get_env_var_name(:anthropic), do: "ANTHROPIC_API_KEY"
  defp get_env_var_name(:gemini), do: "GEMINI_API_KEY"
  defp get_env_var_name(:groq), do: "GROQ_API_KEY"
  defp get_env_var_name(:mistral), do: "MISTRAL_API_KEY"
  defp get_env_var_name(:openrouter), do: "OPENROUTER_API_KEY"
  defp get_env_var_name(:perplexity), do: "PERPLEXITY_API_KEY"
  defp get_env_var_name(:xai), do: "XAI_API_KEY"
  defp get_env_var_name(provider), do: "#{String.upcase(to_string(provider))}_API_KEY"

  defp get_provider_module(:openai), do: ExLLM.Providers.OpenAI
  defp get_provider_module(:anthropic), do: ExLLM.Providers.Anthropic
  defp get_provider_module(:gemini), do: ExLLM.Providers.Gemini
  defp get_provider_module(:groq), do: ExLLM.Providers.Groq
  defp get_provider_module(:mistral), do: ExLLM.Providers.Mistral
  defp get_provider_module(:openrouter), do: ExLLM.Providers.OpenRouter
  defp get_provider_module(:perplexity), do: ExLLM.Providers.Perplexity
  defp get_provider_module(:xai), do: ExLLM.Providers.XAI

  defp get_provider_module(provider),
    do: Module.concat(ExLLM.Providers, Macro.camelize(to_string(provider)))
end
