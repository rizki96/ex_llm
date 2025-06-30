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
    Pipeline,
    Pipeline.Request,
    Pipelines.StandardProvider,
    Types
  }

  @type provider :: ExLLM.Types.provider()
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

    # Use pipeline system for all providers
    case build_pipeline_for_provider(provider) do
      {:ok, pipeline} ->
        # Apply context management if enabled
        prepared_messages = prepare_messages_for_provider(provider, messages, options)

        # Check if recovery is enabled
        recovery_opts = Keyword.get(options, :recovery, [])

        result =
          if recovery_opts[:enabled] do
            execute_stream_with_pipeline_recovery(pipeline, provider, prepared_messages, options)
          else
            execute_stream_with_pipeline(pipeline, provider, prepared_messages, options)
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
    if Code.ensure_loaded?(ExLLM.Core.StructuredOutputs) and
         ExLLM.Core.StructuredOutputs.available?() do
      ExLLM.Core.StructuredOutputs.chat(provider, messages, options)
    else
      {:error, :instructor_not_available}
    end
  end

  defp handle_regular_chat(provider, messages, options) do
    # Use pipeline system for all providers
    case build_pipeline_for_provider(provider) do
      {:ok, pipeline} ->
        # Apply context management if enabled
        prepared_messages = prepare_messages_for_provider(provider, messages, options)

        execute_with_pipeline_retry(pipeline, provider, prepared_messages, options)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_with_pipeline_retry(pipeline, provider, prepared_messages, options) do
    # Check if retry is enabled
    if Keyword.get(options, :retry, true) do
      ExLLM.Infrastructure.Retry.with_provider_retry(
        provider,
        fn ->
          execute_pipeline_chat(pipeline, provider, prepared_messages, options)
        end,
        Keyword.get(options, :retry_options, [])
      )
    else
      execute_pipeline_chat(pipeline, provider, prepared_messages, options)
    end
  end

  defp execute_pipeline_chat(pipeline, provider, messages, options) do
    # Generate cache key if caching might be used
    cache_key = Cache.generate_cache_key(provider, messages, options)

    # Add provider metadata for disk persistence
    cache_options = Keyword.put(options, :provider, provider)

    # Use cache wrapper
    Cache.with_cache(cache_key, cache_options, fn ->
      # Check if function calling is requested
      options = prepare_function_calling(provider, options)

      # Create pipeline request and execute
      request = Request.new(provider, messages, options)
      result = Pipeline.run(request, pipeline)

      # Extract response from pipeline result
      case result.state do
        :completed ->
          response = result.result

          # Track costs if enabled
          if Keyword.get(options, :track_cost, true) do
            cost_info = track_response_cost(provider, response, options)
            # If cost_info is a map with total_cost, extract just the float value
            cost_value =
              case cost_info do
                %{total_cost: total} -> total
                nil -> nil
                cost when is_float(cost) -> cost
                _ -> 0.0
              end

            response_with_cost = Map.put(response, :cost, cost_value)
            {:ok, response_with_cost}
          else
            {:ok, response}
          end

        :error ->
          case result.errors do
            [%{error: error} | _] -> {:error, error}
            [%{reason: reason} | _] -> {:error, reason}
            [%{message: message} | _] -> {:error, message}
            [] -> {:error, :pipeline_failed}
          end

        _other ->
          {:error, :unexpected_pipeline_state}
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

  defp build_pipeline_for_provider(provider) do
    # Define provider plugs for providers that have been migrated to pipeline system
    provider_plugs = %{
      openai: [
        build_request: {ExLLM.Plugs.Providers.OpenAIPrepareRequest, []},
        parse_response: {ExLLM.Providers.OpenAI.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.OpenAIParseStreamResponse, []}
      ],
      anthropic: [
        build_request: {ExLLM.Plugs.Providers.AnthropicPrepareRequest, []},
        parse_response: {ExLLM.Providers.Anthropic.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.AnthropicParseStreamResponse, []}
      ],
      groq: [
        build_request: {ExLLM.Providers.Groq.BuildRequest, []},
        parse_response: {ExLLM.Providers.Groq.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.GroqParseStreamResponse, []}
      ],
      lmstudio: [
        build_request: {ExLLM.Providers.LMStudio.BuildRequest, []},
        parse_response: {ExLLM.Providers.LMStudio.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.LMStudioParseStreamResponse, []}
      ],
      xai: [
        build_request: {ExLLM.Providers.XAI.BuildRequest, []},
        parse_response: {ExLLM.Providers.XAI.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.XAIParseStreamResponse, []}
      ],
      mistral: [
        build_request: {ExLLM.Providers.Mistral.BuildRequest, []},
        parse_response: {ExLLM.Providers.Mistral.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.MistralParseStreamResponse, []}
      ],
      ollama: [
        build_request: {ExLLM.Providers.Ollama.BuildRequest, []},
        parse_response: {ExLLM.Providers.Ollama.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.OllamaParseStreamResponse, []}
      ],
      openrouter: [
        build_request: {ExLLM.Providers.OpenRouter.BuildRequest, []},
        parse_response: {ExLLM.Providers.OpenRouter.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.OpenRouterParseStreamResponse, []}
      ],
      perplexity: [
        build_request: {ExLLM.Providers.Perplexity.BuildRequest, []},
        parse_response: {ExLLM.Providers.Perplexity.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.PerplexityParseStreamResponse, []}
      ],
      gemini: [
        build_request: {ExLLM.Providers.Gemini.BuildRequest, []},
        parse_response: {ExLLM.Providers.Gemini.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.GeminiParseStreamResponse, []}
      ],
      bumblebee: [
        build_request: {ExLLM.Providers.Bumblebee.BuildRequest, []},
        execute_request: {ExLLM.Plugs.ExecuteLocal, []},
        parse_response: {ExLLM.Providers.Bumblebee.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.BumblebeeParseStreamResponse, []}
      ],
      bedrock: [
        build_request: {ExLLM.Providers.Bedrock.BuildRequest, []},
        auth_request: {ExLLM.Plugs.AWSAuth, []},
        parse_response: {ExLLM.Providers.Bedrock.ParseResponse, []},
        stream_parse_response: {ExLLM.Plugs.Providers.BedrockParseStreamResponse, []}
      ],
      mock: [
        build_request: {ExLLM.Plugs.Providers.MockHandler, []},
        execute_request: {ExLLM.Plugs.Providers.MockHandler, []},
        parse_response: {ExLLM.Plugs.Providers.MockHandler, []},
        stream_parse_response: {ExLLM.Plugs.Providers.MockHandler, []}
      ]
    }

    case Map.get(provider_plugs, provider) do
      nil ->
        {:error, {:unsupported_provider, provider}}

      plugs ->
        pipeline = StandardProvider.build(plugs)
        {:ok, pipeline}
    end
  end

  defp prepare_messages_for_provider(provider, messages, options) do
    # Get model from options or use default
    model = Keyword.get(options, :model) || ExLLM.default_model(provider)

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
    # Guard against nil response
    case response do
      nil ->
        nil

      response ->
        # Extract usage info if available
        case Map.get(response, :usage) do
          usage when is_map(usage) ->
            # Normalize usage keys - different providers use different naming
            normalized_usage = %{
              input_tokens: usage[:input_tokens] || usage[:prompt_tokens] || 0,
              output_tokens: usage[:output_tokens] || usage[:completion_tokens] || 0
            }

            model = Keyword.get(options, :model) || ExLLM.default_model(provider)
            cost_info = Cost.calculate(to_string(provider), model, normalized_usage)

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

                # Return the full cost info map
                cost_info

              %{error: error_msg} ->
                # Log error but don't fail - return 0 cost
                if function_exported?(Logger, :warning, 1) do
                  Logger.warning("Cost calculation failed: #{error_msg}")
                end

                0.0
            end

          _ ->
            nil
        end
    end
  end

  defp execute_stream_with_pipeline(pipeline, provider, messages, options) do
    # Create pipeline request with streaming enabled
    options = Keyword.put(options, :stream, true)
    request = Request.new(provider, messages, options)

    # Execute pipeline in streaming mode
    Pipeline.stream(request, pipeline)
  end

  defp execute_stream_with_pipeline_recovery(pipeline, provider, messages, options) do
    recovery_opts = Keyword.get(options, :recovery, [])

    # Create a function that starts the stream
    stream_fn = fn resume_opts ->
      # Merge resume options with original options
      stream_options =
        options
        |> Keyword.delete(:recovery)
        |> Keyword.merge(resume_opts)
        |> Keyword.put(:stream, true)

      # Create request and execute pipeline
      request = Request.new(provider, messages, stream_options)

      case Pipeline.stream(request, pipeline) do
        {:ok, stream} ->
          # Convert stream to a process that sends chunks
          pid =
            spawn_link(fn ->
              recovery_pid = Keyword.get(resume_opts, :stream_recovery_pid)
              _stream_ref = Keyword.get(resume_opts, :stream_ref)

              try do
                Enum.each(stream, fn chunk ->
                  if recovery_pid do
                    send(recovery_pid, {:stream_chunk, chunk})
                  end
                end)

                if recovery_pid do
                  send(recovery_pid, {:stream_complete})
                end
              catch
                kind, reason ->
                  if recovery_pid do
                    send(recovery_pid, {:stream_error, {kind, reason}})
                  end
              end
            end)

          {:ok, pid}

        error ->
          error
      end
    end

    # Create callback function
    callback = Keyword.get(options, :on_chunk, &default_chunk_callback/1)

    # Start recoverable stream
    case ExLLM.Infrastructure.Streaming.StreamRecovery.start_stream(
           stream_fn,
           callback,
           recovery_opts
         ) do
      {:ok, recovery_pid} ->
        # Create a stream that reads from the recovery process
        stream =
          Stream.resource(
            fn -> recovery_pid end,
            fn pid ->
              receive do
                {:stream_chunk, _ref, chunk} -> {[chunk], pid}
                {:stream_complete} -> {:halt, pid}
                {:stream_error, error} -> {[{:error, {:stream_error, error}}], pid}
              after
                30_000 -> {[{:error, :stream_timeout}], pid}
              end
            end,
            fn pid -> ExLLM.Infrastructure.Streaming.StreamRecovery.stop_stream(pid) end
          )

        {:ok, stream}

      error ->
        error
    end
  end

  defp default_chunk_callback(_chunk) do
    # Default callback does nothing, just for compatibility
    :ok
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
    # Safe provider lookup - string keys to avoid atom creation
    provider_strings = %{
      "anthropic" => :anthropic,
      "bumblebee" => :bumblebee,
      "groq" => :groq,
      "lmstudio" => :lmstudio,
      "mistral" => :mistral,
      "openai" => :openai,
      "openrouter" => :openrouter,
      "ollama" => :ollama,
      "perplexity" => :perplexity,
      "bedrock" => :bedrock,
      "gemini" => :gemini,
      "xai" => :xai,
      "mock" => :mock
    }

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
        # Validate provider string BEFORE any atom conversion
        case Map.get(provider_strings, provider_str) do
          nil ->
            # Unknown provider, treat as model string
            {:openai, Keyword.put(options, :model, provider_or_model)}

          provider_atom ->
            # Valid provider, check if module exists
            if Map.has_key?(providers, provider_atom) do
              {provider_atom, Keyword.put(options, :model, model)}
            else
              # Should not happen, but defensive
              {:openai, Keyword.put(options, :model, provider_or_model)}
            end
        end

      [_] ->
        # No slash, treat as model for default provider
        {:openai, Keyword.put(options, :model, provider_or_model)}
    end
  end
end
