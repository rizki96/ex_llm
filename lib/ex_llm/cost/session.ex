defmodule ExLLM.Cost.Session do
  @moduledoc """
  Session-level cost tracking and aggregation functionality.

  This module provides comprehensive cost tracking across an entire conversation
  session, allowing users to monitor cumulative costs, analyze usage patterns,
  and get detailed breakdowns by provider and model.

  ## Usage

      # Start a new session
      session = ExLLM.Cost.Session.new("chat_session_1")

      # Add responses to track costs
      session = session
        |> ExLLM.Cost.Session.add_response(response1)
        |> ExLLM.Cost.Session.add_response(response2)

      # Get session summary
      summary = ExLLM.Cost.Session.get_summary(session)

      # Format for display
      formatted = ExLLM.Cost.Session.format_summary(session, format: :detailed)

  ## Features

  - **Cumulative Cost Tracking**: Track total costs across all messages
  - **Token Aggregation**: Monitor input/output token usage
  - **Provider Breakdown**: See costs by provider (OpenAI, Anthropic, etc.)
  - **Model Breakdown**: Analyze costs by specific model
  - **Efficiency Metrics**: Calculate cost per message, cost per token
  - **Multiple Display Formats**: Detailed, compact, and table formats
  """

  defstruct [
    :session_id,
    :start_time,
    total_cost: 0.0,
    total_input_tokens: 0,
    total_output_tokens: 0,
    messages: [],
    provider_breakdown: %{},
    model_breakdown: %{}
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          start_time: DateTime.t(),
          total_cost: float(),
          total_input_tokens: non_neg_integer(),
          total_output_tokens: non_neg_integer(),
          messages: [message_cost_entry()],
          provider_breakdown: %{String.t() => provider_stats()},
          model_breakdown: %{String.t() => model_stats()}
        }

  @type message_cost_entry :: %{
          timestamp: DateTime.t(),
          cost: float(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          model: String.t(),
          provider: String.t()
        }

  @type provider_stats :: %{
          total_cost: float(),
          total_tokens: non_neg_integer(),
          message_count: non_neg_integer()
        }

  @type model_stats :: %{
          total_cost: float(),
          total_tokens: non_neg_integer(),
          message_count: non_neg_integer(),
          provider: String.t()
        }

  @type session_summary :: %{
          session_id: String.t(),
          duration: non_neg_integer(),
          total_cost: float(),
          total_tokens: non_neg_integer(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          message_count: non_neg_integer(),
          average_cost_per_message: float(),
          cost_per_1k_tokens: float(),
          provider_breakdown: %{String.t() => provider_stats()},
          model_breakdown: %{String.t() => model_stats()}
        }

  @doc """
  Initialize a new cost tracking session.

  ## Parameters
  - `session_id` - Unique identifier for the session

  ## Examples

      iex> session = ExLLM.Cost.Session.new("chat_session_1")
      iex> session.session_id
      "chat_session_1"
      iex> session.total_cost
      0.0
  """
  @spec new(String.t()) :: t()
  def new(session_id) do
    %__MODULE__{
      session_id: session_id,
      start_time: DateTime.utc_now(),
      messages: []
    }
  end

  @doc """
  Add a response cost to the session tracking.

  The response should contain cost information (typically from `ExLLM.Cost.calculate/3`)
  and usage information.

  ## Parameters
  - `session` - Current session state
  - `response` - LLM response with cost and usage data

  ## Examples

      session = session |> ExLLM.Cost.Session.add_response(response)
  """
  @spec add_response(t(), map()) :: t()
  def add_response(session, response) do
    if response.cost && !Map.has_key?(response.cost, :error) do
      cost_data = response.cost
      usage_data = response.usage || %{}

      input_tokens = usage_data.input_tokens || 0
      output_tokens = usage_data.output_tokens || 0

      message_entry = create_message_cost_entry(cost_data, usage_data)

      %{
        session
        | total_cost: session.total_cost + cost_data.total_cost,
          total_input_tokens: session.total_input_tokens + input_tokens,
          total_output_tokens: session.total_output_tokens + output_tokens,
          messages: [message_entry | session.messages],
          provider_breakdown:
            update_provider_breakdown(session.provider_breakdown, message_entry),
          model_breakdown: update_model_breakdown(session.model_breakdown, message_entry)
      }
    else
      session
    end
  end

  @doc """
  Get session cost summary with detailed breakdown.

  Returns a comprehensive summary including totals, averages, and breakdowns.

  ## Examples

      summary = ExLLM.Cost.Session.get_summary(session)
      # => %{session_id: "...", total_cost: 0.45, ...}
  """
  @spec get_summary(t()) :: session_summary()
  def get_summary(session) do
    %{
      session_id: session.session_id,
      duration: DateTime.diff(DateTime.utc_now(), session.start_time, :second),
      total_cost: session.total_cost,
      total_tokens: session.total_input_tokens + session.total_output_tokens,
      input_tokens: session.total_input_tokens,
      output_tokens: session.total_output_tokens,
      message_count: length(session.messages),
      average_cost_per_message: safe_divide(session.total_cost, length(session.messages)),
      cost_per_1k_tokens: calculate_cost_per_1k_tokens(session),
      provider_breakdown: session.provider_breakdown,
      model_breakdown: session.model_breakdown
    }
  end

  @doc """
  Format session cost summary for display.

  ## Options
  - `:format` - Display format (`:detailed`, `:compact`, `:table`) (default: `:detailed`)

  ## Examples

      # Detailed format
      ExLLM.Cost.Session.format_summary(session)

      # Compact format
      ExLLM.Cost.Session.format_summary(session, format: :compact)

      # Table format
      ExLLM.Cost.Session.format_summary(session, format: :table)
  """
  @spec format_summary(t(), keyword()) :: String.t()
  def format_summary(session, opts \\ []) do
    summary = get_summary(session)
    format = Keyword.get(opts, :format, :detailed)

    case format do
      :detailed -> format_detailed_summary(summary)
      :compact -> format_compact_summary(summary)
      :table -> format_table_summary(summary)
      _ -> format_detailed_summary(summary)
    end
  end

  @doc """
  Get cost breakdown by provider.

  Returns a list of providers with their associated costs and usage statistics.

  ## Examples

      breakdown = ExLLM.Cost.Session.provider_breakdown(session)
      # => [%{provider: "openai", total_cost: 0.25, ...}, ...]
  """
  @spec provider_breakdown(t()) :: [map()]
  def provider_breakdown(session) do
    session.provider_breakdown
    |> Enum.map(fn {provider, stats} ->
      Map.put(stats, :provider, provider)
    end)
    |> Enum.sort_by(& &1.total_cost, :desc)
  end

  @doc """
  Get cost breakdown by model.

  Returns a list of models with their associated costs and usage statistics.

  ## Examples

      breakdown = ExLLM.Cost.Session.model_breakdown(session)
      # => [%{model: "gpt-4", total_cost: 0.30, ...}, ...]
  """
  @spec model_breakdown(t()) :: [map()]
  def model_breakdown(session) do
    session.model_breakdown
    |> Enum.map(fn {model, stats} ->
      Map.put(stats, :model, model)
    end)
    |> Enum.sort_by(& &1.total_cost, :desc)
  end

  # Private helper functions

  defp create_message_cost_entry(cost_data, usage_data) do
    %{
      timestamp: DateTime.utc_now(),
      cost: cost_data.total_cost,
      input_tokens: usage_data.input_tokens || 0,
      output_tokens: usage_data.output_tokens || 0,
      model: cost_data.model,
      provider: cost_data.provider
    }
  end

  defp update_provider_breakdown(breakdown, message_entry) do
    provider = message_entry.provider
    total_tokens = message_entry.input_tokens + message_entry.output_tokens

    Map.update(
      breakdown,
      provider,
      %{
        total_cost: message_entry.cost,
        total_tokens: total_tokens,
        message_count: 1
      },
      fn existing ->
        %{
          total_cost: existing.total_cost + message_entry.cost,
          total_tokens: existing.total_tokens + total_tokens,
          message_count: existing.message_count + 1
        }
      end
    )
  end

  defp update_model_breakdown(breakdown, message_entry) do
    model = message_entry.model
    total_tokens = message_entry.input_tokens + message_entry.output_tokens

    Map.update(
      breakdown,
      model,
      %{
        total_cost: message_entry.cost,
        total_tokens: total_tokens,
        message_count: 1,
        provider: message_entry.provider
      },
      fn existing ->
        %{
          total_cost: existing.total_cost + message_entry.cost,
          total_tokens: existing.total_tokens + total_tokens,
          message_count: existing.message_count + 1,
          provider: existing.provider
        }
      end
    )
  end

  defp safe_divide(_numerator, 0), do: 0.0
  defp safe_divide(numerator, denominator), do: numerator / denominator

  defp calculate_cost_per_1k_tokens(session) do
    total_tokens = session.total_input_tokens + session.total_output_tokens

    if total_tokens > 0 do
      session.total_cost / total_tokens * 1000
    else
      0.0
    end
  end

  # Formatting functions

  defp format_detailed_summary(summary) do
    duration_str = format_duration(summary.duration)

    """
    💰 Session Cost Summary (#{summary.session_id})
    ===============================================

    Duration: #{duration_str}
    Total Cost: #{ExLLM.Cost.format(summary.total_cost)}
    Total Tokens: #{format_number(summary.total_tokens)}
      ├─ Input: #{format_number(summary.input_tokens)}
      └─ Output: #{format_number(summary.output_tokens)}

    Messages: #{summary.message_count}
    Avg Cost/Message: #{ExLLM.Cost.format(summary.average_cost_per_message)}
    Cost/1K Tokens: #{ExLLM.Cost.format(summary.cost_per_1k_tokens)}

    #{format_provider_breakdown(summary.provider_breakdown)}
    #{format_model_breakdown(summary.model_breakdown)}
    """
  end

  defp format_compact_summary(summary) do
    "💰 #{ExLLM.Cost.format(summary.total_cost, style: :compact)} " <>
      "(#{summary.message_count} msgs, #{format_number(summary.total_tokens)} tokens)"
  end

  defp format_table_summary(summary) do
    """
    Session: #{summary.session_id}
    | Metric              | Value                                      |
    |---------------------|---------------------------------------------|
    | Total Cost          | #{ExLLM.Cost.format(summary.total_cost)}  |
    | Messages            | #{summary.message_count}                   |
    | Total Tokens        | #{format_number(summary.total_tokens)}     |
    | Avg Cost/Message    | #{ExLLM.Cost.format(summary.average_cost_per_message)} |
    | Cost/1K Tokens      | #{ExLLM.Cost.format(summary.cost_per_1k_tokens)} |
    | Duration            | #{format_duration(summary.duration)}       |
    """
  end

  defp format_provider_breakdown(provider_breakdown) when map_size(provider_breakdown) == 0 do
    ""
  end

  defp format_provider_breakdown(provider_breakdown) do
    breakdown_text =
      provider_breakdown
      |> Enum.map(fn {provider, stats} ->
        "  ├─ #{String.capitalize(provider)}: #{ExLLM.Cost.format(stats.total_cost)} " <>
          "(#{stats.message_count} msgs, #{format_number(stats.total_tokens)} tokens)"
      end)
      |> Enum.join("\n")

    "Provider Breakdown:\n#{breakdown_text}"
  end

  defp format_model_breakdown(model_breakdown) when map_size(model_breakdown) == 0 do
    ""
  end

  defp format_model_breakdown(model_breakdown) do
    breakdown_text =
      model_breakdown
      # Show top 5 models
      |> Enum.take(5)
      |> Enum.map(fn {model, stats} ->
        "  ├─ #{model}: #{ExLLM.Cost.format(stats.total_cost)} " <>
          "(#{stats.message_count} msgs)"
      end)
      |> Enum.join("\n")

    more_text =
      if map_size(model_breakdown) > 5 do
        "\n  └─ ... and #{map_size(model_breakdown) - 5} more models"
      else
        ""
      end

    "Top Models:\n#{breakdown_text}#{more_text}"
  end

  defp format_duration(seconds) when seconds < 60 do
    "#{seconds}s"
  end

  defp format_duration(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)
    "#{minutes}m #{remaining_seconds}s"
  end

  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    remaining_minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{remaining_minutes}m"
  end

  defp format_number(number) when number >= 1_000_000 do
    millions = number / 1_000_000
    "#{:erlang.float_to_binary(millions, decimals: 1)}M"
  end

  defp format_number(number) when number >= 1_000 do
    thousands = number / 1_000
    "#{:erlang.float_to_binary(thousands, decimals: 1)}K"
  end

  defp format_number(number) do
    Integer.to_string(number)
  end
end
