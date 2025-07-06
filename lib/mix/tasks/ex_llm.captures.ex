defmodule Mix.Tasks.ExLlm.Captures do
  @shortdoc "Manage captured API responses"

  @moduledoc """
  Manage captured API responses for debugging.

  ## Commands

      mix ex_llm.captures list [--provider PROVIDER] [--today] [--limit N]
      mix ex_llm.captures show TIMESTAMP
      mix ex_llm.captures clear [--older-than DAYS]
      mix ex_llm.captures stats

  ## Examples

      # List recent captures
      mix ex_llm.captures list --limit 10
      
      # Show specific capture
      mix ex_llm.captures show 2024-01-15T10-30-45
      
      # Clear old captures
      mix ex_llm.captures clear --older-than 7
  """

  use Mix.Task
  alias ExLLM.Testing.LiveApiCacheStorage

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:ex_llm)

    case args do
      ["list" | opts] -> list_captures(opts)
      ["show", timestamp] -> show_capture(timestamp)
      ["clear" | opts] -> clear_captures(opts)
      ["stats"] -> show_stats()
      _ -> show_help()
    end
  end

  defp list_captures(opts) do
    {parsed, _, _} =
      OptionParser.parse(opts,
        switches: [provider: :string, today: :boolean, limit: :integer]
      )

    cache_keys =
      LiveApiCacheStorage.list_cache_keys()
      |> filter_captures()
      |> filter_by_provider(parsed[:provider])
      |> filter_by_date(parsed[:today])
      |> limit_results(parsed[:limit] || 20)

    if Enum.empty?(cache_keys) do
      Mix.shell().info("No captures found")
    else
      Mix.shell().info("Recent captures:")
      Enum.each(cache_keys, &display_capture_summary/1)
    end
  end

  defp filter_captures(keys) do
    # Filter to only captured responses (not test cache)
    Enum.filter(keys, fn key ->
      String.contains?(key, "/v1/") || String.contains?(key, "/chat/") ||
        String.contains?(key, "/models") || String.contains?(key, "/completions")
    end)
  end

  defp filter_by_provider(keys, nil), do: keys

  defp filter_by_provider(keys, provider) do
    Enum.filter(keys, &String.starts_with?(&1, "#{provider}/"))
  end

  defp filter_by_date(keys, nil), do: keys

  defp filter_by_date(keys, true) do
    today = Date.utc_today() |> Date.to_iso8601()
    Enum.filter(keys, &String.contains?(&1, today))
  end

  defp limit_results(keys, limit) do
    keys |> Enum.sort(:desc) |> Enum.take(limit)
  end

  defp display_capture_summary(key) do
    # Extract provider and timestamp from key
    parts = String.split(key, "/")
    provider = List.first(parts) || "unknown"
    timestamp = List.last(parts) || "unknown"

    # For now, just display the key parts
    # The metadata is stored inside the response data, not returned separately
    Mix.shell().info("  #{provider} | #{timestamp}")
  end

  defp show_capture(timestamp) do
    # Find captures matching the timestamp
    matching_keys =
      LiveApiCacheStorage.list_cache_keys()
      |> Enum.filter(&String.contains?(&1, timestamp))

    case matching_keys do
      [] ->
        Mix.shell().error("No capture found for timestamp: #{timestamp}")

      [key] ->
        display_full_capture(key)

      keys ->
        Mix.shell().info("Multiple captures found for #{timestamp}:")
        Enum.each(keys, &Mix.shell().info("  #{&1}"))
        Mix.shell().info("\nPlease be more specific.")
    end
  end

  defp display_full_capture(key) do
    case LiveApiCacheStorage.get(key) do
      {:ok, cache_data} ->
        # Extract metadata and response from the cached data
        metadata = Map.get(cache_data, "request_metadata", %{})
        response = Map.get(cache_data, "response_data", %{})
        Mix.shell().info(format_full_capture(response, metadata))

      {:error, reason} ->
        Mix.shell().error("Failed to load capture: #{inspect(reason)}")

      :miss ->
        Mix.shell().error("Capture not found: #{key}")
    end
  end

  defp format_full_capture(response, metadata) do
    """

    ━━━━━ CAPTURED RESPONSE ━━━━━
    Provider: #{metadata[:provider] || "unknown"}
    Endpoint: #{metadata[:endpoint] || "unknown"}
    Time: #{metadata[:captured_at] || "unknown"}
    Duration: #{metadata[:response_time_ms] || "N/A"}ms
    Status: #{metadata[:status_code] || "N/A"}

    Request Summary:
    #{format_request_summary(metadata[:request_summary])}

    Response:
    #{format_response(response)}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━
    """
  end

  defp format_request_summary(nil), do: "  No request data"

  defp format_request_summary(summary) do
    summary
    |> Enum.map(fn {k, v} -> "  #{k}: #{inspect(v)}" end)
    |> Enum.join("\n")
  end

  defp format_response(response) when is_map(response) do
    Jason.encode!(response, pretty: true)
  end

  defp format_response(response), do: inspect(response, pretty: true)

  defp clear_captures(opts) do
    {parsed, _, _} =
      OptionParser.parse(opts,
        switches: [older_than: :integer]
      )

    older_than_days = parsed[:older_than] || 7
    Mix.shell().info("Clearing captures older than #{older_than_days} days...")

    # Get all capture keys
    keys =
      LiveApiCacheStorage.list_cache_keys()
      |> filter_captures()

    # Filter by age
    cutoff_date = Date.utc_today() |> Date.add(-older_than_days)

    old_keys =
      Enum.filter(keys, fn key ->
        case extract_date_from_key(key) do
          {:ok, date} -> Date.compare(date, cutoff_date) == :lt
          _ -> false
        end
      end)

    # For now, we can't delete individual entries
    # The cache storage doesn't expose a delete method
    # We would need to implement a cleanup method in LiveApiCacheStorage

    Mix.shell().info("Found #{length(old_keys)} old captures")

    Mix.shell().info(
      "Note: Manual deletion not yet implemented. Captures will be cleaned up by the automatic retention policy."
    )
  end

  defp extract_date_from_key(key) do
    # Try to extract ISO8601 date from key
    case Regex.run(~r/(\d{4}-\d{2}-\d{2})/, key) do
      [_, date_str] -> Date.from_iso8601(date_str)
      _ -> :error
    end
  end

  defp show_stats do
    stats = LiveApiCacheStorage.get_stats(:all)

    # Count captures vs test cache entries
    all_keys = LiveApiCacheStorage.list_cache_keys()
    capture_keys = filter_captures(all_keys)

    Mix.shell().info("""
    Capture Statistics:
    Total Entries: #{length(all_keys)}
    Captured Responses: #{length(capture_keys)}
    Test Cache Entries: #{length(all_keys) - length(capture_keys)}
    Total Size: #{format_bytes(stats.total_size)}
    Oldest: #{stats.oldest_entry || "N/A"}
    Newest: #{stats.newest_entry || "N/A"}
    """)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp show_help do
    Mix.shell().info("""
    Usage: mix ex_llm.captures COMMAND [OPTIONS]

    Commands:
      list              List recent captures
      show TIMESTAMP    Show a specific capture
      clear             Clear old captures
      stats             Show capture statistics

    Options:
      --provider PROVIDER    Filter by provider
      --today               Show only today's captures
      --limit N             Limit number of results (default: 20)
      --older-than DAYS     Clear captures older than N days (default: 7)
    """)
  end
end
