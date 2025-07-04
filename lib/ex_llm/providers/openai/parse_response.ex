defmodule ExLLM.Providers.OpenAI.ParseResponse do
  @moduledoc """
  Pipeline plug for parsing OpenAI API responses.

  This plug transforms raw HTTP responses from the OpenAI API into
  standardized ExLLM.Types.LLMResponse structs, including cost calculation,
  usage tracking, and metadata extraction.
  """

  use ExLLM.Plug

  alias ExLLM.Types

  @impl true
  def call(request, _opts) do
    # Skip parsing if this is a streaming request that was already handled
    if request.state == :streaming do
      request
    else
      response = request.assigns[:http_response]

      if response do
        model =
          Map.get(request.assigns, :model) || request.config[:model] || request.options[:model]

        parsed_response = parse_response(response, model)

        request
        |> Request.assign(:llm_response, parsed_response)
        |> Map.put(:result, parsed_response)
        |> Request.put_state(:completed)
      else
        request
        |> Request.halt_with_error(%{
          plug: __MODULE__,
          error: :no_response,
          message: "No HTTP response to parse"
        })
      end
    end
  end

  defp parse_response(response, model) do
    # Handle cases where choices might not be a list
    choices = response["choices"] || []
    choice = if is_list(choices) and length(choices) > 0, do: Enum.at(choices, 0), else: %{}
    message = choice["message"] || %{}
    usage = response["usage"] || %{}

    # Enhanced usage tracking
    enhanced_usage = parse_enhanced_usage(usage)

    # Calculate cost info (model needs provider prefix for pricing lookup)
    full_model_name = "openai/#{model}"

    cost_info =
      ExLLM.Core.Cost.calculate("openai", full_model_name, %{
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
          provider: :openai,
          raw_response: response
        })
    }
  end

  defp parse_enhanced_usage(usage) do
    base_usage = %{
      input_tokens: usage["prompt_tokens"] || 0,
      output_tokens: usage["completion_tokens"] || 0,
      total_tokens: usage["total_tokens"] || 0
    }

    # Add enhanced details if available
    prompt_details = usage["prompt_tokens_details"] || %{}
    completion_details = usage["completion_tokens_details"] || %{}

    enhanced_details = %{
      cached_tokens: prompt_details["cached_tokens"],
      audio_tokens:
        (prompt_details["audio_tokens"] || 0) + (completion_details["audio_tokens"] || 0),
      reasoning_tokens: completion_details["reasoning_tokens"]
    }

    Map.merge(base_usage, enhanced_details)
  end
end
