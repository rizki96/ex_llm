# Compile test support files first
Code.require_file("support/env_helper.ex", __DIR__)
Code.require_file("support/testing_case.ex", __DIR__)
Code.require_file("support/test_helpers.ex", __DIR__)
Code.require_file("support/gemini_oauth2_test_helper.ex", __DIR__)
Code.require_file("support/config_provider_helper.ex", __DIR__)
Code.require_file("support/test_cache_helpers.ex", __DIR__)
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

# Configure default exclusions for fast local development
# These can be overridden with --include flags
default_exclusions = [
  # Exclude by default to speed up local development
  integration: true,
  external: true,
  live_api: true,
  slow: true,
  very_slow: true,
  quota_sensitive: true,
  flaky: true,
  wip: true,

  # OAuth2 tests (legacy tag, will be replaced with :requires_oauth)
  oauth2: true
]

# Check for OAuth2 tokens for backward compatibility
oauth2_available = File.exists?(".gemini_tokens")

if not oauth2_available do
  IO.puts("\n⚠️  OAuth2 tests excluded - no .gemini_tokens file found")
  IO.puts("   Run: elixir scripts/setup_oauth2.exs to enable OAuth2 tests\n")
end

ExUnit.start()
ExUnit.configure(exclude: default_exclusions)
