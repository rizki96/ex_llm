# Compile test support files first
Code.require_file("support/env_helper.ex", __DIR__)
Code.require_file("support/testing_case.ex", __DIR__)
Code.require_file("support/test_helpers.ex", __DIR__)
Code.require_file("support/gemini_oauth2_test_helper.ex", __DIR__)
Code.require_file("support/config_provider_helper.ex", __DIR__)
Code.require_file("support/oauth2_test_case.ex", __DIR__)
Code.require_file("support/capability_helpers.ex", __DIR__)
Code.require_file("support/shared/provider_integration_test.exs", __DIR__)

# Start hackney for tests that use Bypass
{:ok, _} = Application.ensure_all_started(:hackney)

# Apply centralized test configuration
tesla_config = ExLLM.Testing.Config.tesla_config()
app_config = ExLLM.Testing.Config.app_config()
logger_config = ExLLM.Testing.Config.logger_config()

# Set up Tesla configuration
Application.put_env(:tesla, :adapter, tesla_config[:adapter])
Application.put_env(:ex_llm, :use_tesla_mock, tesla_config[:use_tesla_mock])

# Apply ExLLM configuration  
Enum.each(app_config, fn {key, value} ->
  Application.put_env(:ex_llm, key, value)
end)

# Apply Logger configuration
Enum.each(logger_config, fn {key, value} ->
  Application.put_env(:logger, key, value)
end)

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

# Use centralized test configuration for exclusions
default_exclusions = ExLLM.Testing.Config.default_exclusions()

# Check for OAuth2 tokens for backward compatibility
oauth2_available = ExLLM.Testing.Config.oauth2_available?()

if not oauth2_available do
  IO.puts("\n⚠️  OAuth2 tests excluded - no .gemini_tokens file found")
  IO.puts("   Run: elixir scripts/setup_oauth2.exs to enable OAuth2 tests\n")
end

ExUnit.start()
ExUnit.configure(exclude: default_exclusions)
