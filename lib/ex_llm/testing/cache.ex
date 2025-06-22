defmodule ExLLM.Testing.Cache do
  @moduledoc """
  Cache freshness checking for hybrid testing strategy.

  Determines whether cached test responses are fresh enough to use,
  or if live API calls should be made to refresh the cache.
  """

  @cache_dir "test/cache"

  def fresh?(opts \\ []) do
    # 24 hours default
    max_age = Keyword.get(opts, :max_age, 24 * 60 * 60)

    case get_cache_age() do
      {:ok, age_seconds} -> age_seconds <= max_age
      {:error, :no_cache} -> false
    end
  end

  def status do
    case get_cache_age() do
      {:ok, age_seconds} ->
        hours = div(age_seconds, 3600)
        minutes = div(rem(age_seconds, 3600), 60)
        IO.puts("📦 Test cache age: #{hours}h #{minutes}m")
        IO.puts("📍 Cache location: #{@cache_dir}")
        IO.puts("📊 Cache files: #{count_cache_files()}")

        if age_seconds > 24 * 60 * 60 do
          IO.puts("⚠️  Cache is stale (>24h). Consider running `mix test.live`")
        else
          IO.puts("✅ Cache is fresh")
        end

      {:error, :no_cache} ->
        IO.puts("❌ No test cache found")
        IO.puts("💡 Run `mix test.live` to create cache")
    end
  end

  defp get_cache_age do
    if File.exists?(@cache_dir) do
      # Find the newest cache file
      case File.ls(@cache_dir) do
        {:ok, []} ->
          {:error, :no_cache}

        {:ok, files} ->
          cache_files =
            files
            |> Enum.map(&Path.join(@cache_dir, &1))
            |> Enum.filter(&File.regular?/1)

          if Enum.empty?(cache_files) do
            {:error, :no_cache}
          else
            newest_time =
              cache_files
              |> Enum.map(&File.stat!/1)
              |> Enum.map(& &1.mtime)
              |> Enum.max()

            now = :erlang.universaltime()

            age_seconds =
              :calendar.datetime_to_gregorian_seconds(now) -
                :calendar.datetime_to_gregorian_seconds(newest_time)

            {:ok, age_seconds}
          end

        {:error, _} ->
          {:error, :no_cache}
      end
    else
      {:error, :no_cache}
    end
  end

  defp count_cache_files do
    if File.exists?(@cache_dir) do
      case File.ls(@cache_dir) do
        {:ok, files} ->
          files
          |> Enum.map(&Path.join(@cache_dir, &1))
          |> Enum.count(&File.regular?/1)

        {:error, _} ->
          0
      end
    else
      0
    end
  end
end
