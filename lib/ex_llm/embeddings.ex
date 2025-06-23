defmodule ExLLM.Embeddings do
  @moduledoc """
  Embeddings functionality for ExLLM.

  This module provides functions for generating embeddings, calculating similarity,
  and working with embedding vectors across different providers.

  ## Features

  - **Vector Similarity**: Calculate similarity between embeddings using multiple metrics
  - **Embedding Search**: Find similar items in collections using embeddings
  - **Batch Processing**: Generate embeddings for multiple inputs efficiently
  - **Provider Support**: Works with OpenAI, Gemini, Mistral, and other providers
  - **Embedding Index**: Create searchable indexes for large datasets

  ## Examples

      # Generate embeddings
      {:ok, response} = ExLLM.embeddings(:openai, "Hello world")
      
      # Find similar items
      results = ExLLM.Embeddings.find_similar(query_embedding, items, top_k: 5)
      
      # Calculate similarity
      similarity = ExLLM.Embeddings.cosine_similarity(vector1, vector2)
  """

  @doc """
  Find similar items based on embeddings.

  Finds the most similar items by comparing their embeddings with a query embedding.
  Supports multiple similarity metrics and filtering options.

  ## Parameters

    * `query_embedding` - The embedding vector to compare against
    * `items` - List of items with embeddings (see formats below)
    * `opts` - Options for similarity search
    
  ## Options

    * `:top_k` - Number of results to return (default: 10)
    * `:metric` - Similarity metric: `:cosine`, `:euclidean`, `:dot_product` (default: `:cosine`)
    * `:threshold` - Minimum similarity threshold (default: 0.0)
    
  ## Item Formats

  Items can be provided in several formats:

      # Tuple format
      items = [
        {"Document 1", [0.1, 0.2, 0.3, ...]},
        {"Document 2", [0.4, 0.5, 0.6, ...]}
      ]
      
      # Map format with :embedding key
      items = [
        %{id: 1, text: "Doc 1", embedding: [0.1, 0.2, ...]},
        %{id: 2, text: "Doc 2", embedding: [0.4, 0.5, ...]}
      ]

  ## Examples

      # Basic similarity search
      results = ExLLM.Embeddings.find_similar(query_embedding, items, top_k: 5)
      
      # With threshold filtering
      results = ExLLM.Embeddings.find_similar(query_embedding, items, 
        top_k: 10,
        threshold: 0.7,
        metric: :cosine
      )
      
      # Results format
      [
        %{item: {"Document 1", [...]}, similarity: 0.95},
        %{item: {"Document 2", [...]}, similarity: 0.87}
      ]
  """
  @spec find_similar([float()], list(), keyword()) :: list(%{item: any(), similarity: float()})
  def find_similar(query_embedding, items, opts \\ []) do
    ExLLM.Core.Embeddings.find_similar(query_embedding, items, opts)
  end

  @doc """
  Calculate cosine similarity between two vectors.

  Cosine similarity measures the cosine of the angle between two vectors,
  providing a value between -1 and 1, where:
  - 1 means identical direction
  - 0 means perpendicular
  - -1 means opposite direction

  ## Examples

      similarity = ExLLM.Embeddings.cosine_similarity([1.0, 2.0], [3.0, 4.0])
      # => 0.9838699100999074
      
      # Identical vectors have similarity of 1.0
      ExLLM.Embeddings.cosine_similarity([1, 2, 3], [1, 2, 3])
      # => 1.0
      
      # Orthogonal vectors have similarity of 0.0
      ExLLM.Embeddings.cosine_similarity([1, 0], [0, 1])
      # => 0.0
  """
  @spec cosine_similarity([float()], [float()]) :: float()
  def cosine_similarity(vector1, vector2) do
    ExLLM.Core.Embeddings.similarity(vector1, vector2, :cosine)
  end

  @doc """
  List models that support embeddings for a provider.

  Returns a list of model IDs that support embedding generation for the specified provider.

  ## Examples

      {:ok, models} = ExLLM.Embeddings.list_models(:openai)
      # => {:ok, ["text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002"]}
      
      {:ok, models} = ExLLM.Embeddings.list_models(:gemini)
      # => {:ok, ["text-embedding-004", "text-multilingual-embedding-002"]}
  """
  @spec list_models(atom()) :: {:ok, [String.t()]} | {:error, term()}
  def list_models(provider) do
    ExLLM.Core.Embeddings.list_embedding_models(provider)
  end

  @doc """
  Calculate similarity between two embeddings using a specified metric.

  ## Examples
      
      # With custom metric
      similarity = ExLLM.Embeddings.similarity([0.1, 0.2], [0.3, 0.4], :dot_product)
  """
  @spec similarity([float()], [float()], atom()) :: float()
  def similarity(vector1, vector2, metric \\ :cosine) do
    ExLLM.Core.Embeddings.similarity(vector1, vector2, metric)
  end

  @doc """
  Generate embeddings for multiple inputs in a batch.

  More efficient than calling embeddings/3 multiple times for large datasets.
  Automatically handles provider-specific batch size limits and retry logic.

  ## Parameters

    * `provider` - The provider to use (e.g., `:openai`, `:gemini`)
    * `requests` - List of strings to embed
    * `opts` - Options (same as embeddings/3)

  ## Options

    * `:model` - Override the default embedding model
    * `:batch_size` - Maximum items per batch (provider-specific defaults)
    * `:timeout` - Request timeout in milliseconds

  ## Examples

      # Batch embed multiple documents
      {:ok, response} = ExLLM.Embeddings.batch_generate(:openai, [
        "First document text",
        "Second document text", 
        "Third document text"
      ])
      
      # Access embeddings
      embeddings = response.embeddings
      
      # With custom model
      {:ok, response} = ExLLM.Embeddings.batch_generate(:openai, texts,
        model: "text-embedding-3-large",
        batch_size: 100
      )
  """
  @spec batch_generate(atom(), [String.t()], keyword()) ::
          {:ok, ExLLM.Types.EmbeddingResponse.t()} | {:error, term()}
  def batch_generate(provider, requests, opts \\ []) do
    # Core module expects list of {input, options} tuples
    formatted_requests = Enum.map(requests, fn request -> {request, opts} end)
    ExLLM.Core.Embeddings.batch_generate(provider, formatted_requests)
  end

  @doc """
  Get information about an embedding model.

  Returns metadata about the specified embedding model including dimensions,
  context window, and capabilities.

  ## Examples

      {:ok, info} = ExLLM.Embeddings.model_info(:openai, "text-embedding-3-small")
      # => {:ok, %{
      #   id: "text-embedding-3-small",
      #   dimensions: 1536,
      #   max_input: 8192,
      #   pricing: %{input: 0.00002}
      # }}
  """
  @spec model_info(atom(), String.t()) :: {:ok, map()} | {:error, term()}
  def model_info(provider, model_id) do
    ExLLM.get_model_info(provider, model_id)
  end

  @doc """
  Create a searchable embedding index from a collection of documents.

  This function creates an in-memory index that can be used for fast similarity
  searches across large document collections. Useful for RAG applications.

  ## Parameters

    * `provider` - The provider to use for generating embeddings
    * `documents` - List of documents to index (strings or maps)
    * `opts` - Options for index creation

  ## Options

    * `:model` - Embedding model to use
    * `:batch_size` - Batch size for embedding generation
    * `:key` - Key to extract text from map documents (default: `:text`)
    * `:index_type` - Index type: `:memory` (default), `:disk` (future)

  ## Examples

      # Index a collection of documents
      documents = [
        "First document about machine learning",
        "Second document about data science",
        "Third document about artificial intelligence"
      ]
      
      {:ok, index} = ExLLM.Embeddings.create_index(:openai, documents)
      
      # Index documents with metadata
      documents = [
        %{id: 1, text: "ML document", category: "tech"},
        %{id: 2, text: "DS document", category: "tech"},
        %{id: 3, text: "AI document", category: "tech"}
      ]
      
      {:ok, index} = ExLLM.Embeddings.create_index(:openai, documents, key: :text)
  """
  @spec create_index(atom(), [String.t() | map()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_index(provider, documents, opts \\ []) do
    # Core module doesn't have create_index, so we'll implement it here
    key = Keyword.get(opts, :key, :text)

    # Extract text from documents
    texts =
      case documents do
        [text | _] when is_binary(text) ->
          # Simple list of strings
          documents

        [%{} | _] ->
          # List of maps - extract text using key
          Enum.map(documents, fn doc -> Map.get(doc, key) end)

        _ ->
          raise ArgumentError, "Documents must be a list of strings or maps with #{key} key"
      end

    # Generate embeddings for all texts
    case batch_generate(provider, texts, opts) do
      {:ok, results} ->
        # Create index structure
        index = %{
          provider: provider,
          model: Keyword.get(opts, :model),
          documents: documents,
          embeddings: results.embeddings,
          created_at: DateTime.utc_now()
        }

        {:ok, index}

      {:error, _} = error ->
        error
    end
  end
end
