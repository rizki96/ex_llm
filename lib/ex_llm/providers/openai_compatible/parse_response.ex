defmodule ExLLM.Providers.OpenAICompatible.ParseResponse do
  @moduledoc """
  Shared pipeline plug for parsing OpenAI-compatible API responses.

  This module provides a configurable implementation that can be used by
  any provider that follows the OpenAI response format. The main difference
  between providers is the cost calculation provider name.
  """

  alias ExLLM.Types

  @doc """
  Creates a ParseResponse plug for an OpenAI-compatible provider.

  ## Options

  - `:provider` - The provider atom (required) - used for cost calculation and metadata
  - `:cost_provider` - Provider name for cost calculation (defaults to provider)

  ## Example

      defmodule ExLLM.Providers.MyProvider.ParseResponse do
        use ExLLM.Providers.OpenAICompatible.ParseResponse,
          provider: :my_provider,
          cost_provider: "my_provider"
      end
  """
  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)
    cost_provider = Keyword.get(opts, :cost_provider, Atom.to_string(provider))

    quote do
      use ExLLM.Plug

      alias ExLLM.Pipeline.Request

      @provider unquote(provider)
      @cost_provider unquote(cost_provider)

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
        choice = get_in(response, ["choices", Access.at(0)]) || %{}
        message = choice["message"] || %{}
        usage = response["usage"] || %{}

        # Parse usage in OpenAI format
        enhanced_usage = parse_usage(usage)

        # Calculate cost for provider
        cost_info =
          ExLLM.Core.Cost.calculate(@cost_provider, model, %{
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
              provider: @provider,
              raw_response: response
            })
        }
      end

      defp parse_usage(usage) do
        base_usage = %{
          input_tokens: usage["prompt_tokens"] || 0,
          output_tokens: usage["completion_tokens"] || 0,
          total_tokens: usage["total_tokens"] || 0
        }

        # Add enhanced details if available (like OpenAI)
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

      # Allow overriding
      defoverridable parse_response: 2, parse_usage: 1
    end
  end
end
