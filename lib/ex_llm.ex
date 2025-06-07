defmodule ExLLM do
  @moduledoc """
  ExLLM - Unified Elixir client library for Large Language Models.

  ExLLM provides a consistent interface across multiple LLM providers including
  OpenAI, Anthropic Claude, Ollama, and others. It features configuration injection,
  standardized error handling, and streaming support.

  ## Quick Start

      # Using environment variables
      messages = [%{role: "user", content: "Hello!"}]
      {:ok, response} = ExLLM.chat(:anthropic, messages)
      IO.puts(response.content)

      # Using static configuration
      config = %{anthropic: %{api_key: "your-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      {:ok, response} = ExLLM.chat(:anthropic, messages, config_provider: provider)

  ## Supported Providers

  - `:anthropic` - Anthropic Claude models
  - `:openai` - OpenAI GPT models
  - `:groq` - Groq (fast inference)
  - `:openrouter` - OpenRouter (300+ models from multiple providers)
  - `:ollama` - Local models via Ollama
  - `:bedrock` - AWS Bedrock (multiple providers)
  - `:gemini` - Google Gemini models
  - `:xai` - X.AI Grok models
  - `:local` - Local models via Bumblebee (Phi-2, Llama 2, Mistral, etc.)
  - `:mock` - Mock adapter for testing

  ## Features

  - **Unified Interface**: Same API across all providers
  - **Configuration Injection**: Flexible config management
  - **Streaming Support**: Real-time response streaming with error recovery
  - **Error Standardization**: Consistent error handling
  - **Function Calling**: Unified interface for tool use across providers
  - **Model Discovery**: Query and compare model capabilities
  - **Automatic Retries**: Exponential backoff with provider-specific policies
  - **Mock Adapter**: Built-in testing support without API calls
  - **Cost Tracking**: Automatic usage and cost calculation
  - **Context Management**: Automatic message truncation for model limits
  - **Session Management**: Conversation state tracking
  - **Structured Outputs**: Schema validation via instructor integration
  - **No Process Dependencies**: Pure functional core
  - **Extensible**: Easy to add new providers

  ## Configuration

  ExLLM supports multiple configuration methods:

  ### Environment Variables

      export ANTHROPIC_API_KEY="api-..."
      export OPENAI_API_KEY="sk-..."
      export GROQ_API_KEY="gsk-..."
      export OPENROUTER_API_KEY="sk-or-..."
      export OLLAMA_API_BASE="http://localhost:11434"
      export GOOGLE_API_KEY="your-key"
      export XAI_API_KEY="xai-..."
      export AWS_ACCESS_KEY_ID="your-key"
      export AWS_SECRET_ACCESS_KEY="your-secret"

  ### Static Configuration

      config = %{
        anthropic: %{api_key: "api-...", model: "claude-3-5-sonnet-20241022"},
        openai: %{api_key: "sk-...", model: "gpt-4"},
        openrouter: %{api_key: "sk-or-...", model: "openai/gpt-4o"},
        ollama: %{base_url: "http://localhost:11434", model: "llama2"},
        bedrock: %{access_key_id: "...", secret_access_key: "...", region: "us-east-1"},
        gemini: %{api_key: "...", model: "gemini-pro"},
        local: %{model: "microsoft/phi-2"}
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

  ### Custom Configuration

      defmodule MyConfigProvider do
        @behaviour ExLLM.ConfigProvider
        
        def get([:anthropic, :api_key]), do: MyApp.get_secret("anthropic_key")
        def get(_), do: nil
        
        def get_all(), do: %{}
      end

  ## Examples

      # Simple chat
      {:ok, response} = ExLLM.chat(:anthropic, [
        %{role: "user", content: "What is Elixir?"}
      ])

      # With options
      {:ok, response} = ExLLM.chat(:anthropic, messages,
        model: "claude-3-haiku-20240307",
        temperature: 0.7,
        max_tokens: 1000
      )

      # Streaming
      {:ok, stream} = ExLLM.stream_chat(:anthropic, messages)
      for chunk <- stream do
        if chunk.content, do: IO.write(chunk.content)
      end

      # Check if provider is configured
      if ExLLM.configured?(:anthropic) do
        {:ok, response} = ExLLM.chat(:anthropic, messages)
      end

      # List available models
      {:ok, models} = ExLLM.list_models(:anthropic)
      Enum.each(models, fn model ->
        IO.puts(model.name)
      end)
  """

  alias ExLLM.{
    Cache,
    Capabilities,
    Context,
    Cost,
    FunctionCalling,
    Logger,
    ModelCapabilities,
    ProviderCapabilities,
    Session,
    StreamRecovery,
    Types,
    Vision
  }

  @providers %{
    anthropic: ExLLM.Adapters.Anthropic,
    groq: ExLLM.Adapters.Groq,
    local: ExLLM.Adapters.Local,
    openai: ExLLM.Adapters.OpenAI,
    openrouter: ExLLM.Adapters.OpenRouter,
    ollama: ExLLM.Adapters.Ollama,
    bedrock: ExLLM.Adapters.Bedrock,
    gemini: ExLLM.Adapters.Gemini,
    xai: ExLLM.Adapters.XAI,
    mock: ExLLM.Adapters.Mock
  }

  @type provider :: :anthropic | :openai | :groq | :openrouter | :ollama | :local | :bedrock | :gemini | :xai | :mock
  @type messages :: [Types.message()]
  @type options :: keyword()

  @doc """
  Send a chat completion request to the specified LLM provider.

  ## Parameters
  - `provider` - The LLM provider (`:anthropic`, `:openai`, `:groq`, etc.) or a model string like "groq/llama3-70b"
  - `messages` - List of conversation messages
  - `options` - Options for the request (see module docs)

  ## Options
  - `:model` - Override the default model
  - `:temperature` - Temperature setting (0.0 to 1.0)
  - `:max_tokens` - Maximum tokens in response or context
  - `:config_provider` - Configuration provider module or pid
  - `:track_cost` - Whether to track costs (default: true)
  - `:strategy` - Context truncation strategy (default: :sliding_window)
    - `:sliding_window` - Keep most recent messages
    - `:smart` - Preserve system messages and recent context
  - `:preserve_messages` - Number of recent messages to always preserve (default: 5)
  - `:response_model` - Ecto schema or type spec for structured output (requires instructor)
  - `:max_retries` - Number of retries for structured output validation
  - `:functions` - List of available functions for function calling
  - `:function_call` - Control function calling: "auto", "none", or specific function
  - `:tools` - Alternative to functions for providers that use tools API
  - `:retry` - Enable automatic retry (default: true)
  - `:retry_count` - Number of retry attempts (default: 3)
  - `:retry_delay` - Initial retry delay in ms (default: 1000)
  - `:retry_backoff` - Backoff strategy: :exponential or :linear (default: :exponential)
  - `:retry_jitter` - Add jitter to retry delays (default: true)
  - `:stream_recovery` - Enable stream recovery (default: false)
  - `:recovery_strategy` - Recovery strategy: :exact, :paragraph, or :summarize
  - `:cache` - Enable caching for this request (default: false unless globally enabled)
  - `:cache_ttl` - Cache TTL in milliseconds (default: 15 minutes)
  - `:timeout` - Request timeout in milliseconds (provider-specific defaults)
    - Ollama default: 120000 (2 minutes)
    - Other providers use their client library defaults
  - Mock adapter options:
    - `:mock_response` - Static response or response map
    - `:mock_handler` - Function to generate dynamic responses
    - `:mock_error` - Simulate an error
    - `:mock_chunks` - List of chunks for streaming
    - `:chunk_delay` - Delay between chunks in ms
    - `:capture_requests` - Capture requests for testing

  ## Returns
  `{:ok, %ExLLM.Types.LLMResponse{}}` on success, or `{:ok, struct}` when using
  response_model. Returns `{:error, reason}` on failure.

  ## Examples

      # Simple usage
      {:ok, response} = ExLLM.chat(:anthropic, [
        %{role: "user", content: "Hello!"}
      ])
      
      # Using provider/model syntax
      {:ok, response} = ExLLM.chat("groq/llama3-70b", [
        %{role: "user", content: "Hello!"}
      ])
      
      # Groq with specific model
      {:ok, response} = ExLLM.chat(:groq, messages, model: "mixtral-8x7b-32768")

      # With custom configuration
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(%{
        anthropic: %{api_key: "your-key"}
      })
      {:ok, response} = ExLLM.chat(:anthropic, messages, config_provider: provider)

      # With model override
      {:ok, response} = ExLLM.chat(:openai, messages, model: "gpt-4-turbo")

      # With context management
      {:ok, response} = ExLLM.chat(:anthropic, messages,
        max_tokens: 4000,
        strategy: :smart
      )

      # With structured output (requires instructor)
      {:ok, classification} = ExLLM.chat(:anthropic, messages,
        response_model: EmailClassification,
        max_retries: 3
      )
      
      # With function calling
      functions = [
        %{
          name: "get_weather",
          description: "Get current weather",
          parameters: %{
            type: "object",
            properties: %{location: %{type: "string"}},
            required: ["location"]
          }
        }
      ]
      
      {:ok, response} = ExLLM.chat(:openai, messages,
        functions: functions,
        function_call: "auto"
      )
  """
  @spec chat(provider() | String.t(), messages(), options()) ::
          {:ok, Types.LLMResponse.t() | struct() | map()} | {:error, term()}
  def chat(provider_or_model, messages, options \\ []) do
    # Detect provider from model string if needed
    {provider, options} = detect_provider(provider_or_model, options)
    # Check if structured output is requested
    if Keyword.has_key?(options, :response_model) do
      # Delegate to Instructor module if available
      if Code.ensure_loaded?(ExLLM.Instructor) and ExLLM.Instructor.available?() do
        ExLLM.Instructor.chat(provider, messages, options)
      else
        {:error, :instructor_not_available}
      end
    else
      # Regular chat flow with retry support
      case get_adapter(provider) do
        {:ok, adapter} ->
          # Apply context management if enabled
          prepared_messages = prepare_messages_for_provider(provider, messages, options)

          # Check if retry is enabled
          if Keyword.get(options, :retry, true) do
            ExLLM.Retry.with_provider_retry(
              provider,
              fn ->
                execute_chat(adapter, provider, prepared_messages, options)
              end,
              Keyword.get(options, :retry_options, [])
            )
          else
            execute_chat(adapter, provider, prepared_messages, options)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Send a streaming chat completion request to the specified LLM provider.

  ## Parameters
  - `provider` - The LLM provider (`:anthropic`, `:openai`, `:ollama`)
  - `messages` - List of conversation messages
  - `options` - Options for the request (see module docs)

  ## Options
  Same as `chat/3`, plus:
  - `:on_chunk` - Callback function for each chunk
  - `:stream_recovery` - Enable automatic stream recovery (default: false)
  - `:recovery_strategy` - How to resume: :exact, :paragraph, or :summarize
  - `:recovery_id` - Custom ID for recovery (auto-generated if not provided)

  ## Returns
  `{:ok, stream}` on success where stream yields `%ExLLM.Types.StreamChunk{}` structs,
  `{:error, reason}` on failure.

  ## Examples

      {:ok, stream} = ExLLM.stream_chat(:anthropic, messages)
      
      # Process the stream
      for chunk <- stream do
        case chunk do
          %{content: content} when content != nil ->
            IO.write(content)
          %{finish_reason: "stop"} ->
            IO.puts("\\nDone!")
          _ ->
            :continue
        end
      end

      # With context management
      {:ok, stream} = ExLLM.stream_chat(:anthropic, messages,
        max_tokens: 4000,
        strategy: :smart
      )
  """
  @spec stream_chat(provider() | String.t(), messages(), options()) ::
          {:ok, Types.stream()} | {:error, term()}
  def stream_chat(provider_or_model, messages, options \\ []) do
    # Detect provider from model string if needed
    {provider, options} = detect_provider(provider_or_model, options)
    case get_adapter(provider) do
      {:ok, adapter} ->
        # Apply context management if enabled
        prepared_messages = prepare_messages_for_provider(provider, messages, options)

        # Check if recovery is enabled
        recovery_opts = Keyword.get(options, :recovery, [])

        if recovery_opts[:enabled] do
          execute_stream_with_recovery(adapter, provider, prepared_messages, options)
        else
          adapter.stream_chat(prepared_messages, options)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if the specified provider is properly configured.

  ## Parameters
  - `provider` - The LLM provider to check
  - `options` - Options including configuration provider

  ## Returns
  `true` if configured, `false` otherwise.

  ## Examples

      if ExLLM.configured?(:anthropic) do
        {:ok, response} = ExLLM.chat(:anthropic, messages)
      else
        IO.puts("Anthropic not configured")
      end
  """
  @spec configured?(provider(), options()) :: boolean()
  def configured?(provider, options \\ []) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        adapter.configured?(options)

      {:error, _} ->
        false
    end
  end

  @doc """
  Get the default model for the specified provider.

  ## Parameters
  - `provider` - The LLM provider

  ## Returns
  String model identifier.

  ## Examples

      model = ExLLM.default_model(:anthropic)
      # => "claude-sonnet-4-20250514"
  """
  @spec default_model(provider()) :: String.t() | {:error, term()}
  def default_model(provider) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        adapter.default_model()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List available models for the specified provider.

  ## Parameters
  - `provider` - The LLM provider
  - `options` - Options including configuration provider

  ## Returns
  `{:ok, [%ExLLM.Types.Model{}]}` on success, `{:error, reason}` on failure.

  ## Examples

      {:ok, models} = ExLLM.list_models(:anthropic)
      Enum.each(models, fn model ->
        IO.puts(model.name)
      end)
  """
  @spec list_models(provider(), options()) ::
          {:ok, [Types.Model.t()]} | {:error, term()}
  def list_models(provider, options \\ []) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        adapter.list_models(options)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Calculate cost for token usage.

  ## Parameters
  - `provider` - LLM provider name
  - `model` - Model name
  - `token_usage` - Map with `:input_tokens` and `:output_tokens`

  ## Returns
  Cost calculation result or error map.

  ## Examples

      usage = %{input_tokens: 1000, output_tokens: 500}
      cost = ExLLM.calculate_cost("openai", "gpt-4", usage)
      # => %{total_cost: 0.06, ...}
  """
  @spec calculate_cost(provider(), String.t(), Types.token_usage()) ::
          Types.cost_result() | %{error: String.t()}
  def calculate_cost(provider, model, token_usage) do
    Cost.calculate(to_string(provider), model, token_usage)
  end

  @doc """
  Estimate token count for text.

  ## Parameters
  - `text` - Text to analyze (string, message map, or list)

  ## Returns
  Estimated token count.

  ## Examples

      tokens = ExLLM.estimate_tokens("Hello, world!")
      # => 4
  """
  @spec estimate_tokens(String.t() | map() | [map()]) :: non_neg_integer()
  def estimate_tokens(text) do
    Cost.estimate_tokens(text)
  end

  @doc """
  Format cost for display.

  ## Parameters
  - `cost` - Cost in dollars

  ## Returns
  Formatted cost string.

  ## Examples

      ExLLM.format_cost(0.0035)
      # => "$0.003500"
  """
  @spec format_cost(float()) :: String.t()
  def format_cost(cost) do
    Cost.format(cost)
  end

  @doc """
  Get list of supported providers.

  ## Returns
  List of provider atoms.

  ## Examples

      providers = ExLLM.supported_providers()
      # => [:anthropic, :openai, :ollama]
  """
  @spec supported_providers() :: [provider()]
  def supported_providers do
    Map.keys(@providers)
  end

  @doc """
  Prepare messages for sending to a provider with context management.

  ## Parameters
  - `messages` - List of conversation messages
  - `options` - Options for context management

  ## Options
  - `:max_tokens` - Maximum tokens for context (default: model-specific)
  - `:strategy` - Context truncation strategy (default: :sliding_window)
  - `:preserve_messages` - Number of recent messages to preserve (default: 5)

  ## Returns
  Prepared messages list that fits within context window.

  ## Examples

      messages = ExLLM.prepare_messages(long_conversation,
        max_tokens: 4000,
        strategy: :smart
      )
  """
  @spec prepare_messages(messages(), options()) :: messages()
  def prepare_messages(messages, options \\ []) do
    provider = Keyword.get(options, :provider, :openai)
    model = Keyword.get(options, :model) || default_model(provider)
    
    Context.truncate_messages(messages, provider, model, options)
  end


  @doc """
  Validate that messages fit within a model's context window.

  ## Parameters
  - `messages` - List of conversation messages
  - `options` - Options including model info

  ## Returns
  `{:ok, token_count}` if valid, `{:error, reason}` if too large.
  """
  @spec validate_context(messages(), options()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def validate_context(messages, options \\ []) do
    provider = Keyword.get(options, :provider, :openai)
    model = Keyword.get(options, :model) || default_model(provider)
    
    Context.validate_context(messages, provider, model, options)
  end


  @doc """
  Get default model for a provider.

  ## Parameters
  - `provider` - LLM provider name
  - `model` - Model name

  ## Returns
  Context window size in tokens or nil if unknown.

  ## Examples

      tokens = ExLLM.context_window_size(:anthropic, "claude-3-5-sonnet-20241022")
      # => 200000
  """
  @spec context_window_size(provider(), String.t()) :: non_neg_integer() | nil
  def context_window_size(provider, model) do
    Context.get_context_window(to_string(provider), model)
  end

  @doc """
  Get statistics about message context usage.

  ## Parameters
  - `messages` - List of conversation messages

  ## Returns
  Map with context statistics.

  ## Examples

      stats = ExLLM.context_stats(messages)
      # => %{total_tokens: 1500, message_count: 10, ...}
  """
  @spec context_stats(messages()) :: map()
  def context_stats(messages) do
    # TODO: Implement context stats
    %{
      message_count: length(messages),
      total_tokens: Cost.estimate_tokens(messages),
      by_role: Enum.frequencies_by(messages, & &1.role),
      avg_tokens_per_message: div(Cost.estimate_tokens(messages), max(length(messages), 1))
    }
  end

  # Session Management

  @doc """
  Create a new conversation session.

  ## Parameters
  - `provider` - LLM provider to use for the session
  - `opts` - Session options (`:name` for session name)

  ## Returns
  A new session struct.

  ## Examples

      session = ExLLM.new_session(:anthropic)
      session = ExLLM.new_session(:openai, name: "Customer Support")
  """
  @spec new_session(provider(), keyword()) :: Session.Types.Session.t()
  def new_session(provider, opts \\ []) do
    Session.new(to_string(provider), opts)
  end

  @doc """
  Send a chat request using a session, automatically tracking messages and usage.

  ## Parameters
  - `session` - The session to use
  - `content` - The user message content
  - `options` - Chat options (same as `chat/3`)

  ## Returns
  `{:ok, {response, updated_session}}` on success, `{:error, reason}` on failure.

  ## Examples

      session = ExLLM.new_session(:anthropic)
      {:ok, {response, session}} = ExLLM.chat_with_session(session, "Hello!")
      # Session now contains the conversation history
  """
  @spec chat_with_session(Session.Types.Session.t(), String.t(), options()) ::
          {:ok, {Types.LLMResponse.t(), Session.Types.Session.t()}} | {:error, term()}
  def chat_with_session(session, content, options \\ []) do
    # Add user message to session
    session = Session.add_message(session, "user", content)

    # Get provider from session
    provider = String.to_atom(session.llm_backend || "anthropic")

    # Get messages for chat
    messages = Session.get_messages(session)

    # Merge session context with options
    merged_options =
      Keyword.merge(
        Map.to_list(session.context || %{}),
        options
      )

    # Send chat request
    case chat(provider, messages, merged_options) do
      {:ok, response} ->
        # Add assistant response to session
        session = Session.add_message(session, "assistant", response.content)

        # Update token usage if available
        session =
          if response.usage do
            Session.update_token_usage(session, response.usage)
          else
            session
          end

        {:ok, {response, session}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Add a message to a session.

  ## Parameters
  - `session` - The session to update
  - `role` - Message role ("user", "assistant", etc.)
  - `content` - Message content
  - `opts` - Additional message metadata

  ## Returns
  Updated session.

  ## Examples

      session = ExLLM.add_session_message(session, "user", "What is Elixir?")
  """
  @spec add_session_message(Session.Types.Session.t(), String.t(), String.t(), keyword()) ::
          Session.Types.Session.t()
  def add_session_message(session, role, content, opts \\ []) do
    Session.add_message(session, role, content, opts)
  end

  @doc """
  Get messages from a session.

  ## Parameters
  - `session` - The session to query
  - `limit` - Optional message limit

  ## Returns
  List of messages.

  ## Examples

      messages = ExLLM.get_session_messages(session)
      last_10 = ExLLM.get_session_messages(session, 10)
  """
  @spec get_session_messages(Session.Types.Session.t(), non_neg_integer() | nil) ::
          [Session.Types.message()]
  def get_session_messages(session, limit \\ nil) do
    Session.get_messages(session, limit)
  end

  @doc """
  Get total token usage for a session.

  ## Parameters
  - `session` - The session to analyze

  ## Returns
  Total token count.

  ## Examples

      tokens = ExLLM.session_token_usage(session)
      # => 2500
  """
  @spec session_token_usage(Session.Types.Session.t()) :: non_neg_integer()
  def session_token_usage(session) do
    Session.total_tokens(session)
  end

  @doc """
  Clear messages from a session while preserving metadata.

  ## Parameters
  - `session` - The session to clear

  ## Returns
  Updated session with no messages.

  ## Examples

      session = ExLLM.clear_session(session)
  """
  @spec clear_session(Session.Types.Session.t()) :: Session.Types.Session.t()
  def clear_session(session) do
    Session.clear_messages(session)
  end

  @doc """
  Save a session to JSON.

  ## Parameters
  - `session` - The session to save

  ## Returns
  `{:ok, json}` on success, `{:error, reason}` on failure.

  ## Examples

      {:ok, json} = ExLLM.save_session(session)
      File.write!("session.json", json)
  """
  @spec save_session(Session.Types.Session.t()) :: {:ok, String.t()} | {:error, term()}
  def save_session(session) do
    Session.to_json(session)
  end

  @doc """
  Load a session from JSON.

  ## Parameters
  - `json` - JSON string containing session data

  ## Returns
  `{:ok, session}` on success, `{:error, reason}` on failure.

  ## Examples

      json = File.read!("session.json")
      {:ok, session} = ExLLM.load_session(json)
  """
  @spec load_session(String.t()) :: {:ok, Session.Types.Session.t()} | {:error, term()}
  def load_session(json) do
    Session.from_json(json)
  end

  # Private functions

  defp get_adapter(provider) do
    case Map.get(@providers, provider) do
      nil ->
        {:error, {:unsupported_provider, provider}}

      adapter ->
        {:ok, adapter}
    end
  end

  defp prepare_messages_for_provider(provider, messages, options) do
    # Get model from options or use default
    model =
      case Keyword.get(options, :model) do
        nil ->
          case default_model(provider) do
            {:error, _} -> nil
            model -> model
          end

        model ->
          model
      end

    # Add provider and model info to options for context management
    context_options =
      options
      |> Keyword.put(:provider, to_string(provider))
      |> Keyword.put_new(:model, model)

    # Prepare messages for vision if needed
    messages =
      if Enum.any?(messages, &Vision.has_vision_content?/1) do
        Vision.format_for_provider(messages, provider)
      else
        messages
      end

    # Apply context truncation if needed
    case Context.validate_context(messages, provider, model, context_options) do
      {:ok, _tokens} -> 
        messages
      {:error, _reason} ->
        Context.truncate_messages(messages, provider, model, context_options)
    end
  end

  defp execute_chat(adapter, provider, messages, options) do
    # Generate cache key if caching might be used
    cache_key = Cache.generate_cache_key(provider, messages, options)

    # Use cache wrapper
    Cache.with_cache(cache_key, options, fn ->
      # Check if function calling is requested
      options = prepare_function_calling(provider, options)

      result = adapter.chat(messages, options)

      # Track costs if enabled
      case result do
        {:ok, response} when is_map(response) ->
          if Keyword.get(options, :track_cost, true) do
            cost_info = track_response_cost(provider, response, options)
            response_with_cost = Map.put(response, :cost, cost_info)
            {:ok, response_with_cost}
          else
            result
          end
        _ ->
          result
      end
    end)
  end

  defp prepare_function_calling(provider, options) do
    cond do
      # Check if functions are provided
      functions = Keyword.get(options, :functions) ->
        # Convert to provider format
        case FunctionCalling.format_for_provider(functions, provider) do
          {:error, _} ->
            options

          formatted_functions ->
            # Different providers use different keys
            case provider do
              :anthropic ->
                options
                |> Keyword.delete(:functions)
                |> Keyword.put(:tools, formatted_functions)

              _ ->
                Keyword.put(options, :functions, formatted_functions)
            end
        end

      # Check if tools are provided (Anthropic style)
      Keyword.has_key?(options, :tools) ->
        options

      # No function calling
      true ->
        options
    end
  end

  defp track_response_cost(provider, response, options) do
    # Extract usage info if available
    case Map.get(response, :usage) do
      %{input_tokens: _, output_tokens: _} = usage ->
        model = Keyword.get(options, :model) || default_model(provider)
        cost_info = calculate_cost(provider, model, usage)

        # Log cost info if logger is available
        if function_exported?(Logger, :info, 1) do
          Logger.info("LLM cost: #{format_cost(cost_info.total_cost)} for #{provider}/#{model}")
        end

        cost_info

      _ ->
        nil
    end
  end

  defp execute_stream_with_recovery(adapter, provider, messages, options) do
    # Initialize recovery
    {:ok, recovery_id} = StreamRecovery.init_recovery(provider, messages, options)

    # Start the stream
    case adapter.stream_chat(messages, options) do
      {:ok, stream} ->
        # Wrap the stream to track chunks
        wrapped_stream =
          Stream.transform(
            stream,
            fn -> :ok end,
            fn chunk, state ->
              # Record chunk for recovery
              StreamRecovery.record_chunk(recovery_id, chunk)

              # Check for finish reason
              if chunk.finish_reason do
                StreamRecovery.complete_stream(recovery_id)
              end

              {[chunk], state}
            end,
            fn _state -> :ok end,
            fn _state -> :ok end
          )

        {:ok, wrapped_stream}

      {:error, reason} = error ->
        # Record error for potential recovery
        case StreamRecovery.record_error(recovery_id, reason) do
          {:ok, true} ->
            # Error is recoverable, return with recovery info
            {:error, {:recoverable, reason, recovery_id}}

          _ ->
            error
        end
    end
  end

  @doc """
  Resume a previously interrupted stream.

  ## Options
  - `:strategy` - Recovery strategy (:exact, :paragraph, :summarize)

  ## Examples

      {:ok, resumed_stream} = ExLLM.resume_stream(recovery_id)
  """
  @spec resume_stream(String.t(), keyword()) :: {:ok, Types.stream()} | {:error, term()}
  def resume_stream(recovery_id, opts \\ []) do
    StreamRecovery.resume_stream(recovery_id, opts)
  end

  @doc """
  List all recoverable streams.
  """
  @spec list_recoverable_streams() :: list(map())
  def list_recoverable_streams do
    StreamRecovery.list_recoverable_streams()
  end

  # Function calling API

  @doc """
  Parse function calls from an LLM response.

  ## Examples

      case ExLLM.parse_function_calls(response, :openai) do
        {:ok, [function_call | _]} ->
          # Execute the function
          execute_function(function_call)
          
        {:ok, []} ->
          # No function calls in response
          response.content
      end
  """
  @spec parse_function_calls(Types.LLMResponse.t() | map(), provider()) ::
          {:ok, list(FunctionCalling.FunctionCall.t())} | {:error, term()}
  def parse_function_calls(response, provider) do
    FunctionCalling.parse_function_calls(response, provider)
  end

  @doc """
  Execute a function call with available functions.

  ## Examples

      functions = [
        %{
          name: "get_weather",
          description: "Get weather",
          parameters: %{...},
          handler: fn args -> get_weather_impl(args) end
        }
      ]
      
      {:ok, result} = ExLLM.execute_function(function_call, functions)
  """
  @spec execute_function(FunctionCalling.FunctionCall.t(), list(map())) ::
          {:ok, FunctionCalling.FunctionResult.t()}
          | {:error, FunctionCalling.FunctionResult.t()}
  def execute_function(function_call, available_functions) do
    # Normalize functions
    normalized =
      Enum.map(available_functions, fn f ->
        FunctionCalling.normalize_function(f, :generic)
      end)

    FunctionCalling.execute_function(function_call, normalized)
  end

  @doc """
  Format function result for conversation continuation.

  ## Examples

      result = %FunctionCalling.FunctionResult{
        name: "get_weather",
        result: %{temperature: 72, condition: "sunny"}
      }
      
      formatted = ExLLM.format_function_result(result, :openai)
      
      # Continue conversation with result
      messages = messages ++ [formatted]
      {:ok, response} = ExLLM.chat(:openai, messages)
  """
  @spec format_function_result(FunctionCalling.FunctionResult.t(), provider()) ::
          map()
  def format_function_result(result, provider) do
    FunctionCalling.format_function_result(result, provider)
  end

  # Model capability discovery API

  @doc """
  Get complete capability information for a model.

  ## Examples

      {:ok, info} = ExLLM.get_model_info(:openai, "gpt-4-turbo")
      
      # Check capabilities
      info.capabilities[:vision].supported
      # => true
      
      # Get context window
      info.context_window
      # => 128000
  """
  @spec get_model_info(provider(), String.t()) ::
          {:ok, ModelCapabilities.ModelInfo.t()} | {:error, :not_found}
  def get_model_info(provider, model_id) do
    ModelCapabilities.get_capabilities(provider, model_id)
  end

  @doc """
  Check if a model supports a specific feature.

  ## Examples

      ExLLM.model_supports?(:anthropic, "claude-3-opus-20240229", :vision)
      # => true
      
      ExLLM.model_supports?(:openai, "gpt-3.5-turbo", :vision)
      # => false
  """
  @spec model_supports?(provider(), String.t(), atom()) :: boolean()
  def model_supports?(provider, model_id, feature) do
    # Use the Capabilities module which handles normalization
    Capabilities.model_supports?(provider, model_id, feature)
  end

  @doc """
  Find models that support specific features.

  ## Examples

      # Find models with vision and function calling
      models = ExLLM.find_models_with_features([:vision, :function_calling])
      # => [{:openai, "gpt-4-turbo"}, {:anthropic, "claude-3-opus-20240229"}, ...]
      
      # Find models that support streaming and have large context
      models = ExLLM.find_models_with_features([:streaming])
      |> Enum.filter(fn {provider, model} ->
        {:ok, info} = ExLLM.get_model_info(provider, model)
        info.context_window >= 100_000
      end)
  """
  @spec find_models_with_features(list(atom())) :: list({provider(), String.t()})
  def find_models_with_features(required_features) do
    # Normalize features first, then find models
    required_features
    |> Enum.map(&Capabilities.normalize_capability/1)
    |> ModelCapabilities.find_models_with_features()
  end

  @doc """
  Compare capabilities across multiple models.

  ## Examples

      comparison = ExLLM.compare_models([
        {:openai, "gpt-4-turbo"},
        {:anthropic, "claude-3-5-sonnet-20241022"},
        {:gemini, "gemini-pro"}
      ])
      
      # See which features each model supports
      comparison.features[:vision]
      # => [%{supported: true}, %{supported: true}, %{supported: false}]
  """
  @spec compare_models(list({provider(), String.t()})) :: map()
  def compare_models(model_specs) do
    ModelCapabilities.compare_models(model_specs)
  end

  @doc """
  Get recommended models based on requirements.

  ## Options

  - `:features` - Required features (list of atoms)
  - `:min_context_window` - Minimum context window size
  - `:max_cost_per_1k_tokens` - Maximum acceptable cost
  - `:prefer_local` - Prefer local models
  - `:limit` - Number of recommendations (default: 5)

  ## Examples

      # Find best models for vision tasks with large context
      recommendations = ExLLM.recommend_models(
        features: [:vision, :streaming],
        min_context_window: 50_000,
        prefer_local: false
      )
      
      # Find cheapest models for basic chat
      recommendations = ExLLM.recommend_models(
        features: [:multi_turn, :system_messages],
        max_cost_per_1k_tokens: 1.0
      )
  """
  @spec recommend_models(keyword()) :: list({provider(), String.t(), map()})
  def recommend_models(requirements \\ []) do
    ModelCapabilities.recommend_models(requirements)
  end

  @doc """
  List all trackable model features.

  ## Examples

      features = ExLLM.list_model_features()
      # => [:streaming, :function_calling, :vision, :audio, ...]
  """
  @spec list_model_features() :: list(atom())
  def list_model_features do
    ModelCapabilities.list_features()
  end

  @doc """
  Get models grouped by a specific capability.

  ## Examples

      vision_models = ExLLM.models_by_capability(:vision)
      # => %{
      #   supported: [{:openai, "gpt-4-turbo"}, {:anthropic, "claude-3-opus-20240229"}, ...],
      #   not_supported: [{:openai, "gpt-3.5-turbo"}, ...]
      # }
  """
  @spec models_by_capability(atom()) :: %{supported: list(), not_supported: list()}
  def models_by_capability(feature) do
    ModelCapabilities.models_by_capability(feature)
  end

  # Provider Capability Discovery API

  @doc """
  Get provider-level capabilities.

  Provider capabilities are API-level features that are independent of specific models.
  This includes available endpoints, authentication methods, and provider limitations.

  ## Examples

      {:ok, caps} = ExLLM.get_provider_capabilities(:openai)
      caps.endpoints
      # => [:chat, :embeddings, :images, :audio, :completions, :fine_tuning, :files]
      
      caps.features
      # => [:streaming, :function_calling, :cost_tracking, :usage_tracking, ...]
  """
  @spec get_provider_capabilities(provider()) :: 
          {:ok, ProviderCapabilities.ProviderInfo.t()} | {:error, :not_found}
  def get_provider_capabilities(provider) do
    ProviderCapabilities.get_capabilities(provider)
  end

  @doc """
  Check if a provider supports a specific feature or endpoint.

  ## Examples

      ExLLM.provider_supports?(:openai, :embeddings)
      # => true
      
      ExLLM.provider_supports?(:ollama, :cost_tracking)
      # => false
      
      ExLLM.provider_supports?(:anthropic, :computer_use)
      # => true
  """
  @spec provider_supports?(provider(), atom()) :: boolean()
  def provider_supports?(provider, feature) do
    # Use the Capabilities module which handles normalization
    Capabilities.supports?(provider, feature)
  end

  @doc """
  Find providers that support all specified features.

  ## Examples

      # Find providers with embeddings and streaming
      providers = ExLLM.find_providers_with_features([:embeddings, :streaming])
      # => [:openai, :ollama]
      
      # Find providers with vision and function calling
      providers = ExLLM.find_providers_with_features([:vision, :function_calling])
      # => [:openai, :anthropic, :gemini]
  """
  @spec find_providers_with_features([atom()]) :: [provider()]
  def find_providers_with_features(features) do
    # Use the new Capabilities module for normalized lookups
    features
    |> Enum.map(&ExLLM.Capabilities.normalize_capability/1)
    |> Enum.reduce(nil, fn feature, acc ->
      providers = ExLLM.Capabilities.find_providers(feature)
      if acc == nil do
        providers
      else
        # Only keep providers that support all features
        Enum.filter(acc, &(&1 in providers))
      end
    end)
    |> Kernel.||([])
  end

  @doc """
  Compare capabilities across multiple providers.

  ## Examples

      comparison = ExLLM.compare_providers([:openai, :anthropic, :ollama])
      
      # See all features across providers
      comparison.features
      # => [:streaming, :function_calling, :vision, ...]
      
      # Check specific provider capabilities
      comparison.comparison.openai.features
      # => [:streaming, :function_calling, :cost_tracking, ...]
  """
  @spec compare_providers([provider()]) :: map()
  def compare_providers(providers) do
    ProviderCapabilities.compare_providers(providers)
  end

  @doc """
  Get provider recommendations based on requirements.

  ## Parameters
  - `requirements` - Map with:
    - `:required_features` - Features that must be supported
    - `:preferred_features` - Nice-to-have features
    - `:required_endpoints` - Required API endpoints
    - `:exclude_providers` - Providers to exclude
    - `:prefer_local` - Prefer local providers (default: false)
    - `:prefer_free` - Prefer free providers (default: false)

  ## Examples

      # Find best providers for multimodal AI
      recommendations = ExLLM.recommend_providers(%{
        required_features: [:vision, :streaming],
        preferred_features: [:audio_input, :function_calling],
        exclude_providers: [:mock]
      })
      # => [
      #   %{provider: :openai, score: 0.95, matched_features: [...], missing_features: []},
      #   %{provider: :anthropic, score: 0.80, matched_features: [...], missing_features: [...]}
      # ]
      
      # Find free local providers
      recommendations = ExLLM.recommend_providers(%{
        required_features: [:chat],
        prefer_local: true,
        prefer_free: true
      })
  """
  @spec recommend_providers(map()) :: [map()]
  def recommend_providers(requirements \\ %{}) do
    ProviderCapabilities.recommend_providers(requirements)
  end

  @doc """
  List all available providers.

  ## Examples

      providers = ExLLM.list_providers()
      # => [:anthropic, :bedrock, :gemini, :groq, :local, :mock, :ollama, :openai, :openrouter]
  """
  @spec list_providers() :: [provider()]
  def list_providers do
    ProviderCapabilities.list_providers()
  end

  @doc """
  Check if a provider is local (no API calls).

  ## Examples

      ExLLM.is_local_provider?(:ollama)
      # => true
      
      ExLLM.is_local_provider?(:openai)
      # => false
  """
  @spec is_local_provider?(provider()) :: boolean()
  def is_local_provider?(provider) do
    ProviderCapabilities.is_local?(provider)
  end

  @doc """
  Check if a provider requires authentication.

  ## Examples

      ExLLM.provider_requires_auth?(:openai)
      # => true
      
      ExLLM.provider_requires_auth?(:local)
      # => false
  """
  @spec provider_requires_auth?(provider()) :: boolean()
  def provider_requires_auth?(provider) do
    ProviderCapabilities.requires_auth?(provider)
  end

  # Embeddings API

  @doc """
  Generate embeddings for text inputs.

  Embeddings are numerical representations of text that can be used for:
  - Semantic search
  - Clustering
  - Recommendations
  - Anomaly detection
  - Classification

  ## Parameters
  - `provider` - The LLM provider (`:openai`, `:anthropic`, etc.)
  - `inputs` - List of text strings to embed
  - `options` - Options including `:model`, `:dimensions`, etc.

  ## Options
  - `:model` - Embedding model to use (provider-specific)
  - `:dimensions` - Desired embedding dimensions (if supported)
  - `:cache` - Enable caching for embeddings
  - `:cache_ttl` - Cache TTL in milliseconds
  - `:track_cost` - Track embedding costs (default: true)

  ## Examples

      # Single embedding
      {:ok, response} = ExLLM.embeddings(:openai, ["Hello, world!"])
      [embedding] = response.embeddings
      # => [0.0123, -0.0456, 0.0789, ...]
      
      # Multiple embeddings
      texts = ["First text", "Second text", "Third text"]
      {:ok, response} = ExLLM.embeddings(:openai, texts,
        model: "text-embedding-3-small",
        dimensions: 256  # Reduce dimensions for storage
      )
      
      # With caching
      {:ok, response} = ExLLM.embeddings(:openai, texts,
        cache: true,
        cache_ttl: :timer.hours(24)
      )
  """
  @spec embeddings(provider(), list(String.t()), options()) ::
          {:ok, Types.EmbeddingResponse.t()} | {:error, term()}
  def embeddings(provider, inputs, options \\ []) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        # Ensure module is loaded
        Code.ensure_loaded(adapter)
        
        # Check if adapter supports embeddings
        # Note: embeddings/2 with default args exports both embeddings/1 and embeddings/2
        has_embeddings = function_exported?(adapter, :embeddings, 2) or function_exported?(adapter, :embeddings, 1)
        if has_embeddings do
          # Use cache if enabled
          # For embeddings, generate a different type of cache key
          cache_key = generate_embeddings_cache_key(provider, inputs, options)

          Cache.with_cache(cache_key, options, fn ->
            adapter.embeddings(inputs, options)
          end)
        else
          {:error, {:not_supported, "#{provider} does not support embeddings"}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List available embedding models for a provider.

  ## Examples

      {:ok, models} = ExLLM.list_embedding_models(:openai)
      Enum.each(models, fn m ->
        IO.puts("\#{m.name} - \#{m.dimensions} dimensions")
      end)
  """
  @spec list_embedding_models(provider(), options()) ::
          {:ok, list(Types.EmbeddingModel.t())} | {:error, term()}
  def list_embedding_models(provider, options \\ []) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        Code.ensure_loaded(adapter)
        if function_exported?(adapter, :list_embedding_models, 1) or function_exported?(adapter, :list_embedding_models, 0) do
          adapter.list_embedding_models(options)
        else
          # No embedding models if not supported
          {:ok, []}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Calculate similarity between two embeddings.

  Uses cosine similarity: 1.0 = identical, 0.0 = orthogonal, -1.0 = opposite

  ## Examples

      similarity = ExLLM.cosine_similarity(embedding1, embedding2)
      # => 0.87
  """
  @spec cosine_similarity(list(float()), list(float())) :: float()
  def cosine_similarity(embedding1, embedding2) when length(embedding1) == length(embedding2) do
    dot_product =
      Enum.zip(embedding1, embedding2)
      |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)

    magnitude1 = :math.sqrt(Enum.reduce(embedding1, 0.0, fn x, acc -> acc + x * x end))
    magnitude2 = :math.sqrt(Enum.reduce(embedding2, 0.0, fn x, acc -> acc + x * x end))

    if magnitude1 * magnitude2 == 0 do
      0.0
    else
      dot_product / (magnitude1 * magnitude2)
    end
  end

  def cosine_similarity(_, _) do
    raise ArgumentError, "Embeddings must have the same dimension"
  end

  @doc """
  Find the most similar items from a list of embeddings.

  ## Options
  - `:top_k` - Number of results to return (default: 5)
  - `:threshold` - Minimum similarity score (default: 0.0)

  ## Examples

      query_embedding = get_embedding("search query")
      
      items = [
        %{id: 1, text: "First doc", embedding: [...]},
        %{id: 2, text: "Second doc", embedding: [...]},
        # ...
      ]
      
      results = ExLLM.find_similar(query_embedding, items,
        top_k: 10,
        threshold: 0.7
      )
      # => [%{item: %{id: 2, ...}, similarity: 0.92}, ...]
  """
  @spec find_similar(list(float()), list(map()), keyword()) :: list(map())
  def find_similar(query_embedding, items, options \\ []) do
    top_k = Keyword.get(options, :top_k, 5)
    threshold = Keyword.get(options, :threshold, 0.0)

    items
    |> Enum.map(fn item ->
      similarity = cosine_similarity(query_embedding, item.embedding)
      %{item: item, similarity: similarity}
    end)
    |> Enum.filter(fn %{similarity: sim} -> sim >= threshold end)
    |> Enum.sort_by(& &1.similarity, :desc)
    |> Enum.take(top_k)
  end

  # Vision/Multimodal API

  @doc """
  Create a vision-enabled message with text and images.

  ## Examples

      # With image URLs
      {:ok, message} = ExLLM.vision_message("What's in these images?", [
        "https://example.com/image1.jpg",
        "https://example.com/image2.png"
      ])
      
      {:ok, response} = ExLLM.chat(:anthropic, [message])
      
      # With local images
      {:ok, message} = ExLLM.vision_message("Describe these photos", [
        "/path/to/photo1.jpg",
        "/path/to/photo2.png"
      ])
      
      # With options
      {:ok, message} = ExLLM.vision_message("Analyze this chart", 
        ["chart.png"],
        role: "user",
        detail: :high  # High detail for complex images
      )
  """
  @spec vision_message(String.t(), list(String.t()), keyword()) ::
          {:ok, Types.message()} | {:error, term()}
  def vision_message(text, image_sources, options \\ []) do
    role = Keyword.get(options, :role, "user")
    Vision.build_message(role, text, image_sources, options)
  end

  @doc """
  Load an image from file for use in vision requests.

  ## Examples

      {:ok, image_part} = ExLLM.load_image("photo.jpg")
      
      message = %{
        role: "user",
        content: [
          ExLLM.Vision.text("What's in this image?"),
          image_part
        ]
      }
  """
  @spec load_image(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def load_image(file_path, options \\ []) do
    Vision.load_image(file_path, options)
  end

  @doc """
  Check if a provider and model support vision inputs.

  ## Examples

      ExLLM.supports_vision?(:anthropic, "claude-3-opus-20240229")
      # => true
      
      ExLLM.supports_vision?(:openai, "gpt-3.5-turbo")
      # => false
  """
  @spec supports_vision?(provider(), String.t()) :: boolean()
  def supports_vision?(provider, model) do
    Vision.supports_vision?(provider) and
      Capabilities.model_supports?(provider, model, :vision)
  end

  @doc """
  Extract text from an image using vision capabilities.

  This is a convenience function for OCR-like tasks.

  ## Examples

      {:ok, text} = ExLLM.extract_text_from_image(:anthropic, "document.png")
      IO.puts(text)
      
      # With options
      {:ok, text} = ExLLM.extract_text_from_image(:openai, "handwriting.jpg",
        model: "gpt-4-turbo",
        prompt: "Extract all text, preserving formatting"
      )
  """
  @spec extract_text_from_image(provider(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def extract_text_from_image(provider, image_path, options \\ []) do
    prompt =
      Keyword.get(
        options,
        :prompt,
        "Extract all text from this image. Return only the extracted text, no additional commentary."
      )

    with {:ok, message} <- vision_message(prompt, [image_path]) do
      case chat(provider, [message], options) do
        {:ok, response} -> {:ok, response.content}
        error -> error
      end
    end
  end

  @doc """
  Analyze images with a specific prompt.

  ## Examples

      {:ok, analysis} = ExLLM.analyze_images(:anthropic,
        ["chart1.png", "chart2.png"],
        "Compare these two charts and identify key differences"
      )
  """
  @spec analyze_images(provider(), list(String.t()), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def analyze_images(provider, image_paths, prompt, options \\ []) do
    with {:ok, message} <- vision_message(prompt, image_paths, options) do
      case chat(provider, [message], options) do
        {:ok, response} -> {:ok, response.content}
        error -> error
      end
    end
  end

  # Provider detection for "provider/model" syntax
  defp detect_provider(provider_or_model, options) when is_atom(provider_or_model) do
    {provider_or_model, options}
  end

  defp detect_provider(provider_or_model, options) when is_binary(provider_or_model) do
    case String.split(provider_or_model, "/", parts: 2) do
      [provider_str, model] ->
        # Found provider/model pattern
        provider = String.to_atom(provider_str)
        if Map.has_key?(@providers, provider) do
          {provider, Keyword.put(options, :model, model)}
        else
          # Unknown provider, treat as model string
          {:openai, Keyword.put(options, :model, provider_or_model)}
        end
      [_] ->
        # No slash, treat as model for default provider
        {:openai, Keyword.put(options, :model, provider_or_model)}
    end
  end

  # Private helper for generating embeddings cache key
  defp generate_embeddings_cache_key(provider, inputs, options) do
    # Filter relevant options for embeddings
    relevant_opts =
      options
      |> Keyword.take([:model, :dimensions, :encoding_format])
      |> Enum.sort()

    # Create cache key components
    key_data = %{
      provider: provider,
      inputs: inputs,
      options: relevant_opts
    }

    # Generate deterministic hash
    :crypto.hash(:sha256, :erlang.term_to_binary(key_data))
    |> Base.encode64(padding: false)
  end
  
end
