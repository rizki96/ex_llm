defmodule ExLLM.Plugs.Providers.GeminiParseListModelsResponse do
  @moduledoc """
  Parses list models response from the Gemini API.

  Transforms Gemini's models list into a standardized format.
  """

  use ExLLM.Plug
  alias ExLLM.Types.Model

  @impl true
  def call(%ExLLM.Pipeline.Request{response: %Tesla.Env{} = response} = request, _opts) do
    case response.status do
      200 ->
        parse_success_response(request, response)

      status when status in [401, 403] ->
        parse_auth_error_response(request, response, status)

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
          |> Enum.filter(&is_generative_model?/1)
          |> Enum.map(&transform_model/1)
          |> Enum.sort_by(& &1.id)

        _ ->
          []
      end

    %{request | result: models}
    |> ExLLM.Pipeline.Request.put_state(:completed)
  end

  defp parse_auth_error_response(request, response, status) do
    error_data = %{
      type: :authentication_error,
      status: status,
      message: extract_error_message(response.body),
      provider: :gemini
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp parse_server_error_response(request, _response, status) do
    error_data = %{
      type: :server_error,
      status: status,
      message: "Gemini server error (#{status})",
      provider: :gemini,
      retryable: true
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp parse_unknown_error_response(request, response) do
    error_data = %{
      type: :unknown_error,
      status: response.status,
      message: "Unexpected response from Gemini",
      provider: :gemini,
      raw_response: response.body
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp is_generative_model?(model) do
    # Filter to only generative AI models
    name = model["name"] || ""
    name =~ ~r/gemini|palm/i and model["supportedGenerationMethods"] != nil
  end

  defp transform_model(model) do
    model_name = extract_model_name(model["name"])
    pricing = get_pricing(model_name)

    %Model{
      id: model_name,
      name: model["displayName"] || model_name,
      description: model["description"],
      context_window: get_context_window(model),
      max_output_tokens: get_max_output_tokens(model),
      capabilities: %{
        features: get_capabilities(model)
      },
      pricing: %{
        input_cost_per_token: (pricing[:input] || 0) / 1_000_000,
        output_cost_per_token: (pricing[:output] || 0) / 1_000_000,
        currency: "USD"
      }
    }
  end

  defp extract_model_name(full_name) do
    # Extract just the model name from "models/gemini-1.5-pro-001"
    case String.split(full_name, "/") do
      ["models", name] -> name
      _ -> full_name
    end
  end

  defp get_context_window(model) do
    # Try to get from model metadata first
    case model["inputTokenLimit"] do
      nil ->
        # Fallback to known values
        model_name = extract_model_name(model["name"])
        get_known_context_window(model_name)

      limit ->
        limit
    end
  end

  defp get_known_context_window(model_name) do
    cond do
      # 2M context
      model_name =~ ~r/gemini-1\.5-pro/ -> 2_097_152
      # 1M context
      model_name =~ ~r/gemini-1\.5-flash/ -> 1_048_576
      # 1M context
      model_name =~ ~r/gemini-2\.0-flash-exp/ -> 1_048_576
      model_name =~ ~r/gemini-1\.0-pro/ -> 32_768
      model_name =~ ~r/gemini-pro/ -> 32_768
      true -> 32_768
    end
  end

  defp get_max_output_tokens(model) do
    case model["outputTokenLimit"] do
      nil ->
        # Default output tokens
        8192

      limit ->
        limit
    end
  end

  defp get_capabilities(model) do
    methods = model["supportedGenerationMethods"] || []

    capabilities = ["chat"]

    capabilities =
      if "generateContent" in methods or "streamGenerateContent" in methods do
        capabilities
      else
        capabilities
      end

    # Check for vision support
    capabilities =
      if model_supports_vision?(model) do
        ["vision" | capabilities]
      else
        capabilities
      end

    # Check for embeddings support
    capabilities =
      if "embedContent" in methods or "batchEmbedContents" in methods do
        ["embeddings" | capabilities]
      else
        capabilities
      end

    # Check for function calling
    capabilities =
      if model_supports_functions?(model) do
        ["function_calling" | capabilities]
      else
        capabilities
      end

    Enum.uniq(capabilities)
  end

  defp model_supports_vision?(model) do
    model_name = extract_model_name(model["name"])
    model_name =~ ~r/gemini-(1\.5|2\.0)|vision/
  end

  defp model_supports_functions?(model) do
    model_name = extract_model_name(model["name"])
    # Most Gemini models support function calling except embedding models
    not (model_name =~ ~r/embedding/)
  end

  defp get_pricing(model_name) do
    # Pricing per 1M tokens (approximate as of Dec 2024)
    cond do
      model_name =~ ~r/gemini-1\.5-pro/ ->
        %{input: 1.25, output: 5.0}

      model_name =~ ~r/gemini-1\.5-flash/ ->
        %{input: 0.075, output: 0.30}

      model_name =~ ~r/gemini-2\.0-flash-exp/ ->
        # Experimental model, free during preview
        %{input: 0.0, output: 0.0}

      model_name =~ ~r/gemini-1\.0-pro/ ->
        %{input: 0.50, output: 1.50}

      model_name =~ ~r/embedding/ ->
        %{input: 0.0625}

      true ->
        %{input: 0.50, output: 1.50}
    end
  end

  defp extract_error_message(body) when is_map(body) do
    case body do
      %{"error" => %{"message" => message}} -> message
      %{"error" => error} when is_binary(error) -> error
      %{"message" => message} -> message
      _ -> "Unknown error"
    end
  end

  defp extract_error_message(_), do: "Unknown error"
end
