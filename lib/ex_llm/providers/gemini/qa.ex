defmodule ExLLM.Providers.Gemini.QA do
  @moduledoc """
  Google Gemini Question Answering API implementation.

  The Semantic Retrieval API provides a hosted question answering service for building 
  Retrieval Augmented Generation (RAG) systems using Google's infrastructure.

  ## Usage

      # With inline passages
      contents = [
        %{
          parts: [%{text: "What is the capital of France?"}],
          role: "user"
        }
      ]
      
      passages = [
        %{
          id: "france_info",
          content: %{
            parts: [%{text: "France is a country in Europe. Paris is the capital of France."}]
          }
        }
      ]
      
      {:ok, response} = ExLLM.Providers.Gemini.QA.generate_answer(
        "models/gemini-1.5-flash",
        contents,
        :abstractive,
        inline_passages: passages,
        temperature: 0.1,
        api_key: "your-api-key"
      )
      
      # With semantic retriever
      {:ok, response} = ExLLM.Providers.Gemini.QA.generate_answer(
        "models/gemini-1.5-flash",
        contents,
        :verbose,
        semantic_retriever: %{
          source: "corpora/my_corpus",
          query: %{parts: [%{text: "capital of France"}]},
          max_chunks_count: 5
        },
        oauth_token: "your-oauth-token"
      )
  """

  alias ExLLM.Providers.Gemini.Base

  defmodule GenerateAnswerRequest do
    @moduledoc """
    Request structure for generating grounded answers.
    """

    @type t :: %__MODULE__{
            contents: [map()],
            answer_style: :abstractive | :extractive | :verbose,
            grounding_source: GroundingPassages.t() | SemanticRetrieverConfig.t(),
            safety_settings: [map()] | nil,
            temperature: float() | nil
          }

    defstruct [
      :contents,
      :answer_style,
      :grounding_source,
      :safety_settings,
      :temperature
    ]
  end

  defmodule GenerateAnswerResponse do
    @moduledoc """
    Response structure for grounded answers.
    """

    @type t :: %__MODULE__{
            answer: map() | nil,
            answerable_probability: float() | nil,
            input_feedback: InputFeedback.t() | nil
          }

    defstruct [
      :answer,
      :answerable_probability,
      :input_feedback
    ]
  end

  defmodule GroundingPassages do
    @moduledoc """
    A list of passages provided inline with the request.
    """

    @type t :: %__MODULE__{
            passages: [GroundingPassage.t()]
          }

    defstruct [:passages]
  end

  defmodule GroundingPassage do
    @moduledoc """
    A single passage included inline with a grounding configuration.
    """

    @type t :: %__MODULE__{
            id: String.t(),
            content: map()
          }

    defstruct [:id, :content]
  end

  defmodule SemanticRetrieverConfig do
    @moduledoc """
    Configuration for retrieving grounding content from a Corpus or Document 
    created using the Semantic Retriever API.
    """

    @type t :: %__MODULE__{
            source: String.t(),
            query: map(),
            metadata_filters: [map()] | nil,
            max_chunks_count: integer() | nil,
            minimum_relevance_score: float() | nil
          }

    defstruct [
      :source,
      :query,
      :metadata_filters,
      :max_chunks_count,
      :minimum_relevance_score
    ]
  end

  defmodule InputFeedback do
    @moduledoc """
    Feedback related to the input data used to answer the question.
    """

    @type t :: %__MODULE__{
            safety_ratings: [map()],
            block_reason: atom() | nil
          }

    defstruct [:safety_ratings, :block_reason]
  end

  @doc """
  Generates a grounded answer from the model given an input.

  ## Parameters

  * `model` - The name of the model to use (e.g., "models/gemini-1.5-flash")
  * `contents` - List of conversation content (messages)
  * `answer_style` - Style for the answer (:abstractive, :extractive, :verbose)
  * `opts` - Additional options

  ## Options

  * `:inline_passages` - List of passages to use for grounding
  * `:semantic_retriever` - Configuration for semantic retrieval
  * `:temperature` - Controls randomness (0.0-1.0)
  * `:safety_settings` - List of safety settings
  * `:api_key` - Gemini API key
  * `:oauth_token` - OAuth2 token (alternative to API key)

  ## Examples

      {:ok, response} = ExLLM.Providers.Gemini.QA.generate_answer(
        "models/gemini-1.5-flash",
        [%{parts: [%{text: "What is AI?"}], role: "user"}],
        :abstractive,
        inline_passages: [
          %{
            id: "ai_definition",
            content: %{parts: [%{text: "AI is artificial intelligence..."}]}
          }
        ],
        temperature: 0.1,
        api_key: "your-api-key"
      )
  """
  @spec generate_answer(String.t(), [map()], atom(), Keyword.t()) ::
          {:ok, GenerateAnswerResponse.t()} | {:error, map()}
  def generate_answer(model, contents, answer_style, opts \\ []) do
    request = build_generate_answer_request(contents, answer_style, opts)

    request_opts = [
      method: :post,
      url: "/#{model}:generateAnswer",
      body: encode_request(request),
      query: %{}
    ]

    # Add authentication
    request_opts =
      if oauth_token = opts[:oauth_token] do
        Keyword.put(request_opts, :oauth_token, oauth_token)
      else
        api_key = opts[:api_key] || get_api_key(opts)
        Keyword.put(request_opts, :api_key, api_key)
      end

    case Base.request(request_opts) do
      {:ok, response_body} ->
        {:ok, parse_generate_answer_response(response_body)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Builds a GenerateAnswerRequest struct from the given parameters.
  """
  @spec build_generate_answer_request([map()], atom(), map()) :: GenerateAnswerRequest.t()
  def build_generate_answer_request(contents, answer_style, opts) do
    # Validate required fields
    validate_contents!(contents)
    validate_answer_style!(answer_style)

    # Build grounding source
    grounding_source = build_grounding_source!(opts)

    # Validate optional fields
    temperature = validate_temperature(opts[:temperature])

    %GenerateAnswerRequest{
      contents: contents,
      answer_style: answer_style,
      grounding_source: grounding_source,
      safety_settings: opts[:safety_settings],
      temperature: temperature
    }
  end

  @doc """
  Parses a GenerateAnswerResponse from the API response body.
  """
  @spec parse_generate_answer_response(map()) :: GenerateAnswerResponse.t()
  def parse_generate_answer_response(response_body) do
    # Handle different response formats from HTTPClient
    actual_body = 
      cond do
        # Direct response body format (expected)
        is_map(response_body) and Map.has_key?(response_body, "answer") ->
          response_body
        
        # Wrapped HTTP response format (from cache or HTTPClient)
        is_map(response_body) and Map.has_key?(response_body, :body) and is_map(response_body[:body]) ->
          response_body[:body]
        
        # String key wrapped format
        is_map(response_body) and Map.has_key?(response_body, "body") and is_map(response_body["body"]) ->
          response_body["body"]
        
        # Fallback to original format
        true ->
          response_body
      end
    
    %GenerateAnswerResponse{
      answer: actual_body["answer"],
      answerable_probability: actual_body["answerableProbability"],
      input_feedback: parse_input_feedback(actual_body["inputFeedback"])
    }
  end

  @doc """
  Formats an answer style atom to the API string format.
  """
  @spec format_answer_style(atom()) :: String.t()
  def format_answer_style(:abstractive), do: "ABSTRACTIVE"
  def format_answer_style(:extractive), do: "EXTRACTIVE"
  def format_answer_style(:verbose), do: "VERBOSE"

  def format_answer_style(style) do
    raise ArgumentError,
          "Invalid answer_style: #{inspect(style)}. Must be :abstractive, :extractive, or :verbose"
  end

  @doc """
  Formats a block reason string to an atom.
  """
  @spec format_block_reason(String.t()) :: atom()
  def format_block_reason("SAFETY"), do: :safety
  def format_block_reason("OTHER"), do: :other
  def format_block_reason("BLOCK_REASON_UNSPECIFIED"), do: :unspecified
  def format_block_reason(_), do: :unknown

  # Private functions

  defp validate_contents!(nil) do
    raise ArgumentError, "contents is required"
  end

  defp validate_contents!([]) do
    raise ArgumentError, "contents cannot be empty"
  end

  defp validate_contents!(contents) when is_list(contents), do: :ok

  defp validate_contents!(_) do
    raise ArgumentError, "contents must be a list"
  end

  defp validate_answer_style!(nil) do
    raise ArgumentError, "answer_style is required"
  end

  defp validate_answer_style!(style) when style in [:abstractive, :extractive, :verbose], do: :ok

  defp validate_answer_style!(style) do
    raise ArgumentError,
          "Invalid answer_style: #{inspect(style)}. Must be :abstractive, :extractive, or :verbose"
  end

  defp build_grounding_source!(opts) do
    cond do
      inline_passages = opts[:inline_passages] ->
        build_grounding_passages!(inline_passages)

      semantic_retriever = opts[:semantic_retriever] ->
        build_semantic_retriever_config!(semantic_retriever)

      true ->
        raise ArgumentError,
              "grounding source is required (either :inline_passages or :semantic_retriever)"
    end
  end

  defp build_grounding_passages!(passages) when is_list(passages) do
    validated_passages = Enum.map(passages, &validate_grounding_passage!/1)
    %GroundingPassages{passages: validated_passages}
  end

  defp build_grounding_passages!(_) do
    raise ArgumentError, "inline_passages must be a list"
  end

  defp validate_grounding_passage!(passage) do
    id = passage[:id] || passage["id"]
    content = passage[:content] || passage["content"]

    if is_nil(id) do
      raise ArgumentError, "passage id is required"
    end

    if is_nil(content) do
      raise ArgumentError, "passage content is required"
    end

    %GroundingPassage{
      id: id,
      content: content
    }
  end

  defp build_semantic_retriever_config!(config) when is_map(config) do
    source = config[:source] || config["source"]
    query = config[:query] || config["query"]

    if is_nil(source) do
      raise ArgumentError, "semantic retriever source is required"
    end

    if is_nil(query) do
      raise ArgumentError, "semantic retriever query is required"
    end

    %SemanticRetrieverConfig{
      source: source,
      query: query,
      metadata_filters: config[:metadata_filters] || config["metadataFilters"],
      max_chunks_count: config[:max_chunks_count] || config["maxChunksCount"],
      minimum_relevance_score: config[:minimum_relevance_score] || config["minimumRelevanceScore"]
    }
  end

  defp build_semantic_retriever_config!(_) do
    raise ArgumentError, "semantic_retriever must be a map"
  end

  defp validate_temperature(nil), do: nil

  defp validate_temperature(temp) when is_number(temp) and temp >= 0.0 and temp <= 1.0 do
    temp
  end

  defp validate_temperature(temp) do
    raise ArgumentError, "Temperature must be between 0.0 and 1.0, got: #{inspect(temp)}"
  end

  defp encode_request(%GenerateAnswerRequest{} = request) do
    base_request = %{
      "contents" => request.contents,
      "answerStyle" => format_answer_style(request.answer_style)
    }

    # Add grounding source
    base_request =
      case request.grounding_source do
        %GroundingPassages{} = passages ->
          Map.put(base_request, "inlinePassages", encode_grounding_passages(passages))

        %SemanticRetrieverConfig{} = retriever ->
          Map.put(base_request, "semanticRetriever", encode_semantic_retriever_config(retriever))
      end

    # Add optional fields
    base_request =
      if request.temperature do
        Map.put(base_request, "temperature", request.temperature)
      else
        base_request
      end

    base_request =
      if request.safety_settings do
        Map.put(base_request, "safetySettings", request.safety_settings)
      else
        base_request
      end

    base_request
  end

  defp encode_grounding_passages(%GroundingPassages{passages: passages}) do
    %{
      "passages" =>
        Enum.map(passages, fn %GroundingPassage{id: id, content: content} ->
          %{
            "id" => id,
            "content" => content
          }
        end)
    }
  end

  defp encode_semantic_retriever_config(%SemanticRetrieverConfig{} = config) do
    base_config = %{
      "source" => config.source,
      "query" => config.query
    }

    base_config =
      if config.metadata_filters do
        Map.put(base_config, "metadataFilters", config.metadata_filters)
      else
        base_config
      end

    base_config =
      if config.max_chunks_count do
        Map.put(base_config, "maxChunksCount", config.max_chunks_count)
      else
        base_config
      end

    base_config =
      if config.minimum_relevance_score do
        Map.put(base_config, "minimumRelevanceScore", config.minimum_relevance_score)
      else
        base_config
      end

    base_config
  end

  defp parse_input_feedback(nil), do: nil

  defp parse_input_feedback(feedback) do
    %InputFeedback{
      safety_ratings: feedback["safetyRatings"] || [],
      block_reason:
        if feedback["blockReason"] do
          format_block_reason(feedback["blockReason"])
        else
          nil
        end
    }
  end

  defp get_api_key(opts) do
    opts[:api_key] || System.get_env("GEMINI_API_KEY") ||
      raise ArgumentError,
            "API key is required. Set GEMINI_API_KEY environment variable or pass :api_key option"
  end
end
