defmodule ExLLM.Cost do
  @moduledoc """
  Cost calculation functionality for ExLLM.

  Provides token estimation, cost calculation, and pricing information
  for all supported LLM providers.
  """

  alias ExLLM.{Types, ModelConfig}

  # Pricing is now loaded from external YAML configuration files
  # See config/models/ for model pricing, context windows, and capabilities

  @doc """
  Calculate cost for token usage.
  """
  @spec calculate(String.t(), String.t(), Types.token_usage()) ::
          Types.cost_result() | %{error: String.t()}
  def calculate(provider, model, token_usage) do
    case get_pricing(provider, model) do
      nil ->
        %{
          error: "No pricing data available for #{provider}/#{model}",
          provider: provider,
          model: model
        }

      pricing ->
        input_cost = calculate_token_cost(token_usage.input_tokens, pricing.input)
        output_cost = calculate_token_cost(token_usage.output_tokens, pricing.output)
        total_cost = input_cost + output_cost

        %{
          provider: provider,
          model: model,
          input_tokens: token_usage.input_tokens,
          output_tokens: token_usage.output_tokens,
          total_tokens: token_usage.input_tokens + token_usage.output_tokens,
          input_cost: input_cost,
          output_cost: output_cost,
          total_cost: total_cost,
          currency: "USD",
          pricing: pricing
        }
    end
  end

  @doc """
  Get pricing for a specific provider and model.
  """
  @spec get_pricing(String.t(), String.t()) :: %{input: float(), output: float()} | nil
  def get_pricing(provider, model) do
    provider_atom = if is_binary(provider), do: String.to_existing_atom(provider), else: provider
    ModelConfig.get_pricing(provider_atom, model)
  end

  @doc """
  Estimate token count for text using heuristic analysis.
  """
  @spec estimate_tokens(String.t() | map() | [map()]) :: non_neg_integer()
  def estimate_tokens(text) when is_binary(text) do
    if text == "" do
      0
    else
      words = String.split(text, ~r/\s+/)
      word_tokens = length(words) * 1.3

      special_chars = String.replace(text, ~r/[a-zA-Z0-9\s]/, "") |> String.length()
      special_tokens = special_chars * 0.5

      round(word_tokens + special_tokens)
    end
  end

  def estimate_tokens(%{content: nil}), do: 0

  def estimate_tokens(%{content: content}) do
    estimate_tokens(content)
  end

  def estimate_tokens(messages) when is_list(messages) do
    Enum.reduce(messages, 0, fn msg, acc ->
      acc + estimate_tokens(msg) + 3
    end)
  end

  @doc """
  Format cost for human-readable display.
  """
  @spec format(float()) :: String.t()
  def format(cost_in_dollars) do
    cond do
      cost_in_dollars < 0.01 ->
        "$#{:erlang.float_to_binary(cost_in_dollars, decimals: 6)}"

      cost_in_dollars < 1.0 ->
        "$#{:erlang.float_to_binary(cost_in_dollars, decimals: 4)}"

      true ->
        "$#{:erlang.float_to_binary(cost_in_dollars, decimals: 2)}"
    end
  end

  @doc """
  List all available models and their pricing.
  """
  @spec list_pricing :: [
          %{
            provider: String.t(),
            model: String.t(),
            input_per_1m: float(),
            output_per_1m: float()
          }
        ]
  def list_pricing do
    providers = [:anthropic, :openai, :openrouter, :gemini, :ollama, :bedrock]

    for provider <- providers,
        {model, pricing} <- ModelConfig.get_all_pricing(provider),
        pricing != nil do
      %{
        provider: Atom.to_string(provider),
        model: model,
        input_per_1m: pricing.input,
        output_per_1m: pricing.output
      }
    end
    |> Enum.sort_by(&{&1.provider, &1.model})
  end

  @doc """
  Compare costs across different providers for the same usage.
  """
  @spec compare(Types.token_usage(), [{String.t(), String.t()}]) :: [Types.cost_result()]
  def compare(token_usage, provider_models) do
    provider_models
    |> Enum.map(fn {provider, model} ->
      calculate(provider, model, token_usage)
    end)
    |> Enum.reject(&Map.has_key?(&1, :error))
    |> Enum.sort_by(& &1.total_cost)
  end

  # Private functions

  defp calculate_token_cost(tokens, price_per_million) do
    tokens / 1_000_000 * price_per_million
  end
end
