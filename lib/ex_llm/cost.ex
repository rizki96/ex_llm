defmodule ExLLM.Cost do
  @moduledoc """
  Cost calculation functionality for ExLLM.

  Provides token estimation, cost calculation, and pricing information
  for all supported LLM providers.
  """

  alias ExLLM.Types

  # Pricing per 1M tokens (as of January 2025)
  @pricing %{
    "anthropic" => %{
      "claude-3-5-sonnet-20241022" => %{input: 3.00, output: 15.00},
      "claude-3-5-haiku-20241022" => %{input: 1.00, output: 5.00},
      "claude-3-opus-20240229" => %{input: 15.00, output: 75.00},
      "claude-3-sonnet-20240229" => %{input: 3.00, output: 15.00},
      "claude-3-haiku-20240307" => %{input: 0.25, output: 1.25},
      "claude-sonnet-4-20250514" => %{input: 3.00, output: 15.00},
      "claude-4" => %{input: 3.00, output: 15.00}
    },
    "openai" => %{
      "gpt-4-turbo" => %{input: 10.00, output: 30.00},
      "gpt-4-turbo-preview" => %{input: 10.00, output: 30.00},
      "gpt-4" => %{input: 30.00, output: 60.00},
      "gpt-4-32k" => %{input: 60.00, output: 120.00},
      "gpt-3.5-turbo" => %{input: 0.50, output: 1.50},
      "gpt-3.5-turbo-16k" => %{input: 3.00, output: 4.00},
      "gpt-4o" => %{input: 5.00, output: 15.00},
      "gpt-4o-mini" => %{input: 0.15, output: 0.60}
    },
    "bedrock" => %{
      "claude-instant-v1" => %{input: 0.80, output: 2.40},
      "claude-v2" => %{input: 8.00, output: 24.00},
      "claude-v2.1" => %{input: 8.00, output: 24.00},
      "claude-3-sonnet" => %{input: 3.00, output: 15.00},
      "claude-3-haiku" => %{input: 0.25, output: 1.25},
      "titan-lite" => %{input: 0.30, output: 0.40},
      "titan-express" => %{input: 1.30, output: 1.70},
      "llama2-13b" => %{input: 0.75, output: 1.00},
      "llama2-70b" => %{input: 1.95, output: 2.56},
      "command" => %{input: 1.50, output: 2.00},
      "command-light" => %{input: 0.30, output: 0.60},
      "jurassic-2-mid" => %{input: 1.25, output: 1.25},
      "jurassic-2-ultra" => %{input: 18.80, output: 18.80},
      "mistral-7b" => %{input: 0.20, output: 0.26},
      "mixtral-8x7b" => %{input: 0.45, output: 0.70}
    },
    "gemini" => %{
      "gemini-pro" => %{input: 0.50, output: 1.50},
      "gemini-pro-vision" => %{input: 0.50, output: 1.50},
      "gemini-ultra" => %{input: 5.00, output: 15.00},
      "gemini-nano" => %{input: 0.10, output: 0.30}
    },
    "ollama" => %{
      # Local models have no cost
      "llama2" => %{input: 0.0, output: 0.0},
      "mistral" => %{input: 0.0, output: 0.0},
      "codellama" => %{input: 0.0, output: 0.0}
    }
  }

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
    @pricing
    |> Map.get(provider, %{})
    |> Map.get(model)
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
        cents = cost_in_dollars * 100
        "$#{:erlang.float_to_binary(cents, decimals: 3)}¢"

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
    for {provider, models} <- @pricing,
        {model, prices} <- models do
      %{
        provider: provider,
        model: model,
        input_per_1m: prices.input,
        output_per_1m: prices.output
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
