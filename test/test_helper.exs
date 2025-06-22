# Compile test support files first
Code.require_file("support/env_helper.ex", __DIR__)
Code.require_file("support/testing_case.ex", __DIR__)
Code.require_file("support/test_helpers.ex", __DIR__)
Code.require_file("support/gemini_oauth2_test_helper.ex", __DIR__)
Code.require_file("support/config_provider_helper.ex", __DIR__)
Code.require_file("support/oauth2_test_case.ex", __DIR__)
Code.require_file("support/capability_helpers.ex", __DIR__)
Code.require_file("support/shared/provider_integration_test.exs", __DIR__)

# Load environment variables from .env file if available
case ExLLM.Testing.EnvHelper.load_env(warn_missing: false) do
  :ok ->
    # Check which API keys are available
    available_keys =
      ExLLM.Testing.EnvHelper.default_api_keys()
      |> Enum.filter(fn key -> System.get_env(key) != nil end)

    if length(available_keys) > 0 do
      available_providers =
        available_keys
        |> Enum.map(fn key ->
          key
          |> String.replace("_API_KEY", "")
          |> String.replace("_HOST", "")
          |> String.downcase()
        end)

      IO.puts("\n✅ Loaded API keys from .env for: #{Enum.join(available_providers, ", ")}")
    end

  {:error, reason} ->
    IO.puts("\n⚠️  Failed to load .env file: #{inspect(reason)}")
end

# Hybrid Testing Strategy: Balance speed with live API validation
run_live = System.get_env("MIX_RUN_LIVE") == "true"
cache_fresh = ExLLM.Testing.Cache.fresh?(max_age: 24 * 60 * 60)

default_exclusions =
  if run_live or cache_fresh do
    # Include cached API tests when cache is fresh or explicitly requested
    IO.puts("\n🚀 Running with API tests enabled")
    if run_live, do: IO.puts("   Mode: Live API calls")
    if cache_fresh and not run_live, do: IO.puts("   Mode: Cached responses (fresh)")

    [
      # Always exclude these for stability
      slow: true,
      very_slow: true,
      quota_sensitive: true,
      flaky: true,
      wip: true,
      oauth2: true
    ]
  else
    # Exclude live tests when cache is stale
    IO.puts("\n⚠️  Test cache is stale (>24h) - excluding live API tests")
    IO.puts("   💡 Run `mix test.live` to refresh cache and test against live APIs")
    IO.puts("   📊 Check cache status: `mix cache.status`")

    [
      # Exclude API tests when cache is stale
      integration: true,
      external: true,
      live_api: true,
      slow: true,
      very_slow: true,
      quota_sensitive: true,
      flaky: true,
      wip: true,
      oauth2: true
    ]
  end

# Check for OAuth2 tokens for backward compatibility
oauth2_available = File.exists?(".gemini_tokens")

if not oauth2_available do
  IO.puts("\n⚠️  OAuth2 tests excluded - no .gemini_tokens file found")
  IO.puts("   Run: elixir scripts/setup_oauth2.exs to enable OAuth2 tests\n")
end

ExUnit.start()
ExUnit.configure(exclude: default_exclusions)
