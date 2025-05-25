defmodule ExLLM.ConfigProvider do
  @moduledoc """
  Behaviour for configuration providers.

  This allows modules to receive configuration through dependency injection
  rather than directly accessing application configuration, making them more 
  portable and testable.

  ## Example

      # Using static configuration
      config = %{
        openai: %{api_key: "sk-..."},
        anthropic: %{api_key: "api-..."}
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      ExLLM.OpenAI.chat(messages, config_provider: provider)

      # Using environment-based configuration
      ExLLM.OpenAI.chat(messages, config_provider: ExLLM.ConfigProvider.Env)
  """

  @doc """
  Gets configuration value for a provider and key.
  """
  @callback get(provider :: atom(), key :: atom()) :: any()

  @doc """
  Gets all configuration for a provider.
  """
  @callback get_all(provider :: atom()) :: map()

  defmodule Static do
    @moduledoc """
    Static configuration provider for testing and library usage.

    ## Usage

        config = %{
          openai: %{api_key: "sk-test", model: "gpt-4"},
          anthropic: %{api_key: "api-test", model: "claude-3"}
        }
        {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
        ExLLM.OpenAI.chat(messages, config_provider: provider)
    """
    use Agent

    @behaviour ExLLM.ConfigProvider

    def start_link(config) do
      Agent.start_link(fn -> config end)
    end

    @impl true
    def get(provider, key) when is_atom(key) do
      Agent.get(provider, &Map.get(&1, key))
    end

    def get(provider, [head | tail]) when is_atom(head) do
      Agent.get(provider, fn config ->
        get_in(config, [head | tail])
      end)
    end

    @impl true
    def get_all(provider) do
      Agent.get(provider, & &1)
    end
  end

  defmodule Env do
    @moduledoc """
    Environment-based configuration provider.

    Reads configuration from environment variables using standard naming:
    - `OPENAI_API_KEY` for OpenAI
    - `ANTHROPIC_API_KEY` for Anthropic
    - etc.
    """

    @behaviour ExLLM.ConfigProvider

    @impl true
    def get(provider, key) when is_atom(provider) and is_atom(key) do
      get_known_config(provider, key) || get_generic_config(provider, key)
    end

    defp get_known_config(:openai, :api_key), do: System.get_env("OPENAI_API_KEY")
    defp get_known_config(:openai, :base_url), do: System.get_env("OPENAI_BASE_URL", "https://api.openai.com/v1")
    defp get_known_config(:openai, :model), do: System.get_env("OPENAI_MODEL", "gpt-4-turbo-preview")

    defp get_known_config(:anthropic, :api_key), do: System.get_env("ANTHROPIC_API_KEY")
    defp get_known_config(:anthropic, :base_url), do: System.get_env("ANTHROPIC_BASE_URL", "https://api.anthropic.com/v1")
    defp get_known_config(:anthropic, :model), do: System.get_env("ANTHROPIC_MODEL", "claude-sonnet-4-20250514")

    defp get_known_config(:ollama, :base_url), do: System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")
    defp get_known_config(:ollama, :model), do: System.get_env("OLLAMA_MODEL", "llama2")
    defp get_known_config(_, _), do: nil

    defp get_generic_config(provider, key) do
      env_var = "#{String.upcase(to_string(provider))}_#{String.upcase(to_string(key))}"
      System.get_env(env_var)
    end

    @impl true
    def get_all(provider) when is_atom(provider) do
      case provider do
        :openai ->
          %{
            api_key: get(:openai, :api_key),
            base_url: get(:openai, :base_url),
            model: get(:openai, :model)
          }

        :anthropic ->
          %{
            api_key: get(:anthropic, :api_key),
            base_url: get(:anthropic, :base_url),
            model: get(:anthropic, :model)
          }

        :ollama ->
          %{
            base_url: get(:ollama, :base_url),
            model: get(:ollama, :model)
          }

        _ ->
          %{}
      end
    end
  end
end
