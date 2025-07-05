defmodule ExLLM.Plugs.Providers.OllamaParseListModelsResponse do
  @moduledoc """
  Parses list models response from the Ollama API.

  Transforms Ollama's local models list into a standardized format.
  """

  use ExLLM.Plug

  alias ExLLM.Infrastructure.Config.ModelConfig
  alias ExLLM.Infrastructure.Logger

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
      context_window: get_context_window(model_name, base_name),
      max_output_tokens: get_max_output_tokens(model_name, base_name),
      capabilities: get_capabilities(model_name, base_name),
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

  # Helper to find model configuration by trying various name formats.
  defp get_model_config(model_name, base_name) do
    # First try the registry which will check cache, config, and API
    case ExLLM.Infrastructure.OllamaModelRegistry.get_model_details(model_name) do
      {:ok, details} ->
        details

      {:error, _} ->
        # Fallback to trying different name formats in ModelConfig
        ModelConfig.get_model_config(:ollama, model_name) ||
          ModelConfig.get_model_config(:ollama, "ollama/#{model_name}") ||
          ModelConfig.get_model_config(:ollama, base_name) ||
          ModelConfig.get_model_config(:ollama, "ollama/#{base_name}")
    end
  end

  defp get_context_window(model_name, base_name) do
    case get_model_config(model_name, base_name) do
      %{context_window: cw} when is_integer(cw) ->
        cw

      _ ->
        default = 4_096

        Logger.warning(
          "Could not find context_window for Ollama model '#{model_name}'. Falling back to default of #{default}."
        )

        default
    end
  end

  defp get_max_output_tokens(model_name, base_name) do
    case get_model_config(model_name, base_name) do
      %{max_output_tokens: mot} when is_integer(mot) ->
        mot

      _ ->
        default = 2_048

        Logger.warning(
          "Could not find max_output_tokens for Ollama model '#{model_name}'. Falling back to default of #{default}."
        )

        default
    end
  end

  defp get_capabilities(model_name, base_name) do
    case get_model_config(model_name, base_name) do
      %{capabilities: caps} when is_list(caps) ->
        string_caps =
          Enum.map(caps, fn
            cap when is_atom(cap) -> Atom.to_string(cap)
            cap when is_binary(cap) -> cap
          end)

        # Add "chat" capability by default for non-embedding models
        if "embeddings" in string_caps do
          string_caps
        else
          ["chat" | string_caps]
        end
        |> Enum.uniq()

      _ ->
        # Check if this is an embedding model based on the name
        default = if is_embedding_model?(model_name), do: ["embeddings", "streaming"], else: ["chat"]

        Logger.warning(
          "Could not find capabilities for Ollama model '#{model_name}'. Falling back to default of #{inspect(default)}."
        )

        default
    end
  end

  defp is_embedding_model?(model_name) do
    String.contains?(model_name, "embed") ||
      String.contains?(model_name, "embedding") ||
      String.contains?(model_name, "e5") ||
      String.contains?(model_name, "bge")
  end
end
