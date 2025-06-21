defmodule ExLLM.Plugs.ManageContext do
  @moduledoc """
  Manages conversation context to fit within model token limits.

  This plug provides various strategies for handling conversations that might
  exceed the model's context window. It can truncate messages, summarize
  conversations, or implement other context management strategies.

  ## Options

    * `:strategy` - Context management strategy (`:truncate`, `:summarize`, `:none`)
      Defaults to `:truncate`
    * `:max_tokens` - Maximum tokens allowed (defaults to model's limit)
    * `:preserve_system` - Whether to preserve system messages (default: `true`)
    * `:preserve_recent` - Number of recent messages to always preserve (default: `1`)
    * `:token_counter` - Function to count tokens (defaults to estimate)
    
  ## Strategies

  ### `:truncate` (default)

  Removes older messages to fit within the token limit, preserving system
  messages and recent messages based on configuration.

  ### `:summarize`

  Creates a summary of older messages to compress the conversation history.
  This requires an additional LLM call.

  ### `:none`

  No context management - passes messages through unchanged.

  ## Examples

      # Simple truncation
      plug ExLLM.Plugs.ManageContext
      
      # Custom configuration
      plug ExLLM.Plugs.ManageContext,
        strategy: :truncate,
        max_tokens: 8000,
        preserve_recent: 3
        
      # Summarization strategy
      plug ExLLM.Plugs.ManageContext,
        strategy: :summarize,
        max_tokens: 4000
  """

  use ExLLM.Plug
  alias ExLLM.Infrastructure.Logger

  @default_strategy :truncate
  @default_preserve_recent 1

  @impl true
  def init(opts) do
    opts
    |> Keyword.put_new(:strategy, @default_strategy)
    |> Keyword.put_new(:preserve_system, true)
    |> Keyword.put_new(:preserve_recent, @default_preserve_recent)
    |> Keyword.validate!([
      :strategy,
      :max_tokens,
      :preserve_system,
      :preserve_recent,
      :token_counter
    ])
  end

  @impl true
  def call(%Request{messages: messages, config: config} = request, opts) do
    strategy = opts[:strategy]
    max_tokens = opts[:max_tokens] || config[:max_tokens] || get_model_limit(request)

    # Skip if no limit or no messages
    if max_tokens == nil or messages == [] do
      request
      |> Request.assign(:context_managed, true)
      |> Request.assign(:context_skipped, true)
    else
      # Count current tokens
      current_tokens = count_tokens(messages, opts[:token_counter])

      # Apply strategy if needed
      managed_messages =
        if current_tokens > max_tokens do
          apply_strategy(strategy, messages, max_tokens, opts, request)
        else
          messages
        end

      # Update request
      request
      |> Map.put(:messages, managed_messages)
      |> Request.assign(:context_managed, true)
      |> Request.assign(:original_message_count, length(messages))
      |> Request.assign(:managed_message_count, length(managed_messages))
      |> Request.assign(:original_tokens, current_tokens)
      |> Request.assign(:managed_tokens, count_tokens(managed_messages, opts[:token_counter]))
      |> maybe_add_context_warning(messages, managed_messages)
    end
  end

  defp apply_strategy(:none, messages, _max_tokens, _opts, _request) do
    messages
  end

  defp apply_strategy(:truncate, messages, max_tokens, opts, _request) do
    truncate_messages(messages, max_tokens, opts)
  end

  defp apply_strategy(:summarize, messages, max_tokens, opts, request) do
    summarize_messages(messages, max_tokens, opts, request)
  end

  defp apply_strategy(unknown, _messages, _max_tokens, _opts, _request) do
    raise ArgumentError, "Unknown context management strategy: #{inspect(unknown)}"
  end

  defp truncate_messages(messages, max_tokens, opts) do
    preserve_system? = opts[:preserve_system]
    preserve_recent = opts[:preserve_recent] || @default_preserve_recent
    token_counter = opts[:token_counter]

    # Separate messages into categories
    {system_messages, user_messages} =
      Enum.split_with(messages, fn msg ->
        role = msg[:role] || msg["role"]
        role == "system"
      end)

    # Always preserve recent messages
    {recent_messages, older_messages} =
      Enum.split(Enum.reverse(user_messages), preserve_recent)
      |> then(fn {recent, older} -> {Enum.reverse(recent), Enum.reverse(older)} end)

    # Start with system messages (if preserving) and recent messages
    required_messages =
      if preserve_system? do
        system_messages ++ recent_messages
      else
        recent_messages
      end

    required_tokens = count_tokens(required_messages, token_counter)

    if required_tokens > max_tokens do
      # Even required messages exceed limit - warn and return as is
      Logger.warning(
        "Required messages (#{required_tokens} tokens) exceed max tokens (#{max_tokens})"
      )

      required_messages
    else
      # Add older messages that fit
      remaining_tokens = max_tokens - required_tokens

      older_messages
      |> Enum.reduce_while({[], remaining_tokens}, fn msg, {acc, tokens_left} ->
        msg_tokens = count_tokens([msg], token_counter)

        if msg_tokens <= tokens_left do
          {:cont, {[msg | acc], tokens_left - msg_tokens}}
        else
          {:halt, {acc, tokens_left}}
        end
      end)
      |> elem(0)
      |> Enum.reverse()
      |> then(&(required_messages ++ &1))
    end
  end

  defp summarize_messages(messages, max_tokens, opts, _request) do
    # This is a placeholder for summarization logic
    # In a real implementation, this would make an LLM call to summarize
    Logger.warning("Summarization strategy not yet implemented, falling back to truncation")
    truncate_messages(messages, max_tokens, opts)
  end

  defp count_tokens(messages, nil) do
    # Simple estimation: ~4 characters per token
    messages
    |> Enum.map(&message_to_string/1)
    |> Enum.join(" ")
    |> String.length()
    |> div(4)
  end

  defp count_tokens(messages, token_counter) when is_function(token_counter, 1) do
    token_counter.(messages)
  end

  defp message_to_string(%{content: content}) when is_binary(content), do: content
  defp message_to_string(%{"content" => content}) when is_binary(content), do: content

  defp message_to_string(%{content: content}) when is_list(content) do
    Enum.map(content, fn
      %{type: "text", text: text} -> text
      %{text: text} -> text
      _ -> ""
    end)
    |> Enum.join(" ")
  end

  defp message_to_string(msg) when is_map(msg) do
    # Handle both atom and string keys
    content = msg[:content] || msg["content"] || ""
    message_to_string(%{content: content})
  end

  defp message_to_string(_), do: ""

  defp get_model_limit(%Request{provider: provider, config: config}) do
    model = config[:model]

    # This would typically call into a model registry
    # For now, return some common defaults
    case {provider, model} do
      {:openai, "gpt-4"} -> 8192
      {:openai, "gpt-4-turbo"} -> 128_000
      {:openai, "gpt-3.5-turbo"} -> 4096
      {:anthropic, "claude-3-opus"} -> 200_000
      {:anthropic, "claude-3-sonnet"} -> 200_000
      {:anthropic, "claude-3-haiku"} -> 200_000
      _ -> nil
    end
  end

  defp maybe_add_context_warning(request, original_messages, managed_messages) do
    if length(original_messages) > length(managed_messages) do
      removed_count = length(original_messages) - length(managed_messages)

      warning = %{
        type: :context_truncated,
        removed_messages: removed_count,
        original_count: length(original_messages),
        final_count: length(managed_messages)
      }

      Request.assign(request, :context_warning, warning)
    else
      request
    end
  end
end
