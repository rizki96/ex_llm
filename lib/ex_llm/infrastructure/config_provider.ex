defmodule ExLLM.Infrastructure.ConfigProvider do
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
      {:ok, provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)
      ExLLM.OpenAI.chat(messages, config_provider: provider)

      # Using environment-based configuration
      ExLLM.OpenAI.chat(messages, config_provider: ExLLM.Infrastructure.ConfigProvider.Env)
  """

  @doc """
  Gets configuration value for a provider and key.
  """
  @callback get(provider :: atom(), key :: atom()) :: any()

  @doc """
  Gets all configuration for a provider.
  """
  @callback get_all(provider :: atom()) :: map()

  @doc """
  Gets configuration from a config provider instance.
  """
  @spec get_config(module() | pid(), atom()) :: {:ok, map()} | {:error, term()}
  def get_config(provider_module, provider_name) when is_atom(provider_module) do
    try do
      config = provider_module.get_all(provider_name)
      {:ok, config}
    rescue
      _ -> {:error, :provider_error}
    end
  end

  def get_config(provider_pid, provider_name) when is_pid(provider_pid) do
    try do
      config = Agent.get(provider_pid, & &1)

      case Map.get(config, provider_name) do
        nil -> {:error, :not_found}
        provider_config -> {:ok, provider_config}
      end
    rescue
      _ -> {:error, :provider_error}
    end
  end

  defmodule Static do
    @moduledoc """
    Static configuration provider for testing and library usage.

    ## Usage

        config = %{
          openai: %{api_key: "sk-test", model: "gpt-4"},
          anthropic: %{api_key: "api-test", model: "claude-3"}
        }
        {:ok, provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)
        ExLLM.OpenAI.chat(messages, config_provider: provider)
    """
    use Agent

    @behaviour ExLLM.Infrastructure.ConfigProvider

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
    def get_all(provider_pid) do
      Agent.get(provider_pid, & &1)
    end
  end

  defmodule Default do
    @moduledoc """
    Default configuration provider that reads from environment variables.
    This is an alias for the Env provider for backward compatibility.
    """

    @deprecated "Use ExLLM.Infrastructure.ConfigProvider.Env instead"
    @behaviour ExLLM.Infrastructure.ConfigProvider

    @impl true
    def get(provider, key), do: ExLLM.Infrastructure.ConfigProvider.Env.get(provider, key)

    @impl true
    def get_all(provider), do: ExLLM.Infrastructure.ConfigProvider.Env.get_all(provider)
  end

  defmodule Env do
    @moduledoc """
    Environment-based configuration provider.

    Reads configuration from environment variables using standard naming:
    - `OPENAI_API_KEY` for OpenAI
    - `ANTHROPIC_API_KEY` for Anthropic
    - etc.
    """

    @behaviour ExLLM.Infrastructure.ConfigProvider

    @impl true
    def get(provider, key) when is_atom(provider) and is_atom(key) do
      get_known_config(provider, key) || get_generic_config(provider, key)
    end

    defp get_known_config(provider, key) do
      case {provider, key} do
        # API Keys
        {prov, :api_key} ->
          case ExLLM.Environment.api_key_var(prov) do
            vars when is_list(vars) -> Enum.find_value(vars, &System.get_env/1)
            var when is_binary(var) -> System.get_env(var)
            _ -> nil
          end

        # Base URLs
        {prov, :base_url} ->
          case ExLLM.Environment.base_url_var(prov) do
            {var, default} -> System.get_env(var, default)
            _ -> nil
          end

        # Models
        {prov, :model} ->
          case ExLLM.Environment.model_var(prov) do
            {var, default} -> System.get_env(var, default)
            _ -> nil
          end

        # Special cases
        {:openai, :organization} ->
          System.get_env("OPENAI_ORGANIZATION")

        {:openrouter, :app_name} ->
          System.get_env("OPENROUTER_APP_NAME")

        {:openrouter, :app_url} ->
          System.get_env("OPENROUTER_APP_URL")

        {:ollama, :base_url} ->
          System.get_env("OLLAMA_BASE_URL") || System.get_env("OLLAMA_HOST") ||
            "http://localhost:11434"

        _ ->
          nil
      end
    end

    defp get_generic_config(provider, key) do
      env_var = "#{String.upcase(to_string(provider))}_#{String.upcase(to_string(key))}"
      System.get_env(env_var)
    end

    @impl true
    def get_all(provider) when is_atom(provider) do
      # Get base configuration from centralized environment
      base_config = ExLLM.Environment.provider_config(provider)

      # Add provider-specific extras
      case provider do
        :openai ->
          Map.put(base_config, :organization, get(:openai, :organization))

        :openrouter ->
          base_config
          |> Map.put(:app_name, get(:openrouter, :app_name))
          |> Map.put(:app_url, get(:openrouter, :app_url))

        :test_provider ->
          Map.put(base_config, :default_model, get(:test_provider, :default_model))

        _ ->
          base_config
      end
    end
  end
end
