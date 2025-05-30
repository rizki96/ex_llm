defmodule ExLLM.Adapters.Shared.MessageFormatter do
  @moduledoc """
  Shared message formatting utilities for ExLLM adapters.
  
  Provides common message transformations and validations used across
  different LLM providers. Each provider has slightly different message
  formats, but this module provides the common patterns.
  """
  
  alias ExLLM.Types
  
  @doc """
  Validate messages have required fields and proper structure.
  
  ## Examples
  
      MessageFormatter.validate_messages([
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ])
      # => :ok
  """
  @spec validate_messages(list(Types.message())) :: :ok | {:error, term()}
  def validate_messages([]), do: {:error, {:validation, :messages, "cannot be empty"}}
  
  def validate_messages(messages) when is_list(messages) do
    Enum.reduce_while(messages, :ok, fn message, _acc ->
      case validate_message(message) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
  
  def validate_messages(_), do: {:error, {:validation, :messages, "must be a list"}}
  
  @doc """
  Ensure all messages have string keys (some providers require this).
  
  ## Examples
  
      MessageFormatter.stringify_message_keys([
        %{role: :user, content: "Hello"}
      ])
      # => [%{"role" => "user", "content" => "Hello"}]
  """
  @spec stringify_message_keys(list(map())) :: list(map())
  def stringify_message_keys(messages) do
    Enum.map(messages, &stringify_keys/1)
  end
  
  @doc """
  Add a system message to the beginning of the messages list.
  
  Handles cases where system message might already exist.
  
  ## Examples
  
      MessageFormatter.add_system_message(messages, "You are a helpful assistant")
  """
  @spec add_system_message(list(Types.message()), String.t() | nil) :: list(Types.message())
  def add_system_message(messages, nil), do: messages
  def add_system_message(messages, ""), do: messages
  
  def add_system_message(messages, system_prompt) do
    case messages do
      [%{role: "system"} | _rest] ->
        # System message already exists, don't add another
        messages
        
      _ ->
        [%{"role" => "system", "content" => system_prompt} | messages]
    end
  end
  
  @doc """
  Extract system message from messages list if present.
  
  Returns {system_message, remaining_messages}.
  """
  @spec extract_system_message(list(Types.message())) :: {String.t() | nil, list(Types.message())}
  def extract_system_message([%{"role" => "system", "content" => content} | rest]) do
    {content, rest}
  end
  
  def extract_system_message([%{role: "system", content: content} | rest]) do
    {content, rest}
  end
  
  def extract_system_message(messages), do: {nil, messages}
  
  @doc """
  Ensure messages alternate between user and assistant roles.
  
  Some providers require strict alternation. This function adds
  empty assistant messages where needed.
  """
  @spec ensure_alternating_roles(list(Types.message())) :: list(Types.message())
  def ensure_alternating_roles([]), do: []
  
  def ensure_alternating_roles([first | rest]) do
    [first | do_ensure_alternating(get_role(first), rest, [])]
  end
  
  @doc """
  Format a function/tool call message for the provider.
  
  Each provider has different formats for function calls.
  """
  @spec format_function_call(map(), atom()) :: map()
  def format_function_call(function_call, :openai) do
    %{
      "role" => "assistant",
      "content" => nil,
      "function_call" => %{
        "name" => function_call.name,
        "arguments" => Jason.encode!(function_call.arguments)
      }
    }
  end
  
  def format_function_call(function_call, :anthropic) do
    %{
      "role" => "assistant",
      "content" => [
        %{
          "type" => "tool_use",
          "id" => function_call.id || generate_tool_id(),
          "name" => function_call.name,
          "input" => function_call.arguments
        }
      ]
    }
  end
  
  def format_function_call(function_call, _provider) do
    # Default format
    %{
      "role" => "assistant",
      "content" => "Function call: #{function_call.name}",
      "function_call" => function_call
    }
  end
  
  @doc """
  Format a function result message for the provider.
  """
  @spec format_function_result(map(), atom()) :: map()
  def format_function_result(result, :openai) do
    %{
      "role" => "function",
      "name" => result.name,
      "content" => Jason.encode!(result.result)
    }
  end
  
  def format_function_result(result, :anthropic) do
    %{
      "role" => "user",
      "content" => [
        %{
          "type" => "tool_result",
          "tool_use_id" => result.id || result.name,
          "content" => Jason.encode!(result.result)
        }
      ]
    }
  end
  
  def format_function_result(result, _provider) do
    %{
      "role" => "function",
      "name" => result.name,
      "content" => Jason.encode!(result.result)
    }
  end
  
  @doc """
  Count tokens in messages (rough estimate).
  
  This is a very rough estimate - actual token count depends on the
  specific tokenizer used by each model.
  """
  @spec estimate_token_count(list(Types.message())) :: integer()
  def estimate_token_count(messages) do
    messages
    |> Enum.map(&extract_content/1)
    |> Enum.join(" ")
    |> String.split(~r/\s+/)
    |> length()
    |> Kernel.*(1.3)  # Rough adjustment for tokenization
    |> round()
  end
  
  @doc """
  Truncate messages to fit within a token limit.
  
  Keeps most recent messages, preserving system message if present.
  """
  @spec truncate_messages(list(Types.message()), integer()) :: list(Types.message())
  def truncate_messages(messages, max_tokens) do
    {system_msg, other_messages} = extract_system_message(messages)
    
    truncated = do_truncate_messages(Enum.reverse(other_messages), max_tokens, [])
    
    if system_msg do
      [%{"role" => "system", "content" => system_msg} | truncated]
    else
      truncated
    end
  end
  
  # Private functions
  
  defp validate_message(%{role: role, content: content})
       when role in ["system", "user", "assistant", "function"] and
            (is_binary(content) or is_list(content)) do
    :ok
  end
  
  defp validate_message(%{"role" => role, "content" => content})
       when role in ["system", "user", "assistant", "function"] and
            (is_binary(content) or is_list(content)) do
    :ok
  end
  
  defp validate_message(_) do
    {:error, {:validation, :message, "must have role and content fields"}}
  end
  
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), stringify_value(value)}
      {key, value} -> {key, stringify_value(value)}
    end)
  end
  
  defp stringify_value(value) when is_map(value), do: stringify_keys(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value), do: value
  
  defp get_role(%{"role" => role}), do: role
  defp get_role(%{role: role}), do: to_string(role)
  
  defp do_ensure_alternating(_last_role, [], acc), do: Enum.reverse(acc)
  
  defp do_ensure_alternating(last_role, [msg | rest], acc) do
    current_role = get_role(msg)
    
    if should_alternate?(last_role, current_role) do
      # Need to insert an empty message
      empty_msg = create_empty_message(last_role)
      do_ensure_alternating(current_role, rest, [msg, empty_msg | acc])
    else
      do_ensure_alternating(current_role, rest, [msg | acc])
    end
  end
  
  defp should_alternate?("user", "user"), do: true
  defp should_alternate?("assistant", "assistant"), do: true
  defp should_alternate?(_, _), do: false
  
  defp create_empty_message("user") do
    %{"role" => "assistant", "content" => "..."}
  end
  
  defp create_empty_message("assistant") do
    %{"role" => "user", "content" => "..."}
  end
  
  defp generate_tool_id do
    "tool_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
  
  defp extract_content(%{"content" => content}) when is_binary(content), do: content
  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{"content" => contents}) when is_list(contents) do
    contents
    |> Enum.map(fn
      %{"text" => text} -> text
      %{text: text} -> text
      _ -> ""
    end)
    |> Enum.join(" ")
  end
  defp extract_content(_), do: ""
  
  defp do_truncate_messages([], _max_tokens, acc), do: acc
  defp do_truncate_messages([msg | rest], max_tokens, acc) do
    current_tokens = estimate_token_count(acc)
    msg_tokens = estimate_token_count([msg])
    
    if current_tokens + msg_tokens <= max_tokens do
      do_truncate_messages(rest, max_tokens, [msg | acc])
    else
      acc
    end
  end
end