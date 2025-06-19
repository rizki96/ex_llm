defmodule ExLLM.Providers.Gemini.Corpus do
  @moduledoc """
  Google Gemini Corpus Management API implementation.

  Corpora are collections of Documents used for semantic retrieval. A project can 
  create up to 5 corpora.

  ## Usage

      # Create a corpus
      {:ok, corpus} = ExLLM.Providers.Gemini.Corpus.create_corpus(%{
        display_name: "My Knowledge Base"
      }, oauth_token: "your-oauth-token")
      
      # List corpora
      {:ok, response} = ExLLM.Providers.Gemini.Corpus.list_corpora(%{
        page_size: 10
      }, oauth_token: "your-oauth-token")
      
      # Query a corpus
      {:ok, response} = ExLLM.Providers.Gemini.Corpus.query_corpus(
        "corpora/my-corpus",
        "search query",
        %{results_count: 5},
        oauth_token: "your-oauth-token"
      )
      
      # Update corpus
      {:ok, corpus} = ExLLM.Providers.Gemini.Corpus.update_corpus(
        "corpora/my-corpus",
        %{display_name: "Updated Name"},
        ["displayName"],
        oauth_token: "your-oauth-token"
      )
      
      # Delete corpus
      :ok = ExLLM.Providers.Gemini.Corpus.delete_corpus(
        "corpora/my-corpus",
        oauth_token: "your-oauth-token"
      )
  """

  alias ExLLM.Providers.Gemini.Base

  defmodule CreateCorpusRequest do
    @moduledoc """
    Request structure for creating a corpus.
    """

    @type t :: %__MODULE__{
            name: String.t() | nil,
            display_name: String.t() | nil
          }

    defstruct [:name, :display_name]
  end

  defmodule UpdateCorpusRequest do
    @moduledoc """
    Request structure for updating a corpus.
    """

    @type t :: %__MODULE__{
            name: String.t(),
            display_name: String.t() | nil,
            update_mask: [String.t()]
          }

    defstruct [:name, :display_name, :update_mask]
  end

  defmodule ListCorporaRequest do
    @moduledoc """
    Request structure for listing corpora.
    """

    @type t :: %__MODULE__{
            page_size: integer() | nil,
            page_token: String.t() | nil
          }

    defstruct [:page_size, :page_token]
  end

  defmodule QueryCorpusRequest do
    @moduledoc """
    Request structure for querying a corpus.
    """

    @type t :: %__MODULE__{
            name: String.t(),
            query: String.t(),
            metadata_filters: [MetadataFilter.t()],
            results_count: integer() | nil
          }

    defstruct [:name, :query, :metadata_filters, :results_count]
  end

  defmodule CorpusInfo do
    @moduledoc """
    Information about a corpus.
    """

    @type t :: %__MODULE__{
            name: String.t(),
            display_name: String.t() | nil,
            create_time: String.t() | nil,
            update_time: String.t() | nil
          }

    defstruct [:name, :display_name, :create_time, :update_time]
  end

  defmodule ListCorporaResponse do
    @moduledoc """
    Response from listing corpora.
    """

    @type t :: %__MODULE__{
            corpora: [CorpusInfo.t()],
            next_page_token: String.t() | nil
          }

    defstruct [:corpora, :next_page_token]
  end

  defmodule QueryCorpusResponse do
    @moduledoc """
    Response from querying a corpus.
    """

    @type t :: %__MODULE__{
            relevant_chunks: [RelevantChunk.t()]
          }

    defstruct [:relevant_chunks]
  end

  defmodule MetadataFilter do
    @moduledoc """
    Filter for chunk and document metadata.
    """

    @type t :: %__MODULE__{
            key: String.t(),
            conditions: [Condition.t()]
          }

    defstruct [:key, :conditions]
  end

  defmodule Condition do
    @moduledoc """
    Filter condition for metadata values.
    """

    @type t :: %__MODULE__{
            operation: atom(),
            string_value: String.t() | nil,
            numeric_value: number() | nil
          }

    defstruct [:operation, :string_value, :numeric_value]
  end

  defmodule RelevantChunk do
    @moduledoc """
    A chunk relevant to a query with its relevance score.
    """

    @type t :: %__MODULE__{
            chunk_relevance_score: float(),
            chunk: map()
          }

    defstruct [:chunk_relevance_score, :chunk]
  end

  @doc """
  Creates a new corpus.

  ## Parameters

  * `corpus_data` - Map containing corpus information
    * `:name` - Optional corpus name (will be auto-generated if not provided)
    * `:display_name` - Optional human-readable display name
  * `opts` - Options including OAuth2 token

  ## Options

  * `:oauth_token` - OAuth2 token (required for corpus operations)

  ## Examples

      # Create corpus with auto-generated name
      {:ok, corpus} = ExLLM.Providers.Gemini.Corpus.create_corpus(%{
        display_name: "My Knowledge Base"
      }, oauth_token: "your-oauth-token")
      
      # Create corpus with specific name
      {:ok, corpus} = ExLLM.Providers.Gemini.Corpus.create_corpus(%{
        name: "corpora/my-custom-corpus",
        display_name: "Custom Corpus"
      }, oauth_token: "your-oauth-token")
  """
  @spec create_corpus(map(), Keyword.t()) :: {:ok, CorpusInfo.t()} | {:error, map()}
  def create_corpus(corpus_data, opts \\ []) do
    request = build_create_corpus_request(corpus_data)

    request_opts = [
      method: :post,
      url: "/corpora",
      body: encode_create_corpus_request(request),
      query: %{}
    ]

    request_opts = add_auth(request_opts, opts)

    case Base.request(request_opts) do
      {:ok, response_body} ->
        {:ok, parse_corpus_response(response_body)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Lists corpora owned by the user.

  ## Parameters

  * `list_options` - Map containing pagination options
    * `:page_size` - Optional maximum number of corpora per page (1-20)
    * `:page_token` - Optional page token for pagination
  * `opts` - Options including OAuth2 token

  ## Examples

      # List all corpora
      {:ok, response} = ExLLM.Providers.Gemini.Corpus.list_corpora(%{}, 
        oauth_token: "your-oauth-token")
      
      # List with pagination
      {:ok, response} = ExLLM.Providers.Gemini.Corpus.list_corpora(%{
        page_size: 5,
        page_token: "next_page_token"
      }, oauth_token: "your-oauth-token")
  """
  @spec list_corpora(keyword() | map(), Keyword.t()) ::
          {:ok, ListCorporaResponse.t()} | {:error, map()}
  def list_corpora(list_options, opts \\ []) do
    request = build_list_corpora_request(list_options)

    query_params = %{}

    query_params =
      if request.page_size,
        do: Map.put(query_params, "pageSize", request.page_size),
        else: query_params

    query_params =
      if request.page_token,
        do: Map.put(query_params, "pageToken", request.page_token),
        else: query_params

    request_opts = [
      method: :get,
      url: "/corpora",
      body: nil,
      query: query_params
    ]

    request_opts = add_auth(request_opts, opts)

    case Base.request(request_opts) do
      {:ok, response_body} ->
        {:ok, parse_list_corpora_response(response_body)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets information about a specific corpus.

  ## Parameters

  * `corpus_name` - The name of the corpus (e.g., "corpora/my-corpus")
  * `opts` - Options including OAuth2 token

  ## Examples

      {:ok, corpus} = ExLLM.Providers.Gemini.Corpus.get_corpus(
        "corpora/my-corpus",
        oauth_token: "your-oauth-token"
      )
  """
  @spec get_corpus(String.t(), Keyword.t()) :: {:ok, CorpusInfo.t()} | {:error, map()}
  def get_corpus(corpus_name, opts \\ []) do
    request_opts = [
      method: :get,
      url: "/#{corpus_name}",
      body: nil,
      query: %{}
    ]

    request_opts = add_auth(request_opts, opts)

    case Base.request(request_opts) do
      {:ok, response_body} ->
        {:ok, parse_corpus_response(response_body)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Updates a corpus.

  ## Parameters

  * `corpus_name` - The name of the corpus to update
  * `update_data` - Map containing fields to update
    * `:display_name` - New display name
  * `update_mask` - List of fields to update (currently only ["displayName"] is supported)
  * `opts` - Options including OAuth2 token

  ## Examples

      {:ok, corpus} = ExLLM.Providers.Gemini.Corpus.update_corpus(
        "corpora/my-corpus",
        %{display_name: "Updated Name"},
        ["displayName"],
        oauth_token: "your-oauth-token"
      )
  """
  @spec update_corpus(String.t(), map(), [String.t()], Keyword.t()) ::
          {:ok, CorpusInfo.t()} | {:error, map()}
  def update_corpus(corpus_name, update_data, update_mask, opts \\ []) do
    request = build_update_corpus_request(corpus_name, update_data, update_mask)

    query_params = %{"updateMask" => Enum.join(update_mask, ",")}

    request_opts = [
      method: :patch,
      url: "/#{corpus_name}",
      body: encode_update_corpus_request(request),
      query: query_params
    ]

    request_opts = add_auth(request_opts, opts)

    case Base.request(request_opts) do
      {:ok, response_body} ->
        {:ok, parse_corpus_response(response_body)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Deletes a corpus.

  ## Parameters

  * `corpus_name` - The name of the corpus to delete
  * `opts` - Options including OAuth2 token and force flag
    * `:force` - If true, delete all documents in the corpus as well

  ## Examples

      # Delete empty corpus
      :ok = ExLLM.Providers.Gemini.Corpus.delete_corpus(
        "corpora/my-corpus",
        oauth_token: "your-oauth-token"
      )
      
      # Force delete corpus with documents
      :ok = ExLLM.Providers.Gemini.Corpus.delete_corpus(
        "corpora/my-corpus",
        oauth_token: "your-oauth-token",
        force: true
      )
  """
  @spec delete_corpus(String.t(), Keyword.t()) :: :ok | {:error, map()}
  def delete_corpus(corpus_name, opts \\ []) do
    query_params = if opts[:force], do: %{"force" => "true"}, else: %{}

    request_opts = [
      method: :delete,
      url: "/#{corpus_name}",
      body: nil,
      query: query_params
    ]

    request_opts = add_auth(request_opts, opts)

    case Base.request(request_opts) do
      {:ok, _response_body} ->
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Performs semantic search over a corpus.

  ## Parameters

  * `corpus_name` - The name of the corpus to query
  * `query` - The search query string
  * `query_options` - Map containing query options
    * `:results_count` - Maximum number of chunks to return (1-100)
    * `:metadata_filters` - List of metadata filters
  * `opts` - Options including OAuth2 token

  ## Examples

      # Simple query
      {:ok, response} = ExLLM.Providers.Gemini.Corpus.query_corpus(
        "corpora/my-corpus",
        "artificial intelligence",
        %{results_count: 10},
        oauth_token: "your-oauth-token"
      )
      
      # Query with metadata filters
      {:ok, response} = ExLLM.Providers.Gemini.Corpus.query_corpus(
        "corpora/my-corpus",
        "machine learning",
        %{
          results_count: 5,
          metadata_filters: [
            %{
              key: "document.custom_metadata.category",
              conditions: [
                %{string_value: "technology", operation: "EQUAL"}
              ]
            }
          ]
        },
        oauth_token: "your-oauth-token"
      )
  """
  @spec query_corpus(String.t(), String.t(), map(), Keyword.t()) ::
          {:ok, QueryCorpusResponse.t()} | {:error, map()}
  def query_corpus(corpus_name, query, query_options, opts \\ []) do
    request = build_query_corpus_request(corpus_name, query, query_options)

    request_opts = [
      method: :post,
      url: "/#{corpus_name}:query",
      body: encode_query_corpus_request(request),
      query: %{}
    ]

    request_opts = add_auth(request_opts, opts)

    case Base.request(request_opts) do
      {:ok, response_body} ->
        {:ok, parse_query_corpus_response(response_body)}

      {:error, error} ->
        {:error, error}
    end
  end

  # Request builders

  @doc """
  Builds a CreateCorpusRequest struct from the given parameters.
  """
  @spec build_create_corpus_request(map()) :: CreateCorpusRequest.t()
  def build_create_corpus_request(corpus_data) do
    name = corpus_data[:name] || corpus_data["name"]
    display_name = corpus_data[:display_name] || corpus_data["displayName"]

    # Validate inputs
    if name && !valid_corpus_name?(name) do
      raise ArgumentError, "Invalid corpus name format: #{name}"
    end

    if display_name && !valid_display_name?(display_name) do
      raise ArgumentError, "Display name must be 512 characters or less"
    end

    %CreateCorpusRequest{
      name: name,
      display_name: display_name
    }
  end

  @doc """
  Builds a ListCorporaRequest struct from the given parameters.
  """
  @spec build_list_corpora_request(keyword() | map()) :: ListCorporaRequest.t()
  def build_list_corpora_request(list_options) when is_list(list_options) do
    page_size = Keyword.get(list_options, :page_size)
    page_token = Keyword.get(list_options, :page_token)

    build_list_corpora_request(%{page_size: page_size, page_token: page_token})
  end

  def build_list_corpora_request(list_options) when is_map(list_options) do
    page_size = list_options[:page_size] || list_options["pageSize"]
    page_token = list_options[:page_token] || list_options["pageToken"]

    # Validate page size
    if page_size && (page_size < 1 || page_size > 20) do
      raise ArgumentError, "Page size must be between 1 and 20, got: #{page_size}"
    end

    %ListCorporaRequest{
      page_size: page_size,
      page_token: page_token
    }
  end

  @doc """
  Builds an UpdateCorpusRequest struct from the given parameters.
  """
  @spec build_update_corpus_request(String.t(), map(), [String.t()]) :: UpdateCorpusRequest.t()
  def build_update_corpus_request(corpus_name, update_data, update_mask) do
    # Validate update mask
    if Enum.empty?(update_mask) do
      raise ArgumentError, "Update mask is required"
    end

    valid_fields = ["displayName"]
    invalid_fields = Enum.reject(update_mask, &(&1 in valid_fields))

    if !Enum.empty?(invalid_fields) do
      raise ArgumentError,
            "Update mask can only contain: #{Enum.join(valid_fields, ", ")}. Invalid: #{Enum.join(invalid_fields, ", ")}"
    end

    display_name = update_data[:display_name] || update_data["displayName"]

    if display_name && !valid_display_name?(display_name) do
      raise ArgumentError, "Display name must be 512 characters or less"
    end

    %UpdateCorpusRequest{
      name: corpus_name,
      display_name: display_name,
      update_mask: update_mask
    }
  end

  @doc """
  Builds a QueryCorpusRequest struct from the given parameters.
  """
  @spec build_query_corpus_request(String.t(), String.t(), map()) :: QueryCorpusRequest.t()
  def build_query_corpus_request(corpus_name, query, query_options) do
    results_count = query_options[:results_count] || query_options["resultsCount"]
    metadata_filters = query_options[:metadata_filters] || query_options["metadataFilters"] || []

    # Validate results count
    if results_count && (results_count < 1 || results_count > 100) do
      raise ArgumentError, "Results count must be between 1 and 100, got: #{results_count}"
    end

    # Validate and build metadata filters
    validated_filters = Enum.map(metadata_filters, &build_metadata_filter/1)

    %QueryCorpusRequest{
      name: corpus_name,
      query: query,
      metadata_filters: validated_filters,
      results_count: results_count
    }
  end

  # Response parsers

  @doc """
  Parses a corpus response from the API.
  """
  @spec parse_corpus_response(map()) :: CorpusInfo.t()
  def parse_corpus_response(response_body) do
    # Handle different response formats from HTTPClient
    actual_body =
      cond do
        # Direct response body format (expected)
        is_map(response_body) and Map.has_key?(response_body, "name") ->
          response_body

        # Wrapped HTTP response format (from cache or HTTPClient)
        is_map(response_body) and Map.has_key?(response_body, :body) and
            is_map(response_body[:body]) ->
          response_body[:body]

        # String key wrapped format
        is_map(response_body) and Map.has_key?(response_body, "body") and
            is_map(response_body["body"]) ->
          response_body["body"]

        # Fallback to original format
        true ->
          response_body
      end

    %CorpusInfo{
      name: actual_body["name"],
      display_name: actual_body["displayName"],
      create_time: actual_body["createTime"],
      update_time: actual_body["updateTime"]
    }
  end

  @doc """
  Parses a list corpora response from the API.
  """
  @spec parse_list_corpora_response(map()) :: ListCorporaResponse.t()
  def parse_list_corpora_response(response_body) do
    corpora =
      (response_body["corpora"] || [])
      |> Enum.map(&parse_corpus_response/1)

    %ListCorporaResponse{
      corpora: corpora,
      next_page_token: response_body["nextPageToken"]
    }
  end

  @doc """
  Parses a query corpus response from the API.
  """
  @spec parse_query_corpus_response(map()) :: QueryCorpusResponse.t()
  def parse_query_corpus_response(response_body) do
    relevant_chunks =
      (response_body["relevantChunks"] || [])
      |> Enum.map(&parse_relevant_chunk/1)

    %QueryCorpusResponse{
      relevant_chunks: relevant_chunks
    }
  end

  # Format functions

  @doc """
  Formats an operator string from the API to an atom.
  """
  @spec format_operator(String.t()) :: atom()
  def format_operator("EQUAL"), do: :equal
  def format_operator("GREATER"), do: :greater
  def format_operator("GREATER_EQUAL"), do: :greater_equal
  def format_operator("LESS"), do: :less
  def format_operator("LESS_EQUAL"), do: :less_equal
  def format_operator("NOT_EQUAL"), do: :not_equal
  def format_operator("INCLUDES"), do: :includes
  def format_operator("EXCLUDES"), do: :excludes
  def format_operator(_), do: :unknown

  @doc """
  Converts an operator atom to the API string format.
  """
  @spec operator_to_api_string(atom()) :: String.t()
  def operator_to_api_string(:equal), do: "EQUAL"
  def operator_to_api_string(:greater), do: "GREATER"
  def operator_to_api_string(:greater_equal), do: "GREATER_EQUAL"
  def operator_to_api_string(:less), do: "LESS"
  def operator_to_api_string(:less_equal), do: "LESS_EQUAL"
  def operator_to_api_string(:not_equal), do: "NOT_EQUAL"
  def operator_to_api_string(:includes), do: "INCLUDES"
  def operator_to_api_string(:excludes), do: "EXCLUDES"

  def operator_to_api_string(op) do
    raise ArgumentError, "Invalid operator: #{inspect(op)}"
  end

  # Validation helpers

  @doc """
  Validates if a corpus name has the correct format.
  """
  @spec valid_corpus_name?(String.t()) :: boolean()
  def valid_corpus_name?(name) do
    case String.split(name, "/", parts: 2) do
      ["corpora", corpus_id] ->
        String.length(corpus_id) > 0 &&
          String.length(corpus_id) <= 40 &&
          !String.starts_with?(corpus_id, "-") &&
          !String.ends_with?(corpus_id, "-") &&
          String.match?(corpus_id, ~r/^[a-z0-9-]+$/)

      _ ->
        false
    end
  end

  @doc """
  Validates if a display name has a valid length.
  """
  @spec valid_display_name?(String.t()) :: boolean()
  def valid_display_name?(display_name) do
    String.length(display_name) <= 512
  end

  # Private functions

  defp add_auth(request_opts, opts) do
    if oauth_token = opts[:oauth_token] do
      # Add oauth_token and pass through all other options
      request_opts
      |> Keyword.put(:oauth_token, oauth_token)
      |> Keyword.put(:opts, opts)
    else
      raise ArgumentError,
            "OAuth2 token is required for corpus operations. Set :oauth_token option"
    end
  end

  defp encode_create_corpus_request(%CreateCorpusRequest{} = request) do
    base_request = %{}

    base_request =
      if request.name do
        Map.put(base_request, "name", request.name)
      else
        base_request
      end

    base_request =
      if request.display_name do
        Map.put(base_request, "displayName", request.display_name)
      else
        base_request
      end

    base_request
  end

  defp encode_update_corpus_request(%UpdateCorpusRequest{} = request) do
    base_request = %{}

    base_request =
      if request.display_name do
        Map.put(base_request, "displayName", request.display_name)
      else
        base_request
      end

    base_request
  end

  defp encode_query_corpus_request(%QueryCorpusRequest{} = request) do
    base_request = %{
      "query" => request.query
    }

    base_request =
      if request.results_count do
        Map.put(base_request, "resultsCount", request.results_count)
      else
        base_request
      end

    base_request =
      if !Enum.empty?(request.metadata_filters) do
        Map.put(
          base_request,
          "metadataFilters",
          Enum.map(request.metadata_filters, &encode_metadata_filter/1)
        )
      else
        base_request
      end

    base_request
  end

  defp build_metadata_filter(filter_data) when is_map(filter_data) do
    key = filter_data[:key] || filter_data["key"]
    conditions = filter_data[:conditions] || filter_data["conditions"]

    if is_nil(key) do
      raise ArgumentError, "Metadata filter key is required"
    end

    if is_nil(conditions) || !is_list(conditions) || Enum.empty?(conditions) do
      raise ArgumentError, "Metadata filter conditions are required and must be a non-empty list"
    end

    validated_conditions = Enum.map(conditions, &build_condition/1)

    %MetadataFilter{
      key: key,
      conditions: validated_conditions
    }
  end

  defp build_condition(condition_data) when is_map(condition_data) do
    operation = condition_data[:operation] || condition_data["operation"]
    string_value = condition_data[:string_value] || condition_data["stringValue"]
    numeric_value = condition_data[:numeric_value] || condition_data["numericValue"]

    if is_nil(operation) do
      raise ArgumentError, "Condition operation is required"
    end

    if is_nil(string_value) && is_nil(numeric_value) do
      raise ArgumentError, "Condition must have either string_value or numeric_value"
    end

    # Convert operation string to atom if needed
    operation_atom =
      if is_binary(operation) do
        format_operator(operation)
      else
        operation
      end

    %Condition{
      operation: operation_atom,
      string_value: string_value,
      numeric_value: numeric_value
    }
  end

  defp encode_metadata_filter(%MetadataFilter{} = filter) do
    %{
      "key" => filter.key,
      "conditions" => Enum.map(filter.conditions, &encode_condition/1)
    }
  end

  defp encode_condition(%Condition{} = condition) do
    base_condition = %{
      "operation" => operator_to_api_string(condition.operation)
    }

    base_condition =
      if condition.string_value do
        Map.put(base_condition, "stringValue", condition.string_value)
      else
        base_condition
      end

    base_condition =
      if condition.numeric_value do
        Map.put(base_condition, "numericValue", condition.numeric_value)
      else
        base_condition
      end

    base_condition
  end

  defp parse_relevant_chunk(chunk_data) do
    %RelevantChunk{
      chunk_relevance_score: chunk_data["chunkRelevanceScore"],
      chunk: chunk_data["chunk"]
    }
  end
end
