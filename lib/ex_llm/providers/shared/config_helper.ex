defmodule ExLLM.Providers.Shared.ConfigHelper do
  @moduledoc false

  alias ExLLM.{Infrastructure.ConfigProvider, Infrastructure.Config.ModelConfig}

  @doc """
  Get configuration for a specific adapter from the config provider.

  ## Examples

      iex> ConfigHelper.get_config(:anthropic, ExLLM.Infrastructure.ConfigProvider.Env)
      %{api_key: "sk-...", model: "claude-3-5-sonnet", ...}
  """
  def get_config(adapter_name, config_provider) do
    case config_provider do
      ConfigProvider.Env ->
        build_env_config(adapter_name)

      provider when is_pid(provider) ->
        # Static provider
        adapter_config =
          ExLLM.Infrastructure.ConfigProvider.Static.get(provider, adapter_name) || %{}

        normalize_config(adapter_config)

      provider ->
        # Custom provider
        adapter_config = provider.get_all(adapter_name) || %{}
        normalize_config(adapter_config)
    end
  end

  @doc """
  Get API key from config with environment variable fallback.

  ## Examples

      iex> ConfigHelper.get_api_key(%{api_key: "sk-123"}, "OPENAI_API_KEY")
      "sk-123"
      
      iex> ConfigHelper.get_api_key(%{}, "OPENAI_API_KEY")
      "env-api-key"  # From environment
  """
  def get_api_key(config, env_var_name) do
    Map.get(config, :api_key) || System.get_env(env_var_name)
  end

  @doc """
  Get the default model for an adapter, raising if not configured.

  ## Examples

      iex> ConfigHelper.ensure_default_model(:openai)
      "gpt-3.5-turbo"
  """
  def ensure_default_model(adapter_name) do
    case ModelConfig.get_default_model(adapter_name) do
      nil ->
        adapter_str = adapter_name |> to_string() |> String.capitalize()

        raise "Missing configuration: No default model found for #{adapter_str}. " <>
                "Please ensure config/models/#{adapter_name}.yml exists and contains a 'default_model' field."

      model ->
        model
    end
  end

  @doc """
  Get the config provider from options with application default fallback.
  """
  def get_config_provider(options) do
    Keyword.get(
      options,
      :config_provider,
      Application.get_env(:ex_llm, :config_provider, ConfigProvider.Default)
    )
  end

  # Private functions

  defp build_env_config(:anthropic) do
    %{
      api_key: ConfigProvider.Env.get(:anthropic, :api_key),
      base_url: ConfigProvider.Env.get(:anthropic, :base_url),
      model: ConfigProvider.Env.get(:anthropic, :model),
      max_tokens: nil
    }
  end

  defp build_env_config(:openai) do
    %{
      api_key: ConfigProvider.Env.get(:openai, :api_key),
      base_url: ConfigProvider.Env.get(:openai, :base_url),
      model: ConfigProvider.Env.get(:openai, :model),
      organization: ConfigProvider.Env.get(:openai, :organization)
    }
  end

  defp build_env_config(:groq) do
    %{
      api_key: ConfigProvider.Env.get(:groq, :api_key),
      base_url: ConfigProvider.Env.get(:groq, :base_url),
      model: ConfigProvider.Env.get(:groq, :model)
    }
  end

  defp build_env_config(:gemini) do
    %{
      api_key: ConfigProvider.Env.get(:gemini, :api_key),
      base_url: ConfigProvider.Env.get(:gemini, :base_url),
      model: ConfigProvider.Env.get(:gemini, :model)
    }
  end

  defp build_env_config(:openrouter) do
    %{
      api_key: ConfigProvider.Env.get(:openrouter, :api_key),
      base_url: ConfigProvider.Env.get(:openrouter, :base_url),
      model: ConfigProvider.Env.get(:openrouter, :model),
      app_name: ConfigProvider.Env.get(:openrouter, :app_name),
      app_url: ConfigProvider.Env.get(:openrouter, :app_url)
    }
  end

  defp build_env_config(:ollama) do
    %{
      base_url: ConfigProvider.Env.get(:ollama, :base_url) || "http://localhost:11434",
      model: ConfigProvider.Env.get(:ollama, :model)
    }
  end

  defp build_env_config(:bedrock) do
    %{
      access_key_id: ConfigProvider.Env.get(:bedrock, :access_key_id),
      secret_access_key: ConfigProvider.Env.get(:bedrock, :secret_access_key),
      region: ConfigProvider.Env.get(:bedrock, :region) || "us-east-1",
      model: ConfigProvider.Env.get(:bedrock, :model)
    }
  end

  defp build_env_config(:mock) do
    %{
      responses: [],
      stream_chunks: []
    }
  end

  defp build_env_config(:bumblebee) do
    %{
      model_path: ConfigProvider.Env.get(:bumblebee, :model_path),
      device: ConfigProvider.Env.get(:bumblebee, :device) || :cpu
    }
  end

  defp normalize_config(config) when is_map(config), do: config
  defp normalize_config(_), do: %{}
end
