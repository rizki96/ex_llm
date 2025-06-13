defmodule ExLLM.Gemini.Caching do
  @moduledoc """
  Google Gemini Context Caching API implementation.
  
  Provides functionality to cache and reuse large contexts across multiple
  requests, reducing costs and improving performance for repeated queries
  on the same content.
  """

  alias ExLLM.Adapters.Shared.ConfigHelper
  alias ExLLM.Gemini.Content.{Content, Part, Tool, ToolConfig}

  defmodule UsageMetadata do
    @moduledoc """
    Token usage information for cached content.
    """
    
    @type t :: %__MODULE__{
      total_token_count: integer()
    }
    
    @enforce_keys [:total_token_count]
    defstruct [:total_token_count]
    
    @doc """
    Converts API response to UsageMetadata struct.
    """
    @spec from_api(map() | nil) :: t() | nil
    def from_api(nil), do: nil
    def from_api(data) when is_map(data) do
      %__MODULE__{
        total_token_count: data["totalTokenCount"] || 0
      }
    end
  end

  defmodule CachedContent do
    @moduledoc """
    Represents cached content that can be reused across requests.
    """
    
    @type t :: %__MODULE__{
      name: String.t(),
      display_name: String.t() | nil,
      model: String.t(),
      system_instruction: Content.t() | nil,
      contents: [Content.t()] | nil,
      tools: [Tool.t()] | nil,
      tool_config: ToolConfig.t() | nil,
      create_time: DateTime.t() | nil,
      update_time: DateTime.t() | nil,
      expire_time: DateTime.t() | nil,
      ttl: String.t() | nil,
      usage_metadata: UsageMetadata.t() | nil
    }
    
    @enforce_keys [:name, :model, :expire_time]
    defstruct [
      :name,
      :display_name,
      :model,
      :system_instruction,
      :contents,
      :tools,
      :tool_config,
      :create_time,
      :update_time,
      :expire_time,
      :ttl,
      :usage_metadata
    ]
    
    @doc """
    Converts API response to CachedContent struct.
    """
    @spec from_api(map()) :: t()
    def from_api(data) when is_map(data) do
      %__MODULE__{
        name: data["name"],
        display_name: data["displayName"],
        model: data["model"],
        system_instruction: parse_content(data["systemInstruction"]),
        contents: parse_contents(data["contents"]),
        tools: parse_tools(data["tools"]),
        tool_config: parse_tool_config(data["toolConfig"]),
        create_time: parse_timestamp(data["createTime"]),
        update_time: parse_timestamp(data["updateTime"]),
        expire_time: parse_timestamp(data["expireTime"]),
        ttl: data["ttl"],
        usage_metadata: UsageMetadata.from_api(data["usageMetadata"])
      }
    end
    
    defp parse_content(nil), do: nil
    defp parse_content(data) when is_map(data) do
      %Content{
        role: data["role"],
        parts: parse_parts(data["parts"])
      }
    end
    
    defp parse_contents(nil), do: nil
    defp parse_contents(contents) when is_list(contents) do
      Enum.map(contents, &parse_content/1)
    end
    
    defp parse_parts(nil), do: []
    defp parse_parts(parts) when is_list(parts) do
      Enum.map(parts, &parse_part/1)
    end
    
    defp parse_part(data) when is_map(data) do
      %Part{
        text: data["text"],
        inline_data: data["inlineData"],
        function_call: data["functionCall"],
        function_response: data["functionResponse"],
        code_execution_result: data["codeExecutionResult"]
      }
    end
    
    defp parse_tools(nil), do: nil
    defp parse_tools(tools) when is_list(tools) do
      Enum.map(tools, &parse_tool/1)
    end
    
    defp parse_tool(data) when is_map(data) do
      %Tool{
        function_declarations: data["functionDeclarations"],
        google_search: data["googleSearch"],
        code_execution: data["codeExecution"]
      }
    end
    
    defp parse_tool_config(nil), do: nil
    defp parse_tool_config(data) when is_map(data) do
      %ToolConfig{
        function_calling_config: data["functionCallingConfig"]
      }
    end
    
    defp parse_timestamp(nil), do: nil
    defp parse_timestamp(timestamp) when is_binary(timestamp) do
      case DateTime.from_iso8601(timestamp) do
        {:ok, datetime, _offset} -> datetime
        {:error, _} -> nil
      end
    end
  end

  @type create_options :: [
    {:config_provider, pid() | atom()}
  ]
  
  @type list_options :: [
    {:page_size, integer()} |
    {:page_token, String.t()} |
    {:config_provider, pid() | atom()}
  ]
  
  @type update_options :: [
    {:update_mask, String.t()} |
    {:config_provider, pid() | atom()}
  ]

  @doc """
  Creates a new cached content resource.
  
  ## Parameters
    * `request` - Map containing:
      * `:contents` - Content to cache
      * `:model` - Model to use (required)
      * `:ttl` or `:expire_time` - Expiration (one required)
      * `:display_name` - Optional display name
      * `:system_instruction` - Optional system instruction
      * `:tools` - Optional tools
      * `:tool_config` - Optional tool config
    * `opts` - Options including `:config_provider`
  
  ## Examples
      
      request = %{
        contents: [%Content{role: "user", parts: [%Part{text: "Large context"}]}],
        model: "models/gemini-2.0-flash",
        ttl: "3600s",
        display_name: "My Cache"
      }
      {:ok, cached} = ExLLM.Gemini.Caching.create_cached_content(request)
  """
  @spec create_cached_content(map(), create_options()) :: {:ok, CachedContent.t()} | {:error, term()}
  def create_cached_content(request, opts \\ []) do
    with :ok <- validate_create_request(request),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      
      # Normalize model name if needed
      request = Map.update!(request, :model, &normalize_model_name/1)
      
      # Build request body
      body = build_create_request_body(request)
      
      url = build_url("/v1beta/cachedContents", api_key)
      headers = build_headers()
      
      case Req.post(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, CachedContent.from_api(body)}
          
        {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 400, message: message}}
          
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
  Lists cached contents.
  
  ## Parameters
    * `opts` - Options including `:page_size`, `:page_token`, and `:config_provider`
  
  ## Examples
      
      {:ok, %{cached_contents: contents}} = ExLLM.Gemini.Caching.list_cached_contents(page_size: 10)
  """
  @spec list_cached_contents(list_options()) :: 
    {:ok, %{cached_contents: [CachedContent.t()], next_page_token: String.t() | nil}} | 
    {:error, term()}
  def list_cached_contents(opts \\ []) do
    with :ok <- validate_list_params(opts),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      
      query_params = build_list_query_params(opts)
      url = build_url("/v1beta/cachedContents", api_key, query_params)
      headers = build_headers()
      
      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          contents = 
            body
            |> Map.get("cachedContents", [])
            |> Enum.map(&CachedContent.from_api/1)
          
          {:ok, %{
            cached_contents: contents,
            next_page_token: Map.get(body, "nextPageToken")
          }}
          
        {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 400, message: message}}
          
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
  Gets a specific cached content.
  
  ## Parameters
    * `name` - The cached content name (e.g., "cachedContents/abc-123")
    * `opts` - Options including `:config_provider`
  
  ## Examples
      
      {:ok, cached} = ExLLM.Gemini.Caching.get_cached_content("cachedContents/abc-123")
  """
  @spec get_cached_content(String.t(), Keyword.t()) :: {:ok, CachedContent.t()} | {:error, term()}
  def get_cached_content(name, opts \\ []) do
    with :ok <- validate_cached_content_name(name),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      
      url = build_url("/v1beta/#{name}", api_key)
      headers = build_headers()
      
      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, CachedContent.from_api(body)}
          
        {:ok, %{status: 404}} ->
          {:error, %{status: 404, message: "Cached content not found: #{name}"}}
          
        {:ok, %{status: 403, body: body}} ->
          {:error, %{status: 403, message: "API error", body: body}}
          
        {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 400, message: message}}
          
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
  Updates cached content (only expiration can be updated).
  
  ## Parameters
    * `name` - The cached content name
    * `update` - Map containing either `:ttl` or `:expire_time`
    * `opts` - Options including `:update_mask` and `:config_provider`
  
  ## Examples
      
      {:ok, updated} = ExLLM.Gemini.Caching.update_cached_content(
        "cachedContents/abc-123",
        %{ttl: "7200s"}
      )
  """
  @spec update_cached_content(String.t(), map(), update_options()) :: 
    {:ok, CachedContent.t()} | {:error, term()}
  def update_cached_content(name, update, opts \\ []) do
    with :ok <- validate_cached_content_name(name),
         :ok <- validate_update_request(update),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      
      # Build update body and mask
      body = build_update_request_body(update)
      update_mask = opts[:update_mask] || build_update_mask(update)
      
      query_params = %{"updateMask" => update_mask}
      url = build_url("/v1beta/#{name}", api_key, query_params)
      headers = build_headers()
      
      case Req.patch(url, json: body, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, CachedContent.from_api(body)}
          
        {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 400, message: message}}
          
        {:ok, %{status: 404}} ->
          {:error, %{status: 404, message: "Cached content not found: #{name}"}}
          
        {:ok, %{status: 403, body: body}} ->
          {:error, %{status: 403, message: "API error", body: body}}
          
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
  Deletes cached content.
  
  ## Parameters
    * `name` - The cached content name
    * `opts` - Options including `:config_provider`
  
  ## Examples
      
      :ok = ExLLM.Gemini.Caching.delete_cached_content("cachedContents/abc-123")
  """
  @spec delete_cached_content(String.t(), Keyword.t()) :: :ok | {:error, term()}
  def delete_cached_content(name, opts \\ []) do
    with :ok <- validate_cached_content_name(name),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      
      url = build_url("/v1beta/#{name}", api_key)
      headers = build_headers()
      
      case Req.delete(url, headers: headers) do
        {:ok, %{status: status}} when status in [200, 204] ->
          :ok
          
        {:ok, %{status: 404}} ->
          {:error, %{status: 404, message: "Cached content not found: #{name}"}}
          
        {:ok, %{status: 403, body: body}} ->
          {:error, %{status: 403, message: "API error", body: body}}
          
        {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 400, message: message}}
          
        {:ok, %{status: status, body: body}} ->
          {:error, %{status: status, message: "API error", body: body}}
          
        {:error, reason} ->
          {:error, %{reason: :network_error, message: inspect(reason)}}
      end
    else
      {:error, _} = error -> error
    end
  end

  # Public validation functions for testing

  @doc false
  @spec validate_cached_content_name(String.t() | nil) :: :ok | {:error, map()}
  def validate_cached_content_name(nil), do: {:error, %{reason: :invalid_params, message: "Name is required"}}
  def validate_cached_content_name(""), do: {:error, %{reason: :invalid_params, message: "Name is required"}}
  def validate_cached_content_name(name) when is_binary(name) do
    if String.starts_with?(name, "cachedContents/") and String.length(name) > 15 do
      :ok
    else
      {:error, %{reason: :invalid_params, message: "Invalid cached content name format"}}
    end
  end

  @doc false
  @spec validate_page_size(term()) :: :ok | {:error, map()}
  def validate_page_size(size) when is_integer(size) and size > 0 and size <= 1000, do: :ok
  def validate_page_size(_), do: {:error, %{reason: :invalid_params, message: "Page size must be between 1 and 1000"}}

  @doc false
  @spec validate_create_request(map()) :: :ok | {:error, map()}
  def validate_create_request(request) do
    cond do
      not Map.has_key?(request, :model) ->
        {:error, %{reason: :invalid_params, message: "model is required"}}
        
      not Map.has_key?(request, :ttl) and not Map.has_key?(request, :expire_time) ->
        {:error, %{reason: :invalid_params, message: "Either TTL or expire_time is required"}}
        
      Map.has_key?(request, :ttl) and Map.has_key?(request, :expire_time) ->
        {:error, %{reason: :invalid_params, message: "Cannot specify both TTL and expire_time"}}
        
      true ->
        :ok
    end
  end

  @doc false
  @spec validate_update_request(map()) :: :ok | {:error, map()}
  def validate_update_request(request) do
    updatable_fields = [:ttl, :expire_time]
    request_fields = Map.keys(request) |> Enum.map(&to_atom/1)
    
    cond do
      Enum.empty?(request_fields) ->
        {:error, %{reason: :invalid_params, message: "No fields to update"}}
        
      Map.has_key?(request, :ttl) and Map.has_key?(request, :expire_time) ->
        {:error, %{reason: :invalid_params, message: "Cannot specify both TTL and expire_time"}}
        
      not Enum.all?(request_fields, &(&1 in updatable_fields)) ->
        {:error, %{reason: :invalid_params, message: "Only TTL and expire_time can be updated"}}
        
      true ->
        :ok
    end
  end
  
  defp to_atom(key) when is_atom(key), do: key
  defp to_atom(key) when is_binary(key), do: String.to_existing_atom(key)

  @doc false
  @spec parse_ttl(String.t() | nil) :: {:ok, float()} | {:error, :invalid_ttl}
  def parse_ttl(nil), do: {:error, :invalid_ttl}
  def parse_ttl(ttl) when is_binary(ttl) do
    case Regex.run(~r/^(\d+(?:\.\d+)?)s$/, ttl) do
      [_, number] -> 
        value = if String.contains?(number, ".") do
          String.to_float(number)
        else
          String.to_float(number <> ".0")
        end
        {:ok, value}
      nil -> {:error, :invalid_ttl}
    end
  end

  @doc false
  @spec build_create_request_body(map()) :: map()
  def build_create_request_body(request) do
    body = %{}
    
    # Required fields
    body = Map.put(body, "model", request.model)
    
    # Contents (convert to JSON format)
    body = if request[:contents] do
      contents_json = Enum.map(request.contents, &content_to_json/1)
      Map.put(body, "contents", contents_json)
    else
      body
    end
    
    # Expiration
    body = 
      cond do
        request[:ttl] -> Map.put(body, "ttl", request.ttl)
        request[:expire_time] -> Map.put(body, "expireTime", request.expire_time)
        true -> body
      end
    
    # Optional fields
    body = if request[:display_name], do: Map.put(body, "displayName", request.display_name), else: body
    body = if request[:system_instruction], do: Map.put(body, "systemInstruction", content_to_json(request.system_instruction)), else: body
    body = if request[:tools], do: Map.put(body, "tools", Enum.map(request.tools, &tool_to_json/1)), else: body
    body = if request[:tool_config], do: Map.put(body, "toolConfig", tool_config_to_json(request.tool_config)), else: body
    
    body
  end

  @doc false
  @spec build_update_request_body(map()) :: map()
  def build_update_request_body(request) do
    body = %{}
    
    body = 
      cond do
        request[:ttl] -> Map.put(body, "ttl", request.ttl)
        request[:expire_time] -> Map.put(body, "expireTime", request.expire_time)
        true -> body
      end
    
    body
  end

  @doc false
  @spec build_update_mask(map()) :: String.t()
  def build_update_mask(request) do
    cond do
      request[:ttl] -> "ttl"
      request[:expire_time] -> "expireTime"
      true -> ""
    end
  end

  @doc false
  @spec normalize_model_name(String.t()) :: String.t()
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

  defp validate_list_params(opts) do
    case Keyword.get(opts, :page_size) do
      nil -> :ok
      size -> validate_page_size(size)
    end
  end

  defp build_list_query_params(opts) do
    params = %{}
    
    params = 
      case Keyword.get(opts, :page_size) do
        nil -> params
        size -> Map.put(params, "pageSize", size)
      end
    
    case Keyword.get(opts, :page_token) do
      nil -> params
      token -> Map.put(params, "pageToken", token)
    end
  end

  defp build_url(path, api_key, query_params \\ %{}) do
    base = "https://generativelanguage.googleapis.com"
    query_params = Map.put(query_params, "key", api_key)
    query_string = URI.encode_query(query_params)
    "#{base}#{path}?#{query_string}"
  end

  defp build_headers do
    [
      {"Content-Type", "application/json"},
      {"User-Agent", "ExLLM/0.4.2 (Elixir)"}
    ]
  end

  # Content conversion helpers
  
  defp content_to_json(%Content{} = content) do
    %{
      "role" => content.role,
      "parts" => Enum.map(content.parts || [], &part_to_json/1)
    }
  end

  defp part_to_json(%Part{} = part) do
    json = %{}
    json = if part.text, do: Map.put(json, "text", part.text), else: json
    json = if part.inline_data, do: Map.put(json, "inlineData", part.inline_data), else: json
    json = if part.function_call, do: Map.put(json, "functionCall", part.function_call), else: json
    json = if part.function_response, do: Map.put(json, "functionResponse", part.function_response), else: json
    json = if part.code_execution_result, do: Map.put(json, "codeExecutionResult", part.code_execution_result), else: json
    json
  end

  defp tool_to_json(%Tool{} = tool) do
    json = %{}
    json = if tool.function_declarations, do: Map.put(json, "functionDeclarations", tool.function_declarations), else: json
    json = if tool.google_search, do: Map.put(json, "googleSearch", tool.google_search), else: json
    json = if tool.code_execution, do: Map.put(json, "codeExecution", tool.code_execution), else: json
    json
  end
  defp tool_to_json(tool) when is_map(tool), do: tool

  defp tool_config_to_json(%ToolConfig{} = config) do
    json = %{}
    if config.function_calling_config do
      Map.put(json, "functionCallingConfig", config.function_calling_config)
    else
      json
    end
  end
  defp tool_config_to_json(config) when is_map(config), do: config
  defp tool_config_to_json(nil), do: %{}
end