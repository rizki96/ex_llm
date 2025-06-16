defmodule ExLLM.Bumblebee.TokenCounter do
  @moduledoc false

  alias ExLLM.Cost
  alias ExLLM.Bumblebee.ModelLoader

  @doc """
  Count tokens for the given text using the specified model's tokenizer.

  Falls back to heuristic estimation if model is not loaded or Bumblebee
  is not available.

  ## Examples

      {:ok, count} = TokenCounter.count_tokens("Hello world", model: "microsoft/phi-2")
      # => {:ok, 2}
      
      # Fallback when model not loaded
      {:ok, estimate} = TokenCounter.count_tokens("Hello world")
      # => {:ok, 3}
  """
  def count_tokens(text, opts \\ []) do
    model = Keyword.get(opts, :model, "microsoft/phi-2")

    if bumblebee_available?() do
      count_with_tokenizer(text, model)
    else
      # Fallback to estimation
      {:ok, Cost.estimate_tokens(text)}
    end
  end

  @doc """
  Count tokens for a list of messages.

  ## Examples

      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]
      {:ok, count} = TokenCounter.count_messages(messages, model: "microsoft/phi-2")
  """
  def count_messages(messages, opts \\ []) when is_list(messages) do
    model = Keyword.get(opts, :model, "microsoft/phi-2")

    # Format messages the same way the adapter does
    formatted = format_messages_for_counting(messages, model)
    count_tokens(formatted, opts)
  end

  # Private functions

  defp count_with_tokenizer(text, model) do
    case ModelLoader.get_model_info(model) do
      {:ok, %{tokenizer: tokenizer}} ->
        # Use Bumblebee tokenizer to count tokens
        case apply_tokenizer(tokenizer, text) do
          {:ok, inputs} ->
            token_count = get_token_count(inputs)
            {:ok, token_count}

          {:error, _reason} ->
            # Fallback to estimation on tokenizer error
            {:ok, Cost.estimate_tokens(text)}
        end

      {:error, :not_loaded} ->
        # Model not loaded, use estimation
        {:ok, Cost.estimate_tokens(text)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_tokenizer(tokenizer, text) do
    if Code.ensure_loaded?(Bumblebee) do
      try do
        apply(Bumblebee, :apply_tokenizer, [tokenizer, text])
      rescue
        e -> {:error, e}
      end
    else
      {:error, :bumblebee_not_available}
    end
  end

  defp get_token_count(inputs) do
    if Code.ensure_loaded?(Nx) do
      apply(Nx, :size, [inputs["input_ids"]])
    else
      # Rough estimate if Nx not available
      0
    end
  end

  defp format_messages_for_counting(messages, model) do
    # Reuse formatting logic from adapter
    case model do
      "meta-llama/Llama-2" <> _ ->
        format_llama2_messages(messages)

      "mistralai/Mistral" <> _ ->
        format_mistral_messages(messages)

      _ ->
        messages
        |> Enum.map(fn msg ->
          role = format_role(msg["role"] || msg[:role])
          content = msg["content"] || msg[:content]
          "#{role}: #{content}"
        end)
        |> Enum.join("\n\n")
    end
  end

  defp format_role(role) do
    case to_string(role) do
      "system" -> "System"
      "user" -> "Human"
      "assistant" -> "Assistant"
      other -> String.capitalize(other)
    end
  end

  defp format_llama2_messages(messages) do
    messages
    |> Enum.map_join("\n", fn msg ->
      role = to_string(msg["role"] || msg[:role])
      content = msg["content"] || msg[:content]

      case role do
        "system" -> "<<SYS>>\n#{content}\n<</SYS>>\n\n"
        "user" -> "[INST] #{content} [/INST]"
        "assistant" -> content
        _ -> content
      end
    end)
  end

  defp format_mistral_messages(messages) do
    messages
    |> Enum.map_join("\n", fn msg ->
      role = to_string(msg["role"] || msg[:role])
      content = msg["content"] || msg[:content]

      case role do
        "user" -> "[INST] #{content} [/INST]"
        "assistant" -> content
        _ -> content
      end
    end)
  end

  defp bumblebee_available? do
    Code.ensure_loaded?(Bumblebee)
  end
end
