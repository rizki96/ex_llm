defmodule ExLLM.Providers.Bumblebee.BuildRequest do
  @moduledoc """
  Builds a request for local Bumblebee model execution.

  This plug prepares the messages and options for local inference,
  including loading the model if needed and formatting the input.
  """

  use ExLLM.Plug

  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.Bumblebee.ModelLoader

  @impl true
  def call(%Request{state: :pending} = request, _opts) do
    messages = request.messages
    options = request.options
    config = request.assigns.config || %{}

    # Get model name
    model = Keyword.get(options, :model, config[:model] || default_model())

    # Load or get cached model
    case load_model(model) do
      {:ok, model_ref} ->
        # Format messages for the model
        formatted_input = format_messages(messages, model)

        # Prepare generation config
        generation_config = build_generation_config(options)

        request
        |> Request.assign(:model, model)
        |> Request.assign(:model_ref, model_ref)
        |> Request.assign(:formatted_input, formatted_input)
        |> Request.assign(:generation_config, generation_config)
        |> Request.put_state(:executing)

      {:error, reason} ->
        request
        |> Request.add_error(%{
          plug: __MODULE__,
          reason: reason,
          message: "Failed to load model #{model}: #{inspect(reason)}"
        })
        |> Request.put_state(:error)
        |> Request.halt()
    end
  end

  def call(request, _opts), do: request

  defp default_model do
    "HuggingFaceTB/SmolLM2-1.7B-Instruct"
  end

  defp load_model(model_name) do
    # Use the ModelLoader GenServer to load or get cached model
    case ModelLoader.load_model(model_name) do
      {:ok, model_data} ->
        {:ok, model_data}

      {:error, :not_running} ->
        # ModelLoader not started
        {:error, "ModelLoader not running. Ensure ExLLM application is started."}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_messages(messages, model) do
    # Format messages based on model type
    # Different models may have different chat templates

    case get_model_family(model) do
      :llama ->
        format_llama_messages(messages)

      :mistral ->
        format_mistral_messages(messages)

      :phi ->
        format_phi_messages(messages)

      :smollm ->
        format_smollm_messages(messages)

      _ ->
        # Default formatting
        format_default_messages(messages)
    end
  end

  defp get_model_family(model_name) do
    cond do
      String.contains?(model_name, "Llama") || String.contains?(model_name, "llama") ->
        :llama

      String.contains?(model_name, "Mistral") || String.contains?(model_name, "mistral") ->
        :mistral

      String.contains?(model_name, "phi") ->
        :phi

      String.contains?(model_name, "SmolLM") ->
        :smollm

      true ->
        :unknown
    end
  end

  defp format_llama_messages(messages) do
    # Llama 2 chat format
    formatted =
      Enum.map_join(messages, "\n", fn
        %{role: "system", content: content} ->
          "<<SYS>>\n#{content}\n<</SYS>>\n\n"

        %{role: "user", content: content} ->
          "[INST] #{content} [/INST]"

        %{role: "assistant", content: content} ->
          content
      end)

    %{text: formatted}
  end

  defp format_mistral_messages(messages) do
    # Mistral instruction format
    formatted =
      Enum.map_join(messages, "\n", fn
        %{role: "system", content: content} ->
          "<s>[INST] #{content}\n"

        %{role: "user", content: content} ->
          "#{content} [/INST]"

        %{role: "assistant", content: content} ->
          "#{content}</s>"
      end)

    %{text: formatted}
  end

  defp format_phi_messages(messages) do
    # Phi-2 format
    formatted =
      Enum.map_join(messages, "\n", fn
        %{role: "system", content: content} ->
          "System: #{content}\n"

        %{role: "user", content: content} ->
          "User: #{content}\n"

        %{role: "assistant", content: content} ->
          "Assistant: #{content}\n"
      end)

    %{text: formatted <> "Assistant:"}
  end

  defp format_smollm_messages(messages) do
    # SmolLM2 instruction format
    formatted =
      Enum.map_join(messages, "\n", fn
        %{role: "system", content: content} ->
          "<|im_start|>system\n#{content}<|im_end|>\n"

        %{role: "user", content: content} ->
          "<|im_start|>user\n#{content}<|im_end|>\n"

        %{role: "assistant", content: content} ->
          "<|im_start|>assistant\n#{content}<|im_end|>\n"
      end)

    %{text: formatted <> "<|im_start|>assistant\n"}
  end

  defp format_default_messages(messages) do
    # Simple concatenation for unknown models
    formatted =
      Enum.map_join(messages, "\n", fn
        %{role: role, content: content} ->
          "#{String.capitalize(to_string(role))}: #{content}"
      end)

    %{text: formatted}
  end

  defp build_generation_config(options) do
    %{
      max_tokens: Keyword.get(options, :max_tokens, 2048),
      temperature: Keyword.get(options, :temperature, 0.7),
      top_p: Keyword.get(options, :top_p, 1.0),
      stream: Keyword.get(options, :stream, false),
      seed: Keyword.get(options, :seed)
    }
  end
end
