defmodule ExLLM.Cost do
  @moduledoc """
  Cost calculation functionality for ExLLM.

  Provides token estimation, cost calculation, and pricing information
  for all supported LLM providers.
  """

  alias ExLLM.Types

  # Pricing per 1M tokens (as of May 2025)
  @pricing %{
    "anthropic" => %{
      # Claude 4 series
      "claude-opus-4-20250514" => %{input: 15.00, output: 75.00},
      "claude-opus-4-0" => %{input: 15.00, output: 75.00},
      "claude-sonnet-4-20250514" => %{input: 3.00, output: 15.00},
      "claude-sonnet-4-0" => %{input: 3.00, output: 15.00},

      # Claude 3.7 series
      "claude-3-7-sonnet-20250219" => %{input: 3.00, output: 15.00},
      "claude-3-7-sonnet-latest" => %{input: 3.00, output: 15.00},

      # Claude 3.5 series
      "claude-3-5-sonnet-20241022" => %{input: 3.00, output: 15.00},
      "claude-3-5-sonnet-latest" => %{input: 3.00, output: 15.00},
      "claude-3-5-haiku-20241022" => %{input: 0.80, output: 4.00},
      "claude-3-5-haiku-latest" => %{input: 0.80, output: 4.00},

      # Claude 3 series
      "claude-3-opus-20240229" => %{input: 15.00, output: 75.00},
      "claude-3-opus-latest" => %{input: 15.00, output: 75.00},
      "claude-3-haiku-20240307" => %{input: 0.25, output: 1.25}
    },
    "openai" => %{
      # GPT-4.1 series
      "gpt-4.1" => %{input: 2.00, output: 8.00},
      "gpt-4.1-2025-04-14" => %{input: 2.00, output: 8.00},
      "gpt-4.1-mini" => %{input: 0.40, output: 1.60},
      "gpt-4.1-mini-2025-04-14" => %{input: 0.40, output: 1.60},
      "gpt-4.1-nano" => %{input: 0.10, output: 0.40},
      "gpt-4.1-nano-2025-04-14" => %{input: 0.10, output: 0.40},

      # GPT-4.5 preview
      "gpt-4.5-preview" => %{input: 75.00, output: 150.00},
      "gpt-4.5-preview-2025-02-27" => %{input: 75.00, output: 150.00},

      # GPT-4o series
      "gpt-4o" => %{input: 2.50, output: 10.00},
      "gpt-4o-2024-08-06" => %{input: 2.50, output: 10.00},
      "gpt-4o-audio-preview" => %{input: 2.50, output: 10.00},
      "gpt-4o-audio-preview-2024-12-17" => %{input: 2.50, output: 10.00},
      "gpt-4o-realtime-preview" => %{input: 5.00, output: 20.00},
      "gpt-4o-realtime-preview-2024-12-17" => %{input: 5.00, output: 20.00},
      "gpt-4o-mini" => %{input: 0.15, output: 0.60},
      "gpt-4o-mini-2024-07-18" => %{input: 0.15, output: 0.60},
      "gpt-4o-mini-audio-preview" => %{input: 0.15, output: 0.60},
      "gpt-4o-mini-audio-preview-2024-12-17" => %{input: 0.15, output: 0.60},
      "gpt-4o-mini-realtime-preview" => %{input: 0.60, output: 2.40},
      "gpt-4o-mini-realtime-preview-2024-12-17" => %{input: 0.60, output: 2.40},

      # O-series reasoning models
      "o1" => %{input: 15.00, output: 60.00},
      "o1-2024-12-17" => %{input: 15.00, output: 60.00},
      "o1-pro" => %{input: 150.00, output: 600.00},
      "o1-pro-2025-03-19" => %{input: 150.00, output: 600.00},
      "o3" => %{input: 10.00, output: 40.00},
      "o3-2025-04-16" => %{input: 10.00, output: 40.00},
      "o4-mini" => %{input: 1.10, output: 4.40},
      "o4-mini-2025-04-16" => %{input: 1.10, output: 4.40},
      "o3-mini" => %{input: 1.10, output: 4.40},
      "o3-mini-2025-01-31" => %{input: 1.10, output: 4.40},
      "o1-mini" => %{input: 1.10, output: 4.40},
      "o1-mini-2024-09-12" => %{input: 1.10, output: 4.40},

      # Other models
      "codex-mini-latest" => %{input: 1.50, output: 6.00},
      "gpt-4o-mini-search-preview" => %{input: 0.15, output: 0.60},
      "gpt-4o-mini-search-preview-2025-03-11" => %{input: 0.15, output: 0.60},
      "gpt-4o-search-preview" => %{input: 2.50, output: 10.00},
      "gpt-4o-search-preview-2025-03-11" => %{input: 2.50, output: 10.00},
      "computer-use-preview" => %{input: 3.00, output: 12.00},
      "computer-use-preview-2025-03-11" => %{input: 3.00, output: 12.00}

      # Note: gpt-image-1 is excluded as it's for image generation, not text
    },
    "bedrock" => %{
      # Anthropic models (non-batch pricing)
      "claude-opus-4" => %{input: 15.00, output: 75.00},
      "claude-opus-4-20250514" => %{input: 15.00, output: 75.00},
      "claude-sonnet-4" => %{input: 3.00, output: 15.00},
      "claude-sonnet-4-20250514" => %{input: 3.00, output: 15.00},
      "claude-3-7-sonnet" => %{input: 3.00, output: 15.00},
      "claude-3-7-sonnet-20250219" => %{input: 3.00, output: 15.00},
      "claude-3-5-sonnet" => %{input: 3.00, output: 15.00},
      "claude-3-5-sonnet-20241022" => %{input: 3.00, output: 15.00},
      "claude-3-5-haiku" => %{input: 0.80, output: 4.00},
      "claude-3-5-haiku-20241022" => %{input: 0.80, output: 4.00},
      "claude-3-opus" => %{input: 15.00, output: 75.00},
      "claude-3-opus-20240229" => %{input: 15.00, output: 75.00},
      "claude-3-sonnet" => %{input: 3.00, output: 15.00},
      "claude-3-sonnet-20240229" => %{input: 3.00, output: 15.00},
      "claude-3-haiku" => %{input: 0.25, output: 1.25},
      "claude-3-haiku-20240307" => %{input: 0.25, output: 1.25},
      "claude-instant-v1" => %{input: 0.80, output: 2.40},
      "claude-v2" => %{input: 8.00, output: 24.00},
      "claude-v2.1" => %{input: 8.00, output: 24.00},

      # Amazon Nova models
      "nova-micro" => %{input: 0.035, output: 0.14},
      "nova-lite" => %{input: 0.06, output: 0.24},
      "nova-pro" => %{input: 0.80, output: 3.20},
      "nova-premier" => %{input: 2.50, output: 12.50},

      # Amazon Titan models
      "titan-lite" => %{input: 0.30, output: 0.40},
      "titan-express" => %{input: 1.30, output: 1.70},

      # AI21 Labs models
      "jamba-1.5-large" => %{input: 2.00, output: 8.00},
      "jamba-1.5-mini" => %{input: 0.20, output: 0.40},
      "jamba-instruct" => %{input: 0.50, output: 0.70},
      "jurassic-2-mid" => %{input: 12.50, output: 12.50},
      "jurassic-2-ultra" => %{input: 18.80, output: 18.80},

      # Cohere models
      "command" => %{input: 1.50, output: 2.00},
      "command-light" => %{input: 0.30, output: 0.60},
      "command-r-plus" => %{input: 3.00, output: 15.00},
      "command-r" => %{input: 0.50, output: 1.50},

      # DeepSeek models
      "deepseek-r1" => %{input: 1.35, output: 5.40},

      # Meta Llama models
      "llama-4-maverick-17b" => %{input: 0.24, output: 0.97},
      "llama-4-scout-17b" => %{input: 0.17, output: 0.66},
      "llama-3.3-70b" => %{input: 0.72, output: 0.72},
      "llama-3.3-70b-instruct" => %{input: 0.72, output: 0.72},
      "llama-3.2-1b" => %{input: 0.10, output: 0.10},
      "llama-3.2-1b-instruct" => %{input: 0.10, output: 0.10},
      "llama-3.2-3b" => %{input: 0.15, output: 0.15},
      "llama-3.2-3b-instruct" => %{input: 0.15, output: 0.15},
      "llama-3.2-11b" => %{input: 0.32, output: 0.32},
      "llama-3.2-11b-instruct" => %{input: 0.32, output: 0.32},
      "llama-3.2-90b" => %{input: 0.88, output: 0.88},
      "llama-3.2-90b-instruct" => %{input: 0.88, output: 0.88},
      "llama2-13b" => %{input: 0.75, output: 1.00},
      "llama2-70b" => %{input: 1.95, output: 2.56},

      # Mistral models
      "pixtral-large" => %{input: 2.00, output: 6.00},
      "pixtral-large-2025-02" => %{input: 2.00, output: 6.00},
      "mistral-7b" => %{input: 0.20, output: 0.26},
      "mixtral-8x7b" => %{input: 0.45, output: 0.70},

      # Writer models
      "palmyra-x4" => %{input: 2.50, output: 10.00},
      "palmyra-x5" => %{input: 0.60, output: 6.00}
    },
    "gemini" => %{
      # Gemini 2.5 series
      "gemini-2.5-flash-preview-05-20" => %{input: 0.15, output: 0.60},
      # Using lower tier pricing
      "gemini-2.5-pro-preview-05-06" => %{input: 1.25, output: 10.00},

      # Gemini 2.0 series
      "gemini-2.0-flash" => %{input: 0.10, output: 0.40},
      "gemini-2.0-flash-lite" => %{input: 0.075, output: 0.30},

      # Gemini 1.5 series
      # Using lower tier pricing
      "gemini-1.5-flash" => %{input: 0.075, output: 0.30},
      # Using lower tier pricing
      "gemini-1.5-pro" => %{input: 1.25, output: 5.00}
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
