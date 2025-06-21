defmodule ExLLM do
  @moduledoc """
  ExLLM - A unified Elixir client for Large Language Models.

  ExLLM provides a clean, pipeline-based architecture for interacting with various
  LLM providers. The library focuses on two main APIs:

  ## Simple API

  For basic chat completions:

      {:ok, response} = ExLLM.chat(:openai, [
        %{role: "user", content: "Hello!"}
      ])
      
      IO.puts(response.content)
      
  ## Advanced API

  For full control over the pipeline:

      import ExLLM.Pipeline.Request
      
      request = 
        new(:openai, messages)
        |> assign(:temperature, 0.7)
        |> assign(:max_tokens, 1000)
      
      result = ExLLM.run(request, custom_pipeline)
      
  ## Providers

  ExLLM supports 14+ providers including:
  - OpenAI (GPT-4, GPT-3.5)
  - Anthropic (Claude)
  - Google (Gemini)
  - Groq
  - Mistral
  - And many more...

  ## Configuration

  Configure providers in your `config.exs`:

      config :ex_llm, :openai,
        api_key: System.get_env("OPENAI_API_KEY"),
        default_model: "gpt-4"
  """

  alias ExLLM.API.Delegator
  alias ExLLM.Infrastructure.Logger
  alias ExLLM.Pipeline
  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers

  @doc """
  Sends a chat request to the specified provider.

  This is the simple API for basic use cases. For more control and pipeline
  customization, use the builder API with `build/2` or the advanced `run/2`.

  ## Parameters

    * `provider` - The LLM provider atom (e.g., `:openai`, `:anthropic`)
    * `messages` - List of message maps with `:role` and `:content`
    * `opts` - Optional keyword list of options
    
  ## Options

    * `:model` - Override the default model
    * `:temperature` - Control randomness (0.0 to 2.0)
    * `:max_tokens` - Maximum tokens in response
    * `:stream` - Enable streaming (requires callback function)
    * `:timeout` - Request timeout in milliseconds
    
  ## Examples

      # Simple chat
      {:ok, response} = ExLLM.chat(:openai, [
        %{role: "user", content: "Hello!"}
      ])
      
      # With options
      {:ok, response} = ExLLM.chat(:anthropic, messages,
        model: "claude-3-opus",
        temperature: 0.5,
        max_tokens: 1000
      )
      
  ## Builder API Alternative

  For pipeline customization, prefer the builder API:
      
      {:ok, response} = 
        ExLLM.build(:openai, messages)
        |> ExLLM.with_model("gpt-4")
        |> ExLLM.with_cache(ttl: 3600)
        |> ExLLM.execute()
      
  ## Return Values

  Returns `{:ok, response}` on success where response includes:
    * `:content` - The response text
    * `:role` - The role (usually "assistant")
    * `:model` - The model used
    * `:usage` - Token usage information
    * `:cost` - Calculated cost in USD
    
  Returns `{:error, error}` on failure.
  """
  @spec chat(atom(), list(map()), keyword()) :: {:ok, map()} | {:error, term()}
  def chat(provider, messages, opts \\ []) do
    # Build request
    request = Request.new(provider, messages, Enum.into(opts, %{}))

    # Get default pipeline for provider
    pipeline = Providers.get_pipeline(provider, :chat)

    # Run pipeline
    case Pipeline.run(request, pipeline) do
      %Request{state: :completed, result: result, assigns: assigns} ->
        # Check if we should cache the successful result
        if Map.get(assigns, :should_cache, false) do
          cache_key = Map.get(assigns, :cache_key)
          cache_ttl = Map.get(assigns, :cache_ttl, 300)

          if cache_key do
            ExLLM.Infrastructure.Cache.put(cache_key, result, ttl: cache_ttl)
          end
        end

        {:ok, result}

      %Request{state: :error, errors: errors} ->
        {:error, format_errors(errors)}

      %Request{} = failed ->
        {:error, {:pipeline_failed, failed}}
    end
  end

  @doc """
  Sends a streaming chat request to the specified provider.

  Similar to `chat/3` but streams the response in chunks.

  ## Parameters

    * `provider` - The LLM provider atom
    * `messages` - List of message maps
    * `callback` - Function called for each chunk
    * `opts` - Optional keyword list of options
    
  ## Callback Function

  The callback receives chunks with the following structure:
    * `:content` - The text content of this chunk
    * `:done` - Boolean indicating if streaming is complete
    * `:usage` - Token usage (only in final chunk)
    
  ## Examples

      ExLLM.stream(:openai, messages, fn
        %{done: true, usage: usage} ->
          IO.puts("\\nTotal tokens: \#{usage.total_tokens}")
          
        %{content: content} ->
          IO.write(content)
      end)
  """
  @spec stream(atom(), list(map()), function(), keyword()) :: :ok | {:error, term()}
  def stream(provider, messages, callback, opts \\ []) when is_function(callback, 1) do
    # Add streaming options
    opts = Keyword.merge(opts, stream: true, stream_callback: callback)

    # Build request
    request = Request.new(provider, messages, Enum.into(opts, %{}))

    # Get streaming pipeline for provider
    pipeline = Providers.get_pipeline(provider, :stream)

    # Run pipeline
    case Pipeline.run(request, pipeline) do
      %Request{state: :completed} ->
        :ok

      %Request{state: :streaming} ->
        # For streaming, the pipeline starts the stream and returns immediately
        # The actual streaming happens asynchronously via callbacks
        :ok

      %Request{state: :error, errors: errors} ->
        {:error, format_errors(errors)}

      %Request{} = failed ->
        {:error, {:pipeline_failed, failed}}
    end
  end

  @doc """
  Runs a custom pipeline on a request.

  This is the advanced API that gives you full control over the
  request processing pipeline.

  ## Parameters

    * `request` - An `ExLLM.Pipeline.Request` struct
    * `pipeline` - List of plug modules or `{module, opts}` tuples
    
  ## Examples

      # Build custom request
      request = ExLLM.Pipeline.Request.new(:openai, messages)
      
      # Define custom pipeline
      pipeline = [
        ExLLM.Plugs.ValidateProvider,
        ExLLM.Plugs.FetchConfig,
        {ExLLM.Plugs.Cache, ttl: 3600},
        MyApp.Plugs.CustomAuth,
        ExLLM.Plugs.ExecuteRequest,
        ExLLM.Plugs.TrackCost
      ]
      
      # Run it
      result = ExLLM.run(request, pipeline)
  """
  @spec run(Request.t(), Pipeline.pipeline()) :: Request.t()
  def run(%Request{} = request, pipeline) when is_list(pipeline) do
    Pipeline.run(request, pipeline)
  end

  ## Chat Builder API Functions

  @doc "Create a new chat builder for enhanced fluent API. See ExLLM.Builder.build/2 for details."
  defdelegate build(provider, messages), to: ExLLM.Builder

  @doc "Set the model for a chat builder. See ExLLM.Builder.with_model/2 for details."
  defdelegate with_model(builder, model), to: ExLLM.Builder

  @doc "Sets the temperature for a chat builder. See ExLLM.Builder.with_temperature/2 for details."
  defdelegate with_temperature(builder, temperature), to: ExLLM.Builder

  @doc "Sets the maximum tokens for a chat builder. See ExLLM.Builder.with_max_tokens/2 for details."
  defdelegate with_max_tokens(builder, max_tokens), to: ExLLM.Builder

  @doc "Adds a custom plug to the pipeline. See ExLLM.Builder.with_plug/3 for details."
  defdelegate with_plug(builder, plug, opts \\ []), to: ExLLM.Builder

  @doc "Executes a chat builder request. See ExLLM.Builder.execute/1 for details."
  defdelegate execute(builder), to: ExLLM.Builder

  @doc "Streams a chat builder request. See ExLLM.Builder.stream/2 for details."
  defdelegate stream(builder, callback), to: ExLLM.Builder

  ## Enhanced Builder API Methods

  @doc "Enables caching with configurable options on a chat builder. See ExLLM.Builder.with_cache/2 for details."
  defdelegate with_cache(builder, opts \\ []), to: ExLLM.Builder

  @doc "Disables caching for a chat builder request. See ExLLM.Builder.without_cache/1 for details."
  defdelegate without_cache(builder), to: ExLLM.Builder

  @doc "Disables cost tracking for a chat builder request. See ExLLM.Builder.without_cost_tracking/1 for details."
  defdelegate without_cost_tracking(builder), to: ExLLM.Builder

  @doc "Adds a custom plug to the chat builder pipeline. See ExLLM.Builder.with_custom_plug/3 for details."
  defdelegate with_custom_plug(builder, plug, opts \\ []), to: ExLLM.Builder

  @doc "Sets a custom context management strategy for a chat builder. See ExLLM.Builder.with_context_strategy/3 for details."
  defdelegate with_context_strategy(builder, strategy, opts \\ []), to: ExLLM.Builder

  @doc "Returns the pipeline that would be executed without running it. See ExLLM.Builder.inspect_pipeline/1 for details."
  defdelegate inspect_pipeline(builder), to: ExLLM.Builder

  @doc "Returns detailed debugging information about the chat builder state. See ExLLM.Builder.debug_info/1 for details."
  defdelegate debug_info(builder), to: ExLLM.Builder

  # Private helpers

  defp format_errors([]), do: :unknown_error
  defp format_errors([error]), do: format_error(error)

  defp format_errors(errors) do
    %{
      errors: Enum.map(errors, &format_error/1),
      count: length(errors)
    }
  end

  defp format_error(%{message: message}), do: message
  defp format_error(%{error: error}), do: error
  defp format_error(error), do: error

  ## Legacy API Support

  @doc false
  @deprecated "Use ExLLM.stream/4 instead"
  def stream_chat(provider, messages, opts \\ []) do
    Logger.warning("ExLLM.stream_chat/3 is deprecated. Use ExLLM.stream/4 instead.")

    # Create a dummy callback for the legacy API
    callback = fn chunk ->
      send(self(), {:stream_chunk, chunk})
      chunk
    end

    # Convert opts to keyword list if it's a map
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    case stream(provider, messages, callback, opts) do
      :ok ->
        # Collect the stream chunks for legacy API compatibility
        stream = create_legacy_stream()
        {:ok, stream}

      error ->
        error
    end
  end

  defp create_legacy_stream do
    Stream.unfold(:collecting, fn
      :collecting ->
        receive do
          {:stream_chunk, chunk} -> {chunk, :collecting}
        after
          100 -> nil
        end

      :done ->
        nil
    end)
  end

  @doc """
  Returns the default model for a provider.

  This is a convenience function that returns sensible defaults.
  Users should prefer specifying models explicitly.
  """
  def default_model(provider) do
    case provider do
      :openai -> "gpt-4"
      :anthropic -> "claude-3-5-sonnet-20241022"
      :gemini -> "gemini-2.0-flash-exp"
      :groq -> "llama-3.3-70b-instruct"
      :mistral -> "mistral-large-latest"
      :ollama -> "llama3.2"
      :bumblebee -> "HuggingFaceTB/SmolLM2-1.7B-Instruct"
      _ -> "unknown"
    end
  end

  @doc """
  Generate embeddings for text input(s) using the pipeline architecture.

  This function now uses the pipeline system, providing automatic caching,
  cost tracking, circuit breakers, and other middleware benefits.

  ## Parameters

    * `provider` - The LLM provider atom (e.g., `:openai`, `:gemini`)
    * `input` - Text string or list of strings to embed
    * `opts` - Optional keyword list of options

  ## Options

    * `:model` - Override the default embedding model
    * `:dimensions` - Specify output dimensions (for supported models)
    * `:user` - User identifier for tracking (OpenAI)
    * `:encoding_format` - Encoding format (OpenAI)
    * `:cache` - Enable/disable caching (default: true)
    * `:cache_ttl` - Cache TTL in seconds

  ## Examples

      # Single text embedding
      {:ok, response} = ExLLM.embeddings(:openai, "Hello world")
      
      # Multiple texts
      {:ok, response} = ExLLM.embeddings(:openai, ["Hello", "World"])
      
      # With options
      {:ok, response} = ExLLM.embeddings(:openai, "Hello", 
        model: "text-embedding-3-large",
        dimensions: 512
      )

  ## Return Values

  Returns `{:ok, response}` on success where response includes:
    * `:embeddings` - List of embedding vectors
    * `:model` - The model used
    * `:usage` - Token usage information
    * `:cost` - Calculated cost in USD (if applicable)
    * `:metadata` - Provider-specific metadata

  Returns `{:error, error}` on failure.
  """
  @spec embeddings(atom(), String.t() | [String.t()], keyword()) ::
          {:ok, ExLLM.Types.EmbeddingResponse.t()} | {:error, term()}
  def embeddings(provider, input, opts \\ []) do
    # Convert options to map for internal use
    options = Enum.into(opts, %{})

    # Build request - use empty messages since embeddings don't use conversation format
    request = ExLLM.Pipeline.Request.new(provider, [], options)

    # Store embedding input in assigns for pipeline plugs to access
    request = ExLLM.Pipeline.Request.assign(request, :embedding_input, input)

    # Get embeddings pipeline for provider
    pipeline = ExLLM.Providers.get_pipeline(provider, :embeddings)

    # Run pipeline
    case ExLLM.Pipeline.run(request, pipeline) do
      %ExLLM.Pipeline.Request{state: :completed, result: result} ->
        {:ok, result}

      %ExLLM.Pipeline.Request{state: :error, errors: errors} ->
        {:error, format_errors(errors)}

      %ExLLM.Pipeline.Request{} = failed ->
        {:error, {:pipeline_failed, failed}}
    end
  end

  @doc """
  Lists available models for a provider using the pipeline architecture.

  This function now uses the pipeline system, providing automatic caching,
  error handling, and middleware benefits.

  ## Parameters

    * `provider` - The LLM provider atom

  ## Examples

      {:ok, models} = ExLLM.list_models(:openai)
      # Returns list of model structs with id, context_window, etc.
      
      {:ok, models} = ExLLM.list_models(:anthropic)
      # => [
      #   %{id: "claude-3-5-sonnet-20241022", context_window: 200000, ...},
      #   %{id: "claude-3-5-haiku-20241022", context_window: 200000, ...}
      # ]

  ## Return Values

  Returns `{:ok, models}` on success where models is a list of model information maps.
  Returns `{:error, error}` on failure.
  """
  @spec list_models(atom()) :: {:ok, list(map())} | {:error, term()}
  def list_models(provider) do
    # Build request - use empty messages for list_models
    request = ExLLM.Pipeline.Request.new(provider, [], %{})

    # Get list_models pipeline for provider
    pipeline = ExLLM.Providers.get_pipeline(provider, :list_models)

    # Run pipeline
    case ExLLM.Pipeline.run(request, pipeline) do
      %ExLLM.Pipeline.Request{state: :completed, result: result} ->
        {:ok, result}

      %ExLLM.Pipeline.Request{state: :error, errors: errors} ->
        {:error, format_errors(errors)}

      %ExLLM.Pipeline.Request{} = failed ->
        {:error, {:pipeline_failed, failed}}
    end
  end

  ## Session Management Functions

  @doc "Creates a new session for conversation management. See ExLLM.Session.new_session/2 for details."
  defdelegate new_session(provider, opts \\ []), to: ExLLM.Session

  @doc "Adds a message to a session. See ExLLM.Session.add_message/3 for details."
  defdelegate add_message(session, role, content), to: ExLLM.Session

  @doc "Gets all messages from a session. See ExLLM.Session.get_messages/1 for details."
  defdelegate get_messages(session), to: ExLLM.Session

  @doc "Gets session messages with limit. See ExLLM.Session.get_session_messages/2 for details."
  defdelegate get_session_messages(session, limit \\ nil), to: ExLLM.Session

  @doc "Adds a message to a session (alias for add_message). See ExLLM.Session.add_session_message/3 for details."
  defdelegate add_session_message(session, role, content), to: ExLLM.Session

  @doc "Gets total token usage for a session. See ExLLM.Session.session_token_usage/1 for details."
  defdelegate session_token_usage(session), to: ExLLM.Session

  @doc "Clears all messages from a session. See ExLLM.Session.clear_session/1 for details."
  defdelegate clear_session(session), to: ExLLM.Session

  @doc "Saves a session to a file. See ExLLM.Session.save_session/2 for details."
  defdelegate save_session(session, path), to: ExLLM.Session

  @doc "Saves a session to JSON string. See ExLLM.Session.save_session/1 for details."
  defdelegate save_session(session), to: ExLLM.Session

  @doc "Loads a session from a file path or JSON string. See ExLLM.Session.load_session/1 for details."
  defdelegate load_session(path_or_json), to: ExLLM.Session

  @doc "Performs a chat with a session, managing context automatically. See ExLLM.Session.chat_session/3 for details."
  defdelegate chat_session(session, content, opts \\ []), to: ExLLM.Session

  @doc "Performs a chat with a session, managing context automatically. See ExLLM.Session.chat_with_session/3 for details."
  defdelegate chat_with_session(session, content, opts \\ []), to: ExLLM.Session

  ## Model Capability Functions

  @doc """
  Check if a specific model supports a capability.

  ## Examples

      ExLLM.model_supports?(:openai, "gpt-4-vision-preview", :vision)
      # => true
  """
  def model_supports?(provider, model_id, feature) do
    ExLLM.Core.Capabilities.model_supports?(provider, model_id, feature)
  end

  @doc """
  Get detailed information about a model.

  ## Examples

      {:ok, info} = ExLLM.get_model_info(:openai, "gpt-4")
  """
  def get_model_info(provider, model_id) do
    ExLLM.Infrastructure.Config.ModelCapabilities.get_capabilities(provider, model_id)
  end

  @doc """
  Get model recommendations based on required features.

  ## Examples

      models = ExLLM.recommend_models(features: [:vision, :streaming])
  """
  def recommend_models(opts \\ []) do
    features = Keyword.get(opts, :features, [])
    ExLLM.Infrastructure.Config.ModelCapabilities.find_models_with_features(features)
  end

  @doc """
  Group models by a specific capability.

  ## Examples

      groups = ExLLM.models_by_capability(:function_calling)
  """
  def models_by_capability(capability) do
    ExLLM.Infrastructure.Config.ModelCapabilities.models_by_capability(capability)
  end

  @doc """
  Find models that support specific features.

  ## Examples

      models = ExLLM.find_models_with_features([:vision, :streaming])
  """
  def find_models_with_features(features) do
    ExLLM.Infrastructure.Config.ModelCapabilities.find_models_with_features(features)
  end

  ## Vision Functions

  @doc """
  Check if a provider/model combination supports vision.

  ## Examples

      ExLLM.supports_vision?(:openai, "gpt-4-vision-preview")
      # => true
  """
  def supports_vision?(provider, model) do
    model_supports?(provider, model, :vision)
  end

  @doc """
  Load an image from a file path or URL.

  ## Examples

      {:ok, image_data} = ExLLM.load_image("/path/to/image.jpg")
  """
  def load_image(path, opts \\ []) do
    ExLLM.Core.Vision.load_image(path, opts)
  end

  @doc """
  Create a vision message with text and images.

  ## Examples

      {:ok, message} = ExLLM.vision_message("What's in this image?", ["https://example.com/img.jpg"])
  """
  def vision_message(text, images, opts \\ []) do
    ExLLM.Core.Vision.create_message(text, images, opts)
  end

  ## Embeddings Functions

  @doc "Find similar items based on embeddings. See ExLLM.Embeddings.find_similar/3 for details."
  defdelegate find_similar(query_embedding, items, opts \\ []), to: ExLLM.Embeddings

  @doc "Calculate cosine similarity between two vectors. See ExLLM.Embeddings.cosine_similarity/2 for details."
  defdelegate cosine_similarity(vector1, vector2), to: ExLLM.Embeddings

  @doc "List models that support embeddings for a provider. See ExLLM.Embeddings.list_models/1 for details."
  defdelegate list_embedding_models(provider), to: ExLLM.Embeddings, as: :list_models

  @doc "Calculate similarity between embeddings using different metrics. See ExLLM.Embeddings.similarity/3 for details."
  defdelegate embedding_similarity(vector1, vector2, metric \\ :cosine),
    to: ExLLM.Embeddings,
    as: :similarity

  @doc "Batch generate embeddings for multiple texts. See ExLLM.Embeddings.batch_generate/3 for details."
  defdelegate batch_embeddings(provider, requests), to: ExLLM.Embeddings, as: :batch_generate

  @doc "Get detailed information about an embedding model. See ExLLM.Embeddings.model_info/2 for details."
  defdelegate get_embedding_model_info(provider, model_id), to: ExLLM.Embeddings, as: :model_info

  @doc "Compare models across providers."
  def compare_models(model_list) do
    ExLLM.Infrastructure.Config.ModelCapabilities.compare_models(model_list)
  end

  @doc "Create an embedding search index from texts. See ExLLM.Embeddings.create_index/3 for details."
  defdelegate create_embedding_index(provider, texts, opts \\ []),
    to: ExLLM.Embeddings,
    as: :create_index

  ## Context Management Functions

  @doc """
  Get statistics about a conversation's context usage.

  ## Examples

      stats = ExLLM.context_stats(messages)
  """
  def context_stats(messages) do
    ExLLM.Core.Context.stats(messages)
  end

  @doc """
  Get the context window size for a specific model.

  ## Examples

      size = ExLLM.context_window_size(:openai, "gpt-4")
      # => 8192
  """
  def context_window_size(provider, model_id) do
    # Ensure provider is an atom
    provider = if is_binary(provider), do: String.to_atom(provider), else: provider

    result = ExLLM.Infrastructure.Config.ModelConfig.get_model_config(provider, model_id)

    case result do
      {:ok, model} ->
        cond do
          is_struct(model) ->
            model.context_window

          is_map(model) ->
            # Try atom key first, then string key
            Map.get(model, :context_window) || Map.get(model, "context_window")

          true ->
            nil
        end

      {:error, _} ->
        nil

      # Handle case where get_model_config returns the model directly (not wrapped in {:ok, model})
      model when is_map(model) ->
        Map.get(model, :context_window) || Map.get(model, "context_window")

      _other ->
        nil
    end
  end

  @doc """
  Estimate token count for messages.

  ## Examples

      count = ExLLM.estimate_tokens(messages)
  """
  def estimate_tokens(messages) do
    ExLLM.Core.Cost.estimate_tokens(messages)
  end

  @doc """
  Count tokens for content using provider-specific token counting APIs.

  This function provides accurate token counts by using the provider's native
  token counting API, which is more precise than estimation methods.

  Currently supported providers:
  - `:gemini` - Uses Google's countTokens API

  ## Parameters

    * `provider` - The provider atom (currently only `:gemini`)
    * `model` - The model name to use for counting
    * `content` - The content to count tokens for

  ## Content Types

  For Gemini, content can be:
  - A list of messages: `[%{role: "user", content: "Hello"}]`
  - A string: `"Hello world"`
  - Content structs for multimodal input

  ## Examples

      # Count tokens for a simple message
      {:ok, response} = ExLLM.count_tokens(:gemini, "gemini-2.0-flash", "Hello world")
      IO.puts("Total tokens: \#{response.total_tokens}")

      # Count tokens for conversation messages
      messages = [
        %{role: "user", content: "What is machine learning?"},
        %{role: "assistant", content: "Machine learning is..."}
      ]
      {:ok, response} = ExLLM.count_tokens(:gemini, "gemini-2.0-flash", messages)

  ## Return Value

  Returns `{:ok, token_response}` with:
  - `total_tokens` - Total token count
  - `cached_content_token_count` - Cached tokens (if applicable)
  - `prompt_tokens_details` - Breakdown by modality
  - `cache_tokens_details` - Cache token details

  Returns `{:error, reason}` if the request fails.
  """
  @spec count_tokens(atom(), String.t(), term()) ::
          {:ok, ExLLM.Providers.Gemini.Tokens.CountTokensResponse.t()} | {:error, term()}
  def count_tokens(provider, model, content) do
    case Delegator.delegate(:count_tokens, provider, [model, content]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Upload a file to the provider for use in multimodal models or fine-tuning.

  ## Parameters

    * `provider` - The provider atom (`:gemini` or `:openai`)
    * `file_path` - Path to the file to upload
    * `opts` - Upload options

  ## Options

  For Gemini:
    * `:display_name` - Human-readable name for the file
    * `:mime_type` - Override automatic MIME type detection
    * `:config_provider` - Configuration provider

  For OpenAI:
    * `:purpose` - Purpose of the file ("fine-tune", "assistants", "vision", "user_data", etc.)
    * `:config_provider` - Configuration provider

  ## Examples

      # Upload to Gemini
      {:ok, file} = ExLLM.upload_file(:gemini, "/path/to/image.png", 
        display_name: "My Image")
      
      # Upload to OpenAI for fine-tuning
      {:ok, file} = ExLLM.upload_file(:openai, "/path/to/training.jsonl",
        purpose: "fine-tune")

  ## Return Value

  Returns `{:ok, file_info}` with file metadata, or `{:error, reason}`.
  """
  @spec upload_file(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def upload_file(provider, file_path, opts \\ []) do
    case Delegator.delegate(:upload_file, provider, [file_path, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List files uploaded to the provider.

  ## Parameters

    * `provider` - The provider atom (`:gemini` or `:openai`)
    * `opts` - Listing options

  ## Options

  For Gemini:
    * `:page_size` - Number of files per page (default: 10)
    * `:page_token` - Token for pagination
    * `:config_provider` - Configuration provider

  For OpenAI:
    * `:purpose` - Filter by file purpose ("fine-tune", "assistants", etc.)
    * `:limit` - Number of files to return (max 100)
    * `:config_provider` - Configuration provider

  ## Examples

      # List Gemini files
      {:ok, response} = ExLLM.list_files(:gemini)
      Enum.each(response.files, fn file ->
        IO.puts("File: \#{file.display_name} (\#{file.name})")
      end)
      
      # List OpenAI fine-tuning files
      {:ok, response} = ExLLM.list_files(:openai, purpose: "fine-tune")

  ## Return Value

  Returns `{:ok, list_response}` with files and pagination info, or `{:error, reason}`.
  """
  @spec list_files(atom(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_files(provider, opts \\ []) do
    case Delegator.delegate(:list_files, provider, [opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get metadata for a specific file.

  ## Parameters

    * `provider` - The provider atom (currently only `:gemini`)
    * `file_id` - The file identifier
    * `opts` - Request options

  ## Examples

      {:ok, file} = ExLLM.get_file(:gemini, "files/abc-123")
      IO.puts("File size: \#{file.size_bytes} bytes")

  ## Return Value

  Returns `{:ok, file_info}` with file metadata, or `{:error, reason}`.
  """
  @spec get_file(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_file(provider, file_id, opts \\ []) do
    case Delegator.delegate(:get_file, provider, [file_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Delete a file from the provider.

  ## Parameters

    * `provider` - The provider atom (currently only `:gemini`)
    * `file_id` - The file identifier
    * `opts` - Request options

  ## Examples

      :ok = ExLLM.delete_file(:gemini, "files/abc-123")

  ## Return Value

  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  @spec delete_file(atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_file(provider, file_id, opts \\ []) do
    case Delegator.delegate(:delete_file, provider, [file_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Create a knowledge base (corpus) for semantic retrieval. See ExLLM.KnowledgeBase.create_knowledge_base/3 for details."
  defdelegate create_knowledge_base(provider, name, opts \\ []), to: ExLLM.KnowledgeBase

  @doc "List available knowledge bases (corpora). See ExLLM.KnowledgeBase.list_knowledge_bases/2 for details."
  defdelegate list_knowledge_bases(provider, opts \\ []), to: ExLLM.KnowledgeBase

  @doc "Get metadata for a specific knowledge base. See ExLLM.KnowledgeBase.get_knowledge_base/3 for details."
  defdelegate get_knowledge_base(provider, name, opts \\ []), to: ExLLM.KnowledgeBase

  @doc "Delete a knowledge base. See ExLLM.KnowledgeBase.delete_knowledge_base/3 for details."
  defdelegate delete_knowledge_base(provider, name, opts \\ []), to: ExLLM.KnowledgeBase

  @doc "Add a document to a knowledge base. See ExLLM.KnowledgeBase.add_document/4 for details."
  defdelegate add_document(provider, knowledge_base, document, opts \\ []),
    to: ExLLM.KnowledgeBase

  @doc "List documents in a knowledge base. See ExLLM.KnowledgeBase.list_documents/3 for details."
  defdelegate list_documents(provider, knowledge_base, opts \\ []), to: ExLLM.KnowledgeBase

  @doc "Get a specific document from a knowledge base. See ExLLM.KnowledgeBase.get_document/4 for details."
  defdelegate get_document(provider, knowledge_base, document_id, opts \\ []),
    to: ExLLM.KnowledgeBase

  @doc "Delete a document from a knowledge base. See ExLLM.KnowledgeBase.delete_document/4 for details."
  defdelegate delete_document(provider, knowledge_base, document_id, opts \\ []),
    to: ExLLM.KnowledgeBase

  @doc """
  Prepare messages for a specific provider with context management.

  ## Examples

      prepared = ExLLM.prepare_messages(messages, provider: :openai, model: "gpt-4")
  """
  def prepare_messages(messages, opts \\ []) do
    provider = Keyword.get(opts, :provider)
    model = Keyword.get(opts, :model)

    if provider && model do
      ExLLM.Core.Context.truncate_messages(messages, provider, model, opts)
    else
      messages
    end
  end

  @doc """
  Validate context for messages against provider limits.

  ## Examples

      result = ExLLM.validate_context(messages, provider: :openai, model: "gpt-4")
  """
  def validate_context(messages, opts \\ []) do
    provider = Keyword.get(opts, :provider)
    model = Keyword.get(opts, :model)

    if provider && model do
      # Convert string provider to atom if needed
      provider_atom = if is_binary(provider), do: String.to_atom(provider), else: provider

      # Use Core.Context.validate_context which returns {:ok, token_count} or {:error, reason}
      case ExLLM.Core.Context.validate_context(messages, provider_atom, model, opts) do
        {:ok, token_count} -> {:ok, token_count}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :missing_provider_or_model}
    end
  end

  @doc """
  Get a list of all supported providers.

  Returns a list of atoms representing the providers that ExLLM supports.
  Use this to discover available providers or validate provider names.

  ## Examples

      ExLLM.supported_providers()
      # => [:openai, :anthropic, :gemini, :groq, :mistral, :openrouter, ...]

      # Check if a provider is supported
      :openai in ExLLM.supported_providers()
      # => true
  """
  @spec supported_providers() :: [atom()]
  def supported_providers do
    Providers.supported_providers()
  end

  @doc """
  Check if a provider is configured and ready to use.

  This function now uses the pipeline architecture to validate configuration.

  ## Examples

      ExLLM.configured?(:openai)
      # => true

      ExLLM.configured?(:unknown_provider)  
      # => false
  """
  @spec configured?(atom()) :: boolean()
  def configured?(provider) do
    # Build request for validation
    request = Request.new(provider, [], %{})

    # Get validation pipeline for provider
    pipeline = Providers.get_pipeline(provider, :validate)

    # Run pipeline
    case Pipeline.run(request, pipeline) do
      %Request{state: :completed, result: %{configured: true}} ->
        true

      %Request{state: :completed, result: %{configured: false}} ->
        false

      %Request{state: :error} ->
        false

      _ ->
        false
    end
  end

  @doc "Performs semantic search within a knowledge base. See ExLLM.KnowledgeBase.semantic_search/4 for details."
  defdelegate semantic_search(provider, knowledge_base, query, opts \\ []),
    to: ExLLM.KnowledgeBase

  ## Context Caching Functions

  @doc """
  Creates cached content for efficient reuse across multiple requests.

  Context caching allows you to cache large amounts of input content and reuse
  it across multiple requests, reducing costs and improving performance.

  ## Parameters
    * `provider` - The LLM provider (currently only `:gemini` supported)
    * `content` - The content to cache (can be messages, system instructions, etc.)
    * `opts` - Options for caching

  ## Options for Gemini
    * `:model` - Model to use for caching (required)
    * `:display_name` - Human-readable name for the cached content
    * `:ttl` - Time-to-live in seconds (e.g., 3600 for 1 hour)
    * `:system_instruction` - System instruction content
    * `:tools` - Tools available to the model
    * `:config_provider` - Configuration provider

  ## Examples

      # Cache conversation context
      request = %{
        model: "models/gemini-1.5-pro",
        contents: [
          %{role: "user", parts: [%{text: "Long document content..."}]}
        ],
        ttl: "3600s"
      }
      {:ok, cached} = ExLLM.create_cached_context(:gemini, request)

  ## Return Value

  Returns `{:ok, cached_content}` with the cached content details, or `{:error, reason}`.
  """
  @spec create_cached_context(atom(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def create_cached_context(provider, content, opts \\ []) do
    case Delegator.delegate(:create_cached_context, provider, [content, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves cached content by name.

  ## Parameters
    * `provider` - The LLM provider (currently only `:gemini` supported)
    * `name` - The cached content name (e.g., "cachedContents/abc-123")
    * `opts` - Options for retrieval

  ## Examples

      {:ok, cached} = ExLLM.get_cached_context(:gemini, "cachedContents/abc-123")

  ## Return Value

  Returns `{:ok, cached_content}` with the cached content details, or `{:error, reason}`.
  """
  @spec get_cached_context(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_cached_context(provider, name, opts \\ []) do
    case Delegator.delegate(:get_cached_context, provider, [name, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates cached content with new information.

  ## Parameters
    * `provider` - The LLM provider (currently only `:gemini` supported)
    * `name` - The cached content name to update
    * `updates` - Map of updates to apply
    * `opts` - Options for the update

  ## Options
    * `:config_provider` - Configuration provider

  ## Examples

      updates = %{
        display_name: "Updated name",
        ttl: "7200s"
      }
      {:ok, updated} = ExLLM.update_cached_context(:gemini, "cachedContents/abc-123", updates)

  ## Return Value

  Returns `{:ok, updated_content}` with the updated cached content, or `{:error, reason}`.
  """
  @spec update_cached_context(atom(), String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def update_cached_context(provider, name, updates, opts \\ []) do
    case Delegator.delegate(:update_cached_context, provider, [name, updates, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes cached content.

  ## Parameters
    * `provider` - The LLM provider (currently only `:gemini` supported)
    * `name` - The cached content name to delete
    * `opts` - Options for deletion

  ## Examples

      :ok = ExLLM.delete_cached_context(:gemini, "cachedContents/abc-123")

  ## Return Value

  Returns `:ok` if successful, or `{:error, reason}` if failed.
  """
  @spec delete_cached_context(atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_cached_context(provider, name, opts \\ []) do
    case Delegator.delegate(:delete_cached_context, provider, [name, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all cached content.

  ## Parameters
    * `provider` - The LLM provider (currently only `:gemini` supported)
    * `opts` - Options for listing

  ## Options for Gemini
    * `:page_size` - Number of results per page (max 100)
    * `:page_token` - Token for pagination
    * `:config_provider` - Configuration provider

  ## Examples

      {:ok, %{cached_contents: contents, next_page_token: token}} = ExLLM.list_cached_contexts(:gemini)
      
      # With pagination
      {:ok, %{cached_contents: more_contents}} = ExLLM.list_cached_contexts(:gemini, 
        page_token: token, page_size: 50)

  ## Return Value

  Returns `{:ok, %{cached_contents: list, next_page_token: token}}` or `{:error, reason}`.
  """
  @spec list_cached_contexts(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_cached_contexts(provider, opts \\ []) do
    case Delegator.delegate(:list_cached_contexts, provider, [opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  ## Fine-tuning Functions

  @doc """
  Creates a fine-tuning job.

  Fine-tuning allows you to customize a model for your specific use case
  by training it on your own data.

  ## Parameters
    * `provider` - The LLM provider (`:gemini` or `:openai`)
    * `data` - Training data or file identifier (format varies by provider)
    * `opts` - Options for fine-tuning

  ## Options for Gemini
    * `:base_model` - Base model to tune (required)
    * `:display_name` - Human-readable name for the tuned model
    * `:description` - Description of the tuned model
    * `:temperature` - Temperature for tuning
    * `:top_p` - Top-p value for tuning
    * `:top_k` - Top-k value for tuning
    * `:candidate_count` - Number of candidates
    * `:max_output_tokens` - Maximum output tokens
    * `:stop_sequences` - Stop sequences
    * `:hyperparameters` - Training hyperparameters map
    * `:config_provider` - Configuration provider

  ## Options for OpenAI
    * `:model` - Base model to fine-tune (default: "gpt-3.5-turbo")
    * `:validation_file` - Validation file ID
    * `:hyperparameters` - Training hyperparameters
    * `:suffix` - Suffix for the fine-tuned model name
    * `:integrations` - Third-party integration settings
    * `:seed` - Random seed for training
    * `:config_provider` - Configuration provider

  ## Examples

      # Gemini fine-tuning
      dataset = %{
        examples: %{
          examples: [
            %{text_input: "What is AI?", output: "AI is artificial intelligence..."}
          ]
        }
      }
      {:ok, tuned_model} = ExLLM.create_fine_tune(:gemini, dataset, 
        base_model: "models/gemini-1.5-flash-001",
        display_name: "My Custom Model"
      )

      # OpenAI fine-tuning
      {:ok, job} = ExLLM.create_fine_tune(:openai, "file-abc123",
        model: "gpt-3.5-turbo",
        suffix: "my-model"
      )

  ## Return Value

  Returns `{:ok, result}` with the fine-tuning job or model details, or `{:error, reason}`.
  """
  @spec create_fine_tune(atom(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def create_fine_tune(provider, data, opts \\ []) do
    case Delegator.delegate(:create_fine_tune, provider, [data, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists fine-tuning jobs or tuned models.

  ## Parameters
    * `provider` - The LLM provider (`:gemini` or `:openai`)
    * `opts` - Options for listing

  ## Options for Gemini
    * `:page_size` - Number of results per page
    * `:page_token` - Token for pagination
    * `:config_provider` - Configuration provider

  ## Options for OpenAI
    * `:after` - Identifier for pagination
    * `:limit` - Number of results to return (max 100)
    * `:config_provider` - Configuration provider

  ## Examples

      # List Gemini tuned models
      {:ok, %{tuned_models: models}} = ExLLM.list_fine_tunes(:gemini)

      # List OpenAI fine-tuning jobs
      {:ok, %{data: jobs}} = ExLLM.list_fine_tunes(:openai, limit: 20)

  ## Return Value

  Returns `{:ok, response}` with the list of fine-tuning jobs or models, or `{:error, reason}`.
  """
  @spec list_fine_tunes(atom(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_fine_tunes(provider, opts \\ []) do
    case Delegator.delegate(:list_fine_tunes, provider, [opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets details of a specific fine-tuning job or tuned model.

  ## Parameters
    * `provider` - The LLM provider (`:gemini` or `:openai`)
    * `id` - The fine-tuning job ID or tuned model name
    * `opts` - Options for retrieval

  ## Examples

      # Get Gemini tuned model
      {:ok, model} = ExLLM.get_fine_tune(:gemini, "tunedModels/my-model-abc123")

      # Get OpenAI fine-tuning job
      {:ok, job} = ExLLM.get_fine_tune(:openai, "ftjob-abc123")

  ## Return Value

  Returns `{:ok, details}` with the fine-tuning job or model details, or `{:error, reason}`.
  """
  @spec get_fine_tune(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_fine_tune(provider, id, opts \\ []) do
    case Delegator.delegate(:get_fine_tune, provider, [id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cancels or deletes a fine-tuning job or tuned model.

  For OpenAI, this cancels a running fine-tuning job.
  For Gemini, this deletes a tuned model.

  ## Parameters
    * `provider` - The LLM provider (`:gemini` or `:openai`)
    * `id` - The fine-tuning job ID or tuned model name
    * `opts` - Options for cancellation/deletion

  ## Examples

      # Delete Gemini tuned model
      :ok = ExLLM.cancel_fine_tune(:gemini, "tunedModels/my-model-abc123")

      # Cancel OpenAI fine-tuning job
      {:ok, job} = ExLLM.cancel_fine_tune(:openai, "ftjob-abc123")

  ## Return Value

  Returns `:ok` or `{:ok, details}` if successful, or `{:error, reason}` if failed.
  """
  @spec cancel_fine_tune(atom(), String.t(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  def cancel_fine_tune(provider, id, opts \\ []) do
    case Delegator.delegate(:cancel_fine_tune, provider, [id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  ## OpenAI Assistants API Functions

  @doc "Create an AI assistant. See ExLLM.Assistants.create_assistant/2 for details."
  defdelegate create_assistant(provider, opts \\ []), to: ExLLM.Assistants

  @doc "List AI assistants. See ExLLM.Assistants.list_assistants/2 for details."
  defdelegate list_assistants(provider, opts \\ []), to: ExLLM.Assistants

  @doc "Retrieve an AI assistant by ID. See ExLLM.Assistants.get_assistant/3 for details."
  defdelegate get_assistant(provider, assistant_id, opts \\ []), to: ExLLM.Assistants

  @doc "Update an AI assistant. See ExLLM.Assistants.update_assistant/4 for details."
  defdelegate update_assistant(provider, assistant_id, updates, opts \\ []), to: ExLLM.Assistants

  @doc "Delete an AI assistant. See ExLLM.Assistants.delete_assistant/3 for details."
  defdelegate delete_assistant(provider, assistant_id, opts \\ []), to: ExLLM.Assistants

  @doc "Create a conversation thread. See ExLLM.Assistants.create_thread/2 for details."
  defdelegate create_thread(provider, opts \\ []), to: ExLLM.Assistants

  @doc "Create a message in a thread. See ExLLM.Assistants.create_message/4 for details."
  defdelegate create_message(provider, thread_id, content, opts \\ []), to: ExLLM.Assistants

  @doc "Run an assistant on a thread. See ExLLM.Assistants.run_assistant/4 for details."
  defdelegate run_assistant(provider, thread_id, assistant_id, opts \\ []), to: ExLLM.Assistants

  ## Anthropic Message Batches API Functions

  @doc """
  Creates a message batch for processing multiple requests.

  Message batches allow you to process multiple chat requests asynchronously
  at a 50% discount. Batches are processed within 24 hours.

  ## Parameters
    * `provider` - The LLM provider (currently only `:anthropic` supported)
    * `messages_list` - List of message request objects
    * `opts` - Batch options

  ## Request Format

  Each request in `messages_list` should be a map with:
    * `:custom_id` - Unique identifier for tracking (required)
    * `:params` - The message parameters:
      * `:model` - Model to use (e.g., "claude-3-opus-20240229")
      * `:messages` - List of message objects
      * `:max_tokens` - Maximum tokens in response
      * Other standard chat parameters

  ## Options
    * `:config_provider` - Configuration provider

  ## Examples

      requests = [
        %{
          custom_id: "req-1",
          params: %{
            model: "claude-3-opus-20240229",
            messages: [%{role: "user", content: "Hello"}],
            max_tokens: 1000
          }
        },
        %{
          custom_id: "req-2",
          params: %{
            model: "claude-3-opus-20240229",
            messages: [%{role: "user", content: "How are you?"}],
            max_tokens: 1000
          }
        }
      ]
      
      {:ok, batch} = ExLLM.create_batch(:anthropic, requests)
      IO.puts("Batch ID: \#{batch.id}")

  ## Return Value

  Returns `{:ok, batch}` with batch details including ID and status, or `{:error, reason}`.
  """
  @spec create_batch(atom(), list(map()), keyword()) :: {:ok, term()} | {:error, term()}
  def create_batch(provider, messages_list, opts \\ []) do
    case Delegator.delegate(:create_batch, provider, [messages_list, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves the status and details of a message batch.

  ## Parameters
    * `provider` - The LLM provider (currently only `:anthropic` supported)
    * `batch_id` - The batch identifier
    * `opts` - Request options

  ## Examples

      {:ok, batch} = ExLLM.get_batch(:anthropic, "batch_abc123")
      
      case batch.processing_status do
        "in_progress" -> IO.puts("Still processing...")
        "ended" -> IO.puts("Batch complete!")
      end

  ## Return Value

  Returns `{:ok, batch}` with current batch status and metadata, or `{:error, reason}`.

  The batch object includes:
    * `:id` - Batch identifier
    * `:processing_status` - "in_progress" or "ended"
    * `:request_counts` - Map with succeeded/errored/processing/canceled counts
    * `:ended_at` - Completion timestamp (if ended)
    * `:expires_at` - Expiration timestamp
  """
  @spec get_batch(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_batch(provider, batch_id, opts \\ []) do
    case Delegator.delegate(:get_batch, provider, [batch_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cancels a message batch that is still processing.

  Canceling a batch will stop processing of any requests that haven't started yet.
  Requests that are already being processed will complete.

  ## Parameters
    * `provider` - The LLM provider (currently only `:anthropic` supported)
    * `batch_id` - The batch identifier to cancel
    * `opts` - Request options

  ## Examples

      {:ok, batch} = ExLLM.cancel_batch(:anthropic, "batch_abc123")
      IO.puts("Batch canceled. Status: \#{batch.processing_status}")

  ## Return Value

  Returns `{:ok, batch}` with updated batch details, or `{:error, reason}`.
  """
  @spec cancel_batch(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def cancel_batch(provider, batch_id, opts \\ []) do
    case Delegator.delegate(:cancel_batch, provider, [batch_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
