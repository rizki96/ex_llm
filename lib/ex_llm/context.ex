defmodule ExLLM.Context do
  @moduledoc """
  Context management for LLM conversations.

  Provides utilities for managing conversation context windows, including:
  - Token counting and estimation
  - Message truncation strategies
  - Context window validation
  - System prompt preservation
  """

  alias ExLLM.{Cost, Types}

  @default_max_tokens 4_096
  @reserve_tokens 500

  # Model context windows (as of January 2025)
  @model_contexts %{
    "anthropic" => %{
      "claude-3-5-sonnet-20241022" => 200_000,
      "claude-3-5-haiku-20241022" => 200_000,
      "claude-3-opus-20240229" => 200_000,
      "claude-3-sonnet-20240229" => 200_000,
      "claude-3-haiku-20240307" => 200_000,
      "claude-sonnet-4-20250514" => 200_000,
      "claude-4" => 200_000
    },
    "openai" => %{
      "gpt-4-turbo" => 128_000,
      "gpt-4-turbo-preview" => 128_000,
      "gpt-4" => 8_192,
      "gpt-4-32k" => 32_768,
      "gpt-3.5-turbo" => 16_385,
      "gpt-3.5-turbo-16k" => 16_385,
      "gpt-4o" => 128_000,
      "gpt-4o-mini" => 128_000
    },
    "gemini" => %{
      "gemini-pro" => 32_768,
      "gemini-pro-vision" => 32_768,
      "gemini-ultra" => 1_048_576,
      "gemini-nano" => 32_768
    },
    "bedrock" => %{
      "claude-instant-v1" => 100_000,
      "claude-v2" => 200_000,
      "claude-v2.1" => 200_000,
      "claude-3-sonnet" => 200_000,
      "claude-3-haiku" => 200_000,
      "titan-lite" => 4_096,
      "titan-express" => 8_192,
      "llama2-13b" => 4_096,
      "llama2-70b" => 4_096,
      "command" => 4_096,
      "command-light" => 4_096,
      "jurassic-2-mid" => 8_192,
      "jurassic-2-ultra" => 8_192,
      "mistral-7b" => 32_768,
      "mixtral-8x7b" => 32_768
    },
    "ollama" => %{
      "llama2" => 4_096,
      "mistral" => 8_192,
      "codellama" => 16_384
    }
  }

  @doc """
  Prepare messages for sending to LLM, managing context window.

  ## Options
  - `:max_tokens` - Maximum context window size (defaults to model's limit)
  - `:system_prompt` - System prompt to prepend
  - `:strategy` - Truncation strategy (`:sliding_window`, `:smart`, `:none`)
  - `:preserve_system` - Always keep system messages (default: true)
  - `:reserve_tokens` - Tokens to reserve for response (default: 500)

  ## Examples

      messages = [
        %{role: "system", content: "You are helpful."},
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi!"}
      ]

      # Auto-detect context window for model
      prepared = ExLLM.Context.prepare_messages(messages, 
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      )

      # Manual context limit
      prepared = ExLLM.Context.prepare_messages(messages,
        max_tokens: 4096,
        strategy: :smart
      )
  """
  @spec prepare_messages([Types.message()], keyword()) :: [Types.message()]
  def prepare_messages(messages, options \\ []) do
    max_tokens = determine_max_tokens(options)
    system_prompt = Keyword.get(options, :system_prompt)
    strategy = Keyword.get(options, :strategy, :sliding_window)
    preserve_system = Keyword.get(options, :preserve_system, true)
    reserve_tokens = Keyword.get(options, :reserve_tokens, @reserve_tokens)

    # Calculate available tokens, but ensure we have at least some room
    # For very small max_tokens, reduce the reserve proportionally
    actual_reserve = if max_tokens < 1000 do
      div(max_tokens, 4)  # Reserve 25% for small contexts
    else
      reserve_tokens
    end
    
    available_tokens = max(50, max_tokens - actual_reserve)

    # Add system prompt if provided
    messages_with_system =
      if system_prompt do
        system_message = %{role: "system", content: system_prompt}
        [system_message | messages]
      else
        messages
      end

    # Apply truncation strategy
    case strategy do
      :sliding_window ->
        sliding_window_truncate(messages_with_system, available_tokens, preserve_system)

      :smart ->
        smart_truncate(messages_with_system, available_tokens, preserve_system)

      :none ->
        messages_with_system

      _ ->
        messages_with_system
    end
  end

  @doc """
  Check if messages fit within context window.

  ## Parameters
  - `provider` - LLM provider
  - `model` - Model name
  - `messages` - Messages to check

  ## Returns
  `{:ok, true}` if fits, `{:ok, false}` if not, `{:error, reason}` if unknown model.

  ## Examples

      {:ok, fits} = ExLLM.Context.fits_context?(:anthropic, "claude-3-5-sonnet-20241022", messages)
  """
  @spec fits_context?(atom() | String.t(), String.t(), [Types.message()], keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def fits_context?(provider, model, messages, options \\ []) do
    reserve_tokens = Keyword.get(options, :reserve_tokens, @reserve_tokens)

    case get_context_window(provider, model) do
      nil ->
        {:error, "Unknown model context window for #{provider}/#{model}"}

      window ->
        tokens = Cost.estimate_tokens(messages)
        {:ok, tokens + reserve_tokens <= window}
    end
  end

  @doc """
  Get context window size for a model.

  ## Examples

      window = ExLLM.Context.get_context_window(:openai, "gpt-4")
      # => 8192
  """
  @spec get_context_window(atom() | String.t(), String.t()) :: non_neg_integer() | nil
  def get_context_window(provider, model) do
    provider_str = to_string(provider)

    @model_contexts
    |> Map.get(provider_str, %{})
    |> Map.get(model)
  end

  @doc """
  Get context statistics for messages.

  ## Returns
  Map with message count, token usage, and percentages.

  ## Examples

      stats = ExLLM.Context.get_stats(messages, max_tokens: 4096)
      # => %{
      #   message_count: 10,
      #   estimated_tokens: 1234,
      #   max_tokens: 4096,
      #   tokens_used_percentage: 30.1,
      #   tokens_remaining: 2362
      # }
  """
  @spec get_stats([Types.message()], keyword()) :: map()
  def get_stats(messages, options \\ []) do
    max_tokens = determine_max_tokens(options)
    reserve_tokens = Keyword.get(options, :reserve_tokens, @reserve_tokens)
    total_tokens = Cost.estimate_tokens(messages)

    %{
      message_count: length(messages),
      estimated_tokens: total_tokens,
      max_tokens: max_tokens,
      tokens_used_percentage: Float.round(total_tokens / max_tokens * 100, 1),
      tokens_remaining: max(0, max_tokens - total_tokens - reserve_tokens)
    }
  end

  @doc """
  List all models with their context windows.

  ## Examples

      models = ExLLM.Context.list_model_contexts()
      # => [
      #   %{provider: "anthropic", model: "claude-3-5-sonnet-20241022", context_window: 200000},
      #   ...
      # ]
  """
  @spec list_model_contexts() :: [map()]
  def list_model_contexts do
    for {provider, models} <- @model_contexts,
        {model, window} <- models do
      %{
        provider: provider,
        model: model,
        context_window: window
      }
    end
    |> Enum.sort_by(&{&1.provider, &1.model})
  end

  @doc """
  Find models with context windows above a certain size.

  ## Examples

      # Find models with at least 100k token context
      large_models = ExLLM.Context.find_models_by_context(min_tokens: 100_000)
  """
  @spec find_models_by_context(keyword()) :: [map()]
  def find_models_by_context(options \\ []) do
    min_tokens = Keyword.get(options, :min_tokens, 0)
    max_tokens = Keyword.get(options, :max_tokens, nil)

    list_model_contexts()
    |> Enum.filter(fn model ->
      model.context_window >= min_tokens &&
        (is_nil(max_tokens) || model.context_window <= max_tokens)
    end)
  end

  @doc """
  Validate that messages fit within a model's context window.

  ## Options
  - `:provider` - LLM provider name
  - `:model` - Model name
  - `:max_tokens` - Override default context window

  ## Returns
  `{:ok, token_count}` if valid, `{:error, {:context_too_large, details}}` if too large.
  """
  @spec validate_context([Types.message()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, {:context_too_large, map()}}
  def validate_context(messages, options \\ []) do
    token_count = calculate_total_tokens(messages)
    max_tokens = determine_max_tokens(options)
    
    if token_count <= max_tokens do
      {:ok, token_count}
    else
      {:error, {:context_too_large, %{
        tokens: token_count,
        max_tokens: max_tokens,
        overflow: token_count - max_tokens
      }}}
    end
  end

  @doc """
  Get context window size for a specific model.

  ## Parameters
  - `provider` - LLM provider name (string)
  - `model` - Model name

  ## Returns
  Context window size in tokens or nil if unknown.
  """
  @spec context_window_size(String.t(), String.t()) :: non_neg_integer() | nil
  def context_window_size(provider, model) do
    case @model_contexts[provider] do
      nil -> nil
      models -> Map.get(models, model)
    end
  end

  @doc """
  Get statistics about message context usage.

  ## Parameters
  - `messages` - List of conversation messages

  ## Returns
  Map with detailed statistics.
  """
  @spec stats([Types.message()]) :: map()
  def stats(messages) do
    message_count = length(messages)
    total_tokens = calculate_total_tokens(messages)
    
    by_role = Enum.reduce(messages, %{}, fn msg, acc ->
      role = to_string(msg.role)
      Map.update(acc, role, 1, &(&1 + 1))
    end)
    
    avg_tokens = if message_count > 0 do
      div(total_tokens, message_count)
    else
      0
    end
    
    %{
      message_count: message_count,
      total_tokens: total_tokens,
      by_role: by_role,
      avg_tokens_per_message: avg_tokens
    }
  end

  @doc """
  Truncate messages to fit within token limit.

  ## Parameters
  - `messages` - List of messages
  - `options` - Options including `:max_tokens`

  ## Returns
  Truncated list of messages.
  """
  @spec truncate_messages([Types.message()], keyword()) :: [Types.message()]
  def truncate_messages(messages, options \\ []) do
    max_tokens = Keyword.get(options, :max_tokens, 4096)
    
    # If single message exceeds limit, truncate its content
    if length(messages) == 1 do
      [message] = messages
      tokens = Cost.estimate_tokens(message.content)
      
      if tokens > max_tokens do
        # Rough approximation: 4 chars per token
        max_chars = max_tokens * 3
        truncated_content = String.slice(message.content, 0, max_chars) <> "..."
        [%{message | content: truncated_content}]
      else
        messages
      end
    else
      # Use sliding window for multiple messages
      sliding_window_truncate(messages, max_tokens, false)
    end
  end

  # Private functions

  defp calculate_total_tokens(messages) do
    Enum.reduce(messages, 0, fn msg, acc ->
      content_tokens = Cost.estimate_tokens(msg.content)
      role_tokens = 3  # Approximate tokens for role metadata
      acc + content_tokens + role_tokens
    end)
  end

  defp determine_max_tokens(options) do
    cond do
      # Explicit max_tokens takes precedence
      options[:max_tokens] ->
        options[:max_tokens]

      # Try to get from provider/model
      options[:provider] && options[:model] ->
        get_context_window(options[:provider], options[:model]) || @default_max_tokens

      # Default
      true ->
        @default_max_tokens
    end
  end

  defp sliding_window_truncate(messages, available_tokens, preserve_system) do
    if preserve_system do
      {system_msgs, other_msgs} = Enum.split_with(messages, &(&1.role == "system"))
      system_tokens = Cost.estimate_tokens(system_msgs)
      remaining_tokens = max(0, available_tokens - system_tokens)

      truncated_others = do_sliding_window(other_msgs, remaining_tokens)
      system_msgs ++ truncated_others
    else
      do_sliding_window(messages, available_tokens)
    end
  end

  defp do_sliding_window(messages, available_tokens) do
    {kept_messages, _tokens} =
      messages
      |> Enum.reverse()
      |> Enum.reduce({[], 0}, fn msg, {kept, tokens} ->
        msg_tokens = Cost.estimate_tokens(msg.content) + 3  # content + role tokens

        if tokens + msg_tokens <= available_tokens do
          {[msg | kept], tokens + msg_tokens}
        else
          {kept, tokens}
        end
      end)

    kept_messages
  end

  defp smart_truncate(messages, available_tokens, preserve_system) do
    {system_msgs, other_msgs} = Enum.split_with(messages, &(&1.role == "system"))

    # Always preserve system messages if requested
    system_tokens = if preserve_system do
      Enum.reduce(system_msgs, 0, fn msg, acc ->
        acc + Cost.estimate_tokens(msg.content) + 3
      end)
    else
      0
    end
    remaining_tokens = max(0, available_tokens - system_tokens)

    # Smart strategy: keep first few and last several messages
    if length(other_msgs) <= 6 do
      # Few messages, just use sliding window
      result = do_sliding_window(other_msgs, remaining_tokens)
      if preserve_system, do: system_msgs ++ result, else: result
    else
      # Keep first 2 exchanges (4 messages) and recent messages
      {first_msgs, rest} = Enum.split(other_msgs, 4)
      recent_msgs = Enum.take(rest, -10)

      # Add truncation notice
      dropped_count = length(rest) - length(recent_msgs)

      truncation_notice =
        if dropped_count > 0 do
          %{
            role: "system",
            content: "[#{dropped_count} messages omitted for context management]"
          }
        end

      combined =
        first_msgs ++
          if(truncation_notice, do: [truncation_notice], else: []) ++
          recent_msgs

      # Ensure we fit in remaining tokens
      truncated = do_sliding_window(combined, remaining_tokens)

      if preserve_system do
        system_msgs ++ truncated
      else
        truncated
      end
    end
  end
end