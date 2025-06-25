defmodule ExLLM.Core.Cost do
  @moduledoc """
  Cost calculation functionality for ExLLM.

  Provides token estimation, cost calculation, and pricing information
  for all supported LLM providers.
  """

  alias ExLLM.{Infrastructure.Config.ModelConfig, Types}

  # Pricing is now loaded from external YAML configuration files
  # See config/models/ for model pricing, context windows, and capabilities

  @doc """
  Calculate cost for token usage.
  """
  @spec calculate(String.t() | atom(), String.t() | atom(), Types.token_usage()) ::
          Types.cost_result() | %{error: String.t()}
  def calculate(provider, model, token_usage) do
    case get_pricing(provider, model) do
      nil ->
        %{
          error: "No pricing data available for #{provider}/#{model}",
          provider: to_string(provider),
          model: model
        }

      pricing ->
        input_cost = calculate_token_cost(token_usage.input_tokens, pricing.input)
        output_cost = calculate_token_cost(token_usage.output_tokens, pricing.output)
        total_cost = input_cost + output_cost

        %{
          provider: to_string(provider),
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
  @spec get_pricing(String.t() | atom(), String.t()) :: %{input: float(), output: float()} | nil
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

  ## Options

  - `:style` - Formatting style (`:auto`, `:detailed`, `:compact`) (default: `:auto`)
  - `:precision` - Fixed precision or `:auto` for dynamic precision (default: `:auto`)

  ## Examples

      iex> ExLLM.Core.Cost.format(0.0045)
      "$0.004500"

      iex> ExLLM.Core.Cost.format(0.0045, style: :detailed)
      "$0.004500"

      iex> ExLLM.Core.Cost.format(1234.56, style: :auto)
      "$1,234.56"

      iex> ExLLM.Core.Cost.format(0.1234, precision: 3)
      "$0.123"
  """
  @spec format(float(), keyword()) :: String.t()
  def format(cost_in_dollars, opts \\ [])

  def format(cost_in_dollars, opts)
      when is_float(cost_in_dollars) or is_integer(cost_in_dollars) do
    cost = if is_integer(cost_in_dollars), do: cost_in_dollars / 1.0, else: cost_in_dollars
    style = Keyword.get(opts, :style, :auto)
    precision = Keyword.get(opts, :precision, :auto)

    case {style, precision} do
      {:auto, :auto} -> auto_format(cost)
      {:detailed, _} -> detailed_format(cost)
      {:compact, _} -> compact_format(cost)
      {_, precision} when is_integer(precision) -> fixed_precision_format(cost, precision)
      _ -> auto_format(cost)
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

  # Intelligent context-aware formatting
  defp auto_format(cost) when cost < 0.01 do
    "$#{:erlang.float_to_binary(cost, decimals: 6)}"
  end

  defp auto_format(cost) when cost < 1.0 do
    "$#{:erlang.float_to_binary(cost, decimals: 4)}"
  end

  defp auto_format(cost) when cost < 100.0 do
    "$#{:erlang.float_to_binary(cost, decimals: 2)}"
  end

  defp auto_format(cost) do
    formatted = :erlang.float_to_binary(cost, decimals: 2)
    "$#{add_thousands_separator(formatted)}"
  end

  # Detailed formatting with additional context
  defp detailed_format(cost) when cost < 0.01 do
    "$#{:erlang.float_to_binary(cost, decimals: 6)}"
  end

  defp detailed_format(cost) when cost < 1.0 do
    "$#{:erlang.float_to_binary(cost, decimals: 4)}"
  end

  defp detailed_format(cost) do
    "$#{add_thousands_separator(:erlang.float_to_binary(cost, decimals: 2))}"
  end

  # Compact formatting for space-constrained displays
  defp compact_format(cost) when cost < 0.01 do
    "$#{:erlang.float_to_binary(cost, decimals: 4)}"
  end

  defp compact_format(cost) when cost < 1.0 do
    "$#{:erlang.float_to_binary(cost, decimals: 3)}"
  end

  defp compact_format(cost) when cost < 1000.0 do
    "$#{:erlang.float_to_binary(cost, decimals: 1)}"
  end

  defp compact_format(cost) do
    if cost >= 1_000_000 do
      millions = cost / 1_000_000
      "#{:erlang.float_to_binary(millions, decimals: 1)}M"
    else
      thousands = cost / 1000
      "#{:erlang.float_to_binary(thousands, decimals: 1)}K"
    end
  end

  # Fixed precision formatting
  defp fixed_precision_format(cost, precision) do
    "$#{:erlang.float_to_binary(cost, decimals: precision)}"
  end

  # Add thousands separators for readability
  defp add_thousands_separator(number_string) do
    [integer_part | decimal_part] = String.split(number_string, ".")

    integer_with_separators =
      integer_part
      |> String.reverse()
      |> String.codepoints()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.join/1)
      |> Enum.join(",")
      |> String.reverse()

    case decimal_part do
      [] -> integer_with_separators
      [decimals] -> "#{integer_with_separators}.#{decimals}"
    end
  end

  defp calculate_token_cost(tokens, price_per_million) do
    tokens / 1_000_000 * price_per_million
  end
end
