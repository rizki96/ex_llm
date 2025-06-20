defmodule ExLLM.Plugs.Providers.GroqParseListModelsResponse do
  @moduledoc """
  Parses list models response from the Groq API.

  Transforms Groq's models list into a standardized format.
  """

  use ExLLM.Plug

  # Model context windows
  @context_windows %{
    "llama-3.3-70b-versatile" => 128_000,
    "llama-3.3-70b-specdec" => 8_192,
    "llama-3.1-405b-reasoning" => 131_072,
    "llama-3.1-70b-versatile" => 131_072,
    "llama-3.1-8b-instant" => 131_072,
    "llama3-70b-8192" => 8_192,
    "llama3-8b-8192" => 8_192,
    "llama2-70b-4096" => 4_096,
    "mixtral-8x7b-32768" => 32_768,
    "gemma2-9b-it" => 8_192,
    "gemma-7b-it" => 8_192,
    "deepseek-r1-distill-llama-70b" => 128_000,
    "deepseek-r1-distill-qwen-32b" => 128_000
  }

  # Model max output tokens
  @max_output_tokens %{
    "llama-3.3-70b-versatile" => 32_768,
    "llama-3.3-70b-specdec" => 8_192,
    "llama-3.1-405b-reasoning" => 16_384,
    "llama-3.1-70b-versatile" => 16_384,
    "llama-3.1-8b-instant" => 16_384,
    "llama3-70b-8192" => 8_192,
    "llama3-8b-8192" => 8_192,
    "llama2-70b-4096" => 4_096,
    "mixtral-8x7b-32768" => 32_768,
    "deepseek-r1-distill-llama-70b" => 8_000,
    "deepseek-r1-distill-qwen-32b" => 8_000
  }

  # Model pricing per 1M tokens (as of Dec 2024)
  @pricing %{
    "llama-3.3-70b-versatile" => %{input: 0.59, output: 0.79},
    "llama-3.3-70b-specdec" => %{input: 0.59, output: 0.99},
    "llama-3.1-405b-reasoning" => %{input: 3.00, output: 15.00},
    "llama-3.1-70b-versatile" => %{input: 0.59, output: 0.79},
    "llama-3.1-8b-instant" => %{input: 0.05, output: 0.08},
    "llama3-70b-8192" => %{input: 0.59, output: 0.79},
    "llama3-8b-8192" => %{input: 0.05, output: 0.08},
    "mixtral-8x7b-32768" => %{input: 0.24, output: 0.24},
    "gemma2-9b-it" => %{input: 0.20, output: 0.20},
    "gemma-7b-it" => %{input: 0.07, output: 0.07},
    "deepseek-r1-distill-llama-70b" => %{input: 0.59, output: 0.79},
    "deepseek-r1-distill-qwen-32b" => %{input: 0.27, output: 0.27}
  }

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
      case body["data"] do
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

  defp parse_auth_error_response(request, response, status) do
    error_data = %{
      type: :authentication_error,
      status: status,
      message: extract_error_message(response.body),
      provider: :groq
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp parse_server_error_response(request, _response, status) do
    error_data = %{
      type: :server_error,
      status: status,
      message: "Groq server error (#{status})",
      provider: :groq,
      retryable: true
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp parse_unknown_error_response(request, response) do
    error_data = %{
      type: :unknown_error,
      status: response.status,
      message: "Unexpected response from Groq",
      provider: :groq,
      raw_response: response.body
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp transform_model(model) do
    model_id = model["id"]

    %{
      id: model_id,
      name: model_id,
      created: model["created"],
      owned_by: model["owned_by"] || "groq",
      context_window: get_context_window(model_id),
      max_output_tokens: get_max_output_tokens(model_id),
      capabilities: get_capabilities(model_id),
      pricing: get_pricing(model_id),
      metadata: %{
        active: model["active"] != false,
        type: "chat.completion"
      }
    }
  end

  defp get_context_window(model_id) do
    Map.get(@context_windows, model_id, 32_768)
  end

  defp get_max_output_tokens(model_id) do
    Map.get(@max_output_tokens, model_id, 8_192)
  end

  defp get_capabilities(model_id) do
    # All Groq models support chat
    base_capabilities = ["chat"]

    # Check for function calling support
    capabilities =
      if supports_function_calling?(model_id) do
        ["function_calling" | base_capabilities]
      else
        base_capabilities
      end

    # Check for vision support (currently none on Groq)
    capabilities =
      if supports_vision?(model_id) do
        ["vision" | capabilities]
      else
        capabilities
      end

    Enum.uniq(capabilities)
  end

  defp supports_function_calling?(model_id) do
    # Most newer models support function calling
    model_id =~ ~r/llama-3\.[13]|llama-3\.3|mixtral|gemma2/
  end

  defp supports_vision?(_model_id) do
    # Groq doesn't currently offer vision models
    false
  end

  defp get_pricing(model_id) do
    Map.get(@pricing, model_id, %{input: 0.10, output: 0.10})
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
