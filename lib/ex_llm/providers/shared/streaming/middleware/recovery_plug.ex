defmodule ExLLM.Providers.Shared.Streaming.Middleware.RecoveryPlug do
  @moduledoc """
  Tesla middleware for streaming error recovery and automatic resumption.

  This middleware provides automatic recovery capabilities for streaming operations,
  integrating with the existing StreamRecovery GenServer to save partial responses
  and enable resumption strategies.

  ## Features

  - **Automatic State Saving**: Saves streaming state and chunks for recovery
  - **Error Detection**: Identifies recoverable vs non-recoverable errors
  - **Resumption Strategies**: Multiple strategies (exact, paragraph, summarize)
  - **Provider-Aware**: Handles provider-specific recovery logic
  - **Configurable Recovery**: Enable/disable and configure recovery behavior
  - **Automatic Cleanup**: Manages recovery state lifecycle

  ## Usage

  The middleware is automatically included when recovery is enabled:

  ```elixir
  client = Streaming.Engine.client(
    provider: :openai,
    api_key: "sk-...",
    enable_recovery: true
  )
  ```

  ## Configuration

  Configure via Tesla client options:

  ```elixir
  Tesla.client([
    {RecoveryPlug, [
      enabled: true,
      strategy: :paragraph,  # :exact | :paragraph | :summarize
      ttl: :timer.minutes(30),
      auto_resume: true,
      max_resume_attempts: 3
    ]}
  ])
  ```

  ## Recovery Strategies

  - `:exact` - Continue from exact cutoff point
  - `:paragraph` - Regenerate from last complete paragraph  
  - `:summarize` - Summarize received content and continue

  ## Integration with StreamRecovery

  This middleware delegates actual recovery state management to the
  `ExLLM.Core.Streaming.Recovery` GenServer, ensuring consistent
  recovery behavior across the system.
  """

  @behaviour Tesla.Middleware

  alias ExLLM.Core.Streaming.Recovery
  alias ExLLM.Infrastructure.Logger
  alias ExLLM.Types.StreamChunk

  # Default configuration
  @default_enabled true
  @default_strategy :paragraph
  @default_ttl :timer.minutes(30)
  @default_auto_resume true
  @default_max_resume_attempts 3

  @impl Tesla.Middleware
  def call(%Tesla.Env{opts: opts} = env, next, middleware_opts) do
    # Check if recovery is enabled
    enabled = get_option(opts, middleware_opts, :enabled, @default_enabled)

    if enabled && streaming_request?(env, opts) do
      call_with_recovery(env, next, middleware_opts)
    else
      # Recovery disabled or not a streaming request
      Tesla.run(env, next)
    end
  end

  defp call_with_recovery(%Tesla.Env{opts: opts} = env, next, middleware_opts) do
    stream_context = Keyword.get(opts, :stream_context)

    if stream_context && recovery_enabled?() do
      # Initialize recovery for this stream
      setup_recovery(env, next, stream_context, middleware_opts)
    else
      # No stream context or recovery process not running
      Tesla.run(env, next)
    end
  end

  # NOTE: Defensive error handling - init_recovery currently only returns {:ok, id}
  # but this error clause provides safety if the function changes in future versions
  defp setup_recovery(env, next, stream_context, middleware_opts) do
    # Extract recovery configuration
    strategy = get_option(env.opts, middleware_opts, :strategy, @default_strategy)
    auto_resume = get_option(env.opts, middleware_opts, :auto_resume, @default_auto_resume)

    max_attempts =
      get_option(env.opts, middleware_opts, :max_resume_attempts, @default_max_resume_attempts)

    # Initialize recovery with StreamRecovery GenServer
    provider = stream_context[:provider] || :unknown
    messages = extract_messages_from_context(stream_context)
    recovery_opts = build_recovery_options(stream_context, middleware_opts)

    # NOTE: Defensive error handling - init_recovery currently only returns {:ok, id}
    # If error handling is needed in future, add appropriate clause here
    {:ok, recovery_id} = Recovery.init_recovery(provider, messages, recovery_opts)

    Logger.debug("Stream recovery initialized: #{recovery_id}")

    # Wrap the stream context with recovery capabilities
    enhanced_context = enhance_stream_context(stream_context, recovery_id, strategy)

    # Execute the request with recovery monitoring
    execute_with_recovery_monitoring(
      env,
      next,
      enhanced_context,
      recovery_id,
      auto_resume,
      max_attempts,
      0
    )
  end

  defp execute_with_recovery_monitoring(
         env,
         next,
         stream_context,
         recovery_id,
         auto_resume,
         max_attempts,
         attempt
       ) do
    # Update env with enhanced stream context
    env_with_recovery = %{env | opts: Keyword.put(env.opts, :stream_context, stream_context)}

    # Execute the streaming request
    case Tesla.run(env_with_recovery, next) do
      {:ok, response} ->
        # Stream completed successfully
        Recovery.complete_stream(recovery_id)
        Logger.debug("Stream #{recovery_id} completed successfully")
        {:ok, response}

      {:error, reason} = error ->
        # Record the error
        case Recovery.record_error(recovery_id, map_error_reason(reason)) do
          {:ok, true} when auto_resume and attempt < max_attempts ->
            # Error is recoverable and auto-resume is enabled
            Logger.info(
              "Stream #{recovery_id} error is recoverable, attempting resume (#{attempt + 1}/#{max_attempts})"
            )

            # Wait before resuming
            :timer.sleep(calculate_resume_delay(attempt))

            # Attempt to resume
            case resume_stream(recovery_id, stream_context, env, next) do
              {:ok, resumed_response} ->
                {:ok, resumed_response}

              {:error, _resume_error} ->
                # Resume failed, try again
                execute_with_recovery_monitoring(
                  env,
                  next,
                  stream_context,
                  recovery_id,
                  auto_resume,
                  max_attempts,
                  attempt + 1
                )
            end

          {:ok, false} ->
            # Error is not recoverable
            Logger.debug("Stream #{recovery_id} error is not recoverable: #{inspect(reason)}")
            Recovery.complete_stream(recovery_id)
            error

          _ ->
            # Recovery recording failed or max attempts reached
            Recovery.complete_stream(recovery_id)
            error
        end
    end
  end

  defp enhance_stream_context(stream_context, recovery_id, strategy) do
    # Get the original callback
    original_callback = stream_context.callback

    # Create a wrapped callback that saves chunks for recovery
    wrapped_callback = fn chunk ->
      # Save chunk for recovery
      if valid_chunk?(chunk) do
        # Ensure chunk is in the expected format for Recovery
        formatted_chunk =
          case chunk do
            %StreamChunk{} = c ->
              c

            %{content: content, finish_reason: finish_reason} ->
              %StreamChunk{content: content, finish_reason: finish_reason}

            _ ->
              chunk
          end

        Recovery.record_chunk(recovery_id, formatted_chunk)
      end

      # Call original callback
      original_callback.(chunk)
    end

    # Add recovery metadata to context
    stream_context
    |> Map.put(:callback, wrapped_callback)
    |> Map.put(:recovery_id, recovery_id)
    |> Map.put(:recovery_strategy, strategy)
  end

  defp resume_stream(recovery_id, stream_context, original_env, next) do
    strategy = Map.get(stream_context, :recovery_strategy, @default_strategy)

    case Recovery.resume_stream(recovery_id, strategy: strategy) do
      {:error, :streaming_recovery_needs_refactoring} ->
        # The recovery system needs updating for the new streaming API
        # For now, we'll implement a simple continuation
        handle_simple_resume(recovery_id, stream_context, original_env, next)

      {:ok, resumed_stream} ->
        {:ok, resumed_stream}

      error ->
        error
    end
  end

  # NOTE: Defensive error handling - init_recovery currently only returns {:ok, id}
  # but this error clause provides safety if the function changes in future versions
  defp handle_simple_resume(recovery_id, stream_context, original_env, next) do
    # Get partial response chunks
    case Recovery.get_partial_response(recovery_id) do
      {:ok, chunks} when is_list(chunks) and length(chunks) > 0 ->
        # Build continuation context
        content_so_far =
          chunks
          |> Enum.map(& &1.content)
          |> Enum.join("")

        # Modify the request to continue from where it left off
        modified_env =
          modify_request_for_continuation(original_env, content_so_far, stream_context)

        # Create new recovery ID for the resumed stream
        # NOTE: Defensive error handling - init_recovery currently only returns {:ok, id}
        # If error handling is needed in future, add appropriate clause here
        {:ok, new_recovery_id} =
          Recovery.init_recovery(
            stream_context[:provider] || :unknown,
            extract_messages_from_context(stream_context),
            model: stream_context[:model]
          )

        # Update stream context with new recovery ID
        new_context = Map.put(stream_context, :recovery_id, new_recovery_id)

        new_env = %{
          modified_env
          | opts: Keyword.put(modified_env.opts, :stream_context, new_context)
        }

        # Execute the resumed request
        Tesla.run(new_env, next)

      _ ->
        # No chunks to resume from
        {:error, :no_partial_response}
    end
  end

  @doc false
  def modify_request_for_continuation(env, content_so_far, stream_context) do
    provider = stream_context[:provider] || :unknown

    # Provider-specific request modification
    case provider do
      :openai -> modify_openai_request(env, content_so_far)
      :anthropic -> modify_anthropic_request(env, content_so_far)
      :gemini -> modify_gemini_request(env, content_so_far)
      # Unknown provider, return unchanged
      _ -> env
    end
  end

  defp modify_openai_request(%{body: body} = env, content_so_far) when is_map(body) do
    # Add a system message about continuation
    continuation_message = %{
      "role" => "system",
      "content" =>
        "Previous partial response: #{content_so_far}\n\nPlease continue from where you left off."
    }

    # Update messages
    updated_messages = Map.get(body, "messages", []) ++ [continuation_message]
    updated_body = Map.put(body, "messages", updated_messages)

    %{env | body: updated_body}
  end

  defp modify_openai_request(env, _content_so_far), do: env

  defp modify_anthropic_request(%{body: body} = env, content_so_far) when is_map(body) do
    # Similar to OpenAI but with Anthropic's format
    continuation_message = %{
      "role" => "assistant",
      "content" => content_so_far
    }

    user_continuation = %{
      "role" => "user",
      "content" => "Continue from where you left off."
    }

    updated_messages = Map.get(body, "messages", []) ++ [continuation_message, user_continuation]
    updated_body = Map.put(body, "messages", updated_messages)

    %{env | body: updated_body}
  end

  defp modify_anthropic_request(env, _content_so_far), do: env

  defp modify_gemini_request(%{body: body} = env, content_so_far) when is_map(body) do
    # Gemini uses contents array
    continuation_content = %{
      "role" => "model",
      "parts" => [%{"text" => content_so_far}]
    }

    user_continuation = %{
      "role" => "user",
      "parts" => [%{"text" => "Continue from where you left off."}]
    }

    updated_contents = Map.get(body, "contents", []) ++ [continuation_content, user_continuation]
    updated_body = Map.put(body, "contents", updated_contents)

    %{env | body: updated_body}
  end

  defp modify_gemini_request(env, _content_so_far), do: env

  # Helper functions

  defp streaming_request?(%{opts: opts}, _middleware_opts) do
    # Check if this is a streaming request
    Keyword.has_key?(opts, :stream_context)
  end

  defp recovery_enabled? do
    # Check if StreamRecovery process is running
    Process.whereis(Recovery) != nil
  end

  defp extract_messages_from_context(%{messages: messages}) when is_list(messages), do: messages
  defp extract_messages_from_context(%{request: %{"messages" => messages}}), do: messages
  defp extract_messages_from_context(%{request: %{"contents" => contents}}), do: contents
  defp extract_messages_from_context(_), do: []

  defp build_recovery_options(stream_context, middleware_opts) do
    [
      model: Map.get(stream_context, :model),
      provider: Map.get(stream_context, :provider),
      strategy: Keyword.get(middleware_opts, :strategy, @default_strategy),
      ttl: Keyword.get(middleware_opts, :ttl, @default_ttl)
    ]
  end

  defp valid_chunk?(%StreamChunk{} = chunk) do
    chunk.content != nil || chunk.finish_reason != nil
  end

  defp valid_chunk?(%{content: _}), do: true
  defp valid_chunk?(%{finish_reason: _}), do: true
  defp valid_chunk?(_), do: false

  defp map_error_reason({:closed, _}), do: {:network_error, :connection_closed}
  defp map_error_reason({:timeout, _}), do: {:timeout, :request_timeout}
  defp map_error_reason({:error, :timeout}), do: {:timeout, :request_timeout}
  defp map_error_reason({:error, :closed}), do: {:network_error, :connection_closed}
  defp map_error_reason({:error, :econnrefused}), do: {:network_error, :connection_refused}
  defp map_error_reason({:error, reason}), do: {:network_error, reason}
  defp map_error_reason(reason), do: {:unknown_error, reason}

  defp calculate_resume_delay(attempt) do
    # Exponential backoff: 1s, 2s, 4s, 8s...
    base_delay = 1000
    max_delay = 30_000

    delay = (base_delay * :math.pow(2, attempt)) |> round()
    min(delay, max_delay)
  end

  defp get_option(env_opts, middleware_opts, key, default) do
    # First check env opts (runtime), then middleware opts (compile time), then default
    Keyword.get(env_opts, key, Keyword.get(middleware_opts, key, default))
  end
end
