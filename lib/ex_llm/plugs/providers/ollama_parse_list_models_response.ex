defmodule ExLLM.Plugs.Providers.OllamaParseListModelsResponse do
  @moduledoc """
  Parses list models response from the Ollama API.

  Transforms Ollama's local models list into a standardized format.
  """

  use ExLLM.Plug

  @impl true
  def call(%ExLLM.Pipeline.Request{response: %Tesla.Env{} = response} = request, _opts) do
    case response.status do
      200 ->
        parse_success_response(request, response)

      status when status == 404 ->
        # Ollama not running or endpoint not found
        parse_not_found_response(request, response)

      status when status >= 500 ->
        parse_server_error_response(request, response, status)

      _ ->
        parse_unknown_error_response(request, response)
    end
  end

  defp parse_success_response(request, response) do
    body = response.body

    # Extract and transform model data
    models =
      case body["models"] do
        models when is_list(models) ->
          models
          |> Enum.map(&transform_model/1)
          |> Enum.sort_by(& &1.id)

        _ ->
          []
      end

    request
    |> Map.put(:result, models)
    |> ExLLM.Pipeline.Request.put_state(:completed)
  end

  defp parse_not_found_response(request, _response) do
    error_data = %{
      type: :service_unavailable,
      status: 404,
      message: "Ollama service not running or not accessible",
      provider: :ollama,
      hint: "Make sure Ollama is installed and running (ollama serve)"
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp parse_server_error_response(request, _response, status) do
    error_data = %{
      type: :server_error,
      status: status,
      message: "Ollama server error (#{status})",
      provider: :ollama,
      retryable: true
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp parse_unknown_error_response(request, response) do
    error_data = %{
      type: :unknown_error,
      status: response.status,
      message: "Unexpected response from Ollama",
      provider: :ollama,
      raw_response: response.body
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp transform_model(model) do
    model_name = model["name"]
    base_name = extract_base_model_name(model_name)
    size_str = format_size(model["size"])

    description =
      case size_str do
        "Unknown" -> "Local Ollama model"
        size -> "Local Ollama model - #{size}"
      end

    %ExLLM.Types.Model{
      id: model_name,
      name: model_name,
      description: description,
      context_window: get_context_window(base_name),
      max_output_tokens: get_max_output_tokens(base_name),
      capabilities: get_capabilities(base_name),
      # Local models are free
      pricing: %{input: 0.0, output: 0.0}
    }
  end

  defp extract_base_model_name(full_name) do
    # Extract base model name from tags like "llama3.2:3b-instruct-q4_K_M"
    case String.split(full_name, ":") do
      [base | _] -> base
      _ -> full_name
    end
  end

  defp format_size(size_bytes) when is_integer(size_bytes) do
    cond do
      size_bytes >= 1_073_741_824 ->
        "#{Float.round(size_bytes / 1_073_741_824, 1)} GB"

      size_bytes >= 1_048_576 ->
        "#{Float.round(size_bytes / 1_048_576, 1)} MB"

      size_bytes >= 1024 ->
        "#{Float.round(size_bytes / 1024, 1)} KB"

      true ->
        "#{size_bytes} B"
    end
  end

  defp format_size(_), do: "Unknown"

  defp get_context_window(base_name) do
    # Known context windows for common Ollama models
    # Order matters - more specific patterns first
    context_patterns = [
      {~r/llama3\.2/, 128_000},
      {~r/llama3\.1/, 128_000},
      {~r/llama3/, 8_192},
      {~r/llama2/, 4_096},
      {~r/mistral/, 32_768},
      {~r/mixtral/, 32_768},
      {~r/qwen2\.5/, 128_000},
      {~r/qwen2/, 32_768},
      {~r/qwen/, 8_192},
      {~r/deepseek-r1/, 64_000},
      {~r/deepseek-coder-v2/, 128_000},
      {~r/deepseek-v2/, 128_000},
      {~r/phi3/, 128_000},
      {~r/phi/, 2_048},
      {~r/gemma2/, 8_192},
      {~r/gemma/, 8_192},
      {~r/command-r/, 128_000},
      {~r/yi/, 200_000},
      {~r/solar/, 4_096},
      {~r/codellama/, 16_384},
      {~r/starcoder2/, 16_384},
      {~r/wizardlm2/, 65_536}
    ]

    find_matching_value(base_name, context_patterns, 4_096)
  end

  defp get_max_output_tokens(base_name) do
    # Maximum output tokens for common models
    cond do
      base_name =~ ~r/llama3\.[12]/ -> 16_384
      base_name =~ ~r/llama3/ -> 8_192
      base_name =~ ~r/llama2/ -> 4_096
      base_name =~ ~r/mistral/ -> 8_192
      base_name =~ ~r/mixtral/ -> 32_768
      base_name =~ ~r/qwen2\.5/ -> 32_768
      base_name =~ ~r/qwen/ -> 8_192
      base_name =~ ~r/deepseek/ -> 16_384
      base_name =~ ~r/command-r/ -> 4_096
      base_name =~ ~r/yi/ -> 4_096
      true -> 2_048
    end
  end

  defp get_capabilities(base_name) do
    # Base capability for all models
    capabilities = ["chat"]

    # Check for code capabilities
    capabilities =
      if base_name =~ ~r/code|starcoder|deepseek-coder|codellama/ do
        ["code" | capabilities]
      else
        capabilities
      end

    # Check for vision capabilities
    capabilities =
      if base_name =~ ~r/llava|bakllava|vision/ do
        ["vision" | capabilities]
      else
        capabilities
      end

    # Check for embedding capabilities
    capabilities =
      if base_name =~ ~r/embed|bge|e5|nomic-embed/ do
        ["embeddings" | capabilities]
      else
        capabilities
      end

    # Check for function calling (most modern models support it)
    capabilities =
      if base_name =~ ~r/llama3|mistral|mixtral|qwen2|deepseek|phi3|gemma2|command-r/ do
        ["function_calling" | capabilities]
      else
        capabilities
      end

    Enum.uniq(capabilities)
  end

  # Helper function to find first matching pattern value
  defp find_matching_value(string, patterns, default) do
    case Enum.find(patterns, fn {pattern, _value} -> string =~ pattern end) do
      {_pattern, value} -> value
      nil -> default
    end
  end
end
