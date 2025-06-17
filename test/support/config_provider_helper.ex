defmodule ExLLM.Testing.ConfigProviderHelper do
  @moduledoc """
  Helper for setting up static config providers in tests.

  This helper ensures that the Static config provider is properly started
  and returns the PID for use in tests.
  """

  @doc """
  Starts a Static config provider with the given config and returns the PID.

  ## Examples

      config = %{openai: %{api_key: "test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)
      # provider is a PID that can be used with config_provider option
  """
  def setup_static_provider(config) do
    {:ok, pid} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)
    pid
  end

  @doc """
  Starts a Static config provider with invalid API keys for testing error handling.

  This is useful for unit tests that need to verify error handling behavior
  without making real API calls.

  ## Examples

      provider = ConfigProviderHelper.setup_invalid_provider(:openai)
      # Will have an invalid API key that should fail authentication
  """
  def setup_invalid_provider(provider_name) when is_atom(provider_name) do
    config = %{
      provider_name => %{
        api_key: "invalid-test-key-#{provider_name}",
        # Some providers need additional config
        base_url:
          case provider_name do
            :ollama -> "http://localhost:11434"
            _ -> nil
          end
      }
    }

    setup_static_provider(config)
  end

  @doc """
  Temporarily disables environment variable API keys for testing.

  Returns a function to restore the original values.

  ## Examples

      restore_fn = ConfigProviderHelper.disable_env_api_keys()
      # Run tests without environment API keys
      restore_fn.()
  """
  def disable_env_api_keys() do
    env_vars = [
      "OPENAI_API_KEY",
      "ANTHROPIC_API_KEY",
      "GROQ_API_KEY",
      "MISTRAL_API_KEY",
      "PERPLEXITY_API_KEY",
      "OPENROUTER_API_KEY",
      "GOOGLE_API_KEY",
      "GEMINI_API_KEY"
    ]

    # Save current values
    original_values =
      Enum.map(env_vars, fn var ->
        {var, System.get_env(var)}
      end)

    # Clear them
    Enum.each(env_vars, &System.delete_env/1)

    # Return restore function
    fn ->
      Enum.each(original_values, fn
        {_var, nil} -> :ok
        {var, value} -> System.put_env(var, value)
      end)
    end
  end
end
