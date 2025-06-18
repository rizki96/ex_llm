defmodule ExLLM.Plugs.Providers.OpenAIParseEmbeddingResponse do
  @moduledoc """
  Parses embedding responses from the OpenAI API.

  Transforms OpenAI's embedding response format into the standardized
  ExLLM embedding response format.
  """

  use ExLLM.Plug

  alias ExLLM.Types.EmbeddingResponse

  @impl true
  def call(%ExLLM.Pipeline.Request{response: %Tesla.Env{} = response} = request, _opts) do
    case response.status do
      200 ->
        parse_success_response(request, response)

      status when status in [400, 401, 403, 404, 429] ->
        parse_error_response(request, response, status)

      status when status >= 500 ->
        parse_server_error_response(request, response, status)

      _ ->
        parse_unknown_error_response(request, response)
    end
  end

  defp parse_success_response(request, response) do
    body = response.body

    # Extract embeddings data
    embeddings =
      body["data"]
      |> Enum.sort_by(& &1["index"])
      |> Enum.map(& &1["embedding"])

    # Build standardized response
    embedding_response = %EmbeddingResponse{
      embeddings: embeddings,
      model: body["model"],
      usage: normalize_usage(body["usage"]),
      metadata: %{
        provider: :openai,
        request_id: get_request_id(response),
        processing_ms: get_processing_time(response)
      }
    }

    request
    |> Map.put(:result, embedding_response)
    |> ExLLM.Pipeline.Request.put_state(:completed)
  end

  defp parse_error_response(request, response, status) do
    error_data = %{
      type: :api_error,
      status: status,
      message: extract_error_message(response.body),
      provider: :openai,
      raw_response: response.body
    }

    ExLLM.Pipeline.Request.halt_with_error(request, error_data)
  end

  defp parse_server_error_response(request, response, status) do
    error_data = %{
      type: :server_error,
      status: status,
      message: "OpenAI server error (#{status})",
      provider: :openai,
      retryable: true,
      raw_response: response.body
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

  defp normalize_usage(usage) when is_map(usage) do
    %{
      input_tokens: usage["prompt_tokens"] || 0,
      # Embeddings don't have output tokens
      output_tokens: 0,
      total_tokens: usage["total_tokens"] || usage["prompt_tokens"] || 0
    }
  end

  defp normalize_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  defp extract_error_message(body) when is_map(body) do
    case body do
      %{"error" => %{"message" => message}} -> message
      %{"error" => error} when is_binary(error) -> error
      %{"message" => message} -> message
      _ -> "Unknown error"
    end
  end

  defp extract_error_message(_), do: "Unknown error"

  defp get_request_id(response) do
    response.headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "x-request-id" end)
    |> case do
      {_, value} -> value
      nil -> nil
    end
  end

  defp get_processing_time(response) do
    response.headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "openai-processing-ms" end)
    |> case do
      {_, value} ->
        case Integer.parse(value) do
          {ms, _} -> ms
          _ -> nil
        end

      nil ->
        nil
    end
  end
end
