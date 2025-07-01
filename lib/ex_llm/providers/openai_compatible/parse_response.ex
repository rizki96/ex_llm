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
        # Skip parsing if this is a streaming request that was already handled
        if request.state == :streaming do
          request
        else
          response = request.assigns.http_response
          model = request.assigns.model

          parsed_response = __MODULE__.parse_response(response, model, @provider, @cost_provider)

          request
          |> Request.assign(:llm_response, parsed_response)
          |> Map.put(:result, parsed_response)
          |> Request.put_state(:completed)
        end
      end

      def parse_response(response, model, provider, cost_provider) do
        choice = extract_first_choice_from_response(response)
        message = extract_message_from_choice(choice)
        usage = response["usage"] || %{}

        enhanced_usage = parse_usage(usage)
        cost_info = calculate_response_cost(cost_provider, model, enhanced_usage)
        cost_value = extract_cost_value(cost_info)
        content = extract_response_content(message)

        %Types.LLMResponse{
          content: content,
          function_call: message["function_call"],
          tool_calls: message["tool_calls"],
          refusal: message["refusal"],
          logprobs: choice["logprobs"],
          usage: enhanced_usage,
          model: model,
          finish_reason: choice["finish_reason"],
          cost: cost_value,
          metadata: build_response_metadata(response, cost_info, provider)
        }
      end

      defp extract_first_choice_from_response(response) do
        choices = response["choices"] || []

        if is_list(choices) and length(choices) > 0 do
          Enum.at(choices, 0)
        else
          %{}
        end
      end

      defp extract_message_from_choice(choice) do
        choice["message"] || %{}
      end

      defp calculate_response_cost(cost_provider, model, enhanced_usage) do
        full_model_name = "#{cost_provider}/#{model}"

        ExLLM.Core.Cost.calculate(cost_provider, full_model_name, %{
          input_tokens: enhanced_usage.input_tokens,
          output_tokens: enhanced_usage.output_tokens
        })
      end

      defp extract_cost_value(cost_info) do
        case cost_info do
          %{total_cost: cost} -> cost
          %{error: _} -> nil
          _ -> nil
        end
      end

      defp extract_response_content(message) do
        case {message["content"], message["reasoning_content"]} do
          {content, _} when content != nil and content != "" ->
            content

          {_, reasoning_content} when reasoning_content != nil and reasoning_content != "" ->
            reasoning_content

          {content, _} ->
            content || ""
        end
      end

      defp build_response_metadata(response, cost_info, provider) do
        Map.merge(response["metadata"] || %{}, %{
          cost_details: cost_info,
          role: "assistant",
          provider: provider,
          raw_response: response
        })
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
      defoverridable parse_response: 4, parse_usage: 1
    end
  end
end
