defmodule ExLLM.Gemini.Tokens do
  @moduledoc """
  Google Gemini Token Counting API implementation.

  Provides functionality to count tokens for content and generate content requests
  before sending them to the model. This helps estimate costs and ensure requests
  fit within model limits.
  """

  alias ExLLM.Adapters.Shared.ConfigHelper
  alias ExLLM.Gemini.Content.{Content, GenerateContentRequest}

  defmodule CountTokensRequest do
    @moduledoc """
    Request structure for counting tokens.

    Either `contents` or `generate_content_request` must be provided, but not both.
    """

    @type t :: %__MODULE__{
            contents: [Content.t()] | nil,
            generate_content_request: GenerateContentRequest.t() | nil
          }

    defstruct contents: nil, generate_content_request: nil
  end

  defmodule ModalityTokenCount do
    @moduledoc """
    Token count breakdown by modality (TEXT, IMAGE, AUDIO, VIDEO).
    """

    @type t :: %__MODULE__{
            modality: String.t(),
            token_count: integer()
          }

    @enforce_keys [:modality, :token_count]
    defstruct [:modality, :token_count]

    @doc """
    Converts API response to ModalityTokenCount struct.
    """
    @spec from_api(map()) :: t()
    def from_api(data) when is_map(data) do
      %__MODULE__{
        modality: data["modality"],
        token_count: data["tokenCount"]
      }
    end
  end

  defmodule CountTokensResponse do
    @moduledoc """
    Response from the token counting API.
    """

    @type t :: %__MODULE__{
            total_tokens: integer(),
            cached_content_token_count: integer() | nil,
            prompt_tokens_details: [ModalityTokenCount.t()] | nil,
            cache_tokens_details: [ModalityTokenCount.t()] | nil
          }

    @enforce_keys [:total_tokens]
    defstruct [
      :total_tokens,
      :cached_content_token_count,
      :prompt_tokens_details,
      :cache_tokens_details
    ]

    @doc """
    Converts API response to CountTokensResponse struct.
    """
    @spec from_api(map()) :: t()
    def from_api(data) when is_map(data) do
      %__MODULE__{
        total_tokens: data["totalTokens"],
        cached_content_token_count: data["cachedContentTokenCount"],
        prompt_tokens_details: parse_modality_list(data["promptTokensDetails"]),
        cache_tokens_details: parse_modality_list(data["cacheTokensDetails"])
      }
    end

    defp parse_modality_list(nil), do: nil

    defp parse_modality_list(list) when is_list(list) do
      Enum.map(list, &ModalityTokenCount.from_api/1)
    end
  end

  @type options :: [
          {:config_provider, pid() | atom()}
        ]

  @doc """
  Counts tokens for the given content or generate content request.

  ## Parameters
    * `model` - The model name (e.g., "gemini-2.0-flash")
    * `request` - CountTokensRequest with either contents or generate_content_request
    * `opts` - Options including `:config_provider`

  ## Examples
      
      # Count tokens for simple content
      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Hello world"}]
          }
        ]
      }
      {:ok, response} = ExLLM.Gemini.Tokens.count_tokens("gemini-2.0-flash", request)
      
      # Count tokens for full generate request
      request = %CountTokensRequest{
        generate_content_request: %GenerateContentRequest{
          contents: [...],
          system_instruction: %Content{...}
        }
      }
      {:ok, response} = ExLLM.Gemini.Tokens.count_tokens("gemini-2.0-flash", request)
  """
  @spec count_tokens(String.t(), CountTokensRequest.t(), options()) ::
          {:ok, CountTokensResponse.t()} | {:error, term()}
  def count_tokens(model, request, opts \\ [])

  def count_tokens(nil, _request, _opts) do
    {:error, %{reason: :invalid_params, message: "Model name is required"}}
  end

  def count_tokens("", _request, _opts) do
    {:error, %{reason: :invalid_params, message: "Model name is required"}}
  end

  def count_tokens(model, %CountTokensRequest{} = request, opts) when is_binary(model) do
    with :ok <- validate_request(request),
         {:ok, normalized_model} <- normalize_model_name(model),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      # Ensure model is set in GenerateContentRequest
      request_with_model =
        if request.generate_content_request do
          %{
            request
            | generate_content_request: %{
                request.generate_content_request
                | model: request.generate_content_request.model || normalized_model
              }
          }
        else
          request
        end

      # Build request body
      body = to_json(request_with_model)

      # Build URL
      url = build_url(normalized_model, api_key)
      headers = build_headers()

      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, CountTokensResponse.from_api(body)}

        {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 400, message: message}}

        {:ok, %{status: 400, body: body}} ->
          {:error, %{status: 400, message: "Bad request", body: body}}

        {:ok, %{status: 403, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 403, message: message}}

        {:ok, %{status: 404, body: _body}} ->
          {:error, %{status: 404, message: "Model not found: #{model}"}}

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
  Validates that the request has either contents or generate_content_request, but not both.
  """
  @spec validate_request(CountTokensRequest.t()) :: :ok | {:error, map()}
  def validate_request(%CountTokensRequest{contents: nil, generate_content_request: nil}) do
    {:error,
     %{
       reason: :invalid_params,
       message: "Request must provide either contents or generate_content_request"
     }}
  end

  def validate_request(%CountTokensRequest{contents: contents, generate_content_request: gcr})
      when not is_nil(contents) and not is_nil(gcr) do
    {:error,
     %{
       reason: :invalid_params,
       message: "Contents and generate_content_request are mutually exclusive"
     }}
  end

  def validate_request(%CountTokensRequest{}), do: :ok

  @doc """
  Converts a CountTokensRequest to JSON format for the API.
  """
  @spec to_json(CountTokensRequest.t()) :: map()
  def to_json(%CountTokensRequest{} = request) do
    json = %{}

    json =
      if request.contents do
        Map.put(
          json,
          "contents",
          Enum.map(request.contents, &ExLLM.Gemini.Content.content_to_json/1)
        )
      else
        json
      end

    if request.generate_content_request do
      Map.put(
        json,
        "generateContentRequest",
        GenerateContentRequest.to_json(request.generate_content_request)
      )
    else
      json
    end
  end

  @doc """
  Normalizes model name to include proper prefix.
  """
  @spec normalize_model_name(String.t() | nil) :: {:ok, String.t()} | {:error, map()}
  def normalize_model_name(nil),
    do: {:error, %{reason: :invalid_params, message: "Model name is required"}}

  def normalize_model_name(name) when is_binary(name) do
    # Reuse the same normalization logic from Models module
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

  def normalize_model_name(_),
    do: {:error, %{reason: :invalid_params, message: "Model name must be a string"}}

  # Private functions

  defp get_config_provider(opts) do
    Keyword.get(
      opts,
      :config_provider,
      Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default)
    )
  end

  defp get_api_key(config) do
    config[:api_key] || System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY")
  end

  defp validate_api_key(nil),
    do: {:error, %{reason: :missing_api_key, message: "API key is required"}}

  defp validate_api_key(""),
    do: {:error, %{reason: :missing_api_key, message: "API key is required"}}

  defp validate_api_key(_), do: {:ok, :valid}

  defp build_url(model, api_key) do
    base = "https://generativelanguage.googleapis.com/v1beta"
    "#{base}/#{model}:countTokens?key=#{api_key}"
  end

  defp build_headers do
    [
      {"Content-Type", "application/json"},
      {"User-Agent", "ExLLM/0.4.2 (Elixir)"}
    ]
  end
end
