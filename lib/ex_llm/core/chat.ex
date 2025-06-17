defmodule ExLLM.Core.Chat do
  @moduledoc """
  Core chat functionality for ExLLM.

  This module contains the primary chat operations that power ExLLM's unified
  interface. It handles regular and streaming chat requests, with automatic
  context management, retry logic, and cost tracking.

  ## Usage

  While this module can be used directly, most users should use the main ExLLM
  module which delegates to these functions.

      # Direct usage
      {:ok, response} = ExLLM.Core.Chat.chat(:anthropic, messages, options)

      # Recommended usage
      {:ok, response} = ExLLM.chat(:anthropic, messages, options)

  ## Features

  - **Context Management**: Automatic message truncation for model limits
  - **Retry Logic**: Configurable retry with exponential backoff
  - **Cost Tracking**: Automatic usage and cost calculation
  - **Structured Output**: Schema validation via instructor integration
  - **Function Calling**: Unified function calling across providers
  - **Streaming**: Real-time response streaming with recovery
  - **Caching**: Response caching for improved performance
  - **Telemetry**: Comprehensive instrumentation
  """

  alias ExLLM.{
    Core.Context,
    Core.Cost,
    Core.FunctionCalling,
    Core.Vision,
    Infrastructure.Cache,
    Infrastructure.Logger,
    Types
  }

  @type provider :: ExLLM.provider()
  @type messages :: [Types.message()]
  @type options :: keyword()

  @doc """
  Send a chat completion request to the specified LLM provider.

  This is the core chat function that handles regular (non-streaming) requests.
  It includes context management, retry logic, cost tracking, and optional
  structured output via instructor integration.

  ## Parameters
  - `provider` - The LLM provider (`:anthropic`, `:openai`, `:groq`, etc.) or a model string like "groq/llama3-70b"
  - `messages` - List of conversation messages
  - `options` - Options for the request

  ## Options
  See `ExLLM.chat/3` for complete options documentation.

  ## Returns
  `{:ok, %ExLLM.Types.LLMResponse{}}` on success, or `{:ok, struct}` when using
  response_model. Returns `{:error, reason}` on failure.
  """
  @spec chat(provider() | String.t(), messages(), options()) ::
          {:ok, Types.LLMResponse.t() | struct() | map()} | {:error, term()}
  def chat(provider_or_model, messages, options \\ []) do
    # Detect provider from model string if needed
    {provider, options} = detect_provider(provider_or_model, options)

    # Build telemetry metadata
    metadata = %{
      provider: provider,
      model: Keyword.get(options, :model, provider_or_model),
      structured_output: Keyword.has_key?(options, :response_model),
      stream: false,
      retry_enabled: Keyword.get(options, :retry, true),
      cache_enabled: Keyword.get(options, :cache, false)
    }

    # Instrument with telemetry
    ExLLM.Infrastructure.Telemetry.span([:ex_llm, :chat], metadata, fn ->
      # Check if structured output is requested
      if Keyword.has_key?(options, :response_model) do
        handle_structured_output(provider, messages, options)
      else
        handle_regular_chat(provider, messages, options)
      end
    end)
  end

  @doc """
  Send a streaming chat completion request to the specified LLM provider.

  This function handles streaming requests with optional recovery capabilities.
  It provides real-time response chunks and can automatically recover from
  interruptions.

  ## Parameters
  - `provider` - The LLM provider (`:anthropic`, `:openai`, `:ollama`)
  - `messages` - List of conversation messages
  - `options` - Options for the request

  ## Options
  Same as `chat/3`, plus:
  - `:on_chunk` - Callback function for each chunk
  - `:stream_recovery` - Enable automatic stream recovery (default: false)
  - `:recovery_strategy` - How to resume: :exact, :paragraph, or :summarize
  - `:recovery_id` - Custom ID for recovery (auto-generated if not provided)

  ## Returns
  `{:ok, stream}` on success where stream yields `%ExLLM.Types.StreamChunk{}` structs,
  `{:error, reason}` on failure.
  """
  @spec stream_chat(provider() | String.t(), messages(), options()) ::
          {:ok, Types.stream()} | {:error, term()}
  def stream_chat(provider_or_model, messages, options \\ []) do
    # Detect provider from model string if needed
    {provider, options} = detect_provider(provider_or_model, options)

    # Build telemetry metadata
    metadata = %{
      provider: provider,
      model: Keyword.get(options, :model, provider_or_model),
      stream: true,
      recovery_enabled: get_in(options, [:recovery, :enabled]) || false
    }

    # Emit stream start event
    ExLLM.Infrastructure.Telemetry.emit_stream_start(provider, metadata.model)
    start_time = System.monotonic_time()

    case get_adapter(provider) do
      {:ok, adapter} ->
        # Apply context management if enabled
        prepared_messages = prepare_messages_for_provider(provider, messages, options)

        # Check if recovery is enabled
        recovery_opts = Keyword.get(options, :recovery, [])

        result =
          if recovery_opts[:enabled] do
            execute_stream_with_recovery(adapter, provider, prepared_messages, options)
          else
            adapter.stream_chat(prepared_messages, options)
          end

        # Wrap stream to track chunks
        case result do
          {:ok, stream} ->
            wrapped_stream =
              wrap_stream_with_telemetry(stream, provider, metadata.model, start_time)

            {:ok, wrapped_stream}

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp handle_structured_output(provider, messages, options) do
    # Delegate to Instructor module if available
    if Code.ensure_loaded?(ExLLM.StructuredOutputs) and ExLLM.Core.StructuredOutputs.available?() do
      ExLLM.Core.StructuredOutputs.chat(provider, messages, options)
    else
      {:error, :instructor_not_available}
    end
  end

  defp handle_regular_chat(provider, messages, options) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        # Apply context management if enabled
        prepared_messages = prepare_messages_for_provider(provider, messages, options)

        execute_with_retry(adapter, provider, prepared_messages, options)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_with_retry(adapter, provider, prepared_messages, options) do
    # Check if retry is enabled
    if Keyword.get(options, :retry, true) do
      ExLLM.Infrastructure.Retry.with_provider_retry(
        provider,
        fn ->
          execute_chat(adapter, provider, prepared_messages, options)
        end,
        Keyword.get(options, :retry_options, [])
      )
    else
      execute_chat(adapter, provider, prepared_messages, options)
    end
  end

  defp execute_chat(adapter, provider, messages, options) do
    # Generate cache key if caching might be used
    cache_key = Cache.generate_cache_key(provider, messages, options)

    # Add provider metadata for disk persistence
    cache_options = Keyword.put(options, :provider, provider)

    # Use cache wrapper
    Cache.with_cache(cache_key, cache_options, fn ->
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

  defp get_adapter(provider) do
    providers = %{
      anthropic: ExLLM.Providers.Anthropic,
      bumblebee: ExLLM.Providers.Bumblebee,
      groq: ExLLM.Providers.Groq,
      lmstudio: ExLLM.Providers.LMStudio,
      mistral: ExLLM.Providers.Mistral,
      openai: ExLLM.Providers.OpenAI,
      openrouter: ExLLM.Providers.OpenRouter,
      ollama: ExLLM.Providers.Ollama,
      perplexity: ExLLM.Providers.Perplexity,
      bedrock: ExLLM.Providers.Bedrock,
      gemini: ExLLM.Providers.Gemini,
      xai: ExLLM.Providers.XAI,
      mock: ExLLM.Providers.Mock
    }

    case Map.get(providers, provider) do
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
          case ExLLM.default_model(provider) do
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

  defp track_response_cost(provider, response, options) do
    # Extract usage info if available
    case Map.get(response, :usage) do
      %{input_tokens: _, output_tokens: _} = usage ->
        model = Keyword.get(options, :model) || ExLLM.default_model(provider)
        cost_info = Cost.calculate(to_string(provider), model, usage)

        # Log cost info if logger is available and cost calculation succeeded
        case cost_info do
          %{total_cost: total_cost} ->
            if function_exported?(Logger, :info, 1) do
              Logger.info("LLM cost: #{Cost.format(total_cost)} for #{provider}/#{model}")
            end

            # Emit cost telemetry
            ExLLM.Infrastructure.Telemetry.emit_cost_calculated(
              provider,
              model,
              # Convert to cents
              round(total_cost * 100)
            )

            cost_info

          %{error: _} ->
            # No pricing data available, just return nil
            nil
        end

      _ ->
        nil
    end
  end

  defp execute_stream_with_recovery(adapter, _provider, messages, options) do
    # TODO: Implement StreamRecovery module
    # For now, just delegate to regular streaming
    adapter.stream_chat(messages, options)
  end

  defp wrap_stream_with_telemetry(stream, provider, model, start_time) do
    chunk_count = :counters.new(1, [])

    Stream.transform(stream, nil, fn chunk, _acc ->
      # Increment chunk counter
      :counters.add(chunk_count, 1, 1)

      # Emit chunk telemetry
      chunk_size = byte_size(chunk.content || "")
      ExLLM.Infrastructure.Telemetry.emit_stream_chunk(provider, model, chunk_size)

      # Check if stream is complete
      if chunk.finish_reason == "stop" do
        # Emit completion telemetry
        duration = System.monotonic_time() - start_time
        total_chunks = :counters.get(chunk_count, 1)

        ExLLM.Infrastructure.Telemetry.emit_stream_complete(
          provider,
          model,
          total_chunks,
          duration
        )
      end

      {[chunk], nil}
    end)
  end

  # Provider detection for "provider/model" syntax
  defp detect_provider(provider_or_model, options) when is_atom(provider_or_model) do
    {provider_or_model, options}
  end

  defp detect_provider(provider_or_model, options) when is_binary(provider_or_model) do
    providers = %{
      anthropic: ExLLM.Providers.Anthropic,
      bumblebee: ExLLM.Providers.Bumblebee,
      groq: ExLLM.Providers.Groq,
      lmstudio: ExLLM.Providers.LMStudio,
      mistral: ExLLM.Providers.Mistral,
      openai: ExLLM.Providers.OpenAI,
      openrouter: ExLLM.Providers.OpenRouter,
      ollama: ExLLM.Providers.Ollama,
      perplexity: ExLLM.Providers.Perplexity,
      bedrock: ExLLM.Providers.Bedrock,
      gemini: ExLLM.Providers.Gemini,
      xai: ExLLM.Providers.XAI,
      mock: ExLLM.Providers.Mock
    }

    case String.split(provider_or_model, "/", parts: 2) do
      [provider_str, model] ->
        # Found provider/model pattern
        provider = String.to_existing_atom(provider_str)

        if Map.has_key?(providers, provider) do
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
end
