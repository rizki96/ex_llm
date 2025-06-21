defmodule ExLLM.Plugs.Providers.BedrockParseResponse do
  @moduledoc """
  Parses responses from AWS Bedrock API.

  Different model families return different response formats.
  """

  use ExLLM.Plug
  alias ExLLM.Types.LLMResponse

  @impl true
  def call(%Request{response: nil} = request, _opts) do
    Request.halt_with_error(request, %{
      plug: __MODULE__,
      error: :no_response,
      message: "No response to parse"
    })
  end

  def call(%Request{response: %{body: body}, assigns: assigns} = request, _opts) do
    model = assigns[:bedrock_model] || ""

    case parse_response(body, model) do
      {:ok, result} ->
        request
        |> Map.put(:result, result)
        |> Request.assign(:response_parsed, true)

      {:error, reason} ->
        Request.halt_with_error(request, %{
          plug: __MODULE__,
          error: :parse_error,
          message: "Failed to parse Bedrock response: #{inspect(reason)}"
        })
    end
  end

  defp parse_response(body, model) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> parse_model_response(data, model)
      {:error, _} = error -> error
    end
  end

  defp parse_response(body, model) when is_map(body) do
    parse_model_response(body, model)
  end

  defp parse_model_response(data, model) do
    cond do
      String.contains?(model, "claude") ->
        parse_claude_response(data)

      String.contains?(model, "titan") ->
        parse_titan_response(data)

      String.contains?(model, "llama") ->
        parse_llama_response(data)

      String.contains?(model, "command") ->
        parse_cohere_response(data)

      String.contains?(model, "mistral") ->
        parse_mistral_response(data)

      true ->
        parse_claude_response(data)
    end
  end

  defp parse_claude_response(%{"content" => [%{"text" => text} | _]} = data) do
    usage = %{
      prompt_tokens: data["usage"]["input_tokens"] || 0,
      completion_tokens: data["usage"]["output_tokens"] || 0,
      total_tokens: (data["usage"]["input_tokens"] || 0) + (data["usage"]["output_tokens"] || 0)
    }

    {:ok,
     %LLMResponse{
       content: text,
       finish_reason: data["stop_reason"] || "stop",
       usage: usage,
       metadata: %{
         role: "assistant",
         provider: :bedrock,
         raw_response: data
       }
     }}
  end

  defp parse_claude_response(%{"completion" => text} = data) do
    # Older Claude format
    {:ok,
     %LLMResponse{
       content: text,
       finish_reason: data["stop_reason"] || "stop",
       usage: %{},
       metadata: %{
         role: "assistant",
         provider: :bedrock,
         raw_response: data
       }
     }}
  end

  defp parse_claude_response(_), do: {:error, :invalid_claude_response}

  defp parse_titan_response(%{"results" => [%{"outputText" => text} | _]} = data) do
    {:ok,
     %LLMResponse{
       content: text,
       finish_reason: data["completionReason"] || "FINISH",
       usage: %{
         prompt_tokens: data["inputTextTokenCount"] || 0,
         completion_tokens: data["results"] |> List.first() |> Map.get("tokenCount", 0),
         total_tokens:
           (data["inputTextTokenCount"] || 0) +
             (data["results"] |> List.first() |> Map.get("tokenCount", 0))
       },
       metadata: %{
         role: "assistant",
         provider: :bedrock,
         raw_response: data
       }
     }}
  end

  defp parse_titan_response(_), do: {:error, :invalid_titan_response}

  defp parse_llama_response(%{"generation" => text} = data) do
    {:ok,
     %LLMResponse{
       content: text,
       finish_reason: data["stop_reason"] || "stop",
       usage: %{
         prompt_tokens: data["prompt_token_count"] || 0,
         completion_tokens: data["generation_token_count"] || 0,
         total_tokens: (data["prompt_token_count"] || 0) + (data["generation_token_count"] || 0)
       },
       metadata: %{
         role: "assistant",
         provider: :bedrock,
         raw_response: data
       }
     }}
  end

  defp parse_llama_response(_), do: {:error, :invalid_llama_response}

  defp parse_cohere_response(%{"generations" => [%{"text" => text} | _]} = data) do
    {:ok,
     %LLMResponse{
       content: text,
       finish_reason: data["finish_reason"] || "COMPLETE",
       usage: %{},
       metadata: %{
         role: "assistant",
         provider: :bedrock,
         raw_response: data
       }
     }}
  end

  defp parse_cohere_response(_), do: {:error, :invalid_cohere_response}

  defp parse_mistral_response(%{"outputs" => [%{"text" => text} | _]} = data) do
    {:ok,
     %LLMResponse{
       content: text,
       finish_reason: "stop",
       usage: %{},
       metadata: %{
         role: "assistant",
         provider: :bedrock,
         raw_response: data
       }
     }}
  end

  defp parse_mistral_response(
         %{"choices" => [%{"message" => %{"content" => content}} | _]} = data
       ) do
    # Alternative Mistral format
    usage = data["usage"] || %{}

    {:ok,
     %LLMResponse{
       content: content,
       finish_reason: data["choices"] |> List.first() |> Map.get("finish_reason", "stop"),
       usage: %{
         prompt_tokens: usage["prompt_tokens"] || 0,
         completion_tokens: usage["completion_tokens"] || 0,
         total_tokens: usage["total_tokens"] || 0
       },
       metadata: %{
         role: "assistant",
         provider: :bedrock,
         raw_response: data
       }
     }}
  end

  defp parse_mistral_response(_), do: {:error, :invalid_mistral_response}
end
