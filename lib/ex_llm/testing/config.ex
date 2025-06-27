defmodule ExLLM.Testing.Config do
  @moduledoc """
  Centralized test configuration for ExLLM.

  This module provides a single source of truth for all test-related configuration,
  including tag strategies, environment requirements, cache behavior, and provider
  settings.

  ## Test Categories

  Tests are organized into semantic categories using ExUnit tags:

  ### Core Categories
  - `:unit` - Pure unit tests (no external dependencies)
  - `:integration` - Tests requiring external services or API calls  
  - `:external` - Tests calling external APIs (subset of integration)
  - `:live_api` - Tests requiring live API calls (not cached)

  ### Stability Categories  
  - `:slow` - Tests that take >5 seconds to complete
  - `:very_slow` - Tests that take >30 seconds to complete
  - `:flaky` - Tests with intermittent failures
  - `:wip` - Work-in-progress tests (should not run in CI)
  - `:quota_sensitive` - Tests that consume significant API quota

  ### Provider Categories
  - `provider: :anthropic` - Anthropic Claude tests
  - `provider: :openai` - OpenAI GPT tests
  - `provider: :gemini` - Google Gemini tests
  - `provider: :ollama` - Local Ollama tests
  - etc.

  ### Requirement Categories
  - `:requires_api_key` - Tests needing API authentication
  - `:requires_oauth` - Tests needing OAuth2 authentication
  - `:requires_service` - Tests needing local services (Ollama, LM Studio)
  - `:requires_resource` - Tests needing specific resources (tuned models, etc.)
  """

  @doc """
  Default test exclusions based on cache configuration and environment.

  Integration tests run against live APIs by default unless caching is explicitly enabled.
  """
  @spec default_exclusions() :: keyword()
  def default_exclusions do
    cache_enabled = cache_enabled?()
    run_live = System.get_env("MIX_RUN_LIVE") == "true"

    base_exclusions = always_excluded_tags()

    cond do
      run_live ->
        # Force live mode - always include integration tests, never cache
        log_test_mode(true, false)
        base_exclusions

      cache_enabled ->
        # Cache mode explicitly enabled - use cached responses when available
        cache_fresh = cache_fresh?()
        log_test_mode(false, cache_fresh)

        if cache_fresh do
          # Cache is fresh - include integration tests using cached responses
          base_exclusions
        else
          # Cache is stale - exclude integration tests or run live
          log_cache_stale()
          base_exclusions ++ api_excluded_tags()
        end

      true ->
        # Default mode - run integration tests against live APIs (no caching)
        log_test_mode(:live_default, false)
        base_exclusions
    end
  end

  @doc """
  Tags that are always excluded for stability.
  """
  @spec always_excluded_tags() :: keyword()
  def always_excluded_tags do
    [
      slow: true,
      very_slow: true,
      quota_sensitive: true,
      flaky: true,
      wip: true,
      oauth2: true
    ]
  end

  @doc """
  Tags excluded when API cache is stale.
  """
  @spec api_excluded_tags() :: keyword()
  def api_excluded_tags do
    [
      integration: true,
      external: true,
      live_api: true
    ]
  end

  @doc """
  CI-specific test exclusions for fast, reliable builds.
  """
  @spec ci_exclusions() :: keyword()
  def ci_exclusions do
    [
      wip: true,
      flaky: true,
      quota_sensitive: true,
      very_slow: true
    ]
  end

  @doc """
  Provider-specific API key mappings.
  Uses centralized environment variable definitions.
  """
  @spec provider_api_keys() :: map()
  def provider_api_keys do
    # Transform the centralized definitions to match the expected format
    ExLLM.Environment.all_api_key_vars()
    |> Enum.reduce(%{}, fn var, acc ->
      provider = provider_from_api_key_var(var)

      if provider do
        existing = Map.get(acc, provider, [])
        Map.put(acc, provider, Enum.uniq([var | existing]))
      else
        acc
      end
    end)
  end

  @doc """
  Standard list of API keys for environment checking.
  """
  @spec default_api_keys() :: list(String.t())
  def default_api_keys do
    ExLLM.Environment.all_api_key_vars()
  end

  # Helper to extract provider from API key variable name
  defp provider_from_api_key_var(var) do
    case var do
      "ANTHROPIC_API_KEY" -> :anthropic
      "OPENAI_API_KEY" -> :openai
      "GEMINI_API_KEY" -> :gemini
      "GOOGLE_API_KEY" -> :gemini
      "GROQ_API_KEY" -> :groq
      "MISTRAL_API_KEY" -> :mistral
      "OPENROUTER_API_KEY" -> :openrouter
      "PERPLEXITY_API_KEY" -> :perplexity
      "XAI_API_KEY" -> :xai
      "OLLAMA_HOST" -> :ollama
      "LMSTUDIO_HOST" -> :lmstudio
      _ -> nil
    end
  end

  @doc """
  Tesla configuration for tests.

  Unit tests should use Tesla.Mock, but integration tests should use real HTTP adapter
  to make actual API calls.
  """
  @spec tesla_config() :: keyword()
  def tesla_config do
    cache_enabled = cache_enabled?()
    run_live = System.get_env("MIX_RUN_LIVE") == "true"

    # Use real HTTP adapter for integration tests, mock for unit tests
    if cache_enabled or run_live or integration_tests_enabled?() do
      [
        adapter: Tesla.Adapter.Hackney,
        use_tesla_mock: false
      ]
    else
      [
        adapter: Tesla.Mock,
        use_tesla_mock: true
      ]
    end
  end

  @doc """
  ExLLM application configuration for tests.
  """
  @spec app_config() :: keyword()
  def app_config do
    [
      cache_strategy: ExLLM.Cache.Strategies.Test,
      cache_enabled: cache_enabled?(),
      cache_persist_disk: false,
      startup_validation: %{enabled: false},
      log_level: log_level(),
      log_components: log_components()
    ]
  end

  @doc """
  Logger configuration for tests.
  """
  @spec logger_config() :: keyword()
  def logger_config do
    [
      level: :error,
      console: [metadata: []]
    ]
  end

  @doc """
  Environment file path for test API keys.
  """
  @spec env_file_path() :: String.t()
  def env_file_path do
    System.get_env("EX_LLM_ENV_FILE") ||
      Application.get_env(:ex_llm, :env_file) ||
      Path.join(File.cwd!(), ".env")
  end

  @doc """
  Check if test cache is fresh (within 24 hours).
  """
  @spec cache_fresh?() :: boolean()
  def cache_fresh? do
    try do
      ExLLM.Testing.Cache.fresh?(max_age: 24 * 60 * 60)
    rescue
      _ -> false
    end
  end

  @doc """
  Check if test caching is enabled.
  """
  @spec cache_enabled?() :: boolean()
  def cache_enabled? do
    System.get_env("EX_LLM_TEST_CACHE_ENABLED") == "true"
  end

  @doc """
  Check if OAuth2 tokens are available.
  """
  @spec oauth2_available?() :: boolean()
  def oauth2_available? do
    File.exists?(".gemini_tokens")
  end

  @doc """
  Check if debug logging is enabled for tests.
  """
  @spec debug_logging?() :: boolean()
  def debug_logging? do
    System.get_env("EX_LLM_LOG_LEVEL") == "debug"
  end

  @doc """
  Check if integration tests should use real HTTP adapter.

  Always return true - integration tests should use real HTTP by default
  as per the new design where cache is disabled by default.
  """
  @spec integration_tests_enabled?() :: boolean()
  def integration_tests_enabled? do
    true
  end

  # Private functions

  defp log_level do
    if debug_logging?() do
      :debug
    else
      :none
    end
  end

  defp log_components do
    if debug_logging?() do
      %{
        requests: true,
        responses: true,
        streaming: true,
        retries: true,
        cache: true,
        models: true
      }
    else
      %{
        requests: false,
        responses: false,
        streaming: false,
        retries: false,
        cache: false,
        models: false
      }
    end
  end

  defp log_test_mode(mode, cache_fresh) do
    case mode do
      true ->
        IO.puts("\n🚀 Running with integration tests enabled")
        IO.puts("   Mode: Live API calls (forced)")

      :live_default ->
        IO.puts("\n🚀 Running with integration tests enabled")
        IO.puts("   Mode: Live API calls (default - cache disabled)")
        IO.puts("   💡 Enable caching with: export EX_LLM_TEST_CACHE_ENABLED=true")

      false ->
        IO.puts("\n🚀 Running with integration tests enabled")

        if cache_fresh do
          IO.puts("   Mode: Cached responses (fresh)")
        else
          IO.puts("   Mode: Cache enabled but stale")
        end
    end
  end

  defp log_cache_stale do
    IO.puts("\n⚠️  Cache is enabled but stale (>24h) - excluding integration tests")
    IO.puts("   💡 Options:")
    IO.puts("     - Run `mix test.live` to refresh cache and run against live APIs")
    IO.puts("     - Run `MIX_RUN_LIVE=true mix test` to bypass cache and use live APIs")
    IO.puts("     - Disable cache with: unset EX_LLM_TEST_CACHE_ENABLED")
    IO.puts("   📊 Check cache status: `mix cache.status`")
  end
end
