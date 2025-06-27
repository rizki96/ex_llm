defmodule ExLLM.Providers.Groq.ParseResponse do
  @moduledoc """
  Pipeline plug for parsing Groq API responses.

  Since Groq uses OpenAI-compatible response format, this plug largely follows
  the same pattern as OpenAI but uses Groq-specific cost calculation and metadata.
  """

  use ExLLM.Plug

  alias ExLLM.Types

  @impl true
  def call(request, _opts) do
    # Skip parsing if this is a streaming request that was already handled
    if request.state == :streaming do
      request
    else
      response = request.assigns.http_response
      model = request.assigns.model

      parsed_response = parse_response(response, model)

      request
      |> Request.assign(:llm_response, parsed_response)
      |> Map.put(:result, parsed_response)
      |> Request.put_state(:completed)
    end
  end

  defp parse_response(response, model) do
    choice = get_in(response, ["choices", Access.at(0)]) || %{}
    message = choice["message"] || %{}
    usage = response["usage"] || %{}

    # Parse usage in OpenAI format
    enhanced_usage = parse_usage(usage)

    # Calculate cost for Groq (model needs provider prefix for pricing lookup)
    full_model_name = "groq/#{model}"

    cost_info =
      ExLLM.Core.Cost.calculate("groq", full_model_name, %{
        input_tokens: enhanced_usage.input_tokens,
        output_tokens: enhanced_usage.output_tokens
      })

    # Extract just the total cost float for backward compatibility
    cost_value = Map.get(cost_info, :total_cost)

    %Types.LLMResponse{
      content: message["content"] || "",
      function_call: message["function_call"],
      tool_calls: message["tool_calls"],
      refusal: message["refusal"],
      logprobs: choice["logprobs"],
      usage: enhanced_usage,
      model: model,
      finish_reason: choice["finish_reason"],
      cost: cost_value,
      metadata:
        Map.merge(response["metadata"] || %{}, %{
          cost_details: cost_info,
          role: "assistant",
          provider: :groq,
          raw_response: response
        })
    }
  end

  defp parse_usage(usage) do
    %{
      input_tokens: usage["prompt_tokens"] || 0,
      output_tokens: usage["completion_tokens"] || 0,
      total_tokens: usage["total_tokens"] || 0
    }
  end
end
