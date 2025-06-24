defmodule ExLLM.Providers.Bumblebee.ParseResponse do
  @moduledoc """
  Parses the response from local Bumblebee model execution.

  This plug converts the raw model output into the standard
  ExLLM.Types.LLMResponse format.
  """

  use ExLLM.Plug

  alias ExLLM.Pipeline.Request
  alias ExLLM.Types

  @impl true
  def call(%Request{state: :completed} = request, _opts) do
    raw_response = request.assigns[:raw_response]
    generated_text = request.assigns[:generated_text]
    model = request.assigns[:model]

    if raw_response && generated_text do
      parse_local_response(request, raw_response, generated_text, model)
    else
      # Not a local inference response, pass through
      request
    end
  end

  def call(request, _opts), do: request

  defp parse_local_response(request, raw_response, generated_text, model) do
    # Extract token counts if available
    usage = extract_usage(raw_response)

    # Clean up the generated text
    cleaned_text = clean_generated_text(generated_text, model)

    # Build the LLMResponse
    llm_response = %Types.LLMResponse{
      content: cleaned_text,
      model: model,
      usage: usage,
      metadata: extract_metadata(raw_response)
    }

    request
    |> Request.assign(:llm_response, llm_response)
    |> Request.assign(:parsed_response, llm_response)
  end

  defp extract_usage(raw_response) do
    # Try to extract token counts from the response
    # This depends on what Bumblebee/Nx.Serving provides

    input_tokens =
      get_in(raw_response, [:metadata, :input_tokens]) || estimate_tokens(raw_response)

    output_tokens =
      get_in(raw_response, [:metadata, :output_tokens]) || estimate_output_tokens(raw_response)

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: input_tokens + output_tokens
    }
  end

  defp estimate_tokens(raw_response) do
    # Rough estimation if not provided
    # ~4 characters per token is a common approximation
    input_text = get_in(raw_response, [:input, :text]) || ""
    div(String.length(input_text), 4)
  end

  defp estimate_output_tokens(raw_response) do
    case raw_response do
      %{results: [%{text: text} | _]} ->
        div(String.length(text), 4)

      _ ->
        0
    end
  end

  defp clean_generated_text(text, model) do
    # Remove any special tokens or formatting based on model
    family = get_model_family(model)

    text
    |> remove_special_tokens(family)
    |> String.trim()
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

  defp remove_special_tokens(text, :llama) do
    text
    |> String.replace(~r/\[\/INST\]/, "")
    |> String.replace(~r/<<SYS>>.*?<<\/SYS>>/s, "")
    |> String.replace(~r/\[INST\]/, "")
  end

  defp remove_special_tokens(text, :mistral) do
    text
    |> String.replace(~r/<s>/, "")
    |> String.replace(~r/<\/s>/, "")
    |> String.replace(~r/\[INST\]/, "")
    |> String.replace(~r/\[\/INST\]/, "")
  end

  defp remove_special_tokens(text, :smollm) do
    text
    |> String.replace(~r/<\|im_start\|>assistant\n/, "")
    |> String.replace(~r/<\|im_end\|>/, "")
    |> String.replace(~r/<\|im_start\|>\w+\n/, "")
  end

  defp remove_special_tokens(text, :phi) do
    text
    |> String.replace(~r/^Assistant:\s*/, "")
  end

  defp remove_special_tokens(text, _), do: text

  defp extract_metadata(raw_response) do
    # Extract any useful metadata from the response
    %{
      generation_time_ms: get_in(raw_response, [:metadata, :generation_time_ms]),
      device: get_in(raw_response, [:metadata, :device]) || detect_device(),
      backend: get_in(raw_response, [:metadata, :backend]) || detect_backend()
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp detect_device do
    # Try to detect if we're using GPU/Metal/CPU
    cond do
      Code.ensure_loaded?(EMLX) -> "metal"
      cuda_available?() -> "cuda"
      true -> "cpu"
    end
  end

  defp detect_backend do
    # Detect which backend is being used
    cond do
      Code.ensure_loaded?(EMLX) -> "emlx"
      Code.ensure_loaded?(EXLA) -> "exla"
      true -> "nx"
    end
  end

  defp cuda_available? do
    # Check if CUDA is available through EXLA
    if Code.ensure_loaded?(EXLA) do
      try do
        # Use apply to avoid compile-time warnings when EXLA is not available
        platforms = apply(EXLA.Backend, :get_supported_platforms, [])
        Enum.any?(platforms, fn platform -> String.contains?(to_string(platform), "cuda") end)
      rescue
        _ -> false
      end
    else
      false
    end
  end
end
