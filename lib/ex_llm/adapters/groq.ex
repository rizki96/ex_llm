defmodule ExLLM.Adapters.Groq do
  @moduledoc """
  Groq adapter for ExLLM.

  Groq provides extremely fast inference for open-source models using their
  custom LPU (Language Processing Unit) hardware.

  ## Configuration

      config :ex_llm,
        groq: [
          api_key: System.get_env("GROQ_API_KEY"),
          base_url: "https://api.groq.com/openai/v1"  # optional
        ]

  ## Supported Models

  - llama-3.3-70b-versatile
  - llama-3.1-70b-versatile
  - llama-3.1-8b-instant
  - llama3-70b-8192
  - llama3-8b-8192
  - mixtral-8x7b-32768
  - gemma2-9b-it
  - gemma-7b-it

  ## Example Usage

      messages = [
        %{role: "user", content: "Hello, how are you?"}
      ]
      
      {:ok, response} = ExLLM.Adapters.Groq.chat(messages, model: "llama3-70b-8192")
  """

  alias ExLLM.{Error, ModelConfig}
  alias ExLLM.Adapters.Shared.{ConfigHelper, ErrorHandler, ModelUtils}
  import ExLLM.Adapters.Shared.ModelUtils, only: [format_model_name: 1]

  use ExLLM.Adapters.OpenAICompatible,
    provider: :groq,
    base_url: "https://api.groq.com/openai/v1",
    # Models are now loaded dynamically
    models: []

  # Override list_models to use dynamic loading
  defoverridable list_models: 0

  @impl ExLLM.Adapter
  def default_model do
    ModelConfig.get_default_model(:groq)
  end

  @impl ExLLM.Adapter
  def list_models(options \\ []) do
    config_provider = ConfigHelper.get_config_provider(options)
    config = ConfigHelper.get_config(:groq, config_provider)

    # Use ModelLoader with API fetching
    ExLLM.ModelLoader.load_models(
      :groq,
      Keyword.merge(options,
        api_fetcher: fn _opts -> fetch_groq_models(config) end,
        config_transformer: &groq_model_transformer/2
      )
    )
  end

  @impl ExLLM.Adapters.OpenAICompatible
  def get_api_key(config) do
    Map.get(config, :api_key) || System.get_env("GROQ_API_KEY")
  end

  @impl ExLLM.Adapters.OpenAICompatible
  def get_headers(api_key, options) do
    base_headers = super(api_key, options)

    # Add Groq-specific headers if needed
    base_headers ++
      [
        {"x-groq-version", "v1"}
      ]
  end

  @impl ExLLM.Adapters.OpenAICompatible
  def transform_request(request, _options) do
    # Groq has some specific parameter handling
    request
    |> handle_groq_stop_sequences()
    |> handle_groq_temperature()
  end

  # Filter out non-LLM models (e.g., whisper models)
  def filter_model(%{"id" => id}) do
    not String.contains?(id, "whisper")
  end

  @impl ExLLM.Adapters.OpenAICompatible
  def parse_error(%{status: status, body: body}) do
    # Use shared error handler for consistent error handling
    ErrorHandler.handle_provider_error(:groq, status, body)
  end

  # Private functions

  defp handle_groq_stop_sequences(request) do
    # Groq supports max 4 stop sequences
    case Map.get(request, "stop") do
      nil ->
        request

      stops when is_list(stops) and length(stops) > 4 ->
        Map.put(request, "stop", Enum.take(stops, 4))

      _ ->
        request
    end
  end

  defp handle_groq_temperature(request) do
    # Groq recommends temperature between 0 and 2
    case Map.get(request, "temperature") do
      nil -> request
      temp when temp > 2 -> Map.put(request, "temperature", 2)
      temp when temp < 0 -> Map.put(request, "temperature", 0)
      _ -> request
    end
  end

  defp fetch_groq_models(config) do
    api_key = ConfigHelper.get_api_key(config, "GROQ_API_KEY")

    if !api_key || api_key == "" do
      {:error, "No API key available"}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      case Req.get("https://api.groq.com/openai/v1/models", headers: headers) do
        {:ok, %{status: 200, body: %{"data" => models}}} ->
          # Return a list of transformed models directly
          parsed_models =
            models
            |> Enum.filter(&filter_model/1)
            |> Enum.map(fn model ->
              %ExLLM.Types.Model{
                id: model["id"],
                name: ModelUtils.format_model_name(model["id"]),
                description: ModelUtils.generate_description(model["id"], :groq),
                context_window: model["context_window"] || 4096,
                capabilities: %{
                  supports_streaming: true,
                  supports_functions: model["supports_tools"] || false,
                  supports_vision: false,
                  features: ["streaming"]
                }
              }
            end)
            |> Enum.sort_by(& &1.id)

          {:ok, parsed_models}

        {:ok, %{status: status, body: body}} ->
          ErrorHandler.handle_provider_error(:groq, status, body)

        {:error, reason} ->
          {:error, "Network error: #{inspect(reason)}"}
      end
    end
  end

  defp groq_model_transformer(model_id, config) do
    %ExLLM.Types.Model{
      id: to_string(model_id),
      name: ModelUtils.format_model_name(to_string(model_id)),
      description: ModelUtils.generate_description(to_string(model_id), :groq),
      context_window: Map.get(config, :context_window, 4096),
      capabilities: %{
        supports_streaming: :streaming in Map.get(config, :capabilities, []),
        supports_functions: :function_calling in Map.get(config, :capabilities, []),
        supports_vision: false,
        features: Map.get(config, :capabilities, [])
      }
    }
  end

  # Model name formatting moved to shared ModelUtils module

  # Model description generation moved to shared ModelUtils module
end
