defmodule ExLLM.Providers.Gemini.Document do
  @moduledoc """
  Document management for Gemini's Semantic Retrieval API.

  A Document is a collection of Chunks. A Corpus can have a maximum of 10,000 Documents.
  Documents are used to organize and query related content within a corpus.

  ## Authentication

  Document operations require authentication. Both API key and OAuth2 are supported:

  - **API key**: Most operations work with API keys
  - **OAuth2**: Required for some operations, especially those involving user-specific data

  ## Examples

      # Create a document
      {:ok, document} = Document.create_document(
        "corpora/my-corpus",
        %{display_name: "Research Papers"}
      )
      
      # List documents with pagination
      {:ok, result} = Document.list_documents(
        "corpora/my-corpus",
        %{page_size: 10}
      )
      
      # Query a document
      {:ok, results} = Document.query_document(
        "corpora/my-corpus/documents/my-doc",
        "artificial intelligence",
        %{results_count: 5}
      )
      
      # Update document
      {:ok, updated} = Document.update_document(
        "corpora/my-corpus/documents/my-doc",
        %{display_name: "Updated Name"},
        %{update_mask: "displayName"}
      )
      
      # Delete document
      :ok = Document.delete_document("corpora/my-corpus/documents/my-doc")
  """

  alias ExLLM.Providers.Gemini.Base

  defstruct [
    :name,
    :display_name,
    :custom_metadata,
    :create_time,
    :update_time
  ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          display_name: String.t() | nil,
          custom_metadata: [CustomMetadata.t()] | nil,
          create_time: String.t() | nil,
          update_time: String.t() | nil
        }

  defmodule CustomMetadata do
    @moduledoc """
    User provided metadata stored as key-value pairs.
    """

    defstruct [
      :key,
      :string_value,
      :numeric_value,
      :string_list_value
    ]

    @type t :: %__MODULE__{
            key: String.t(),
            string_value: String.t() | nil,
            numeric_value: number() | nil,
            string_list_value: StringList.t() | nil
          }
  end

  defmodule StringList do
    @moduledoc """
    User provided string values assigned to a single metadata key.
    """

    defstruct [:values]

    @type t :: %__MODULE__{
            values: [String.t()]
          }
  end

  defmodule MetadataFilter do
    @moduledoc """
    User provided filter to limit retrieval based on Chunk or Document level metadata values.
    """

    defstruct [:key, :conditions]

    @type t :: %__MODULE__{
            key: String.t(),
            conditions: [Condition.t()]
          }
  end

  defmodule Condition do
    @moduledoc """
    Filter condition applicable to a single key.
    """

    defstruct [
      :operation,
      :string_value,
      :numeric_value
    ]

    @type t :: %__MODULE__{
            operation: String.t(),
            string_value: String.t() | nil,
            numeric_value: number() | nil
          }
  end

  defmodule QueryResult do
    @moduledoc """
    Response from document query containing a list of relevant chunks.
    """

    defstruct [:relevant_chunks]

    @type t :: %__MODULE__{
            relevant_chunks: [RelevantChunk.t()]
          }
  end

  defmodule RelevantChunk do
    @moduledoc """
    The information for a chunk relevant to a query.
    """

    defstruct [
      :chunk_relevance_score,
      :chunk
    ]

    @type t :: %__MODULE__{
            chunk_relevance_score: number(),
            chunk: map()
          }
  end

  defmodule ListResult do
    @moduledoc """
    Response from listing documents with pagination support.
    """

    defstruct [:documents, :next_page_token]

    @type t :: %__MODULE__{
            documents: [t()],
            next_page_token: String.t() | nil
          }
  end

  @doc """
  Creates an empty Document in the specified corpus.

  ## Parameters

  - `parent` - The corpus name in format "corpora/{corpus_id}"
  - `params` - Document creation parameters
  - `auth` - Authentication (API key or OAuth2 token)

  ## Params

  - `:name` - Optional custom document name
  - `:display_name` - Human-readable display name (max 512 characters)
  - `:custom_metadata` - List of key-value metadata (max 20 items)

  ## Examples

      # Create with auto-generated name
      {:ok, doc} = Document.create_document(
        "corpora/my-corpus",
        %{display_name: "Research Papers"}
      )
      
      # Create with custom name and metadata
      {:ok, doc} = Document.create_document(
        "corpora/my-corpus",
        %{
          name: "corpora/my-corpus/documents/research-2024",
          display_name: "Research Papers 2024",
          custom_metadata: [
            %{key: "category", string_value: "research"},
            %{key: "year", numeric_value: 2024}
          ]
        }
      )
  """
  @spec create_document(String.t(), map(), Keyword.t()) :: {:ok, t()} | {:error, map()}
  def create_document(parent, params, opts \\ []) do
    with :ok <- validate_corpus_name(parent),
         :ok <- validate_create_params(params) do
      url = "/#{parent}/documents"
      body = build_create_request(params)

      request_opts = [
        method: :post,
        url: url,
        body: body,
        query: %{}
      ]

      request_opts = add_auth(request_opts, opts)

      case Base.request(request_opts) do
        {:ok, response} ->
          {:ok, parse_document(response)}

        {:error, %{status: status, message: message}} ->
          {:error, %{code: status, message: message}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Lists all Documents in a Corpus with pagination support.

  ## Parameters

  - `parent` - The corpus name in format "corpora/{corpus_id}"
  - `opts` - Optional listing parameters
  - `auth` - Authentication (API key or OAuth2 token)

  ## Options

  - `:page_size` - Maximum documents per page (1-20, default 10)
  - `:page_token` - Token for pagination

  ## Examples

      # List all documents
      {:ok, result} = Document.list_documents("corpora/my-corpus")
      
      # List with pagination
      {:ok, result} = Document.list_documents(
        "corpora/my-corpus",
        %{page_size: 20, page_token: "next-page-token"}
      )
  """
  @spec list_documents(String.t(), Keyword.t()) :: {:ok, ListResult.t()} | {:error, map()}
  def list_documents(parent, opts \\ []) do
    {list_opts, auth_opts} = Keyword.split(opts, [:page_size, :page_token])

    with :ok <- validate_corpus_name(parent),
         :ok <- validate_list_opts(list_opts) do
      query = build_list_query(list_opts)
      url = "/#{parent}/documents"

      request_opts = [
        method: :get,
        url: url,
        body: nil,
        query: query
      ]

      request_opts = add_auth(request_opts, auth_opts)

      case Base.request(request_opts) do
        {:ok, response} ->
          {:ok, parse_list_result(response)}

        {:error, %{status: status, message: message}} ->
          {:error, %{code: status, message: message}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Gets information about a specific Document.

  ## Parameters

  - `name` - The document name in format "corpora/{corpus_id}/documents/{document_id}"
  - `auth` - Authentication (API key or OAuth2 token)

  ## Examples

      {:ok, document} = Document.get_document("corpora/my-corpus/documents/my-doc")
  """
  @spec get_document(String.t(), Keyword.t()) :: {:ok, t()} | {:error, map()}
  def get_document(name, opts \\ []) do
    with :ok <- validate_document_name(name) do
      request_opts = [
        method: :get,
        url: "/#{name}",
        body: nil,
        query: %{}
      ]

      request_opts = add_auth(request_opts, opts)

      case Base.request(request_opts) do
        {:ok, response} ->
          {:ok, parse_document(response)}

        {:error, %{status: status, message: message}} ->
          {:error, %{code: status, message: message}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Updates a Document.

  ## Parameters

  - `name` - The document name in format "corpora/{corpus_id}/documents/{document_id}"
  - `updates` - Fields to update
  - `opts` - Update options including update_mask
  - `auth` - Authentication (API key or OAuth2 token)

  ## Updates

  - `:display_name` - New display name
  - `:custom_metadata` - New custom metadata

  ## Options

  - `:update_mask` - Required. Fields to update ("displayName", "customMetadata")

  ## Examples

      # Update display name
      {:ok, doc} = Document.update_document(
        "corpora/my-corpus/documents/my-doc",
        %{display_name: "New Name"},
        %{update_mask: "displayName"}
      )
      
      # Update metadata
      {:ok, doc} = Document.update_document(
        "corpora/my-corpus/documents/my-doc",
        %{custom_metadata: [%{key: "status", string_value: "published"}]},
        %{update_mask: "customMetadata"}
      )
  """
  @spec update_document(String.t(), map(), [String.t()], Keyword.t()) ::
          {:ok, t()} | {:error, map()}
  def update_document(name, updates, update_mask, opts \\ []) do
    with :ok <- validate_document_name(name),
         :ok <- validate_update_params(updates, update_mask) do
      query = build_update_query(update_mask)
      body = build_update_request(updates)

      request_opts = [
        method: :patch,
        url: "/#{name}",
        body: body,
        query: query
      ]

      request_opts = add_auth(request_opts, opts)

      case Base.request(request_opts) do
        {:ok, response} ->
          {:ok, parse_document(response)}

        {:error, %{status: status, message: message}} ->
          {:error, %{code: status, message: message}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Deletes a Document.

  ## Parameters

  - `name` - The document name in format "corpora/{corpus_id}/documents/{document_id}"
  - `opts` - Delete options
  - `auth` - Authentication (API key or OAuth2 token)

  ## Options

  - `:force` - If true, delete related chunks. If false (default), fail if chunks exist.

  ## Examples

      # Delete document (fails if chunks exist)
      :ok = Document.delete_document("corpora/my-corpus/documents/my-doc")
      
      # Force delete with chunks
      :ok = Document.delete_document(
        "corpora/my-corpus/documents/my-doc",
        %{force: true}
      )
  """
  @spec delete_document(String.t(), Keyword.t()) :: :ok | {:error, map()}
  def delete_document(name, opts \\ []) do
    {delete_opts, auth_opts} = Keyword.split(opts, [:force])

    with :ok <- validate_document_name(name) do
      query = build_delete_query(delete_opts)

      request_opts = [
        method: :delete,
        url: "/#{name}",
        body: nil,
        query: query
      ]

      request_opts = add_auth(request_opts, auth_opts)

      case Base.request(request_opts) do
        {:ok, _response} ->
          :ok

        {:error, %{status: status, message: message}} ->
          {:error, %{code: status, message: message}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Performs semantic search over a Document.

  ## Parameters

  - `name` - The document name in format "corpora/{corpus_id}/documents/{document_id}"
  - `query` - Query string to perform semantic search
  - `opts` - Query options
  - `auth` - Authentication (API key or OAuth2 token)

  ## Options

  - `:results_count` - Maximum chunks to return (1-100, default 10)
  - `:metadata_filters` - List of metadata filters for chunk filtering

  ## Examples

      # Simple query
      {:ok, result} = Document.query_document(
        "corpora/my-corpus/documents/my-doc",
        "artificial intelligence"
      )
      
      # Query with filters
      {:ok, result} = Document.query_document(
        "corpora/my-corpus/documents/my-doc",
        "machine learning",
        %{
          results_count: 5,
          metadata_filters: [
            %{
              key: "chunk.custom_metadata.category",
              conditions: [%{operation: "EQUAL", string_value: "research"}]
            }
          ]
        }
      )
  """
  @spec query_document(String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, QueryResult.t()} | {:error, map()}
  def query_document(name, query, query_opts \\ %{}, opts \\ []) do
    with :ok <- validate_document_name(name),
         :ok <- validate_query_params(query, query_opts) do
      url = "/#{name}:query"
      body = build_query_request(query, query_opts)

      request_opts = [
        method: :post,
        url: url,
        body: body,
        query: %{}
      ]

      request_opts = add_auth(request_opts, opts)

      case Base.request(request_opts) do
        {:ok, response} ->
          {:ok, parse_query_result(response)}

        {:error, %{status: status, message: message}} ->
          {:error, %{code: status, message: message}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  # Private functions

  @doc false
  def validate_corpus_name(nil) do
    {:error, %{message: "corpus name cannot be nil"}}
  end

  def validate_corpus_name(name) when is_binary(name) do
    # Corpus ID can contain up to 40 characters that are lowercase alphanumeric or dashes
    # but cannot start or end with a dash
    if String.match?(name, ~r/^corpora\/[a-zA-Z0-9]([a-zA-Z0-9\-]{0,38}[a-zA-Z0-9])?$/) do
      :ok
    else
      {:error, %{message: "corpus name must be in format 'corpora/{corpus_id}'"}}
    end
  end

  def validate_corpus_name(_) do
    {:error, %{message: "corpus name must be a string"}}
  end

  @doc false
  def validate_document_name(name) do
    # Both corpus and document IDs follow the same pattern:
    # up to 40 characters that are alphanumeric or dashes, but cannot start or end with a dash
    corpus_pattern = ~r/[a-zA-Z0-9]([a-zA-Z0-9\-]{0,38}[a-zA-Z0-9])?/
    document_pattern = ~r/[a-zA-Z0-9]([a-zA-Z0-9\-]{0,38}[a-zA-Z0-9])?/

    if String.match?(
         name,
         ~r/^corpora\/#{corpus_pattern.source}\/documents\/#{document_pattern.source}$/
       ) do
      :ok
    else
      {:error,
       %{message: "document name must be in format 'corpora/{corpus_id}/documents/{document_id}'"}}
    end
  end

  @doc false
  def validate_create_params(params) do
    cond do
      params[:display_name] && String.length(params[:display_name]) > 512 ->
        {:error, %{message: "display name must be no more than 512 characters"}}

      params[:custom_metadata] && Enum.count(params[:custom_metadata]) > 20 ->
        {:error, %{message: "maximum of 20 CustomMetadata allowed"}}

      true ->
        :ok
    end
  end

  @doc false
  def validate_list_opts(opts) do
    cond do
      opts[:page_size] && opts[:page_size] > 20 ->
        {:error, %{message: "maximum size limit is 20 Documents per page"}}

      true ->
        :ok
    end
  end

  @doc false
  def validate_update_params(updates, update_mask) do
    valid_fields = ["displayName", "customMetadata"]

    cond do
      not is_list(update_mask) || Enum.empty?(update_mask) ->
        {:error, %{message: "updateMask is required"}}

      not Enum.all?(update_mask, &(&1 in valid_fields)) ->
        {:error, %{message: "updateMask only supports updating displayName and customMetadata"}}

      updates[:display_name] && String.length(updates[:display_name]) > 512 ->
        {:error, %{message: "display name must be no more than 512 characters"}}

      updates[:custom_metadata] && Enum.count(updates[:custom_metadata]) > 20 ->
        {:error, %{message: "maximum of 20 CustomMetadata allowed"}}

      true ->
        :ok
    end
  end

  @doc false
  def validate_query_params(query, opts) do
    cond do
      query == "" ->
        {:error, %{message: "query is required and cannot be empty"}}

      opts[:results_count] && opts[:results_count] > 100 ->
        {:error, %{message: "maximum specified result count is 100"}}

      true ->
        :ok
    end
  end

  defp build_list_query(opts) do
    query = %{}

    query = if opts[:page_size], do: Map.put(query, "pageSize", opts[:page_size]), else: query
    query = if opts[:page_token], do: Map.put(query, "pageToken", opts[:page_token]), else: query

    query
  end

  defp build_update_query(update_mask) do
    if update_mask && not Enum.empty?(update_mask) do
      %{"updateMask" => Enum.join(update_mask, ",")}
    else
      %{}
    end
  end

  defp build_delete_query(opts) do
    query = %{}

    query = if opts[:force], do: Map.put(query, "force", opts[:force]), else: query

    query
  end

  @doc false
  def build_create_request(params) do
    request = %{}

    request = if params[:name], do: Map.put(request, :name, params[:name]), else: request

    request =
      if params[:display_name],
        do: Map.put(request, :displayName, params[:display_name]),
        else: request

    request =
      if params[:custom_metadata],
        do: Map.put(request, :customMetadata, format_metadata(params[:custom_metadata])),
        else: request

    request
  end

  @doc false
  def build_update_request(updates) do
    request = %{}

    request =
      if updates[:display_name],
        do: Map.put(request, :displayName, updates[:display_name]),
        else: request

    request =
      if updates[:custom_metadata],
        do: Map.put(request, :customMetadata, format_metadata(updates[:custom_metadata])),
        else: request

    request
  end

  @doc false
  def build_query_request(query, opts) do
    request = %{query: query}

    request =
      if opts[:results_count],
        do: Map.put(request, :resultsCount, opts[:results_count]),
        else: request

    request =
      if opts[:metadata_filters],
        do: Map.put(request, :metadataFilters, format_filters(opts[:metadata_filters])),
        else: request

    request
  end

  @doc false
  def format_metadata(metadata) do
    Enum.map(metadata, fn meta ->
      formatted = %{key: meta.key}

      cond do
        meta[:string_value] ->
          Map.put(formatted, :stringValue, meta[:string_value])

        meta[:numeric_value] ->
          Map.put(formatted, :numericValue, meta[:numeric_value])

        meta[:string_list_value] ->
          Map.put(formatted, :stringListValue, %{values: meta[:string_list_value][:values]})

        true ->
          formatted
      end
    end)
  end

  defp format_filters(filters) do
    Enum.map(filters, fn filter ->
      %{
        key: filter.key,
        conditions:
          Enum.map(filter.conditions, fn condition ->
            formatted = %{operation: condition.operation}

            cond do
              condition[:string_value] ->
                Map.put(formatted, :stringValue, condition[:string_value])

              condition[:numeric_value] ->
                Map.put(formatted, :numericValue, condition[:numeric_value])

              true ->
                formatted
            end
          end)
      }
    end)
  end

  @doc false
  def parse_document(response) do
    # Handle different response formats from HTTPClient
    actual_body = 
      cond do
        # Direct response body format (expected)
        is_map(response) and Map.has_key?(response, "name") ->
          response
        
        # Wrapped HTTP response format (from cache or HTTPClient)
        is_map(response) and Map.has_key?(response, :body) and is_map(response[:body]) ->
          response[:body]
        
        # String key wrapped format
        is_map(response) and Map.has_key?(response, "body") and is_map(response["body"]) ->
          response["body"]
        
        # Fallback to original format
        true ->
          response
      end
    
    %__MODULE__{
      name: actual_body["name"],
      display_name: actual_body["displayName"],
      custom_metadata: parse_metadata(actual_body["customMetadata"]),
      create_time: actual_body["createTime"],
      update_time: actual_body["updateTime"]
    }
  end

  defp parse_metadata(nil), do: nil

  defp parse_metadata(metadata) do
    Enum.map(metadata, fn meta ->
      %CustomMetadata{
        key: meta["key"],
        string_value: meta["stringValue"],
        numeric_value: meta["numericValue"],
        string_list_value: parse_string_list(meta["stringListValue"])
      }
    end)
  end

  defp parse_string_list(nil), do: nil

  defp parse_string_list(string_list) do
    %StringList{values: string_list["values"]}
  end

  defp parse_list_result(response) do
    %ListResult{
      documents: Enum.map(response["documents"] || [], &parse_document/1),
      next_page_token: response["nextPageToken"]
    }
  end

  defp parse_query_result(response) do
    %QueryResult{
      relevant_chunks: Enum.map(response["relevantChunks"] || [], &parse_relevant_chunk/1)
    }
  end

  defp parse_relevant_chunk(chunk) do
    %RelevantChunk{
      chunk_relevance_score: chunk["chunkRelevanceScore"],
      chunk: chunk["chunk"]
    }
  end

  defp add_auth(request_opts, opts) do
    if oauth_token = opts[:oauth_token] do
      # Add oauth_token and pass through all other options
      request_opts
      |> Keyword.put(:oauth_token, oauth_token)
      |> Keyword.put(:opts, opts)
    else
      if api_key = opts[:api_key] do
        # Add api_key and pass through all other options
        request_opts
        |> Keyword.put(:api_key, api_key)
        |> Keyword.put(:opts, opts)
      else
        raise ArgumentError,
              "Authentication required. Set :oauth_token or :api_key option"
      end
    end
  end
end
