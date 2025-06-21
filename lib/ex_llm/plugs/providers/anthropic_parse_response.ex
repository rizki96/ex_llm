defmodule ExLLM.Plugs.Providers.AnthropicParseResponse do
  @moduledoc """
  Parses responses from the Anthropic API.

  Transforms Anthropic's response format into the standard ExLLM
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
          message: "Failed to parse Anthropic response: #{inspect(reason)}",
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
    content = extract_content(body)

    result = %{
      content: content,
      role: "assistant",
      model: body["model"],
      stop_reason: body["stop_reason"],
      usage: parse_usage(body["usage"]),
      provider: :anthropic,
      raw_response: body
    }

    {:ok, result}
  rescue
    e ->
      Logger.error("Error parsing Anthropic response: #{inspect(e)}")
      {:error, e}
  end

  defp parse_response(_body), do: {:error, :invalid_response_format}

  defp extract_content(%{"content" => [%{"text" => text} | _]}) do
    text
  end

  defp extract_content(%{"content" => content}) when is_list(content) do
    # Handle multiple content blocks
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      %{"text" => text} -> text
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp extract_content(_), do: ""

  defp parse_usage(nil), do: %{}

  defp parse_usage(usage) when is_map(usage) do
    %{
      prompt_tokens: usage["input_tokens"] || 0,
      completion_tokens: usage["output_tokens"] || 0,
      total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
    }
  end

  defp parse_error_response(body, status) when is_map(body) do
    error = body["error"] || %{}

    %{
      status: status,
      type: error["type"] || "unknown_error",
      message: error["message"] || "Unknown error from Anthropic API",
      details: error
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
