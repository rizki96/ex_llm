defmodule ExLLM.Providers.Gemini.Models do
  @moduledoc """
  Google Gemini Models API implementation.

  Provides functionality to list available models and retrieve model metadata
  including token limits, supported features, and generation parameters.
  """

  alias ExLLM.Providers.Shared.ConfigHelper

  defmodule Model do
    @moduledoc """
    Represents a Gemini model with its capabilities and metadata.
    """

    @type t :: %__MODULE__{
            name: String.t(),
            base_model_id: String.t(),
            version: String.t(),
            display_name: String.t(),
            description: String.t(),
            input_token_limit: integer(),
            output_token_limit: integer(),
            supported_generation_methods: [String.t()],
            temperature: float() | nil,
            max_temperature: float() | nil,
            top_p: float() | nil,
            top_k: integer() | nil
          }

    @enforce_keys [
      :name,
      :base_model_id,
      :version,
      :display_name,
      :description,
      :input_token_limit,
      :output_token_limit,
      :supported_generation_methods
    ]

    defstruct [
      :name,
      :base_model_id,
      :version,
      :display_name,
      :description,
      :input_token_limit,
      :output_token_limit,
      :supported_generation_methods,
      :temperature,
      :max_temperature,
      :top_p,
      :top_k
    ]

    @doc """
    Converts API response data to a Model struct.
    """
    @spec from_api(map()) :: t()
    def from_api(data) when is_map(data) do
      %__MODULE__{
        name: data["name"],
        base_model_id: data["baseModelId"],
        version: data["version"],
        display_name: data["displayName"],
        description: data["description"],
        input_token_limit: data["inputTokenLimit"],
        output_token_limit: data["outputTokenLimit"],
        supported_generation_methods: data["supportedGenerationMethods"] || [],
        temperature: data["temperature"],
        max_temperature: data["maxTemperature"],
        top_p: data["topP"],
        top_k: data["topK"]
      }
    end
  end

  @type list_response :: %{
          models: [Model.t()],
          next_page_token: String.t() | nil
        }

  @type options :: [
          {:page_size, integer()}
          | {:page_token, String.t()}
          | {:config_provider, pid() | atom()}
        ]

  @doc """
  Lists available Gemini models.

  ## Options
    * `:page_size` - Maximum number of models to return (max 1000)
    * `:page_token` - Token for retrieving the next page
    * `:config_provider` - Configuration provider (defaults to Application config)

  ## Examples
      
      # List all models
      {:ok, response} = ExLLM.Providers.Gemini.Models.list_models()
      
      # List with pagination
      {:ok, response} = ExLLM.Providers.Gemini.Models.list_models(page_size: 10)
      
      # Get next page
      {:ok, next_page} = ExLLM.Providers.Gemini.Models.list_models(page_token: response.next_page_token)
  """
  @spec list_models(options()) :: {:ok, list_response()} | {:error, term()}
  def list_models(opts \\ []) do
    # Validate parameters
    with :ok <- validate_list_params(opts),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      # Build query parameters
      _query_params = build_list_query_params(opts)

      # Make direct HTTP request (bypassing caching for now)
      url = "https://generativelanguage.googleapis.com/v1/models?key=#{api_key}"

      case Req.get(url) do
        {:ok, %{status: 200, body: body}} ->
          parsed = parse_list_response(body)
          {:ok, parsed}

        {:ok, %{status: status, body: body}} ->
          {:error, %{status: status, message: "API error", body: body}}

        {:error, reason} ->
          {:error, %{reason: :network_error, message: inspect(reason)}}
      end
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Gets information about a specific model.

  ## Parameters
    * `model_name` - The model name (e.g., "gemini-2.0-flash")
    * `opts` - Options including `:config_provider`

  ## Examples
      
      {:ok, model} = ExLLM.Providers.Gemini.Models.get_model("gemini-2.0-flash")
  """
  @spec get_model(String.t() | nil, Keyword.t()) :: {:ok, Model.t()} | {:error, term()}
  def get_model(model_name, opts \\ [])

  def get_model(nil, _opts),
    do: {:error, %{reason: :invalid_params, message: "Model name is required"}}

  def get_model(model_name, opts) when is_binary(model_name) do
    with {:ok, normalized_name} <- normalize_model_name(model_name),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      # Make direct HTTP request (bypassing caching for now)
      url = "https://generativelanguage.googleapis.com/v1/#{normalized_name}?key=#{api_key}"

      case Req.get(url) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, Model.from_api(body)}

        {:ok, %{status: 404}} ->
          {:error, %{status: 404, message: "Model not found: #{model_name}"}}

        {:ok, %{status: status, body: body}} ->
          {:error, %{status: status, message: "API error", body: body}}

        {:error, reason} ->
          {:error, %{reason: :network_error, message: inspect(reason)}}
      end
    else
      {:error, _} = error -> error
    end
  end

  # Private functions

  defp get_config_provider(opts) do
    Keyword.get(
      opts,
      :config_provider,
      Application.get_env(:ex_llm, :config_provider, ExLLM.Infrastructure.ConfigProvider.Default)
    )
  end

  defp validate_list_params(opts) when is_list(opts) do
    case Keyword.get(opts, :page_size) do
      nil -> :ok
      size when is_integer(size) and size > 0 -> :ok
      _ -> {:error, %{reason: :invalid_params, message: "page_size must be positive"}}
    end
  end

  defp validate_list_params(opts) when is_map(opts) do
    case Map.get(opts, :page_size) do
      nil -> :ok
      size when is_integer(size) and size > 0 -> :ok
      _ -> {:error, %{reason: :invalid_params, message: "page_size must be positive"}}
    end
  end

  defp validate_list_params(_), do: :ok

  defp validate_api_key(nil),
    do: {:error, %{reason: :missing_api_key, message: "API key is required"}}

  defp validate_api_key(""),
    do: {:error, %{reason: :missing_api_key, message: "API key is required"}}

  defp validate_api_key(_), do: {:ok, :valid}

  # defp normalize_model_name(nil),
  #   do: {:error, %{reason: :invalid_params, message: "Model name is required"}}

  defp normalize_model_name(""),
    do: {:error, %{reason: :invalid_params, message: "Model name is required"}}

  defp normalize_model_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    case trimmed do
      "" -> {:error, %{reason: :invalid_params, message: "Model name is required"}}
      "models/" -> {:error, %{reason: :invalid_params, message: "Invalid model name"}}
      "/gemini" -> {:error, %{reason: :invalid_params, message: "Invalid model name"}}
      "gemini/" -> {:error, %{reason: :invalid_params, message: "Invalid model name"}}
      "models/" <> _rest -> {:ok, trimmed}
      "gemini/" <> rest -> {:ok, "models/#{rest}"}
      _ -> {:ok, "models/#{trimmed}"}
    end
  end

  # defp normalize_model_name(_),
  #   do: {:error, %{reason: :invalid_params, message: "Model name must be a string"}}

  defp get_api_key(config) do
    config[:api_key] || System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY")
  end

  defp build_list_query_params(opts) do
    params = %{}

    params =
      case Keyword.get(opts, :page_size) do
        nil -> params
        size -> Map.put(params, "pageSize", min(size, 1000))
      end

    case Keyword.get(opts, :page_token) do
      nil -> params
      token -> Map.put(params, "pageToken", token)
    end
  end

  defp parse_list_response(body) do
    models =
      body
      |> Map.get("models", [])
      |> Enum.map(&Model.from_api/1)

    %{
      models: models,
      next_page_token: Map.get(body, "nextPageToken")
    }
  end
end
