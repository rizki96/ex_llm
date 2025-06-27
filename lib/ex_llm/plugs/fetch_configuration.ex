defmodule ExLLM.Plugs.FetchConfiguration do
  @moduledoc """
  Fetches and validates provider configuration.

  This plug extracts the common pattern of fetching configuration and validating
  the API key for a given provider. It should be placed in a pipeline after
  `ExLLM.Plugs.ValidateProvider`.

  For providers that require an API key, this plug:
  1. Fetches the provider-specific configuration.
  2. Retrieves the API key from the config or environment variables.
  3. Validates that the API key is present.
  4. Assigns the `:config` and `:api_key` to the request for later use.

  If the API key is missing or invalid, the pipeline is halted with an
  `:unauthorized` error.

  For providers that do not require a standard API key (e.g., Ollama, Bedrock),
  this plug simply fetches the configuration and assigns it to `:config`,
  allowing the pipeline to continue.

  ## Example Usage

      plug ExLLM.Plugs.FetchConfiguration
  """

  use ExLLM.Plug

  alias ExLLM.ErrorBuilder
  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.Shared.{ConfigHelper, Validation}

  @impl true
  def init(_opts), do: %{}

  @impl true
  def call(%Request{provider: provider, options: options} = request, _opts) do
    # Convert options map to keyword list for ConfigHelper compatibility
    options_kw = if is_map(options), do: Map.to_list(options), else: options

    config_provider = ConfigHelper.get_config_provider(options_kw)
    base_config = ConfigHelper.get_config(provider, config_provider)
    # Merge options into config so they're available as configuration
    config = Map.merge(base_config, options)

    case api_key_env_var(provider) do
      nil ->
        # This provider does not use a standard API key.
        # We just assign the config and continue.
        # Specific validation (e.g., for Bedrock credentials) will be
        # handled within the provider module itself.
        %{request | config: config}
        |> Request.assign(:config, config)
        |> Request.assign(:api_key, "no-api-key-required")

      env_var ->
        # This provider uses a standard API key.
        # Fetch it and validate its presence.
        api_key = ConfigHelper.get_api_key(config, env_var)

        case Validation.validate_api_key(api_key) do
          {:ok, :valid} ->
            %{request | config: config}
            |> Request.assign(:config, config)
            |> Request.assign(:api_key, api_key)

          {:error, _message} ->
            error = ErrorBuilder.authentication_error(provider)
            Request.halt_with_error(request, error)
        end
    end
  end

  @doc false
  @spec api_key_env_var(atom) :: String.t() | nil
  defp api_key_env_var(:anthropic), do: "ANTHROPIC_API_KEY"
  defp api_key_env_var(:gemini), do: "GEMINI_API_KEY"
  defp api_key_env_var(:groq), do: "GROQ_API_KEY"
  defp api_key_env_var(:mistral), do: "MISTRAL_API_KEY"
  defp api_key_env_var(:openai), do: "OPENAI_API_KEY"
  defp api_key_env_var(:openrouter), do: "OPENROUTER_API_KEY"
  defp api_key_env_var(:perplexity), do: "PERPLEXITY_API_KEY"
  defp api_key_env_var(:xai), do: "XAI_API_KEY"
  # Test provider for testing purposes
  defp api_key_env_var(:test_provider), do: "TEST_API_KEY"
  # Providers without a standard API key (e.g., ollama, bedrock, mock)
  defp api_key_env_var(_provider), do: nil
end
