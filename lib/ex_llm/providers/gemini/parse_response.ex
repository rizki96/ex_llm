defmodule ExLLM.Providers.Gemini.ParseResponse do
  @moduledoc """
  Pipeline plug for parsing Gemini API responses.
  """

  use ExLLM.Plug

  alias ExLLM.Pipeline.Request
  alias ExLLM.Types

  @impl true
  def call(request, _opts) do
    response = request.assigns.http_response
    model = request.assigns.model

    parsed_response = parse_response(response, model)

    request
    |> Request.assign(:llm_response, parsed_response)
    |> Request.put_state(:completed)
  end

  defp parse_response(response, model) do
    case get_in(response, ["candidates"]) do
      [candidate | _] ->
        content = extract_text_from_candidate(candidate)

        usage =
          if usage_metadata = get_in(response, ["usageMetadata"]) do
            %{
              input_tokens: usage_metadata["promptTokenCount"] || 0,
              output_tokens: usage_metadata["candidatesTokenCount"] || 0,
              total_tokens: usage_metadata["totalTokenCount"] || 0
            }
          else
            output_tokens = ExLLM.Core.Cost.estimate_tokens(content)

            %{
              input_tokens: 0,
              output_tokens: output_tokens,
              total_tokens: output_tokens
            }
          end

        # Extract only the required fields for cost calculation
        cost_usage = %{
          input_tokens: usage.input_tokens,
          output_tokens: usage.output_tokens
        }
        cost_info = ExLLM.Core.Cost.calculate(:gemini, model, cost_usage)
        cost_value = Map.get(cost_info, :total_cost)

        tool_calls = extract_tool_calls_from_candidate(candidate)
        audio_content = extract_audio_from_candidate(candidate)

        %Types.LLMResponse{
          content: content,
          usage: usage,
          model: model,
          finish_reason: get_in(candidate, ["finishReason"]) || "stop",
          cost: cost_value,
          tool_calls: tool_calls,
          metadata: %{
            provider: :gemini,
            role: "assistant",
            audio_content: audio_content,
            safety_ratings: get_in(candidate, ["safetyRatings"]),
            cost_details: cost_info,
            raw_response: response
          }
        }

      [] ->
        block_reason = get_in(response, ["promptFeedback", "blockReason"])

        %Types.LLMResponse{
          content: "",
          usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0},
          model: model,
          finish_reason: block_reason || "error",
          cost: 0.0,
          metadata: %{
            provider: :gemini,
            role: "assistant",
            error: "Response blocked: #{block_reason || "No candidates returned"}",
            raw_response: response
          }
        }
    end
  end

  defp extract_text_from_candidate(candidate) do
    (get_in(candidate, ["content", "parts"]) || [])
    |> Enum.map(fn part -> part["text"] || "" end)
    |> Enum.join("")
  end

  @dialyzer {:nowarn_function, extract_tool_calls_from_candidate: 1}
  defp extract_tool_calls_from_candidate(candidate) do
    function_calls =
      (get_in(candidate, ["content", "parts"]) || [])
      |> Enum.filter(fn part ->
        Map.has_key?(part, "functionCall") && part["functionCall"] != nil
      end)
      |> Enum.map(fn part ->
        fc = part["functionCall"]

        %{
          id: Map.get(fc, "name", "unknown"),
          type: "function",
          function: %{
            name: Map.get(fc, "name", "unknown"),
            arguments: Map.get(fc, "args", %{})
          }
        }
      end)

    if Enum.empty?(function_calls), do: nil, else: function_calls
  end

  @dialyzer {:nowarn_function, extract_audio_from_candidate: 1}
  defp extract_audio_from_candidate(candidate) do
    audio_parts =
      (get_in(candidate, ["content", "parts"]) || [])
      |> Enum.filter(fn part ->
        case get_in(part, ["inlineData", "mimeType"]) do
          nil -> false
          mime_type -> String.contains?(mime_type, "audio")
        end
      end)
      |> Enum.map(fn part -> get_in(part, ["inlineData", "data"]) end)

    case audio_parts do
      [] -> nil
      [audio | _] -> audio
    end
  end
end
