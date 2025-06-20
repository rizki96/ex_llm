defmodule Mix.Tasks.ExLlm.Cache do
  @moduledoc """
  Mix tasks for managing the ExLLM test response cache.

  ## Available Commands

      mix ex_llm.cache.stats          # Show cache statistics
      mix ex_llm.cache.clear          # Clear all cache
      mix ex_llm.cache.clear --provider openai  # Clear specific provider
      mix ex_llm.cache.cleanup        # Clean up old entries
      mix ex_llm.cache.deduplicate    # Deduplicate content
      mix ex_llm.cache.list           # List cache keys
      mix ex_llm.cache.verify         # Verify cache integrity
  """

  use Mix.Task

  alias ExLLM.Infrastructure.Cache.Storage.TestCache
  alias ExLLM.Testing.TestCacheHelpers
  alias ExLLM.Testing.TestCacheStats

  @shortdoc "Manage ExLLM test response cache"

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:ex_llm)

    case parse_args(args) do
      {:stats, opts} -> show_stats(opts)
      {:clear, opts} -> clear_cache(opts)
      {:cleanup, opts} -> cleanup_cache(opts)
      {:deduplicate, opts} -> deduplicate_cache(opts)
      {:list, opts} -> list_cache_keys(opts)
      {:verify, opts} -> verify_cache(opts)
      {:help, _} -> show_help()
      {:error, msg} -> Mix.shell().error(msg)
    end
  end

  defp parse_args([]), do: {:help, []}
  defp parse_args(["stats" | rest]), do: {:stats, parse_options(rest)}
  defp parse_args(["clear" | rest]), do: {:clear, parse_options(rest)}
  defp parse_args(["cleanup" | rest]), do: {:cleanup, parse_options(rest)}
  defp parse_args(["deduplicate" | rest]), do: {:deduplicate, parse_options(rest)}
  defp parse_args(["list" | rest]), do: {:list, parse_options(rest)}
  defp parse_args(["verify" | rest]), do: {:verify, parse_options(rest)}
  defp parse_args(["help" | _]), do: {:help, []}
  defp parse_args([cmd | _]), do: {:error, "Unknown command: #{cmd}"}

  defp parse_options(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          provider: :string,
          verbose: :boolean,
          days: :integer,
          format: :string
        ],
        aliases: [
          p: :provider,
          v: :verbose,
          d: :days,
          f: :format
        ]
      )

    opts
  end

  defp show_stats(opts) do
    Mix.shell().info("ExLLM Test Cache Statistics")
    Mix.shell().info(String.duplicate("=", 50))

    if provider = opts[:provider] do
      provider_atom = String.to_atom(provider)

      stats =
        TestCacheStats.get_stats_by_provider()
        |> Enum.find(fn %{provider: p} -> p == provider_atom end)

      if stats do
        print_provider_stats(stats)
      else
        Mix.shell().error("No cache found for provider: #{provider}")
      end
    else
      stats = TestCacheStats.get_global_stats()
      print_global_stats(stats)

      if opts[:verbose] do
        Mix.shell().info("\nProvider Breakdown:")

        TestCacheStats.get_stats_by_provider()
        |> Enum.each(&print_provider_summary/1)
      end
    end
  end

  defp clear_cache(opts) do
    scope =
      case opts[:provider] do
        nil -> :all
        provider -> provider
      end

    Mix.shell().info("Clearing cache for: #{scope}")

    case TestCache.clear(scope) do
      :ok ->
        Mix.shell().info("✅ Cache cleared successfully")

      {:error, reason} ->
        Mix.shell().error("❌ Failed to clear cache: #{inspect(reason)}")
    end
  end

  defp cleanup_cache(opts) do
    days = opts[:days] || 30
    max_age = days * 24 * 60 * 60 * 1000

    Mix.shell().info("Cleaning up cache entries older than #{days} days...")

    if Code.ensure_loaded?(ExLLM.TestCacheHelpers) do
      report = TestCacheHelpers.cleanup_old_timestamps(max_age)

      Mix.shell().info("✅ Cleanup complete:")
      Mix.shell().info("   Files deleted: #{report.deleted_files}")
      Mix.shell().info("   Space freed: #{format_bytes(report.freed_bytes)}")

      if length(report.errors) > 0 do
        Mix.shell().error("   Errors: #{length(report.errors)}")
      end
    else
      Mix.shell().error("TestCacheHelpers not available")
    end
  end

  defp deduplicate_cache(_opts) do
    Mix.shell().info("Deduplicating cache content...")

    if Code.ensure_loaded?(ExLLM.TestCacheHelpers) do
      report = TestCacheHelpers.deduplicate_cache_content()

      Mix.shell().info("✅ Deduplication complete:")
      Mix.shell().info("   Duplicates found: #{report.duplicates_found}")
      Mix.shell().info("   Space saved: #{format_bytes(report.space_saved)}")
      Mix.shell().info("   Symlinks created: #{report.symlinks_created}")
    else
      Mix.shell().error("TestCacheHelpers not available")
    end
  end

  defp list_cache_keys(opts) do
    keys = TestCache.list_cache_keys()

    keys =
      if opts[:provider] do
        provider = opts[:provider]
        Enum.filter(keys, &String.starts_with?(&1, provider))
      else
        keys
      end

    Mix.shell().info("Cache Keys (#{length(keys)} total):")
    Mix.shell().info(String.duplicate("-", 50))

    Enum.each(keys, fn key ->
      stats = TestCache.get_stats(key)
      size_str = format_bytes(stats.total_size)
      entries_str = "#{stats.total_entries} entries"
      Mix.shell().info("  #{key} (#{entries_str}, #{size_str})")
    end)
  end

  defp verify_cache(_opts) do
    Mix.shell().info("Verifying cache integrity...")

    if Code.ensure_loaded?(ExLLM.TestCacheHelpers) do
      case TestCacheHelpers.verify_cache_integrity() do
        :ok ->
          Mix.shell().info("✅ Cache integrity check passed!")

        {:error, issues} ->
          Mix.shell().error("❌ Cache integrity issues found:")

          Enum.each(issues, fn issue ->
            Mix.shell().error("  - #{issue}")
          end)
      end
    else
      Mix.shell().error("TestCacheHelpers not available")
    end
  end

  defp show_help do
    Mix.shell().info(@moduledoc)
  end

  defp print_global_stats(stats) do
    Mix.shell().info("Total Requests: #{stats.total_requests}")
    Mix.shell().info("Cache Hits: #{stats.cache_hits} (#{format_percentage(stats.hit_rate)})")
    Mix.shell().info("Cache Misses: #{stats.cache_misses}")
    Mix.shell().info("Storage Used: #{format_bytes(stats.total_cache_size)}")
    Mix.shell().info("Unique Content: #{format_bytes(stats.unique_content_size)}")
    Mix.shell().info("Space Saved: #{format_bytes(stats.deduplication_savings)}")
    Mix.shell().info("Timestamp Count: #{stats.timestamp_count}")

    if stats.estimated_cost_savings > 0 do
      Mix.shell().info("Est. Cost Savings: $#{Float.round(stats.estimated_cost_savings, 2)}")
    end

    if stats.time_savings_ms > 0 do
      Mix.shell().info("Time Saved: #{format_duration(stats.time_savings_ms)}")
    end
  end

  defp print_provider_stats(%{provider: provider, stats: stats}) do
    Mix.shell().info("\n#{String.upcase(to_string(provider))}:")
    print_global_stats(stats)
  end

  defp print_provider_summary(%{provider: provider, stats: stats}) do
    Mix.shell().info(
      "  #{String.pad_trailing(to_string(provider), 15)} - " <>
        "Requests: #{String.pad_leading(to_string(stats.total_requests), 6)} | " <>
        "Hit Rate: #{String.pad_leading(format_percentage(stats.hit_rate), 6)} | " <>
        "Storage: #{String.pad_leading(format_bytes(stats.total_cache_size), 8)}"
    )
  end

  defp format_bytes(bytes) when is_number(bytes) do
    cond do
      bytes < 1024 -> "#{bytes}B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)}KB"
      bytes < 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 1)}MB"
      true -> "#{Float.round(bytes / (1024 * 1024 * 1024), 1)}GB"
    end
  end

  defp format_bytes(_), do: "0B"

  defp format_percentage(ratio) when is_number(ratio) do
    "#{Float.round(ratio * 100, 1)}%"
  end

  defp format_percentage(_), do: "0.0%"

  defp format_duration(ms) when is_number(ms) do
    cond do
      ms < 1000 -> "#{round(ms)}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      ms < 3_600_000 -> "#{Float.round(ms / 60_000, 1)}m"
      true -> "#{Float.round(ms / 3_600_000, 1)}h"
    end
  end

  defp format_duration(_), do: "0ms"
end

defmodule Mix.Tasks.ExLlm.Cache.Stats do
  @moduledoc "Show test cache statistics"
  use Mix.Task
  @shortdoc "Show test cache statistics"
  def run(args), do: Mix.Tasks.ExLlm.Cache.run(["stats" | args])
end

defmodule Mix.Tasks.ExLlm.Cache.Clear do
  @moduledoc "Clear test cache"
  use Mix.Task
  @shortdoc "Clear test cache"
  def run(args), do: Mix.Tasks.ExLlm.Cache.run(["clear" | args])
end

defmodule Mix.Tasks.ExLlm.Cache.Cleanup do
  @moduledoc "Clean up old cache entries"
  use Mix.Task
  @shortdoc "Clean up old cache entries"
  def run(args), do: Mix.Tasks.ExLlm.Cache.run(["cleanup" | args])
end
