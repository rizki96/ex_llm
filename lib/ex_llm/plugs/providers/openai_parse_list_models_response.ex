defmodule ExLLM.Plugs.Providers.OpenAIParseListModelsResponse do
  @moduledoc """
  Parses list models response from the OpenAI API.

  Transforms OpenAI's models list into a standardized format.
  """

  use ExLLM.Plug

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
          |> Enum.filter(&is_chat_model?/1)
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
      provider: :openai
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp parse_server_error_response(request, _response, status) do
    error_data = %{
      type: :server_error,
      status: status,
      message: "OpenAI server error (#{status})",
      provider: :openai,
      retryable: true
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp parse_unknown_error_response(request, response) do
    error_data = %{
      type: :unknown_error,
      status: response.status,
      message: "Unexpected response from OpenAI",
      provider: :openai,
      raw_response: response.body
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp is_chat_model?(model) do
    # Filter to only chat-capable models
    model["id"] =~ ~r/^(gpt|o1|o3|chatgpt)/
  end

  defp transform_model(model) do
    %{
      id: model["id"],
      name: model["id"],
      created: model["created"],
      owned_by: model["owned_by"],
      context_window: get_context_window(model["id"]),
      max_output_tokens: get_max_output_tokens(model["id"]),
      capabilities: get_capabilities(model["id"]),
      pricing: get_pricing(model["id"])
    }
  end

  defp get_context_window(model_id) do
    # Known context windows for OpenAI models
    case model_id do
      "gpt-4-turbo" <> _ -> 128_000
      "gpt-4-1106" <> _ -> 128_000
      "gpt-4-0125" <> _ -> 128_000
      "gpt-4-32k" <> _ -> 32_768
      "gpt-4" <> _ -> 8192
      "gpt-3.5-turbo-1106" -> 16_385
      "gpt-3.5-turbo-16k" <> _ -> 16_385
      "gpt-3.5-turbo" <> _ -> 4096
      "o1-preview" <> _ -> 128_000
      "o1-mini" <> _ -> 128_000
      _ -> 4096
    end
  end

  defp get_max_output_tokens(model_id) do
    case model_id do
      "gpt-4-turbo" <> _ -> 4096
      "gpt-4" <> _ -> 4096
      "gpt-3.5-turbo" <> _ -> 4096
      "o1-preview" <> _ -> 32_768
      "o1-mini" <> _ -> 65_536
      _ -> 4096
    end
  end

  defp get_capabilities(model_id) do
    base_capabilities = ["chat"]

    capabilities =
      if model_id =~ ~r/^(gpt-4|gpt-3\.5-turbo)/ and not (model_id =~ ~r/instruct/) do
        ["function_calling" | base_capabilities]
      else
        base_capabilities
      end

    if model_id =~ ~r/vision|gpt-4-turbo|gpt-4o/ do
      ["vision" | capabilities]
    else
      capabilities
    end
  end

  defp get_pricing(model_id) do
    # Pricing per 1M tokens
    case model_id do
      "gpt-4-turbo" <> _ -> %{input: 10.0, output: 30.0}
      "gpt-4-32k" <> _ -> %{input: 60.0, output: 120.0}
      "gpt-4" <> _ -> %{input: 30.0, output: 60.0}
      "gpt-3.5-turbo" <> _ -> %{input: 0.5, output: 1.5}
      "o1-preview" <> _ -> %{input: 15.0, output: 60.0}
      "o1-mini" <> _ -> %{input: 3.0, output: 12.0}
      _ -> %{input: 0.5, output: 1.5}
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
