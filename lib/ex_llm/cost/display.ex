defmodule ExLLM.Cost.Display do
  @moduledoc """
  Utilities for displaying cost information in various formats.

  This module provides flexible display functions for cost data, supporting
  multiple output formats including ASCII tables, markdown, CSV, and specialized
  CLI displays. It's designed to work with ExLLM.Cost and ExLLM.Cost.Session
  data structures.

  ## Supported Formats

  - **ASCII Tables**: Terminal-friendly tables with borders and alignment
  - **Markdown Tables**: GitHub-flavored markdown tables
  - **CSV Output**: Comma-separated values for data processing
  - **JSON Output**: Structured JSON for API responses
  - **CLI Summary**: Rich terminal output with emojis and formatting
  - **Streaming Display**: Real-time cost updates during streaming

  ## Usage

      # Generate cost breakdown table
      table = ExLLM.Cost.Display.cost_breakdown_table(cost_data, format: :ascii)

      # CLI-friendly session summary
      summary = ExLLM.Cost.Display.cli_summary(session_summary)

      # Real-time streaming cost display
      display = ExLLM.Cost.Display.streaming_cost_display(0.05, 0.12)

      # Cost alerts
      alert = ExLLM.Cost.Display.cost_alert(:budget_exceeded, %{current: 1.25, budget: 1.00})
  """

  @doc """
  Generate cost breakdown table in various formats.

  ## Options
  - `:format` - Output format (`:ascii`, `:markdown`, `:csv`, `:json`) (default: `:ascii`)
  - `:columns` - List of columns to include (default: all available)
  - `:sort_by` - Column to sort by (default: `:total_cost`)

  ## Examples

      # ASCII table
      ExLLM.Cost.Display.cost_breakdown_table(cost_data)

      # Markdown table
      ExLLM.Cost.Display.cost_breakdown_table(cost_data, format: :markdown)

      # CSV with specific columns
      ExLLM.Cost.Display.cost_breakdown_table(cost_data, 
        format: :csv, 
        columns: [:provider, :model, :total_cost]
      )
  """
  @spec cost_breakdown_table(list() | map(), keyword()) :: String.t()
  def cost_breakdown_table(cost_data, opts \\ []) do
    format = Keyword.get(opts, :format, :ascii)

    columns =
      Keyword.get(opts, :columns, [:provider, :model, :total_cost, :message_count, :total_tokens])

    sort_by = Keyword.get(opts, :sort_by, :total_cost)

    # Normalize data to list format
    normalized_data = normalize_cost_data(cost_data, sort_by)

    case format do
      :ascii -> generate_ascii_table(normalized_data, columns)
      :markdown -> generate_markdown_table(normalized_data, columns)
      :csv -> generate_csv_output(normalized_data, columns)
      :json -> Jason.encode!(normalized_data, pretty: true)
      _ -> generate_ascii_table(normalized_data, columns)
    end
  end

  @doc """
  Generate cost summary for CLI display.

  Creates a rich, formatted summary perfect for terminal display with emojis,
  hierarchical structure, and color-friendly formatting.

  ## Examples

      summary_text = ExLLM.Cost.Display.cli_summary(session_summary)
      IO.puts(summary_text)
  """
  @spec cli_summary(map()) :: String.t()
  def cli_summary(session_summary) do
    duration_str = format_duration(session_summary.duration)

    """
    💰 Session Cost Summary
    =====================

    Session ID: #{session_summary.session_id}
    Duration: #{duration_str}

    Total Cost: #{ExLLM.Cost.format(session_summary.total_cost)}
    Total Tokens: #{format_number(session_summary.total_tokens)}
      ├─ Input: #{format_number(session_summary.input_tokens)}
      └─ Output: #{format_number(session_summary.output_tokens)}

    Messages: #{session_summary.message_count}
    Avg Cost/Message: #{ExLLM.Cost.format(session_summary.average_cost_per_message)}
    Cost/1K Tokens: #{ExLLM.Cost.format(session_summary.cost_per_1k_tokens)}

    #{format_provider_breakdown(session_summary.provider_breakdown)}
    """
  end

  @doc """
  Generate real-time cost display for streaming responses.

  Shows current cost with progress indication toward estimated final cost.
  Perfect for displaying during streaming responses.

  ## Examples

      # During streaming
      display = ExLLM.Cost.Display.streaming_cost_display(0.05, 0.12)
      # => "💰 $0.0500 (41.7% of estimated $0.1200)"

      # With custom format
      display = ExLLM.Cost.Display.streaming_cost_display(0.05, 0.12, style: :compact)
      # => "💰 $0.050 (42%)"
  """
  @spec streaming_cost_display(float(), float(), keyword()) :: String.t()
  def streaming_cost_display(current_cost, estimated_final_cost, opts \\ []) do
    style = Keyword.get(opts, :style, :detailed)

    progress =
      if estimated_final_cost > 0 do
        current_cost / estimated_final_cost * 100
      else
        0.0
      end

    case style do
      :compact ->
        "💰 #{ExLLM.Cost.format(current_cost, style: :compact)} (#{format_percentage(progress, 0)}%)"

      :detailed ->
        "💰 #{ExLLM.Cost.format(current_cost)} (#{format_percentage(progress, 1)}% of estimated #{ExLLM.Cost.format(estimated_final_cost)})"

      _ ->
        "💰 #{ExLLM.Cost.format(current_cost)} (#{format_percentage(progress, 1)}%)"
    end
  end

  @doc """
  Generate cost alert messages.

  Creates formatted alert messages for various cost-related events like
  budget overruns, high costs, or efficiency warnings.

  ## Alert Types
  - `:budget_exceeded` - When session or message exceeds budget
  - `:high_cost_warning` - When a single message has unusually high cost
  - `:efficiency_warning` - When cost efficiency is below expected thresholds
  - `:provider_recommended` - When suggesting a more cost-effective provider

  ## Examples

      # Budget exceeded alert
      alert = ExLLM.Cost.Display.cost_alert(:budget_exceeded, %{
        current: 1.25, 
        budget: 1.00,
        session_id: "chat_123"
      })

      # High cost warning
      alert = ExLLM.Cost.Display.cost_alert(:high_cost_warning, %{
        cost: 0.75,
        model: "gpt-4",
        threshold: 0.50
      })
  """
  @spec cost_alert(atom(), map()) :: String.t()
  def cost_alert(alert_type, data) do
    case alert_type do
      :budget_exceeded ->
        session_info = if data[:session_id], do: " (Session: #{data.session_id})", else: ""

        "🚨 Budget exceeded!#{session_info} Current: #{ExLLM.Cost.format(data.current)}, Budget: #{ExLLM.Cost.format(data.budget)}"

      :high_cost_warning ->
        model_info = if data[:model], do: " using #{data.model}", else: ""
        "⚠️  High cost detected: #{ExLLM.Cost.format(data.cost)}#{model_info}"

      :efficiency_warning ->
        "📊 Low efficiency detected. Consider switching to a more cost-effective model."

      :provider_recommended ->
        savings = data[:potential_savings] || 0.0

        "💡 Consider #{data.recommended_provider} for #{ExLLM.Cost.format(savings)} potential savings"

      :session_complete ->
        "✅ Session complete. Total cost: #{ExLLM.Cost.format(data.total_cost)}"

      _ ->
        "ℹ️  Cost notification: #{inspect(data)}"
    end
  end

  @doc """
  Generate comparison table for multiple providers or models.

  Creates a side-by-side comparison table showing costs across different
  providers or models for the same usage pattern.

  ## Examples

      comparison = ExLLM.Cost.Display.comparison_table([
        %{provider: "openai", model: "gpt-4", cost: 0.75},
        %{provider: "anthropic", model: "claude-3-5-sonnet", cost: 0.45},
        %{provider: "openai", model: "gpt-3.5-turbo", cost: 0.15}
      ])
  """
  @spec comparison_table(list(), keyword()) :: String.t()
  def comparison_table(comparisons, opts \\ []) do
    format = Keyword.get(opts, :format, :ascii)
    columns = [:rank, :provider, :model, :cost, :savings]

    # Add ranking and savings calculation
    sorted_comparisons = Enum.sort_by(comparisons, & &1.cost)
    cheapest_cost = List.first(sorted_comparisons).cost

    ranked_comparisons =
      sorted_comparisons
      |> Enum.with_index(1)
      |> Enum.map(fn {comparison, rank} ->
        savings = comparison.cost - cheapest_cost
        savings_pct = if cheapest_cost > 0, do: savings / cheapest_cost * 100, else: 0.0

        comparison
        |> Map.put(:rank, rank)
        |> Map.put(
          :savings,
          if(savings > 0,
            do: "+#{ExLLM.Cost.format(savings)} (+#{format_percentage(savings_pct, 0)}%)",
            else: "Cheapest"
          )
        )
      end)

    case format do
      :ascii -> generate_ascii_table(ranked_comparisons, columns)
      :markdown -> generate_markdown_table(ranked_comparisons, columns)
      _ -> generate_ascii_table(ranked_comparisons, columns)
    end
  end

  # Private helper functions

  defp normalize_cost_data(data, sort_by) when is_list(data) do
    Enum.sort_by(data, &Map.get(&1, sort_by, 0), :desc)
  end

  defp normalize_cost_data(data, _sort_by) when is_map(data) do
    # Convert session breakdown to list format
    case data do
      %{provider_breakdown: provider_breakdown} when is_map(provider_breakdown) ->
        Enum.map(provider_breakdown, fn {provider, stats} ->
          Map.put(stats, :provider, provider)
        end)

      %{model_breakdown: model_breakdown} when is_map(model_breakdown) ->
        Enum.map(model_breakdown, fn {model, stats} ->
          Map.put(stats, :model, model)
        end)

      _ ->
        [data]
    end
  end

  defp generate_ascii_table(data, columns) do
    if Enum.empty?(data) do
      "No data to display"
    else
      headers = Enum.map(columns, &format_column_header/1)
      rows = Enum.map(data, &format_table_row(&1, columns))

      # Calculate column widths
      all_rows = [headers | rows]
      col_widths = calculate_column_widths(all_rows)

      # Generate table
      header_line = format_table_line(headers, col_widths)
      separator = generate_separator(col_widths)
      data_lines = Enum.map(rows, &format_table_line(&1, col_widths))

      [header_line, separator | data_lines]
      |> Enum.join("\n")
    end
  end

  defp generate_markdown_table(data, columns) do
    if Enum.empty?(data) do
      "No data to display"
    else
      headers = Enum.map(columns, &format_column_header/1)
      separator = List.duplicate("---", length(columns))
      rows = Enum.map(data, &format_table_row(&1, columns))

      ([
         "| #{Enum.join(headers, " | ")} |",
         "| #{Enum.join(separator, " | ")} |"
       ] ++
         Enum.map(rows, fn row ->
           "| #{Enum.join(row, " | ")} |"
         end))
      |> Enum.join("\n")
    end
  end

  defp generate_csv_output(data, columns) do
    if Enum.empty?(data) do
      ""
    else
      headers = Enum.map(columns, &format_column_header/1)
      rows = Enum.map(data, &format_csv_row(&1, columns))

      [Enum.join(headers, ",") | Enum.map(rows, &Enum.join(&1, ","))]
      |> Enum.join("\n")
    end
  end

  defp format_column_header(column) do
    column
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_table_row(item, columns) do
    Enum.map(columns, &format_cell_value(Map.get(item, &1)))
  end

  defp format_csv_row(item, columns) do
    Enum.map(columns, fn col ->
      value = format_cell_value(Map.get(item, col))

      if String.contains?(value, ",") do
        "\"#{value}\""
      else
        value
      end
    end)
  end

  defp format_cell_value(nil), do: ""

  defp format_cell_value(value) when is_float(value) do
    if value < 0.01 do
      ExLLM.Cost.format(value)
    else
      ExLLM.Cost.format(value, style: :compact)
    end
  end

  defp format_cell_value(value) when is_integer(value), do: format_number(value)
  defp format_cell_value(value) when is_binary(value), do: value
  defp format_cell_value(value), do: to_string(value)

  defp format_table_line(row, col_widths) do
    padded_cells =
      row
      |> Enum.zip(col_widths)
      |> Enum.map(fn {cell, width} ->
        String.pad_trailing(cell, width)
      end)

    "| #{Enum.join(padded_cells, " | ")} |"
  end

  defp calculate_column_widths(rows) do
    rows
    |> Enum.zip()
    |> Enum.map(fn column_tuple ->
      column_tuple
      |> Tuple.to_list()
      |> Enum.map(&String.length/1)
      |> Enum.max()
    end)
  end

  defp generate_separator(col_widths) do
    separators = Enum.map(col_widths, &String.duplicate("-", &1))
    "| #{Enum.join(separators, " | ")} |"
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

  defp format_percentage(percentage, decimals \\ 1) do
    :erlang.float_to_binary(percentage, decimals: decimals)
  end
end
