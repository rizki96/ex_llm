defmodule ExLLM.Plugs.Providers.GeminiParseResponse do
  @moduledoc """
  Parses responses from the Google Gemini API.

  Transforms Gemini's response format into the standard ExLLM
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
          message: "Failed to parse Gemini response: #{inspect(reason)}",
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
    # Get the first candidate (Gemini can return multiple)
    candidate = get_first_candidate(body)

    if candidate do
      content = extract_content(candidate)

      result = %{
        content: content,
        role: "assistant",
        model: extract_model_name(body),
        finish_reason: candidate["finishReason"],
        safety_ratings: candidate["safetyRatings"],
        usage: parse_usage(body["usageMetadata"]),
        provider: :gemini,
        raw_response: body
      }

      {:ok, result}
    else
      {:error, :no_candidates}
    end
  rescue
    e ->
      Logger.error("Error parsing Gemini response: #{inspect(e)}")
      {:error, e}
  end

  defp parse_response(_body), do: {:error, :invalid_response_format}

  defp get_first_candidate(%{"candidates" => [candidate | _]}), do: candidate
  defp get_first_candidate(_), do: nil

  defp extract_content(%{"content" => %{"parts" => parts}}) when is_list(parts) do
    parts
    |> Enum.map(fn
      %{"text" => text} -> text
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp extract_content(_), do: ""

  defp extract_model_name(%{"modelVersion" => version}), do: version
  defp extract_model_name(_), do: "gemini-pro"

  defp parse_usage(nil), do: %{}

  defp parse_usage(usage) when is_map(usage) do
    %{
      prompt_tokens: usage["promptTokenCount"] || 0,
      completion_tokens: usage["candidatesTokenCount"] || 0,
      total_tokens: usage["totalTokenCount"] || 0
    }
  end

  defp parse_error_response(body, status) when is_map(body) do
    error = body["error"] || %{}

    %{
      status: status,
      code: error["code"] || "unknown_error",
      message: error["message"] || "Unknown error from Gemini API",
      details: error["details"] || []
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
