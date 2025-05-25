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
  - `:ollama` - Local Ollama models
  - More providers coming soon!

  ## Features

  - **Unified Interface**: Same API across all providers
  - **Configuration Injection**: Flexible config management
  - **Streaming Support**: Real-time response streaming
  - **Error Standardization**: Consistent error handling
  - **No Process Dependencies**: Pure functional core
  - **Extensible**: Easy to add new providers

  ## Configuration

  ExLLM supports multiple configuration methods:

  ### Environment Variables

      export OPENAI_API_KEY="sk-..."
      export ANTHROPIC_API_KEY="api-..."
      export OLLAMA_BASE_URL="http://localhost:11434"

  ### Static Configuration

      config = %{
        openai: %{api_key: "sk-...", model: "gpt-4"},
        anthropic: %{api_key: "api-...", model: "claude-3"},
        ollama: %{base_url: "http://localhost:11434", model: "llama2"}
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

  ### Custom Configuration

      defmodule MyConfigProvider do
        @behaviour ExLLM.ConfigProvider
        
        def get([:openai, :api_key]), do: MyApp.get_secret("openai_key")
        def get(_), do: nil
        
        def get_all(), do: %{}
      end

  ## Examples

      # Simple chat
      {:ok, response} = ExLLM.chat(:openai, [
        %{role: "user", content: "What is Elixir?"}
      ])

      # With options
      {:ok, response} = ExLLM.chat(:anthropic, messages,
        model: "claude-3-haiku-20240307",
        temperature: 0.7,
        max_tokens: 1000
      )

      # Streaming
      {:ok, stream} = ExLLM.stream_chat(:openai, messages)
      for chunk <- stream do
        if chunk.content, do: IO.write(chunk.content)
      end

      # Check if provider is configured
      if ExLLM.configured?(:anthropic) do
        {:ok, response} = ExLLM.chat(:anthropic, messages)
      end

      # List available models
      {:ok, models} = ExLLM.list_models(:openai)
      Enum.each(models, fn model ->
        IO.puts(model.name)
      end)
  """

  require Logger
  alias ExLLM.{Context, Cost, Session, Types}

  @providers %{
    anthropic: ExLLM.Adapters.Anthropic,
    local: ExLLM.Adapters.Local
    # openai: ExLLM.Adapters.OpenAI,
    # ollama: ExLLM.Adapters.Ollama
  }

  @type provider :: :anthropic | :openai | :ollama | :local
  @type messages :: [Types.message()]
  @type options :: keyword()

  @doc """
  Send a chat completion request to the specified LLM provider.

  ## Parameters
  - `provider` - The LLM provider (`:anthropic`, `:openai`, `:ollama`)
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

  ## Returns
  `{:ok, %ExLLM.Types.LLMResponse{}}` on success, `{:error, reason}` on failure.

  ## Examples

      # Simple usage
      {:ok, response} = ExLLM.chat(:anthropic, [
        %{role: "user", content: "Hello!"}
      ])

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
  """
  @spec chat(provider(), messages(), options()) ::
          {:ok, Types.LLMResponse.t()} | {:error, term()}
  def chat(provider, messages, options \\ []) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        # Apply context management if enabled
        prepared_messages = prepare_messages_for_provider(provider, messages, options)
        
        result = adapter.chat(prepared_messages, options)
        
        # Track costs if enabled
        if Keyword.get(options, :track_cost, true) and match?({:ok, _}, result) do
          {:ok, response} = result
          track_response_cost(provider, response, options)
        end
        
        result

      {:error, reason} ->
        {:error, reason}
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
  @spec stream_chat(provider(), messages(), options()) ::
          {:ok, Types.stream()} | {:error, term()}
  def stream_chat(provider, messages, options \\ []) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        # Apply context management if enabled
        prepared_messages = prepare_messages_for_provider(provider, messages, options)
        
        adapter.stream_chat(prepared_messages, options)

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
      # => "$0.350¢"
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
    Context.prepare_messages(messages, options)
  end

  @doc """
  Validate that messages fit within a model's context window.

  ## Parameters
  - `messages` - List of conversation messages
  - `options` - Options including model info

  ## Returns
  `{:ok, token_count}` if valid, `{:error, reason}` if too large.

  ## Examples

      {:ok, tokens} = ExLLM.validate_context(messages, model: "claude-3-5-sonnet-20241022")
      # => {:ok, 3500}
  """
  @spec validate_context(messages(), options()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def validate_context(messages, options \\ []) do
    Context.validate_context(messages, options)
  end

  @doc """
  Get context window size for a model.

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
    Context.context_window_size(to_string(provider), model)
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
    Context.stats(messages)
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
    merged_options = Keyword.merge(
      Map.to_list(session.context || %{}),
      options
    )
    
    # Send chat request
    case chat(provider, messages, merged_options) do
      {:ok, response} ->
        # Add assistant response to session
        session = Session.add_message(session, "assistant", response.content)
        
        # Update token usage if available
        session = if response.usage do
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
    model = case Keyword.get(options, :model) do
      nil -> 
        case default_model(provider) do
          {:error, _} -> nil
          model -> model
        end
      model -> model
    end
    
    # Add provider and model info to options for context management
    context_options = options
    |> Keyword.put(:provider, to_string(provider))
    |> Keyword.put_new(:model, model)
    
    Context.prepare_messages(messages, context_options)
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
end
