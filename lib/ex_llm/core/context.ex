defmodule ExLLM.Core.Context do
  @moduledoc """
  Context management for LLM conversations.

  Provides utilities for managing conversation context windows, including:
  - Token counting and estimation
  - Message truncation strategies
  - Context window validation
  - System prompt preservation
  """

  alias ExLLM.{Core.Cost, Infrastructure.Config.ModelConfig}

  @reserve_tokens 500

  # Model context windows are now loaded from external YAML configuration files
  # See config/models/ for model pricing, context windows, and capabilities

  @doc """
  Get the context window size for a given provider and model.

  Returns the maximum number of tokens the model can handle.
  Raises an error if the model is not found in configuration.
  """
  @spec get_context_window(String.t() | atom(), String.t()) :: pos_integer()
  def get_context_window(provider, model) do
    provider_atom = if is_binary(provider), do: String.to_existing_atom(provider), else: provider

    # Try with the model as-is first
    context_window = ModelConfig.get_context_window(provider_atom, model)

    # If not found and model doesn't already have provider prefix, try with prefix
    context_window =
      if is_nil(context_window) and not String.starts_with?(model, "#{provider}/") do
        prefixed_model = "#{provider}/#{model}"
        ModelConfig.get_context_window(provider_atom, prefixed_model)
      else
        context_window
      end

    case context_window do
      nil ->
        raise "Unknown model #{model} for provider #{provider}. " <>
                "Please ensure the model exists in config/models/#{provider}.yml"

      context_window ->
        context_window
    end
  end

  @doc """
  Check if messages fit within the context window for a given model.

  Returns `{:ok, token_count}` if messages fit, or `{:error, reason}` if not.
  """
  @spec validate_context(list(), String.t() | atom(), String.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, String.t()}
  def validate_context(messages, provider, model, options \\ []) do
    max_tokens = Keyword.get(options, :max_tokens)
    context_window = get_context_window(provider, model)

    available_tokens =
      if max_tokens do
        context_window - max_tokens - @reserve_tokens
      else
        context_window - @reserve_tokens
      end

    estimated_tokens = Cost.estimate_tokens(messages)

    if estimated_tokens <= available_tokens do
      {:ok, estimated_tokens}
    else
      # Emit telemetry when context window is exceeded
      :telemetry.execute(
        [:ex_llm, :context, :window_exceeded],
        %{
          estimated_tokens: estimated_tokens,
          available_tokens: available_tokens,
          excess_tokens: estimated_tokens - available_tokens
        },
        %{
          provider: provider,
          model: model,
          message_count: length(messages)
        }
      )

      {:error,
       "Messages exceed context window: #{estimated_tokens} tokens > #{available_tokens} available"}
    end
  end

  @doc """
  Truncate messages to fit within context window.

  Supports different truncation strategies:
  - `:sliding_window` - Remove old messages from the beginning
  - `:smart` - Preserve system message and recent messages, remove from middle
  """
  @spec truncate_messages(list(), String.t() | atom(), String.t(), keyword()) :: list()
  def truncate_messages(messages, provider, model, options \\ []) do
    strategy = Keyword.get(options, :strategy, :sliding_window)
    max_tokens = Keyword.get(options, :max_tokens)
    context_window = get_context_window(provider, model)

    available_tokens =
      if max_tokens do
        context_window - max_tokens - @reserve_tokens
      else
        context_window - @reserve_tokens
      end

    case validate_context(messages, provider, model, options) do
      {:ok, _} -> messages
      {:error, _} -> apply_truncation_strategy(messages, available_tokens, strategy)
    end
  end

  @doc """
  Get optimal token allocation for different message types.

  Returns a map with recommended token allocations.
  """
  @spec get_token_allocation(String.t() | atom(), String.t(), keyword()) :: %{
          system: non_neg_integer(),
          conversation: non_neg_integer(),
          response: non_neg_integer(),
          total: non_neg_integer()
        }
  def get_token_allocation(provider, model, options \\ []) do
    max_tokens = Keyword.get(options, :max_tokens, 1000)
    context_window = get_context_window(provider, model)

    # Reserve tokens for response
    response_tokens = max_tokens

    # Reserve tokens for system message
    system_tokens = min(1000, context_window * 0.1) |> round()

    # Remaining tokens for conversation
    conversation_tokens = context_window - response_tokens - system_tokens - @reserve_tokens

    %{
      system: system_tokens,
      conversation: max(0, conversation_tokens),
      response: response_tokens,
      total: context_window
    }
  end

  # Private functions

  defp apply_truncation_strategy(messages, available_tokens, strategy) do
    start_time = System.monotonic_time()
    initial_message_count = length(messages)
    initial_tokens = Cost.estimate_tokens(messages)

    # Execute the truncation strategy
    truncated_messages =
      case strategy do
        :sliding_window -> truncate_sliding_window(messages, available_tokens)
        :smart -> truncate_smart(messages, available_tokens)
      end

    # Calculate metrics
    final_message_count = length(truncated_messages)
    final_tokens = Cost.estimate_tokens(truncated_messages)
    duration = System.monotonic_time() - start_time

    # Emit telemetry for truncation
    :telemetry.execute(
      [:ex_llm, :context, :truncation, :stop],
      %{
        duration: duration,
        messages_removed: initial_message_count - final_message_count,
        tokens_removed: initial_tokens - final_tokens,
        final_tokens: final_tokens
      },
      %{
        strategy: strategy,
        initial_message_count: initial_message_count,
        final_message_count: final_message_count
      }
    )

    truncated_messages
  end

  defp truncate_sliding_window(messages, available_tokens) do
    truncate_sliding_window(messages, available_tokens, [])
  end

  defp truncate_sliding_window([], _available_tokens, acc) do
    Enum.reverse(acc)
  end

  defp truncate_sliding_window([msg | rest], available_tokens, acc) do
    msg_tokens = Cost.estimate_tokens(msg)
    acc_tokens = Cost.estimate_tokens(acc)

    if acc_tokens + msg_tokens <= available_tokens do
      truncate_sliding_window(rest, available_tokens, [msg | acc])
    else
      Enum.reverse(acc)
    end
  end

  defp truncate_smart(messages, available_tokens) do
    # Preserve system message and last few messages
    {system_msgs, other_msgs} = Enum.split_with(messages, &is_system_message?/1)

    # Always keep system messages
    system_tokens = Cost.estimate_tokens(system_msgs)
    remaining_tokens = available_tokens - system_tokens

    if remaining_tokens <= 0 do
      system_msgs
    else
      # Keep as many recent messages as possible
      recent_msgs = truncate_sliding_window(Enum.reverse(other_msgs), remaining_tokens)
      system_msgs ++ Enum.reverse(recent_msgs)
    end
  end

  defp is_system_message?(%{role: "system"}), do: true
  defp is_system_message?(%{"role" => "system"}), do: true
  defp is_system_message?(_), do: false
  
  @doc """
  Get statistics about a conversation's context usage.
  
  ## Examples
  
      stats = ExLLM.Core.Context.stats(messages)
  """
  @spec stats(list(map())) :: map()
  def stats(messages) do
    total_tokens = Cost.estimate_tokens(messages)
    message_count = length(messages)
    
    system_messages = Enum.filter(messages, &is_system_message?/1)
    user_messages = Enum.filter(messages, fn msg -> 
      msg[:role] == "user" || msg["role"] == "user"
    end)
    assistant_messages = Enum.filter(messages, fn msg ->
      msg[:role] == "assistant" || msg["role"] == "assistant"
    end)
    
    # Group messages by role for by_role stats
    by_role = 
      messages
      |> Enum.group_by(fn msg ->
        msg[:role] || msg["role"] || "unknown"
      end)
      |> Enum.into(%{}, fn {role, msgs} -> {role, length(msgs)} end)
    
    %{
      total_tokens: total_tokens,
      message_count: message_count,
      avg_tokens_per_message: if(message_count > 0, do: total_tokens / message_count, else: 0),
      system_message_count: length(system_messages),
      user_message_count: length(user_messages),
      assistant_message_count: length(assistant_messages),
      system_tokens: Cost.estimate_tokens(system_messages),
      user_tokens: Cost.estimate_tokens(user_messages),
      assistant_tokens: Cost.estimate_tokens(assistant_messages),
      by_role: by_role
    }
  end
end
