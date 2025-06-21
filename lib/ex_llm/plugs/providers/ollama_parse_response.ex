defmodule ExLLM.Plugs.Providers.OllamaParseResponse do
  @moduledoc """
  Parses responses from the Ollama API.

  Transforms Ollama's response format into the standard ExLLM
  response format. Handles both regular and streaming responses.
  """

  use ExLLM.Plug
  alias ExLLM.Infrastructure.Logger

  @impl true
  def call(%Request{response: nil} = request, _opts) do
    # No response to parse
    request
  end

  def call(%Request{response: %Tesla.Env{status: 200, body: body}} = request, _opts) do
    case parse_response(body) do
      {:ok, result} ->
        request
        |> Map.put(:result, result)
        |> Request.put_state(:completed)
        |> Request.assign(:response_parsed, true)

      {:error, reason} ->
        Request.halt_with_error(request, %{
          plug: __MODULE__,
          error: :parse_error,
          message: "Failed to parse Ollama response: #{inspect(reason)}",
          details: %{body: body}
        })
    end
  end

  def call(%Request{response: %Tesla.Env{status: status, body: body}} = request, _opts) do
    error_details = parse_error_response(body, status)

    Request.halt_with_error(request, %{
      plug: __MODULE__,
      error: :api_error,
      message: error_details.message,
      details: error_details
    })
  end

  def call(%Request{} = request, _opts) do
    Request.halt_with_error(request, %{
      plug: __MODULE__,
      error: :invalid_response,
      message: "Invalid response structure"
    })
  end

  defp parse_response(body) when is_map(body) do
    # Ollama chat response format
    content = extract_content(body)

    result = %{
      content: content,
      role: "assistant",
      model: body["model"],
      done: body["done"],
      usage: parse_usage(body),
      provider: :ollama,
      raw_response: body
    }

    # Add optional fields if present
    result =
      result
      |> maybe_add_field(:context, body["context"])
      |> maybe_add_field(:total_duration, body["total_duration"])
      |> maybe_add_field(:load_duration, body["load_duration"])
      |> maybe_add_field(:prompt_eval_duration, body["prompt_eval_duration"])
      |> maybe_add_field(:eval_duration, body["eval_duration"])

    {:ok, result}
  rescue
    e ->
      Logger.error("Error parsing Ollama response: #{inspect(e)}")
      {:error, e}
  end

  defp parse_response(_body), do: {:error, :invalid_response_format}

  defp extract_content(%{"message" => %{"content" => content}}) do
    content
  end

  defp extract_content(%{"response" => response}) do
    # For generate endpoint
    response
  end

  defp extract_content(_), do: ""

  defp parse_usage(body) do
    %{
      prompt_tokens: body["prompt_eval_count"] || 0,
      completion_tokens: body["eval_count"] || 0,
      total_tokens: (body["prompt_eval_count"] || 0) + (body["eval_count"] || 0)
    }
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  defp parse_error_response(body, status) when is_map(body) do
    %{
      status: status,
      error: body["error"] || "Unknown error",
      message: body["error"] || "Error from Ollama API"
    }
  end

  defp parse_error_response(body, status) when is_binary(body) do
    %{
      status: status,
      error: "response_error",
      message: body
    }
  end

  defp parse_error_response(body, status) do
    %{
      status: status,
      type: "parse_error",
      message: "Could not parse error response",
      body: body
    }
  end
end
