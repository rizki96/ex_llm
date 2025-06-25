defmodule ExLLM.Providers.Gemini.Content do
  @moduledoc """
  Google Gemini Content Generation API implementation.

  Provides functionality for generating content using Gemini models including
  text generation, streaming, multimodal inputs, function calling, and structured outputs.
  """

  alias ExLLM.Providers.Shared.{ConfigHelper, HTTPClient}

  defmodule Part do
    @moduledoc """
    Represents a content part which can be text, inline data, or function call/response.
    """

    @type t :: %__MODULE__{
            text: String.t() | nil,
            inline_data: map() | nil,
            function_call: map() | nil,
            function_response: map() | nil,
            code_execution_result: map() | nil
          }

    defstruct [:text, :inline_data, :function_call, :function_response, :code_execution_result]

    @doc """
    Converts Part struct to JSON format for API requests.
    """
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = part) do
      json = %{}

      json = if part.text, do: Map.put(json, "text", part.text), else: json
      json = if part.inline_data, do: Map.put(json, "inlineData", part.inline_data), else: json

      json =
        if part.function_call, do: Map.put(json, "functionCall", part.function_call), else: json

      json =
        if part.function_response,
          do: Map.put(json, "functionResponse", part.function_response),
          else: json

      if part.code_execution_result do
        Map.put(json, "codeExecutionResult", part.code_execution_result)
      else
        json
      end
    end
  end

  defmodule Content do
    @moduledoc """
    Represents content with a role and parts.
    """

    @type t :: %__MODULE__{
            role: String.t(),
            parts: [Part.t()]
          }

    @enforce_keys [:role, :parts]
    defstruct [:role, :parts]
  end

  defmodule GenerationConfig do
    @moduledoc """
    Configuration for content generation.
    """

    @type t :: %__MODULE__{
            temperature: float() | nil,
            top_p: float() | nil,
            top_k: integer() | nil,
            candidate_count: integer() | nil,
            max_output_tokens: integer() | nil,
            stop_sequences: [String.t()] | nil,
            response_mime_type: String.t() | nil,
            response_schema: map() | nil,
            thinking_config: map() | nil
          }

    defstruct [
      :temperature,
      :top_p,
      :top_k,
      :candidate_count,
      :max_output_tokens,
      :stop_sequences,
      :response_mime_type,
      :response_schema,
      :thinking_config
    ]
  end

  defmodule SafetySetting do
    @moduledoc """
    Safety settings for content generation.
    """

    @type t :: %__MODULE__{
            category: String.t(),
            threshold: String.t()
          }

    @enforce_keys [:category, :threshold]
    defstruct [:category, :threshold]
  end

  defmodule Tool do
    @moduledoc """
    Tool definitions for function calling.
    """

    @type t :: %__MODULE__{
            function_declarations: [map()] | nil,
            google_search: map() | nil,
            code_execution: map() | nil
          }

    defstruct [:function_declarations, :google_search, :code_execution]
  end

  defmodule ToolConfig do
    @moduledoc """
    Configuration for tool usage.
    """

    @type t :: %__MODULE__{
            function_calling_config: map() | nil
          }

    defstruct [:function_calling_config]
  end

  defmodule GenerateContentRequest do
    @moduledoc """
    Request structure for content generation.
    """

    @type t :: %__MODULE__{
            model: String.t() | nil,
            contents: [Content.t()],
            system_instruction: Content.t() | nil,
            generation_config: GenerationConfig.t() | nil,
            safety_settings: [SafetySetting.t()] | nil,
            tools: [Tool.t()] | nil,
            tool_config: ToolConfig.t() | nil,
            cached_content: String.t() | nil
          }

    @enforce_keys [:contents]
    defstruct [
      :model,
      :contents,
      :system_instruction,
      :generation_config,
      :safety_settings,
      :tools,
      :tool_config,
      :cached_content
    ]

    @doc """
    Converts GenerateContentRequest struct to JSON format for API requests.
    """
    @spec to_json(t()) :: map()
    def to_json(%__MODULE__{} = request) do
      json = %{
        "contents" =>
          Enum.map(request.contents, &ExLLM.Providers.Gemini.Content.content_to_json/1)
      }

      json = if request.model, do: Map.put(json, "model", request.model), else: json

      json =
        if request.system_instruction,
          do:
            Map.put(
              json,
              "systemInstruction",
              ExLLM.Providers.Gemini.Content.content_to_json(request.system_instruction)
            ),
          else: json

      json =
        if request.generation_config,
          do:
            Map.put(
              json,
              "generationConfig",
              generation_config_to_json(request.generation_config)
            ),
          else: json

      json =
        if request.safety_settings,
          do:
            Map.put(
              json,
              "safetySettings",
              Enum.map(request.safety_settings, &safety_setting_to_json/1)
            ),
          else: json

      json =
        if request.tools,
          do: Map.put(json, "tools", Enum.map(request.tools, &tool_to_json/1)),
          else: json

      json =
        if request.tool_config,
          do: Map.put(json, "toolConfig", tool_config_to_json(request.tool_config)),
          else: json

      if request.cached_content do
        Map.put(json, "cachedContent", request.cached_content)
      else
        json
      end
    end

    defp generation_config_to_json(nil), do: nil

    defp generation_config_to_json(config) when is_struct(config, GenerationConfig) do
      json = %{}

      json =
        if config.temperature, do: Map.put(json, "temperature", config.temperature), else: json

      json = if config.top_p, do: Map.put(json, "topP", config.top_p), else: json
      json = if config.top_k, do: Map.put(json, "topK", config.top_k), else: json

      json =
        if config.candidate_count,
          do: Map.put(json, "candidateCount", config.candidate_count),
          else: json

      json =
        if config.max_output_tokens,
          do: Map.put(json, "maxOutputTokens", config.max_output_tokens),
          else: json

      json =
        if config.stop_sequences,
          do: Map.put(json, "stopSequences", config.stop_sequences),
          else: json

      json =
        if config.response_mime_type,
          do: Map.put(json, "responseMimeType", config.response_mime_type),
          else: json

      json =
        if config.response_schema,
          do: Map.put(json, "responseSchema", config.response_schema),
          else: json

      if config.thinking_config do
        Map.put(json, "thinkingConfig", config.thinking_config)
      else
        json
      end
    end

    defp generation_config_to_json(config) when is_map(config) do
      # Handle plain maps (for tests)
      json = %{}

      json =
        if Map.has_key?(config, :temperature),
          do: Map.put(json, "temperature", config.temperature),
          else: json

      json = if Map.has_key?(config, :top_p), do: Map.put(json, "topP", config.top_p), else: json
      json = if Map.has_key?(config, :top_k), do: Map.put(json, "topK", config.top_k), else: json

      json =
        if Map.has_key?(config, :candidate_count),
          do: Map.put(json, "candidateCount", config.candidate_count),
          else: json

      json =
        if Map.has_key?(config, :max_output_tokens),
          do: Map.put(json, "maxOutputTokens", config.max_output_tokens),
          else: json

      json =
        if Map.has_key?(config, :stop_sequences),
          do: Map.put(json, "stopSequences", config.stop_sequences),
          else: json

      json =
        if Map.has_key?(config, :response_mime_type),
          do: Map.put(json, "responseMimeType", config.response_mime_type),
          else: json

      json =
        if Map.has_key?(config, :response_schema),
          do: Map.put(json, "responseSchema", config.response_schema),
          else: json

      if Map.has_key?(config, :thinking_config) do
        Map.put(json, "thinkingConfig", config.thinking_config)
      else
        json
      end
    end

    defp safety_setting_to_json(nil), do: nil

    defp safety_setting_to_json(setting) do
      %{
        "category" => setting.category,
        "threshold" => setting.threshold
      }
    end

    defp tool_to_json(nil), do: nil

    defp tool_to_json(tool) do
      json = %{}

      json =
        if tool.function_declarations,
          do: Map.put(json, "functionDeclarations", tool.function_declarations),
          else: json

      json =
        if tool.google_search, do: Map.put(json, "googleSearch", tool.google_search), else: json

      if tool.code_execution do
        Map.put(json, "codeExecution", tool.code_execution)
      else
        json
      end
    end

    defp tool_config_to_json(nil), do: nil

    defp tool_config_to_json(config) do
      if config.function_calling_config do
        %{"functionCallingConfig" => config.function_calling_config}
      else
        %{}
      end
    end
  end

  defmodule UsageMetadata do
    @moduledoc """
    Token usage information.
    """

    @type t :: %__MODULE__{
            prompt_token_count: integer(),
            candidates_token_count: integer(),
            total_token_count: integer(),
            cached_content_token_count: integer() | nil,
            thoughts_token_count: integer() | nil
          }

    defstruct [
      :prompt_token_count,
      :candidates_token_count,
      :total_token_count,
      :cached_content_token_count,
      :thoughts_token_count
    ]
  end

  defmodule Candidate do
    @moduledoc """
    A generated candidate response.
    """

    @type t :: %__MODULE__{
            content: Content.t(),
            finish_reason: String.t() | nil,
            safety_ratings: [map()] | nil,
            citation_metadata: map() | nil,
            token_count: integer() | nil,
            grounding_metadata: map() | nil,
            index: integer() | nil
          }

    defstruct [
      :content,
      :finish_reason,
      :safety_ratings,
      :citation_metadata,
      :token_count,
      :grounding_metadata,
      :index
    ]
  end

  defmodule GenerateContentResponse do
    @moduledoc """
    Response from content generation.
    """

    @type t :: %__MODULE__{
            candidates: [Candidate.t()],
            prompt_feedback: map() | nil,
            usage_metadata: UsageMetadata.t() | nil
          }

    defstruct [:candidates, :prompt_feedback, :usage_metadata]
  end

  @type options :: [
          {:config_provider, pid() | atom()}
        ]

  @doc """
  Generates content using a Gemini model.

  ## Parameters
    * `model` - The model name (e.g., "gemini-2.0-flash")
    * `request` - A GenerateContentRequest struct
    * `opts` - Options including `:config_provider`

  ## Examples
      
      request = %GenerateContentRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Hello!"}]
          }
        ]
      }
      
      {:ok, response} = ExLLM.Providers.Gemini.Content.generate_content("gemini-2.0-flash", request)
  """
  @spec generate_content(String.t(), GenerateContentRequest.t(), options()) ::
          {:ok, GenerateContentResponse.t()} | {:error, term()}
  def generate_content(model, request, opts \\ []) do
    with :ok <- validate_request(request),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key),
         {:ok, normalized_model} <- normalize_model_name(model) do
      # Build request body
      body = build_request_body(request)

      # Make API request
      url = build_url(normalized_model, "generateContent", api_key)
      headers = build_headers()

      case HTTPClient.post_json(url, body, headers, provider: :gemini) do
        {:ok, response_body} ->
          # Check if the response contains an error
          parsed = parse_response(response_body)

          # Check for safety blocking
          if parsed.prompt_feedback && parsed.prompt_feedback["blockReason"] do
            {:ok, parsed}
          else
            {:ok, parsed}
          end

        {:error, reason} ->
          {:error, %{reason: :network_error, message: inspect(reason)}}
      end
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Streams content generation using a Gemini model.

  Returns a stream of GenerateContentResponse chunks.
  """
  @spec stream_generate_content(String.t(), GenerateContentRequest.t(), options()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_generate_content(model, request, opts \\ []) do
    with :ok <- validate_request(request),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key),
         {:ok, normalized_model} <- normalize_model_name(model) do
      # Build request body
      body = build_request_body(request)

      # Use HTTPClient directly for streaming
      chunks_ref = make_ref()
      parent = self()

      # Create a callback that accumulates chunks
      callback = fn chunk_data ->
        # Parse chunk immediately
        case parse_streaming_chunk(chunk_data) do
          # Skip empty chunks
          nil -> :ok
          chunk -> send(parent, {chunks_ref, {:chunk, chunk}})
        end
      end

      # Build URL with SSE support
      url = build_url(normalized_model, "streamGenerateContent", api_key) <> "&alt=sse"

      headers =
        HTTPClient.build_provider_headers(:gemini, api_key: api_key) ++
          [{"Accept", "text/event-stream"}]

      # Start async streaming request
      Task.start(fn ->
        result =
          HTTPClient.stream_request(url, body, headers, callback,
            provider: :gemini,
            timeout: 60_000
          )

        # Forward the completion or error message to the stream
        case result do
          {:ok, _stream_result} ->
            # Wait for the stream to complete
            receive do
              :stream_done ->
                send(parent, {chunks_ref, :done})

              {:stream_error, error} ->
                send(parent, {chunks_ref, {:error, error}})
            after
              70_000 ->
                send(parent, {chunks_ref, {:error, "Stream timeout"}})
            end

            # Note: HTTPClient.stream_request currently always returns {:ok, :streaming} on success
            # but keeping this clause for completeness in case of future changes
            # {:error, error} ->
            #   send(parent, {chunks_ref, {:error, error}})
        end
      end)

      # Create stream that receives parsed chunks
      stream =
        Stream.resource(
          fn -> chunks_ref end,
          fn ref ->
            receive do
              {^ref, {:chunk, chunk}} ->
                {[chunk], ref}

              {^ref, :done} ->
                {:halt, ref}

              {^ref, {:error, error}} ->
                throw(error)

              _other ->
                # Skip unexpected messages
                {[], ref}
            after
              100 -> {[], ref}
            end
          end,
          fn _ -> :ok end
        )

      {:ok, stream}
    else
      {:error, _} = error -> error
    end
  end

  # Module-level functions

  @doc """
  Converts Content struct to JSON format for API requests.
  """
  @spec content_to_json(Content.t()) :: map()
  def content_to_json(%Content{} = content) do
    %{
      "role" => content.role,
      "parts" => Enum.map(content.parts, &Part.to_json/1)
    }
  end

  # Private functions

  defp get_config_provider(opts) do
    Keyword.get(
      opts,
      :config_provider,
      Application.get_env(:ex_llm, :config_provider, ExLLM.Infrastructure.ConfigProvider.Default)
    )
  end

  defp validate_request(%GenerateContentRequest{contents: []}),
    do: {:error, %{reason: :invalid_request, message: "Contents cannot be empty"}}

  defp validate_request(%GenerateContentRequest{contents: contents}) do
    # Validate roles
    valid_roles = ["user", "model", "system"]

    invalid_role =
      Enum.find(contents, fn content ->
        content.role not in valid_roles
      end)

    if invalid_role do
      {:error, %{reason: :invalid_request, message: "Invalid role: #{invalid_role.role}"}}
    else
      :ok
    end
  end

  defp validate_api_key(nil),
    do: {:error, %{reason: :missing_api_key, message: "API key is required"}}

  defp validate_api_key(""),
    do: {:error, %{reason: :missing_api_key, message: "API key is required"}}

  defp validate_api_key(_), do: {:ok, :valid}

  defp normalize_model_name(nil),
    do: {:error, %{reason: :invalid_params, message: "Model name is required"}}

  defp normalize_model_name(""),
    do: {:error, %{reason: :invalid_params, message: "Model name is required"}}

  defp normalize_model_name("models/" <> _rest = name), do: {:ok, name}
  defp normalize_model_name("gemini/" <> rest), do: {:ok, "models/#{rest}"}
  defp normalize_model_name(name) when is_binary(name), do: {:ok, "models/#{name}"}

  defp get_api_key(config) do
    config[:api_key] || System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY")
  end

  defp build_url(model_name, method, api_key) do
    base = "https://generativelanguage.googleapis.com"
    "#{base}/v1beta/#{model_name}:#{method}?key=#{api_key}"
  end

  defp build_headers do
    [
      {"Content-Type", "application/json"},
      {"User-Agent", "ExLLM/0.4.2 (Elixir)"}
    ]
  end

  defp build_request_body(request) do
    body = %{
      "contents" => Enum.map(request.contents, &serialize_content/1)
    }

    body =
      if request.system_instruction do
        Map.put(body, "systemInstruction", serialize_content(request.system_instruction))
      else
        body
      end

    body =
      if request.generation_config do
        Map.put(body, "generationConfig", serialize_generation_config(request.generation_config))
      else
        body
      end

    body =
      if request.safety_settings do
        Map.put(
          body,
          "safetySettings",
          Enum.map(request.safety_settings, &serialize_safety_setting/1)
        )
      else
        body
      end

    body =
      if request.tools do
        Map.put(body, "tools", Enum.map(request.tools, &serialize_tool/1))
      else
        body
      end

    body =
      if request.tool_config do
        Map.put(body, "toolConfig", serialize_tool_config(request.tool_config))
      else
        body
      end

    body =
      if request.cached_content do
        Map.put(body, "cachedContent", request.cached_content)
      else
        body
      end

    # Remove empty objects and nil values to match the working pipeline behavior
    compact(body)
  end

  defp serialize_content(content) do
    %{
      "role" => content.role,
      "parts" => Enum.map(content.parts, &serialize_part/1)
    }
  end

  defp serialize_part(part) do
    cond do
      part.text -> %{"text" => part.text}
      part.inline_data -> %{"inlineData" => part.inline_data}
      part.function_call -> %{"functionCall" => part.function_call}
      part.function_response -> %{"functionResponse" => part.function_response}
      part.code_execution_result -> %{"codeExecutionResult" => part.code_execution_result}
      true -> %{}
    end
  end

  defp serialize_generation_config(config) do
    config_map = %{}

    config_map =
      if config.temperature,
        do: Map.put(config_map, "temperature", config.temperature),
        else: config_map

    config_map = if config.top_p, do: Map.put(config_map, "topP", config.top_p), else: config_map
    config_map = if config.top_k, do: Map.put(config_map, "topK", config.top_k), else: config_map

    config_map =
      if config.candidate_count,
        do: Map.put(config_map, "candidateCount", config.candidate_count),
        else: config_map

    config_map =
      if config.max_output_tokens,
        do: Map.put(config_map, "maxOutputTokens", config.max_output_tokens),
        else: config_map

    config_map =
      if config.stop_sequences,
        do: Map.put(config_map, "stopSequences", config.stop_sequences),
        else: config_map

    config_map =
      if config.response_mime_type,
        do: Map.put(config_map, "responseMimeType", config.response_mime_type),
        else: config_map

    config_map =
      if config.response_schema,
        do: Map.put(config_map, "responseSchema", config.response_schema),
        else: config_map

    config_map =
      if config.thinking_config,
        do: Map.put(config_map, "thinkingConfig", config.thinking_config),
        else: config_map

    config_map
  end

  defp serialize_safety_setting(setting) do
    %{
      "category" => setting.category,
      "threshold" => setting.threshold
    }
  end

  defp serialize_tool(tool) do
    tool_map = %{}

    tool_map =
      if tool.function_declarations,
        do: Map.put(tool_map, "functionDeclarations", tool.function_declarations),
        else: tool_map

    tool_map =
      if tool.google_search,
        do: Map.put(tool_map, "googleSearch", tool.google_search),
        else: tool_map

    tool_map =
      if tool.code_execution,
        do: Map.put(tool_map, "codeExecution", tool.code_execution),
        else: tool_map

    tool_map
  end

  defp serialize_tool_config(config) do
    config_map = %{}

    if config.function_calling_config do
      Map.put(config_map, "functionCallingConfig", config.function_calling_config)
    else
      config_map
    end
  end

  defp parse_response(body) do
    %GenerateContentResponse{
      candidates: parse_candidates(body["candidates"] || []),
      prompt_feedback: body["promptFeedback"],
      usage_metadata: parse_usage_metadata(body["usageMetadata"])
    }
  end

  defp parse_candidates(candidates) do
    Enum.map(candidates, &parse_candidate/1)
  end

  defp parse_candidate(data) do
    %Candidate{
      content: parse_content(data["content"]),
      finish_reason: data["finishReason"],
      safety_ratings: data["safetyRatings"],
      citation_metadata: data["citationMetadata"],
      token_count: data["tokenCount"],
      grounding_metadata: data["groundingMetadata"],
      index: data["index"]
    }
  end

  defp parse_content(nil), do: %Content{role: "model", parts: []}

  defp parse_content(data) do
    %Content{
      role: data["role"] || "model",
      parts: parse_parts(data["parts"] || [])
    }
  end

  defp parse_parts(parts) do
    Enum.map(parts, &parse_part/1)
  end

  defp parse_part(data) do
    %Part{
      text: data["text"],
      inline_data: data["inlineData"],
      function_call: data["functionCall"],
      function_response: data["functionResponse"],
      code_execution_result: data["codeExecutionResult"]
    }
  end

  defp parse_usage_metadata(nil), do: nil

  defp parse_usage_metadata(data) do
    %UsageMetadata{
      prompt_token_count: data["promptTokenCount"] || 0,
      candidates_token_count: data["candidatesTokenCount"] || 0,
      total_token_count: data["totalTokenCount"] || 0,
      cached_content_token_count: data["cachedContentTokenCount"],
      thoughts_token_count: data["thoughtsTokenCount"]
    }
  end

  defp parse_streaming_chunk(json_data) do
    case Jason.decode(json_data) do
      {:ok, data} ->
        parse_response(data)

      {:error, _} ->
        nil
    end
  end

  # Remove nil values and empty maps from the request body
  defp compact(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == %{} end)
    |> Map.new()
  end
end
