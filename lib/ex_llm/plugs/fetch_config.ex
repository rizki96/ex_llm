defmodule ExLLM.Plugs.FetchConfig do
  @moduledoc """
  Fetches and merges configuration from various sources.

  This plug combines configuration in the following order of precedence
  (later sources override earlier ones):

  1. Provider defaults
  2. Application configuration
  3. Request options (user-provided)

  The merged configuration is stored in `request.config` for use by
  subsequent plugs.

  ## Configuration Sources

  ### Provider Defaults

  Each provider can define default configuration by implementing
  `default_config/0` in their provider module.

  ### Application Configuration

  Configuration from `config.exs` or runtime configuration:

      config :ex_llm, :openai,
        api_key: System.get_env("OPENAI_API_KEY"),
        default_model: "gpt-4",
        timeout: 60_000
        
  ### Request Options

  Options passed directly to the request:

      ExLLM.chat(:openai, messages, model: "gpt-4-turbo", temperature: 0.5)
      
  ## Examples

      plug ExLLM.Plugs.FetchConfig
      
  After this plug runs, `request.config` will contain the merged configuration.
  """

  use ExLLM.Plug
  require Logger

  @impl true
  def call(%Request{provider: provider, options: options} = request, _opts) do
    # Get provider defaults
    provider_defaults = get_provider_defaults(provider)

    # Get application config
    app_config = get_app_config(provider)

    # Merge in order: defaults -> app config -> user options
    merged_config =
      provider_defaults
      |> deep_merge(app_config)
      |> deep_merge(options)
      |> ensure_required_config(provider)

    # Store the merged config
    request
    |> Map.put(:config, merged_config)
    |> Request.assign(:config_sources, %{
      provider_defaults: provider_defaults,
      app_config: app_config,
      user_options: options
    })
    |> Request.put_metadata(:config_fetched, true)
  end

  defp get_provider_defaults(provider) do
    # Try to call the provider module's default_config/0 function
    provider_module = provider_to_module(provider)

    cond do
      is_nil(provider_module) ->
        # Unknown provider
        default_provider_config()

      function_exported?(provider_module, :default_config, 0) ->
        apply(provider_module, :default_config, [])

      true ->
        # Provider exists but no default_config function
        default_provider_config()
    end
  end

  defp default_provider_config do
    %{
      timeout: 60_000,
      retry_attempts: 3,
      retry_delay: 1_000,
      stream_timeout: 120_000
    }
  end

  defp get_app_config(provider) do
    # Fetch from application environment
    config = Application.get_env(:ex_llm, provider, %{})

    # Convert keyword list to map if needed
    case config do
      config when is_map(config) -> config
      config when is_list(config) -> Map.new(config)
      _ -> %{}
    end
  end

  defp ensure_required_config(config, provider) do
    # Check for required configuration like API keys
    required_keys = get_required_keys(provider)

    Enum.reduce(required_keys, config, fn key, acc ->
      if Map.has_key?(acc, key) && acc[key] != nil do
        acc
      else
        # Try to get from environment variable
        env_var = provider_env_var(provider, key)

        case System.get_env(env_var) do
          nil ->
            Logger.warning(
              "Missing required config #{inspect(key)} for provider #{provider}. " <>
                "Set it in config or #{env_var} environment variable."
            )

            acc

          value ->
            Map.put(acc, key, value)
        end
      end
    end)
  end

  defp get_required_keys(:mock), do: []
  defp get_required_keys(:ollama), do: []
  defp get_required_keys(:lmstudio), do: []
  defp get_required_keys(:bumblebee), do: []
  defp get_required_keys(_provider), do: [:api_key]

  defp provider_env_var(:openai, :api_key), do: "OPENAI_API_KEY"
  defp provider_env_var(:anthropic, :api_key), do: "ANTHROPIC_API_KEY"
  defp provider_env_var(:gemini, :api_key), do: "GEMINI_API_KEY"
  defp provider_env_var(:groq, :api_key), do: "GROQ_API_KEY"
  defp provider_env_var(:mistral, :api_key), do: "MISTRAL_API_KEY"
  defp provider_env_var(:openrouter, :api_key), do: "OPENROUTER_API_KEY"
  defp provider_env_var(:perplexity, :api_key), do: "PERPLEXITY_API_KEY"
  defp provider_env_var(:xai, :api_key), do: "XAI_API_KEY"
  defp provider_env_var(:bedrock, :api_key), do: "AWS_ACCESS_KEY_ID"
  defp provider_env_var(_provider, _key), do: nil

  defp provider_to_module(:openai), do: ExLLM.Providers.OpenAI
  defp provider_to_module(:anthropic), do: ExLLM.Providers.Anthropic
  defp provider_to_module(:gemini), do: ExLLM.Providers.Gemini
  defp provider_to_module(:groq), do: ExLLM.Providers.Groq
  defp provider_to_module(:mistral), do: ExLLM.Providers.Mistral
  defp provider_to_module(:openrouter), do: ExLLM.Providers.OpenRouter
  defp provider_to_module(:perplexity), do: ExLLM.Providers.Perplexity
  defp provider_to_module(:ollama), do: ExLLM.Providers.Ollama
  defp provider_to_module(:lmstudio), do: ExLLM.Providers.LMStudio
  defp provider_to_module(:bumblebee), do: ExLLM.Providers.Bumblebee
  defp provider_to_module(:xai), do: ExLLM.Providers.XAI
  defp provider_to_module(:bedrock), do: ExLLM.Providers.Bedrock
  defp provider_to_module(:mock), do: ExLLM.Providers.Mock
  defp provider_to_module(_), do: nil

  @doc """
  Deep merges two maps, with values from the second map taking precedence.

  ## Examples

      iex> deep_merge(%{a: %{b: 1}}, %{a: %{c: 2}})
      %{a: %{b: 1, c: 2}}
  """
  def deep_merge(left, right) do
    Map.merge(left, right, &deep_resolve/3)
  end

  defp deep_resolve(_key, left, right) when is_map(left) and is_map(right) do
    deep_merge(left, right)
  end

  defp deep_resolve(_key, _left, right) do
    right
  end
end
