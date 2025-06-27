defmodule ExLLM.Plugs.TrackCost do
  @moduledoc """
  Tracks the cost of LLM API calls based on token usage and provider pricing.

  This plug should run after the response has been parsed and token usage
  information is available. It calculates the cost based on the provider's
  pricing model and adds it to the request metadata.

  ## Cost Calculation

  Costs are calculated based on:
  - Input tokens (prompt)
  - Output tokens (completion)
  - Provider-specific pricing tiers
  - Model-specific pricing

  ## Options

    * `:pricing_override` - Override default pricing (per 1M tokens)
    
  ## Examples

      plug ExLLM.Plugs.TrackCost
      
      # With custom pricing
      plug ExLLM.Plugs.TrackCost,
        pricing_override: %{
          input: 10.00,  # $10 per 1M input tokens
          output: 30.00  # $30 per 1M output tokens
        }
  """

  use ExLLM.Plug
  alias ExLLM.Core.Cost
  alias ExLLM.Infrastructure.Logger

  @impl true
  def init(opts) do
    Keyword.validate!(opts, [:pricing_override])
  end

  @impl true
  def call(%Request{result: nil} = request, _opts) do
    # No result to track cost for
    request
  end

  def call(%Request{result: result} = request, opts) do
    usage = get_usage(result)

    if usage == %{} do
      # No usage data available
      request
    else
      # Calculate cost
      cost_data = calculate_cost(request, usage, opts)

      # Update result with cost (as float) and detailed cost breakdown
      updated_result =
        result
        |> put_cost(cost_data.total)
        |> put_cost_details(cost_data)

      # Emit telemetry event
      :telemetry.execute(
        [:ex_llm, :cost, :calculated],
        %{
          cost: cost_data.total,
          input_tokens: usage[:prompt_tokens] || 0,
          output_tokens: usage[:completion_tokens] || 0
        },
        %{
          provider: request.provider,
          model: get_model(result) || request.config[:model]
        }
      )

      request
      |> Map.put(:result, updated_result)
      |> Request.put_metadata(:cost, cost_data.total)
      |> Request.put_metadata(:cost_usd, cost_data.total)
      |> Request.assign(:cost_tracked, true)
    end
  end

  defp calculate_cost(request, usage, opts) do
    provider = request.provider
    model = get_model(request.result) || request.config[:model]

    # Strip any provider prefix from model name for pricing lookup
    clean_model = strip_provider_prefix(model, provider)

    # Get pricing
    pricing = get_pricing(provider, clean_model, opts)

    # Extract token counts
    input_tokens = usage[:prompt_tokens] || 0
    output_tokens = usage[:completion_tokens] || 0
    total_tokens = usage[:total_tokens] || input_tokens + output_tokens

    # Calculate costs (pricing is per 1M tokens)
    input_cost = input_tokens / 1_000_000 * pricing.input
    output_cost = output_tokens / 1_000_000 * pricing.output
    total_cost = input_cost + output_cost

    %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens,
      input_cost: input_cost,
      output_cost: output_cost,
      total: total_cost,
      currency: "USD",
      pricing: pricing
    }
  end

  defp get_pricing(provider, model, opts) do
    if opts[:pricing_override] do
      %{
        input: opts[:pricing_override][:input] || 0,
        output: opts[:pricing_override][:output] || 0
      }
    else
      # Use the existing Cost module for pricing
      case Cost.get_pricing(provider, model) do
        %{input: input_price, output: output_price} ->
          # Core.Cost returns %{input: 30.0, output: 60.0} format (already per 1M tokens)
          %{
            input: input_price,
            output: output_price
          }

        _ ->
          # Fallback pricing
          Logger.warning("No pricing found for #{provider}/#{model}, using defaults")
          get_default_pricing(provider)
      end
    end
  end

  defp get_default_pricing(provider) when is_binary(provider) do
    get_default_pricing(String.to_atom(provider))
  end

  defp get_default_pricing(provider) when is_atom(provider) do
    case provider do
      :openai -> %{input: 3.00, output: 15.00}
      :anthropic -> %{input: 15.00, output: 75.00}
      :gemini -> %{input: 0.50, output: 1.50}
      :groq -> %{input: 0.10, output: 0.10}
      :mistral -> %{input: 2.00, output: 6.00}
      :ollama -> %{input: 0.00, output: 0.00}
      :lmstudio -> %{input: 0.00, output: 0.00}
      :bumblebee -> %{input: 0.00, output: 0.00}
      _ -> %{input: 1.00, output: 3.00}
    end
  end

  # Helper functions for struct/map compatibility
  defp get_usage(%{usage: usage}), do: usage || %{}
  defp get_usage(result) when is_map(result), do: result[:usage] || %{}
  defp get_usage(_), do: %{}

  defp put_cost(%{__struct__: _} = struct, cost), do: %{struct | cost: cost}
  defp put_cost(result, cost) when is_map(result), do: Map.put(result, :cost, cost)
  defp put_cost(result, _cost), do: result

  defp get_model(%{model: model}), do: model
  defp get_model(result) when is_map(result), do: result[:model]
  defp get_model(_), do: nil

  defp put_cost_details(%{__struct__: _} = struct, cost_data) do
    %{struct | metadata: Map.put(struct.metadata || %{}, :cost_details, cost_data)}
  end

  defp put_cost_details(result, cost_data) when is_map(result) do
    Map.put(result, :cost_details, cost_data)
  end

  defp put_cost_details(result, _cost_data), do: result

  # Strip provider prefix from model name to ensure clean lookup
  defp strip_provider_prefix(model, provider) when is_binary(model) and is_atom(provider) do
    provider_prefix = "#{provider}/"

    # Recursively strip provider prefixes until none remain
    if String.starts_with?(model, provider_prefix) do
      cleaned = String.replace_prefix(model, provider_prefix, "")
      strip_provider_prefix(cleaned, provider)
    else
      model
    end
  end

  defp strip_provider_prefix(model, _provider), do: model
end
