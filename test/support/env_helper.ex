defmodule ExLLM.Testing.EnvHelper do
  @moduledoc """
  Helper module for loading environment variables from .env files in tests.

  This module provides functionality to load API keys and other configuration
  from .env files, making it easier to run integration tests without wrapper scripts.

  ## Usage

  In your test files that need API keys:

      setup do
        ExLLM.Testing.EnvHelper.load_env()
        :ok
      end

  ## .env File Format

  Create a `.env` file in your project root with your API keys:

      ANTHROPIC_API_KEY=your-key-here
      OPENAI_API_KEY=your-key-here
      GEMINI_API_KEY=your-key-here
      # ... other keys

  ## Custom .env Location

  You can specify a custom .env file location:

      # In config/test.exs
      config :ex_llm, :env_file, ".env.test"
      
      # Or via environment variable
      EX_LLM_ENV_FILE=.env.local mix test
  """

  require Logger

  @default_env_file ".env"
  @env_file_env_var "EX_LLM_ENV_FILE"

  @doc """
  Loads environment variables from the configured .env file.

  The .env file location is determined in this order:
  1. EX_LLM_ENV_FILE environment variable
  2. :ex_llm, :env_file application config
  3. Default: .env in project root

  ## Options

    * `:required` - List of required environment variables that must be present
    * `:warn_missing` - Whether to warn about missing variables (default: true)
    * `:override` - Whether to override existing environment variables (default: false)
    
  ## Examples

      # Load with defaults
      EnvHelper.load_env()
      
      # Require specific keys
      EnvHelper.load_env(required: ["OPENAI_API_KEY", "ANTHROPIC_API_KEY"])
      
      # Don't override existing vars
      EnvHelper.load_env(override: false)
  """
  @spec load_env(keyword()) :: :ok | {:error, String.t()}
  def load_env(opts \\ []) do
    env_file = get_env_file_path()

    case load_env_file(env_file, opts) do
      :ok ->
        validate_required_vars(opts)
        :ok

      {:error, :enoent} ->
        if Keyword.get(opts, :warn_missing, true) do
          Logger.warning("No .env file found at #{env_file}")
        end

        validate_required_vars(opts)

      {:error, reason} = error ->
        Logger.error("Failed to load .env file: #{reason}")
        error
    end
  end

  @doc """
  Checks if all required API keys are present in the environment.

  ## Examples

      # Check default provider keys
      {:ok, available} = EnvHelper.check_api_keys()
      
      # Check specific keys
      {:ok, available} = EnvHelper.check_api_keys([
        "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY"
      ])
  """
  @spec check_api_keys(list(String.t()) | nil) :: {:ok, map()} | {:error, list(String.t())}
  def check_api_keys(keys \\ nil) do
    keys = keys || default_api_keys()

    results =
      Enum.map(keys, fn key ->
        {key, System.get_env(key) != nil}
      end)
      |> Map.new()

    missing =
      results
      |> Enum.filter(fn {_key, present} -> not present end)
      |> Enum.map(fn {key, _} -> key end)

    if Enum.empty?(missing) do
      {:ok, results}
    else
      {:error, missing}
    end
  end

  @doc """
  Ensures the test environment has required API keys loaded.

  This is useful in setup blocks to skip tests when keys are missing:

      setup do
        case EnvHelper.ensure_api_keys(["OPENAI_API_KEY"]) do
          :ok -> 
            :ok
          {:error, missing} ->
            {:skip, "Missing API keys: " <> Enum.join(missing, ", ")}
        end
      end
  """
  @spec ensure_api_keys(list(String.t())) :: :ok | {:error, list(String.t())}
  def ensure_api_keys(required_keys) do
    case check_api_keys(required_keys) do
      {:ok, _} -> :ok
      {:error, missing} -> {:error, missing}
    end
  end

  @doc """
  Refreshes OAuth2 tokens for providers that support OAuth authentication.

  Currently supports:
  - Gemini OAuth2 tokens (for Permissions, Corpus, Document APIs)

  ## Examples

      # Refresh OAuth tokens automatically in test setup
      case ExLLM.Testing.EnvHelper.refresh_oauth_tokens() do
        :ok -> 
          IO.puts("OAuth tokens refreshed")
        {:error, reason} -> 
          IO.puts("OAuth refresh failed: \#{reason}")
      end
  """
  @spec refresh_oauth_tokens(keyword()) :: :ok | {:error, String.t()}
  def refresh_oauth_tokens(opts \\ []) do
    results = []

    # Check if Gemini OAuth refresh is needed
    results =
      if should_refresh_gemini_oauth?(opts) do
        case refresh_gemini_oauth() do
          :ok -> results
          {:error, reason} -> [{:gemini, {:error, reason}} | results]
        end
      else
        results
      end

    # Check if all refreshes succeeded
    errors = Enum.filter(results, fn {_, result} -> match?({:error, _}, result) end)

    if Enum.empty?(errors) do
      :ok
    else
      error_msg =
        errors
        |> Enum.map(fn {provider, {:error, reason}} -> "#{provider}: #{reason}" end)
        |> Enum.join(", ")

      {:error, "OAuth refresh failed: #{error_msg}"}
    end
  end

  @doc """
  Setup function for OAuth2 tests that automatically refreshes tokens if needed.

  Use this in your test setup blocks:

      setup do
        ExLLM.Testing.EnvHelper.setup_oauth()
      end
  """
  @spec setup_oauth(map()) :: map()
  def setup_oauth(context \\ %{}) do
    case refresh_oauth_tokens() do
      :ok ->
        # Also get the OAuth token if available
        if Code.ensure_loaded?(ExLLM.Testing.GeminiOAuth2Helper) do
          case ExLLM.Testing.GeminiOAuth2Helper.get_valid_token() do
            {:ok, token} ->
              Map.put(context, :oauth_token, token)

            _ ->
              context
          end
        else
          context
        end

      {:error, reason} ->
        IO.puts("⚠️  OAuth refresh failed: #{reason}")
        context
    end
  end

  # Private functions

  defp get_env_file_path do
    cond do
      env_var = System.get_env(@env_file_env_var) ->
        env_var

      config_path = Application.get_env(:ex_llm, :env_file) ->
        config_path

      true ->
        Path.join(File.cwd!(), @default_env_file)
    end
  end

  defp load_env_file(path, opts) do
    case File.read(path) do
      {:ok, content} ->
        parse_and_set_env(content, opts)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_and_set_env(content, opts) do
    override = Keyword.get(opts, :override, false)

    content
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(String.trim(&1), "#")))
    |> Enum.each(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          key = String.trim(key)
          value = String.trim(value) |> strip_quotes()

          if override or System.get_env(key) == nil do
            System.put_env(key, value)
          end

        _ ->
          :ok
      end
    end)
  end

  defp strip_quotes(value) do
    value
    |> String.trim()
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
    |> String.trim_leading("'")
    |> String.trim_trailing("'")
  end

  defp validate_required_vars(opts) do
    case Keyword.get(opts, :required) do
      nil ->
        :ok

      required ->
        missing = Enum.filter(required, &(System.get_env(&1) == nil))

        if not Enum.empty?(missing) do
          Logger.error("Missing required environment variables: #{Enum.join(missing, ", ")}")
          {:error, {:missing_env_vars, missing}}
        else
          :ok
        end
    end
  end

  @doc """
  Returns the default list of API keys to check for.
  """
  def default_api_keys do
    [
      "ANTHROPIC_API_KEY",
      "OPENAI_API_KEY",
      "GEMINI_API_KEY",
      "GROQ_API_KEY",
      "MISTRAL_API_KEY",
      "OPENROUTER_API_KEY",
      "PERPLEXITY_API_KEY",
      "XAI_API_KEY",
      "OLLAMA_HOST",
      "LMSTUDIO_HOST"
    ]
  end

  defp should_refresh_gemini_oauth?(opts) do
    # Skip if explicitly disabled
    if Keyword.get(opts, :skip_gemini, false) do
      false
    else
      # Check if we have OAuth credentials
      has_client_id = System.get_env("GOOGLE_CLIENT_ID") != nil
      has_client_secret = System.get_env("GOOGLE_CLIENT_SECRET") != nil
      token_file_exists = File.exists?(".gemini_tokens")

      has_client_id and has_client_secret and token_file_exists
    end
  end

  defp refresh_gemini_oauth do
    refresh_script = Path.join(File.cwd!(), "scripts/refresh_oauth2_token.exs")

    if File.exists?(refresh_script) do
      IO.puts("🔄 Refreshing Gemini OAuth2 tokens...")

      case System.cmd("elixir", [refresh_script], stderr_to_stdout: true) do
        {output, 0} ->
          if String.contains?(output, "✅") do
            IO.puts("✅ Gemini OAuth tokens refreshed")
            :ok
          else
            {:error, "Token refresh did not complete successfully"}
          end

        {output, exit_code} ->
          # Extract meaningful error from output
          error_lines =
            output
            |> String.split("\n")
            |> Enum.filter(&String.contains?(&1, "❌"))
            |> Enum.join("; ")

          if error_lines == "" do
            {:error, "Token refresh failed with exit code #{exit_code}"}
          else
            {:error, error_lines}
          end
      end
    else
      {:error, "OAuth refresh script not found at #{refresh_script}"}
    end
  end
end
