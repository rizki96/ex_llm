defmodule ExLLM.Providers.Anthropic.ParseResponse do
  @moduledoc """
  Pipeline plug for parsing Anthropic API responses.

  This plug transforms raw HTTP responses from the Anthropic API into
  standardized ExLLM.Types.LLMResponse structs, including cost calculation,
  usage tracking, and metadata extraction.
  """

  use ExLLM.Plug

  alias ExLLM.Types

  @impl true
  def call(request, _opts) do
    response = request.assigns.http_response

    parsed_response = parse_response(response)

    request
    |> Request.assign(:llm_response, parsed_response)
    |> Request.put_state(:completed)
  end

  defp parse_response(response) do
    content =
      response["content"]
      |> List.first()
      |> Map.get("text", "")

    usage =
      case response["usage"] do
        nil ->
          nil

        usage_map ->
          %{
            input_tokens: Map.get(usage_map, "input_tokens", 0),
            output_tokens: Map.get(usage_map, "output_tokens", 0)
          }
      end

    # Calculate cost if we have usage data
    cost =
      if usage && response["model"] do
        cost_result = ExLLM.Core.Cost.calculate("anthropic", response["model"], usage)
        Map.get(cost_result, :total_cost)
      else
        nil
      end

    %Types.LLMResponse{
      content: content,
      model: response["model"],
      usage: usage,
      finish_reason: response["stop_reason"],
      cost: cost,
      metadata: %{
        provider: :anthropic,
        role: "assistant",
        raw_response: response
      }
    }
  end
end
