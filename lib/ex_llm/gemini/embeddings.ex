defmodule ExLLM.Gemini.Embeddings do
  @moduledoc """
  Google Gemini Embeddings API implementation.
  
  Provides functionality to generate text embeddings using Gemini embedding models.
  Supports both single and batch embedding generation with various task types
  and configuration options.
  """

  alias ExLLM.Adapters.Shared.ConfigHelper
  alias ExLLM.Gemini.Content.{Content, Part}

  defmodule ContentEmbedding do
    @moduledoc """
    A list of floats representing an embedding.
    """
    
    @type t :: %__MODULE__{
      values: [float()]
    }
    
    @enforce_keys [:values]
    defstruct [:values]
    
    @doc """
    Converts API response to ContentEmbedding struct.
    """
    @spec from_api(map()) :: t()
    def from_api(data) when is_map(data) do
      %__MODULE__{
        values: data["values"] || []
      }
    end
  end

  defmodule EmbedContentRequest do
    @moduledoc """
    Request containing the Content for the model to embed.
    """
    
    @type task_type :: 
      :retrieval_query | :retrieval_document | :semantic_similarity |
      :classification | :clustering | :question_answering |
      :fact_verification | :code_retrieval_query
    
    @type t :: %__MODULE__{
      model: String.t() | nil,
      content: Content.t(),
      task_type: task_type() | nil,
      title: String.t() | nil,
      output_dimensionality: integer() | nil
    }
    
    @enforce_keys [:content]
    defstruct [:model, :content, :task_type, :title, :output_dimensionality]
  end

  @type options :: [
    {:config_provider, pid() | atom()}
  ]

  @doc """
  Generates a text embedding vector from the input Content.
  
  ## Parameters
    * `model` - The model to use (e.g., "models/text-embedding-004")
    * `request` - EmbedContentRequest with content and options
    * `opts` - Options including `:config_provider`
  
  ## Examples
      
      request = %EmbedContentRequest{
        content: %Content{
          role: "user",
          parts: [%Part{text: "Hello world"}]
        },
        task_type: :retrieval_query
      }
      {:ok, embedding} = ExLLM.Gemini.Embeddings.embed_content("models/text-embedding-004", request)
  """
  @spec embed_content(String.t(), EmbedContentRequest.t(), options()) :: 
    {:ok, ContentEmbedding.t()} | {:error, term()}
  def embed_content(model, %EmbedContentRequest{} = request, opts \\ []) do
    with :ok <- validate_embed_request(request),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      
      # Normalize model name
      model = normalize_model_name(model)
      
      # Build request body
      body = build_embed_request_body(request)
      
      url = build_url("/v1beta/#{model}:embedContent", api_key)
      headers = build_headers()
      
      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          parse_embedding_response(body)
          
        {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 400, message: message}}
          
        {:ok, %{status: 404}} ->
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
  Generates multiple embedding vectors from a batch of content.
  
  ## Parameters
    * `model` - The model to use
    * `requests` - List of EmbedContentRequest
    * `opts` - Options including `:config_provider`
  
  ## Examples
      
      requests = [
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user", parts: [%Part{text: "First text"}]}
        },
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user", parts: [%Part{text: "Second text"}]}
        }
      ]
      {:ok, embeddings} = ExLLM.Gemini.Embeddings.batch_embed_contents("models/text-embedding-004", requests)
  """
  @spec batch_embed_contents(String.t(), [EmbedContentRequest.t()], options()) :: 
    {:ok, [ContentEmbedding.t()]} | {:error, term()}
  def batch_embed_contents(model, requests, opts \\ []) do
    with :ok <- validate_batch_requests(model, requests),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      
      # Normalize model name
      model = normalize_model_name(model)
      
      # Build request body
      body = build_batch_request_body(requests)
      
      url = build_url("/v1beta/#{model}:batchEmbedContents", api_key)
      headers = build_headers()
      
      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          parse_batch_response(body)
          
        {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 400, message: message}}
          
        {:ok, %{status: 404}} ->
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
  Convenience function to embed a single text string.
  
  ## Examples
      
      {:ok, embedding} = ExLLM.Gemini.Embeddings.embed_text("models/text-embedding-004", "Hello world")
  """
  @spec embed_text(String.t(), String.t(), Keyword.t()) :: 
    {:ok, ContentEmbedding.t()} | {:error, term()}
  def embed_text(model, text, opts \\ []) do
    {embed_opts, call_opts} = Keyword.split(opts, [:task_type, :title, :output_dimensionality])
    
    request = %EmbedContentRequest{
      content: %Content{
        role: "user",
        parts: [%Part{text: text}]
      },
      task_type: embed_opts[:task_type],
      title: embed_opts[:title],
      output_dimensionality: embed_opts[:output_dimensionality]
    }
    
    embed_content(model, request, call_opts)
  end

  @doc """
  Convenience function to embed multiple text strings.
  
  ## Examples
      
      texts = ["First text", "Second text", "Third text"]
      {:ok, embeddings} = ExLLM.Gemini.Embeddings.embed_texts("models/text-embedding-004", texts)
  """
  @spec embed_texts(String.t(), [String.t()], Keyword.t()) :: 
    {:ok, [ContentEmbedding.t()]} | {:error, term()}
  def embed_texts(model, texts, opts \\ []) do
    {embed_opts, call_opts} = Keyword.split(opts, [:task_type, :title, :output_dimensionality])
    
    requests = Enum.map(texts, fn text ->
      %EmbedContentRequest{
        model: model,
        content: %Content{
          role: "user",
          parts: [%Part{text: text}]
        },
        task_type: embed_opts[:task_type],
        title: embed_opts[:title],
        output_dimensionality: embed_opts[:output_dimensionality]
      }
    end)
    
    batch_embed_contents(model, requests, call_opts)
  end

  # Public validation functions for testing

  @doc false
  @spec validate_embed_request(EmbedContentRequest.t() | map()) :: :ok | {:error, map()}
  def validate_embed_request(%{content: content} = request) do
    cond do
      is_nil(content) ->
        {:error, %{reason: :invalid_params, message: "content is required"}}
        
      not is_struct(content, Content) ->
        {:error, %{reason: :invalid_params, message: "content must be a Content struct"}}
        
      Enum.empty?(content.parts || []) ->
        {:error, %{reason: :invalid_params, message: "content.parts cannot be empty"}}
        
      not Enum.all?(content.parts || [], &has_text?/1) ->
        {:error, %{reason: :invalid_params, message: "All parts must have text for embeddings"}}
        
      request.title && request.task_type != :retrieval_document ->
        {:error, %{reason: :invalid_params, message: "title is only valid for RETRIEVAL_DOCUMENT task type"}}
        
      true ->
        :ok
    end
  end
  def validate_embed_request(_), do: {:error, %{reason: :invalid_params, message: "Invalid request"}}

  defp has_text?(%Part{text: text}) when is_binary(text) and text != "", do: true
  defp has_text?(_), do: false

  @doc false
  @spec validate_batch_requests(String.t(), [EmbedContentRequest.t()]) :: :ok | {:error, map()}
  def validate_batch_requests(_model, []) do
    {:error, %{reason: :invalid_params, message: "Batch cannot be empty"}}
  end
  
  def validate_batch_requests(model, requests) do
    normalized_model = normalize_model_name(model)
    
    # Check if all requests have matching models
    mismatched = Enum.any?(requests, fn req ->
      req.model && normalize_model_name(req.model) != normalized_model
    end)
    
    if mismatched do
      {:error, %{reason: :invalid_params, message: "All requests must use the same model"}}
    else
      # Validate each request
      case Enum.find_value(requests, fn req -> 
        case validate_embed_request(req) do
          :ok -> nil
          error -> error
        end
      end) do
        nil -> :ok
        error -> error
      end
    end
  end

  @doc false
  @spec task_type_to_string(atom() | nil) :: String.t() | nil
  def task_type_to_string(nil), do: nil
  def task_type_to_string(:retrieval_query), do: "RETRIEVAL_QUERY"
  def task_type_to_string(:retrieval_document), do: "RETRIEVAL_DOCUMENT"
  def task_type_to_string(:semantic_similarity), do: "SEMANTIC_SIMILARITY"
  def task_type_to_string(:classification), do: "CLASSIFICATION"
  def task_type_to_string(:clustering), do: "CLUSTERING"
  def task_type_to_string(:question_answering), do: "QUESTION_ANSWERING"
  def task_type_to_string(:fact_verification), do: "FACT_VERIFICATION"
  def task_type_to_string(:code_retrieval_query), do: "CODE_RETRIEVAL_QUERY"

  @doc false
  @spec build_embed_request_body(EmbedContentRequest.t()) :: map()
  def build_embed_request_body(%EmbedContentRequest{} = request) do
    body = %{}
    
    # Add content
    body = Map.put(body, "content", content_to_json(request.content))
    
    # Add optional fields
    body = if request.model, do: Map.put(body, "model", request.model), else: body
    body = if request.task_type, do: Map.put(body, "taskType", task_type_to_string(request.task_type)), else: body
    body = if request.title, do: Map.put(body, "title", request.title), else: body
    body = if request.output_dimensionality, do: Map.put(body, "outputDimensionality", request.output_dimensionality), else: body
    
    body
  end

  @doc false
  @spec build_batch_request_body([EmbedContentRequest.t()]) :: map()
  def build_batch_request_body(requests) do
    %{
      "requests" => Enum.map(requests, &build_embed_request_body/1)
    }
  end

  @doc false
  @spec parse_embedding_response(map()) :: {:ok, ContentEmbedding.t()} | {:error, map()}
  def parse_embedding_response(%{"embedding" => embedding}) when is_map(embedding) do
    {:ok, ContentEmbedding.from_api(embedding)}
  end
  def parse_embedding_response(_) do
    {:error, %{reason: :invalid_response, message: "Invalid embedding response"}}
  end

  @doc false
  @spec parse_batch_response(map()) :: {:ok, [ContentEmbedding.t()]} | {:error, map()}
  def parse_batch_response(%{"embeddings" => embeddings}) when is_list(embeddings) do
    embeddings = Enum.map(embeddings, &ContentEmbedding.from_api/1)
    {:ok, embeddings}
  end
  def parse_batch_response(_) do
    {:error, %{reason: :invalid_response, message: "Invalid batch response"}}
  end

  @doc false
  @spec normalize_model_name(String.t() | nil) :: String.t() | nil
  def normalize_model_name(nil), do: nil
  def normalize_model_name(name) when is_binary(name) do
    cond do
      String.starts_with?(name, "models/") -> name
      String.starts_with?(name, "gemini/") -> "models/" <> String.trim_leading(name, "gemini/")
      true -> "models/#{name}"
    end
  end

  # Private helper functions

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

  defp validate_api_key(nil), do: {:error, %{reason: :missing_api_key, message: "API key is required"}}
  defp validate_api_key(""), do: {:error, %{reason: :missing_api_key, message: "API key is required"}}
  defp validate_api_key(_), do: {:ok, :valid}

  defp build_url(path, api_key) do
    base = "https://generativelanguage.googleapis.com"
    "#{base}#{path}?key=#{api_key}"
  end

  defp build_headers do
    [
      {"Content-Type", "application/json"},
      {"User-Agent", "ExLLM/0.4.2 (Elixir)"}
    ]
  end

  defp content_to_json(%Content{} = content) do
    %{
      "role" => content.role,
      "parts" => Enum.map(content.parts || [], &part_to_json/1)
    }
  end

  defp part_to_json(%Part{} = part) do
    json = %{}
    json = if part.text, do: Map.put(json, "text", part.text), else: json
    json
  end
end