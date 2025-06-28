# Ensure critical lib modules are available before loading support files
Code.ensure_loaded(ExLLM.Testing.Config)
Code.ensure_loaded(ExLLM.Environment)

# Compile test support files
Code.require_file("support/env_helper.ex", __DIR__)
Code.require_file("support/testing_case.ex", __DIR__)
Code.require_file("support/test_helpers.ex", __DIR__)
Code.require_file("support/gemini_oauth2_test_helper.ex", __DIR__)
Code.require_file("support/config_provider_helper.ex", __DIR__)
Code.require_file("support/oauth2_test_case.ex", __DIR__)
Code.require_file("support/capability_helpers.ex", __DIR__)
Code.require_file("support/service_helpers.ex", __DIR__)
Code.require_file("support/shared/provider_integration_test.exs", __DIR__)

# Start hackney for tests that use Bypass
{:ok, _} = Application.ensure_all_started(:hackney)

# Ensure ExLLM application is started (this initializes circuit breaker ETS table)
{:ok, _} = Application.ensure_all_started(:ex_llm)

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
# Try loading from .env file
env_result =
  try do
    ExLLM.Testing.EnvHelper.load_env(warn_missing: false)
  rescue
    _ ->
      # Fallback: Try to load .env manually if helper fails
      if File.exists?(".env") do
        File.read!(".env")
        |> String.split("\n")
        |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(String.trim(&1), "#")))
        |> Enum.each(fn line ->
          case String.split(line, "=", parts: 2) do
            [key, value] ->
              key = String.trim(key)

              value =
                String.trim(value) |> String.trim_leading("\"") |> String.trim_trailing("\"")

              System.put_env(key, value)

            _ ->
              :ok
          end
        end)

        :ok
      else
        {:error, :no_env_file}
      end
  end

case env_result do
  :ok ->
    # Check which API keys are available
    available_keys =
      [
        "ANTHROPIC_API_KEY",
        "OPENAI_API_KEY",
        "GEMINI_API_KEY",
        "GROQ_API_KEY",
        "MISTRAL_API_KEY",
        "OPENROUTER_API_KEY",
        "PERPLEXITY_API_KEY",
        "XAI_API_KEY"
      ]
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
    IO.puts("   💡 Run tests with: ./scripts/run_with_env.sh mix test")
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
