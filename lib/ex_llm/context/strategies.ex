defmodule ExLLM.Context.Strategies do
  @moduledoc """
  Message truncation strategies for context window management.

  Provides different algorithms for fitting messages within token limits:
  - Sliding window: Remove oldest messages first
  - Smart: Preserve system messages and prioritize recent messages
  - Summary: Replace old messages with summaries (future)
  """

  alias ExLLM.Cost

  @doc """
  Apply a truncation strategy to fit messages within token limit.

  ## Strategies
  - `:sliding_window` - Remove messages from the beginning
  - `:smart` - Keep system messages and recent messages
  - `:fifo` - First in, first out (alias for sliding_window)
  - `:lifo` - Last in, first out (keep oldest messages)

  ## Examples

      Strategies.truncate(messages, 1000, :sliding_window)
  """
  @spec truncate(list(map()), non_neg_integer(), atom()) :: list(map())
  def truncate(messages, max_tokens, strategy \\ :sliding_window)

  def truncate(messages, max_tokens, :sliding_window) do
    sliding_window(messages, max_tokens)
  end

  def truncate(messages, max_tokens, :fifo) do
    sliding_window(messages, max_tokens)
  end

  def truncate(messages, max_tokens, :smart) do
    smart_truncate(messages, max_tokens)
  end

  def truncate(messages, max_tokens, :lifo) do
    messages
    |> Enum.reverse()
    |> sliding_window(max_tokens)
    |> Enum.reverse()
  end

  def truncate(_messages, _max_tokens, unknown) do
    raise ArgumentError, "Unknown truncation strategy: #{inspect(unknown)}"
  end

  @doc """
  Sliding window truncation - keep most recent messages.
  """
  @spec sliding_window(list(map()), non_neg_integer()) :: list(map())
  def sliding_window(messages, max_tokens) do
    messages
    |> Enum.reverse()
    |> do_sliding_window(max_tokens, 0, [])
  end

  defp do_sliding_window([], _max_tokens, _current_tokens, acc), do: acc

  defp do_sliding_window([msg | rest], max_tokens, current_tokens, acc) do
    msg_tokens = Cost.estimate_tokens(msg)
    new_total = current_tokens + msg_tokens

    if new_total <= max_tokens do
      do_sliding_window(rest, max_tokens, new_total, [msg | acc])
    else
      acc
    end
  end

  @doc """
  Smart truncation - preserve system messages and recent conversation.
  """
  @spec smart_truncate(list(map()), non_neg_integer()) :: list(map())
  def smart_truncate(messages, max_tokens) do
    {system_msgs, conversation} = split_system_messages(messages)

    system_tokens = Cost.estimate_tokens(system_msgs)
    remaining_tokens = max(0, max_tokens - system_tokens)

    if remaining_tokens == 0 do
      # Only keep system messages if they exceed limit
      system_msgs
    else
      # Keep system messages and as much recent conversation as possible
      truncated_conversation = sliding_window(conversation, remaining_tokens)
      system_msgs ++ truncated_conversation
    end
  end

  @doc """
  Split messages into system and non-system messages.
  """
  @spec split_system_messages(list(map())) :: {list(map()), list(map())}
  def split_system_messages(messages) do
    Enum.split_with(messages, &is_system_message?/1)
  end

  @doc """
  Calculate token distribution for different message types.

  Returns suggested token allocations for system, conversation, and response.
  """
  @spec calculate_distribution(non_neg_integer(), keyword()) :: map()
  def calculate_distribution(total_tokens, opts \\ []) do
    response_tokens = Keyword.get(opts, :max_tokens, min(1000, total_tokens * 0.25))
    system_ratio = Keyword.get(opts, :system_ratio, 0.1)
    reserve_tokens = Keyword.get(opts, :reserve, 500)

    system_tokens = min(1000, total_tokens * system_ratio) |> round()
    available = total_tokens - response_tokens - system_tokens - reserve_tokens

    %{
      system: system_tokens,
      conversation: max(0, available),
      response: response_tokens,
      reserve: reserve_tokens,
      total: total_tokens
    }
  end

  @doc """
  Group consecutive messages by role for better token efficiency.

  Some models handle grouped messages more efficiently.
  """
  @spec group_by_role(list(map())) :: list(map())
  def group_by_role(messages) do
    messages
    |> Enum.chunk_by(&get_role/1)
    |> Enum.map(&merge_role_group/1)
  end

  # Private helpers

  defp is_system_message?(%{role: "system"}), do: true
  defp is_system_message?(%{"role" => "system"}), do: true
  defp is_system_message?(_), do: false

  defp get_role(%{role: role}), do: role
  defp get_role(%{"role" => role}), do: role

  defp merge_role_group([single]), do: single

  defp merge_role_group(messages) do
    role = get_role(List.first(messages))

    content =
      messages
      |> Enum.map(&get_content/1)
      |> Enum.join("\n\n")

    %{role: role, content: content}
  end

  defp get_content(%{content: content}), do: content
  defp get_content(%{"content" => content}), do: content
end
