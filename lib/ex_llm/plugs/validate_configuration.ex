defmodule ExLLM.Plugs.ValidateConfiguration do
  @moduledoc """
  Validates that a provider is properly configured and ready to use.

  This plug checks that all required configuration is present and valid
  for the provider. It's used by ExLLM.configured?/1 to determine if
  a provider can be used for actual requests.

  ## What it checks

  - Required API keys are present (for remote providers)
  - Configuration values are valid
  - Provider-specific requirements are met

  ## Examples

      plug ExLLM.Plugs.ValidateConfiguration
      
  After this plug runs, the request will be in :completed state if the
  provider is configured, or :error state if it's not.
  """

  use ExLLM.Plug
  require Logger

  @impl true
  def call(%Request{provider: provider, config: config} = request, _opts) do
    case validate_provider_config(provider, config) do
      {:ok, validation_result} ->
        request
        |> Map.put(:result, validation_result)
        |> Request.put_state(:completed)
        |> Request.put_metadata(:configuration_valid, true)

      {:error, reason} ->
        request
        |> Request.halt_with_error(%{
          plug: __MODULE__,
          error: :configuration_invalid,
          message: reason,
          provider: provider
        })
        |> Request.put_metadata(:configuration_valid, false)
    end
  end

  defp validate_provider_config(provider, config) do
    case provider do
      :mock ->
        # Mock provider is always configured
        {:ok, %{configured: true, type: :mock}}

      :ollama ->
        # Ollama just needs to be reachable
        validate_local_provider(provider, config)

      :lmstudio ->
        # LM Studio just needs to be reachable
        validate_local_provider(provider, config)

      :bumblebee ->
        # Bumblebee is always configured (local models)
        {:ok, %{configured: true, type: :local}}

      _ ->
        # Remote providers need API keys
        validate_remote_provider(provider, config)
    end
  end

  defp validate_local_provider(provider, config) do
    # For local providers, configuration is valid if they have basic config
    base_url = config[:base_url] || get_default_base_url(provider)

    {:ok,
     %{
       configured: true,
       type: :local,
       base_url: base_url
     }}
  end

  defp validate_remote_provider(provider, config) do
    # Check for API key
    case config[:api_key] do
      nil ->
        env_var = get_env_var_name(provider)

        {:error,
         "Missing API key for #{provider}. Set it in config or #{env_var} environment variable."}

      "" ->
        {:error, "Empty API key for #{provider}. Please provide a valid API key."}

      api_key when is_binary(api_key) ->
        # API key is present, provider is configured
        {:ok,
         %{
           configured: true,
           type: :remote,
           api_key_present: true,
           api_key_length: String.length(api_key)
         }}

      _ ->
        {:error, "Invalid API key format for #{provider}. Expected string."}
    end
  end

  defp get_default_base_url(:ollama), do: "http://localhost:11434"
  defp get_default_base_url(:lmstudio), do: "http://localhost:1234"
  defp get_default_base_url(_), do: nil

  defp get_env_var_name(:openai), do: "OPENAI_API_KEY"
  defp get_env_var_name(:anthropic), do: "ANTHROPIC_API_KEY"
  defp get_env_var_name(:gemini), do: "GEMINI_API_KEY"
  defp get_env_var_name(:groq), do: "GROQ_API_KEY"
  defp get_env_var_name(:mistral), do: "MISTRAL_API_KEY"
  defp get_env_var_name(:openrouter), do: "OPENROUTER_API_KEY"
  defp get_env_var_name(:perplexity), do: "PERPLEXITY_API_KEY"
  defp get_env_var_name(:xai), do: "XAI_API_KEY"
  defp get_env_var_name(:bedrock), do: "AWS_ACCESS_KEY_ID"
  defp get_env_var_name(provider), do: "#{String.upcase(to_string(provider))}_API_KEY"
end
