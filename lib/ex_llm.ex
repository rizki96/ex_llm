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

  alias ExLLM.ChatBuilder
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

  @doc """
  Creates a new chat builder for enhanced fluent API.

  The chat builder provides comprehensive pipeline customization capabilities
  for advanced use cases while maintaining a simple interface.

  ## Examples

      # Basic usage
      {:ok, response} = 
        ExLLM.build(:openai, messages)
        |> ExLLM.with_model("gpt-4")
        |> ExLLM.with_temperature(0.7)
        |> ExLLM.execute()
        
      # Advanced pipeline customization
      {:ok, response} = 
        ExLLM.build(:openai, messages)
        |> ExLLM.with_cache(ttl: 3600)
        |> ExLLM.with_custom_plug(MyApp.Plugs.Logger)
        |> ExLLM.without_cost_tracking()
        |> ExLLM.execute()
        
      # Streaming with builder
      ExLLM.build(:openai, messages)
      |> ExLLM.with_model("gpt-4")
      |> ExLLM.stream(fn chunk ->
        IO.write(chunk.content)
      end)
  """
  @spec build(atom(), list(map())) :: ExLLM.ChatBuilder.t()
  def build(provider, messages) do
    ExLLM.ChatBuilder.new(provider, messages)
  end

  @doc """
  Sets the model for a chat builder.

  ## Examples

      builder
      |> ExLLM.with_model("gpt-4-turbo")
  """
  @spec with_model(ExLLM.ChatBuilder.t(), String.t()) :: ExLLM.ChatBuilder.t()
  def with_model(%ExLLM.ChatBuilder{} = builder, model) when is_binary(model) do
    ExLLM.ChatBuilder.with_model(builder, model)
  end

  @doc """
  Sets the temperature for a chat builder.

  ## Examples

      builder
      |> ExLLM.with_temperature(0.5)
  """
  @spec with_temperature(ExLLM.ChatBuilder.t(), float()) :: ExLLM.ChatBuilder.t()
  def with_temperature(%ExLLM.ChatBuilder{} = builder, temperature)
      when is_number(temperature) and temperature >= 0 and temperature <= 2 do
    ExLLM.ChatBuilder.with_temperature(builder, temperature)
  end

  @doc """
  Sets the maximum tokens for a chat builder.

  ## Examples

      builder
      |> ExLLM.with_max_tokens(1000)
  """
  @spec with_max_tokens(ExLLM.ChatBuilder.t(), pos_integer()) :: ExLLM.ChatBuilder.t()
  def with_max_tokens(%ExLLM.ChatBuilder{} = builder, max_tokens)
      when is_integer(max_tokens) and max_tokens > 0 do
    ExLLM.ChatBuilder.with_max_tokens(builder, max_tokens)
  end

  @doc """
  Adds a custom plug to the pipeline.

  ## Examples

      builder
      |> ExLLM.with_plug(MyApp.Plugs.Logger)
      |> ExLLM.with_plug({ExLLM.Plugs.Cache, ttl: 3600})
  """
  @spec with_plug(ExLLM.ChatBuilder.t(), module(), keyword()) :: ExLLM.ChatBuilder.t()
  def with_plug(%ExLLM.ChatBuilder{} = builder, plug, opts \\ []) do
    ExLLM.ChatBuilder.with_custom_plug(builder, plug, opts)
  end

  @doc """
  Executes a chat builder request.

  ## Examples

      {:ok, response} = 
        ExLLM.build(:openai, messages)
        |> ExLLM.with_model("gpt-4")
        |> ExLLM.execute()
  """
  @spec execute(ExLLM.ChatBuilder.t()) :: {:ok, map()} | {:error, term()}
  def execute(%ExLLM.ChatBuilder{} = builder) do
    ExLLM.ChatBuilder.execute(builder)
  end

  @doc """
  Streams a chat builder request.

  ## Examples

      ExLLM.build(:openai, messages)
      |> ExLLM.with_model("gpt-4")
      |> ExLLM.stream(fn chunk ->
        IO.write(chunk.content)
      end)
  """
  @spec stream(ExLLM.ChatBuilder.t(), function()) :: :ok | {:error, term()}
  def stream(%ExLLM.ChatBuilder{} = builder, callback) when is_function(callback, 1) do
    ExLLM.ChatBuilder.stream(builder, callback)
  end

  ## Enhanced Builder API Methods

  @doc """
  Enables caching with configurable options on a chat builder.

  ## Examples

      builder |> ExLLM.with_cache()
      builder |> ExLLM.with_cache(ttl: 3600)
  """
  @spec with_cache(ChatBuilder.t(), keyword()) :: ChatBuilder.t()
  def with_cache(%ChatBuilder{} = builder, opts \\ []) do
    ChatBuilder.with_cache(builder, opts)
  end

  @doc """
  Disables caching for a chat builder request.

  ## Examples

      builder |> ExLLM.without_cache()
  """
  @spec without_cache(ChatBuilder.t()) :: ChatBuilder.t()
  def without_cache(%ChatBuilder{} = builder) do
    ChatBuilder.without_cache(builder)
  end

  @doc """
  Disables cost tracking for a chat builder request.

  ## Examples

      builder |> ExLLM.without_cost_tracking()
  """
  @spec without_cost_tracking(ChatBuilder.t()) :: ChatBuilder.t()
  def without_cost_tracking(%ChatBuilder{} = builder) do
    ChatBuilder.without_cost_tracking(builder)
  end

  @doc """
  Adds a custom plug to the chat builder pipeline.

  ## Examples

      builder |> ExLLM.with_custom_plug(MyApp.Plugs.Logger)
      builder |> ExLLM.with_custom_plug(MyApp.Plugs.Auth, api_key: "secret")
  """
  @spec with_custom_plug(ChatBuilder.t(), module(), keyword()) :: ChatBuilder.t()
  def with_custom_plug(%ChatBuilder{} = builder, plug, opts \\ []) do
    ChatBuilder.with_custom_plug(builder, plug, opts)
  end

  @doc """
  Sets a custom context management strategy for a chat builder.

  ## Examples

      builder |> ExLLM.with_context_strategy(:truncate, max_tokens: 8000)
      builder |> ExLLM.with_context_strategy(:summarize, preserve_system: true)
  """
  @spec with_context_strategy(ChatBuilder.t(), atom(), keyword()) :: ChatBuilder.t()
  def with_context_strategy(%ChatBuilder{} = builder, strategy, opts \\ []) do
    ChatBuilder.with_context_strategy(builder, strategy, opts)
  end

  @doc """
  Returns the pipeline that would be executed without running it.

  ## Examples

      pipeline = builder |> ExLLM.inspect_pipeline()
      IO.inspect(pipeline, label: "Pipeline")
  """
  @spec inspect_pipeline(ChatBuilder.t()) :: Pipeline.pipeline()
  def inspect_pipeline(%ChatBuilder{} = builder) do
    ChatBuilder.inspect_pipeline(builder)
  end

  @doc """
  Returns detailed debugging information about the chat builder state.

  ## Examples

      info = builder |> ExLLM.debug_info()
      IO.inspect(info, label: "Builder State")
  """
  @spec debug_info(ChatBuilder.t()) :: map()
  def debug_info(%ChatBuilder{} = builder) do
    ChatBuilder.debug_info(builder)
  end

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

  @doc """
  Creates a new session for conversation management.

  ## Examples

      session = ExLLM.new_session(:openai)
      session = ExLLM.new_session(:anthropic, name: "Assistant Session")
  """
  def new_session(provider, opts \\ []) do
    # Convert provider atom to string as expected by Session type
    provider_string = if is_atom(provider), do: to_string(provider), else: provider
    ExLLM.Core.Session.new(provider_string, opts)
  end

  @doc """
  Adds a message to a session.

  ## Examples

      session = session |> ExLLM.add_message("user", "Hello!")
  """
  def add_message(session, role, content) do
    ExLLM.Core.Session.add_message(session, role, content)
  end

  @doc """
  Gets all messages from a session.

  ## Examples

      messages = ExLLM.get_messages(session)
  """
  def get_messages(session) do
    ExLLM.Core.Session.get_messages(session)
  end

  @doc """
  Gets session messages with limit (alias for get_messages).

  ## Examples

      messages = ExLLM.get_session_messages(session)
      last_2 = ExLLM.get_session_messages(session, 2)
  """
  def get_session_messages(session, limit \\ nil) do
    messages = ExLLM.Core.Session.get_messages(session)
    if limit, do: Enum.take(messages, -limit), else: messages
  end

  @doc """
  Adds a message to a session (alias for add_message).

  ## Examples

      session = ExLLM.add_session_message(session, "user", "Hello!")
  """
  def add_session_message(session, role, content) do
    ExLLM.Core.Session.add_message(session, role, content)
  end

  @doc """
  Gets total token usage for a session.

  ## Examples

      total = ExLLM.session_token_usage(session)
  """
  def session_token_usage(session) do
    ExLLM.Core.Session.total_tokens(session)
  end

  @doc """
  Clears all messages from a session.

  ## Examples

      session = session |> ExLLM.clear_session()
  """
  def clear_session(session) do
    ExLLM.Core.Session.clear_messages(session)
  end

  @doc """
  Saves a session to a file.

  ## Examples

      :ok = ExLLM.save_session(session, "path/to/session.json")
  """
  def save_session(session, path) do
    ExLLM.Core.Session.save_to_file(session, path)
  end

  @doc """
  Saves a session to JSON string.

  ## Examples

      {:ok, json} = ExLLM.save_session(session)
  """
  def save_session(session) do
    ExLLM.Core.Session.to_json(session)
  end

  @doc """
  Loads a session from a file path or JSON string.

  ## Examples

      {:ok, session} = ExLLM.load_session("path/to/session.json")
      {:ok, session} = ExLLM.load_session(json_string)
  """
  def load_session(path_or_json) when is_binary(path_or_json) do
    # Try to determine if this is a JSON string or a file path
    # JSON strings typically start with { and end with }
    if String.starts_with?(String.trim(path_or_json), "{") and
         String.ends_with?(String.trim(path_or_json), "}") do
      ExLLM.Core.Session.from_json(path_or_json)
    else
      ExLLM.Core.Session.load_from_file(path_or_json)
    end
  end

  @doc """
  Performs a chat with a session, managing context automatically.

  ## Examples

      {:ok, response} = ExLLM.chat_session(session, "What's the weather?")
  """
  def chat_session(session, content, opts \\ []) do
    # Add user message to session
    session = ExLLM.Core.Session.add_message(session, "user", content)

    # Convert provider string back to atom for chat function
    provider =
      if is_binary(session.llm_backend),
        do: String.to_atom(session.llm_backend),
        else: session.llm_backend

    # Perform chat with session messages
    case chat(provider, ExLLM.Core.Session.get_messages(session), opts) do
      {:ok, response} ->
        # Add assistant message to session
        session = ExLLM.Core.Session.add_message(session, "assistant", response.content)
        {:ok, response, session}

      error ->
        error
    end
  end

  @doc """
  Performs a chat with a session, managing context automatically.

  ## Examples

      {:ok, {response, session}} = ExLLM.chat_with_session(session, "What's the weather?")
  """
  def chat_with_session(session, content, opts \\ []) do
    case chat_session(session, content, opts) do
      {:ok, response, updated_session} ->
        {:ok, {response, updated_session}}

      error ->
        error
    end
  end

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
      results = ExLLM.find_similar(query_embedding, items, top_k: 5)
      
      # With threshold filtering
      results = ExLLM.find_similar(query_embedding, items, 
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

      similarity = ExLLM.cosine_similarity([1.0, 2.0], [3.0, 4.0])
      # => 0.9838699100999074
      
      # Identical vectors have similarity of 1.0
      ExLLM.cosine_similarity([1, 2, 3], [1, 2, 3])
      # => 1.0
      
      # Orthogonal vectors have similarity of 0.0
      ExLLM.cosine_similarity([1, 0], [0, 1])
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

      {:ok, models} = ExLLM.list_embedding_models(:openai)
      # => {:ok, ["text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002"]}
      
      {:ok, models} = ExLLM.list_embedding_models(:gemini)
      # => {:ok, ["text-embedding-004", "text-multilingual-embedding-002"]}
  """
  @spec list_embedding_models(atom()) :: {:ok, [String.t()]} | {:error, term()}
  def list_embedding_models(provider) do
    ExLLM.Core.Embeddings.list_embedding_models(provider)
  end

  @doc """
  Calculate similarity between embeddings using different metrics.

  Supports multiple similarity/distance metrics for comparing embedding vectors.

  ## Parameters

    * `vector1` - First embedding vector
    * `vector2` - Second embedding vector  
    * `metric` - Similarity metric (default: `:cosine`)
    
  ## Supported Metrics

    * `:cosine` - Cosine similarity (0 to 1, higher is more similar)
    * `:euclidean` - Euclidean distance (0 to ∞, lower is more similar)
    * `:dot_product` - Dot product (can be any value)
    
  ## Examples

      # Cosine similarity (default)
      similarity = ExLLM.embedding_similarity([1.0, 2.0], [3.0, 4.0])
      # => 0.9838699100999074
      
      # Euclidean distance
      distance = ExLLM.embedding_similarity([1, 2, 3], [4, 5, 6], :euclidean)
      # => 5.196152422706632
      
      # Dot product
      dot = ExLLM.embedding_similarity([1, 2], [3, 4], :dot_product)
      # => 11
  """
  @spec embedding_similarity([float()], [float()], atom()) :: float()
  def embedding_similarity(vector1, vector2, metric \\ :cosine) do
    ExLLM.Core.Embeddings.similarity(vector1, vector2, metric)
  end

  @doc """
  Batch generate embeddings for multiple texts.

  Efficiently processes multiple embedding requests in a batch. Each text
  can have its own options (like different models).

  ## Parameters

    * `provider` - The LLM provider atom
    * `requests` - List of {text, options} tuples
    
  ## Examples

      # Batch with same options
      requests = [
        {"Document 1", []},
        {"Document 2", []},
        {"Document 3", []}
      ]
      {:ok, results} = ExLLM.batch_embeddings(:openai, requests)
      
      # Batch with different models
      requests = [
        {"Short text", [model: "text-embedding-3-small"]},
        {"Long document", [model: "text-embedding-3-large", dimensions: 1024]}
      ]
      {:ok, results} = ExLLM.batch_embeddings(:openai, requests)
      
      # Results include batch index
      [
        %{embeddings: [[...]], batch_index: 0, ...},
        %{embeddings: [[...]], batch_index: 1, ...}
      ]
  """
  @spec batch_embeddings(atom(), [{String.t() | [String.t()], keyword()}]) ::
          {:ok, list()} | {:error, term()}
  def batch_embeddings(provider, requests) do
    # Process each request through the pipeline
    results =
      requests
      |> Enum.with_index()
      |> Enum.map(fn {{input, opts}, index} ->
        case embeddings(provider, input, opts) do
          {:ok, response} ->
            # Add batch index to response
            response_with_index = Map.put(response, :batch_index, index)
            {:ok, response_with_index}

          {:error, error} ->
            {:error, {index, error}}
        end
      end)

    # Check if any failed
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      successes = Enum.map(results, fn {:ok, result} -> result end)
      {:ok, successes}
    else
      {:error, {:batch_errors, errors}}
    end
  end

  @doc """
  Get detailed information about an embedding model.

  Returns comprehensive information about a specific embedding model including
  dimensions, pricing, and capabilities.

  ## Examples

      {:ok, info} = ExLLM.get_embedding_model_info(:openai, "text-embedding-3-large")
      # => %{
      #   id: "text-embedding-3-large",
      #   dimensions: 3072,
      #   max_input_tokens: 8191,
      #   pricing: %{input: 0.13},
      #   capabilities: ["embeddings"]
      # }
  """
  @spec get_embedding_model_info(atom(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_embedding_model_info(provider, model_id) do
    ExLLM.Core.Embeddings.get_model_info(provider, model_id)
  end

  @doc """
  Compare models across providers.

  ## Examples

      comparison = ExLLM.compare_models([openai: "gpt-4", anthropic: "claude-3-5-sonnet-20241022"])
  """
  def compare_models(model_list) do
    ExLLM.Infrastructure.Config.ModelCapabilities.compare_models(model_list)
  end

  @doc """
  Create an embedding search index from texts.

  Generates embeddings for a collection of texts and prepares them for
  similarity search. This is useful for building semantic search systems.

  ## Parameters

    * `provider` - The LLM provider atom
    * `texts` - List of texts or {id, text} tuples
    * `opts` - Options for embedding generation
    
  ## Options

    * `:model` - Embedding model to use
    * `:batch_size` - Process texts in batches (default: 100)
    * `:dimensions` - Output dimensions for models that support it
    
  ## Examples

      # Simple text list
      texts = ["Document 1", "Document 2", "Document 3"]
      {:ok, index} = ExLLM.create_embedding_index(:openai, texts)
      
      # With IDs
      texts = [
        {1, "First document"},
        {2, "Second document"},
        {"doc3", "Third document"}
      ]
      {:ok, index} = ExLLM.create_embedding_index(:openai, texts,
        model: "text-embedding-3-small"
      )
      
      # Use the index for search
      {:ok, query_resp} = ExLLM.embeddings(:openai, "search query")
      results = ExLLM.find_similar(hd(query_resp.embeddings), index, top_k: 3)
  """
  @spec create_embedding_index(atom(), [String.t()] | [{any(), String.t()}], keyword()) ::
          {:ok, list()} | {:error, term()}
  def create_embedding_index(provider, texts, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 100)
    embedding_opts = Keyword.delete(opts, :batch_size)

    # Normalize input format
    normalized_texts = normalize_text_input(texts)

    # Process in batches
    normalized_texts
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
      # Extract texts for embedding
      batch_texts = Enum.map(batch, fn {_id, text} -> text end)

      case embeddings(provider, batch_texts, embedding_opts) do
        {:ok, response} ->
          # Combine IDs with embeddings
          indexed_items =
            batch
            |> Enum.zip(response.embeddings)
            |> Enum.map(fn {{id, text}, embedding} ->
              %{
                id: id,
                text: text,
                embedding: embedding,
                metadata: %{
                  model: response.model,
                  timestamp: DateTime.utc_now()
                }
              }
            end)

          {:cont, {:ok, acc ++ indexed_items}}

        {:error, error} ->
          {:halt, {:error, {:batch_failed, error}}}
      end
    end)
  end

  defp normalize_text_input(texts) do
    texts
    |> Enum.with_index()
    |> Enum.map(fn
      {{id, text}, _index} when is_binary(text) -> {id, text}
      {text, index} when is_binary(text) -> {index, text}
      _ -> raise ArgumentError, "Invalid text input format"
    end)
  end

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
end
