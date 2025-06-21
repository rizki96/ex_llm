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
    usage = result[:usage] || %{}

    if usage == %{} do
      # No usage data available
      request
    else
      # Calculate cost
      cost = calculate_cost(request, usage, opts)

      # Update result with cost
      updated_result = Map.put(result, :cost, cost)

      # Emit telemetry event
      :telemetry.execute(
        [:ex_llm, :cost, :calculated],
        %{
          cost: cost.total,
          input_tokens: usage[:prompt_tokens] || 0,
          output_tokens: usage[:completion_tokens] || 0
        },
        %{
          provider: request.provider,
          model: result[:model] || request.config[:model]
        }
      )

      request
      |> Map.put(:result, updated_result)
      |> Request.put_metadata(:cost, cost)
      |> Request.put_metadata(:cost_usd, cost.total)
      |> Request.assign(:cost_tracked, true)
    end
  end

  defp calculate_cost(request, usage, opts) do
    provider = request.provider
    model = request.result[:model] || request.config[:model]

    # Get pricing
    pricing = get_pricing(provider, model, opts)

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
          get_default_pricing(ensure_atom_provider(provider))
      end
    end
  end

  defp get_default_pricing(provider) when is_atom(provider) do
    case provider do
      :openai -> %{input: 3.00, output: 15.00}
      :anthropic -> %{input: 15.00, output: 75.00}
      :gemini -> %{input: 0.50, output: 1.50}
      :groq -> %{input: 0.10, output: 0.10}
      :mistral -> %{input: 2.00, output: 6.00}
      _ -> %{input: 1.00, output: 3.00}
    end
  end

  defp ensure_atom_provider(provider) when is_binary(provider), do: String.to_atom(provider)
end
