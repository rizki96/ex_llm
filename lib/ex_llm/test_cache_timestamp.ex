defmodule ExLLM.TestCacheTimestamp do
  @moduledoc """
  Manage timestamped cache entries and cleanup policies.

  This module handles timestamp generation, parsing, cleanup operations,
  and content deduplication for the timestamp-based caching system.
  """

  @type cleanup_report :: %{
          deleted_files: non_neg_integer(),
          freed_bytes: non_neg_integer(),
          errors: [String.t()]
        }

  @type dedup_report :: %{
          duplicates_found: non_neg_integer(),
          space_saved: non_neg_integer(),
          symlinks_created: non_neg_integer(),
          errors: [String.t()]
        }

  @doc """
  Generate a timestamp-based filename for the current moment.
  """
  @spec generate_timestamp_filename() :: String.t()
  def generate_timestamp_filename do
    generate_timestamp_filename(DateTime.utc_now())
  end

  @doc """
  Generate a timestamp-based filename for a specific DateTime.
  """
  @spec generate_timestamp_filename(DateTime.t()) :: String.t()
  def generate_timestamp_filename(%DateTime{} = datetime) do
    config = ExLLM.TestCacheConfig.get_config()

    case config.timestamp_format do
      :iso8601 ->
        datetime
        |> DateTime.to_iso8601()
        |> String.replace(":", "-")
        |> Kernel.<>(".json")

      :unix ->
        datetime
        |> DateTime.to_unix()
        |> to_string()
        |> Kernel.<>(".json")

      :compact ->
        datetime
        |> Calendar.strftime("%Y%m%d_%H%M%S")
        |> Kernel.<>(".json")
    end
  end

  @doc """
  Parse timestamp from filename.
  """
  @spec parse_timestamp_from_filename(String.t()) :: {:ok, DateTime.t()} | :error
  def parse_timestamp_from_filename(filename) do
    basename = Path.basename(filename, ".json")

    cond do
      # ISO8601 format: 2024-01-22T09-15-33Z
      String.contains?(basename, "T") and String.ends_with?(basename, "Z") ->
        parse_iso8601_timestamp(basename)

      # Unix timestamp: 1706004933
      String.match?(basename, ~r/^\d{10}$/) ->
        parse_unix_timestamp(basename)

      # Compact format: 20240122_091533
      String.match?(basename, ~r/^\d{8}_\d{6}$/) ->
        parse_compact_timestamp(basename)

      true ->
        :error
    end
  end

  @doc """
  List all cache timestamps for a given cache directory, sorted newest first.
  """
  @spec list_cache_timestamps(String.t()) :: [DateTime.t()]
  def list_cache_timestamps(cache_dir) do
    case File.ls(cache_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.reject(&(&1 == "index.json"))
        |> Enum.map(&parse_timestamp_from_filename/1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(&elem(&1, 1))
        |> Enum.sort(&(DateTime.compare(&1, &2) == :gt))

      {:error, _} ->
        []
    end
  end

  @doc """
  Clean up old cache entries based on max entries and max age policies.
  """
  @spec cleanup_old_entries(String.t(), non_neg_integer(), non_neg_integer()) :: cleanup_report()
  def cleanup_old_entries(cache_dir, max_entries, max_age_ms) do
    case File.ls(cache_dir) do
      {:ok, files} ->
        timestamp_files = get_timestamp_files(cache_dir, files)

        # Apply cleanup policies
        to_delete_by_count = apply_max_entries_policy(timestamp_files, max_entries)
        to_delete_by_age = apply_max_age_policy(timestamp_files, max_age_ms)

        # Combine and deduplicate files to delete
        to_delete = (to_delete_by_count ++ to_delete_by_age) |> Enum.uniq()

        delete_files(to_delete)

      {:error, reason} ->
        %{
          deleted_files: 0,
          freed_bytes: 0,
          errors: ["Failed to list directory #{cache_dir}: #{reason}"]
        }
    end
  end

  @doc """
  Deduplicate content across timestamps using file hashes.
  """
  @spec deduplicate_content(String.t()) :: dedup_report()
  def deduplicate_content(cache_dir) do
    case File.ls(cache_dir) do
      {:ok, files} ->
        timestamp_files = get_timestamp_files(cache_dir, files)

        # Group files by content hash
        hash_groups = group_files_by_hash(timestamp_files)

        # Create symlinks for duplicates
        create_symlinks_for_duplicates(hash_groups)

      {:error, reason} ->
        %{
          duplicates_found: 0,
          space_saved: 0,
          symlinks_created: 0,
          errors: ["Failed to list directory #{cache_dir}: #{reason}"]
        }
    end
  end

  @doc """
  Get content hash for a file.
  """
  @spec get_content_hash(String.t()) :: String.t()
  def get_content_hash(file_path) do
    config = ExLLM.TestCacheConfig.get_config()

    case File.read(file_path) do
      {:ok, content} ->
        case config.content_hash_algorithm do
          :sha256 -> :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
          :md5 -> :crypto.hash(:md5, content) |> Base.encode16(case: :lower)
          :blake2b -> :crypto.hash(:blake2b, content) |> Base.encode16(case: :lower)
        end

      {:error, _} ->
        "error"
    end
  end

  # Private functions

  defp parse_iso8601_timestamp(basename) do
    # Convert back to standard ISO8601 format
    # Replace the time separator hyphens back to colons
    # Format: "2024-01-22T09-15-33Z" -> "2024-01-22T09:15:33Z"
    iso_string =
      case String.split(basename, "T") do
        [date, time_part] ->
          # Replace hyphens with colons in the time part only
          fixed_time = String.replace(time_part, "-", ":")
          "#{date}T#{fixed_time}"

        _ ->
          basename
      end

    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> :error
    end
  end

  defp parse_unix_timestamp(basename) do
    case Integer.parse(basename) do
      {unix_time, ""} ->
        case DateTime.from_unix(unix_time) do
          {:ok, datetime} -> {:ok, datetime}
          {:error, _} -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_compact_timestamp(basename) do
    case String.split(basename, "_") do
      [date_part, time_part] when byte_size(date_part) == 8 and byte_size(time_part) == 6 ->
        try do
          year = String.slice(date_part, 0, 4) |> String.to_integer()
          month = String.slice(date_part, 4, 2) |> String.to_integer()
          day = String.slice(date_part, 6, 2) |> String.to_integer()
          hour = String.slice(time_part, 0, 2) |> String.to_integer()
          minute = String.slice(time_part, 2, 2) |> String.to_integer()
          second = String.slice(time_part, 4, 2) |> String.to_integer()

          case DateTime.new(
                 Date.new!(year, month, day),
                 Time.new!(hour, minute, second),
                 "Etc/UTC"
               ) do
            {:ok, datetime} -> {:ok, datetime}
            {:error, _} -> :error
          end
        catch
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp get_timestamp_files(cache_dir, files) do
    files
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.reject(&(&1 == "index.json"))
    |> Enum.map(fn filename ->
      file_path = Path.join(cache_dir, filename)

      case parse_timestamp_from_filename(filename) do
        {:ok, timestamp} ->
          {:ok,
           %{
             path: file_path,
             filename: filename,
             timestamp: timestamp,
             size: get_file_size(file_path)
           }}

        :error ->
          :error
      end
    end)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(&elem(&1, 1))
  end

  defp apply_max_entries_policy(timestamp_files, max_entries) when max_entries > 0 do
    timestamp_files
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.drop(max_entries)
    |> Enum.map(& &1.path)
  end

  defp apply_max_entries_policy(_timestamp_files, _max_entries), do: []

  defp apply_max_age_policy(timestamp_files, max_age_ms) when max_age_ms > 0 do
    cutoff_time = DateTime.add(DateTime.utc_now(), -max_age_ms, :millisecond)

    timestamp_files
    |> Enum.filter(&(DateTime.compare(&1.timestamp, cutoff_time) == :lt))
    |> Enum.map(& &1.path)
  end

  defp apply_max_age_policy(_timestamp_files, _max_age_ms), do: []

  defp delete_files(file_paths) do
    {deleted_count, freed_bytes, errors} =
      Enum.reduce(file_paths, {0, 0, []}, fn file_path, {count, bytes, errs} ->
        case File.stat(file_path) do
          {:ok, %{size: size}} ->
            case File.rm(file_path) do
              :ok ->
                {count + 1, bytes + size, errs}

              {:error, reason} ->
                {count, bytes, ["Failed to delete #{file_path}: #{reason}" | errs]}
            end

          {:error, reason} ->
            {count, bytes, ["Failed to stat #{file_path}: #{reason}" | errs]}
        end
      end)

    %{
      deleted_files: deleted_count,
      freed_bytes: freed_bytes,
      errors: errors
    }
  end

  defp group_files_by_hash(timestamp_files) do
    timestamp_files
    |> Enum.group_by(fn file -> get_content_hash(file.path) end)
    |> Enum.filter(fn {_hash, files} -> length(files) > 1 end)
  end

  defp create_symlinks_for_duplicates(hash_groups) do
    Enum.reduce(
      hash_groups,
      %{duplicates_found: 0, space_saved: 0, symlinks_created: 0, errors: []},
      fn {_hash, files}, acc ->
        # Keep the oldest file as the original, symlink the newer ones
        [original | duplicates] = Enum.sort_by(files, & &1.timestamp)

        Enum.reduce(duplicates, acc, fn dup, inner_acc ->
          case create_symlink(original.path, dup.path) do
            :ok ->
              %{
                inner_acc
                | duplicates_found: inner_acc.duplicates_found + 1,
                  space_saved: inner_acc.space_saved + dup.size,
                  symlinks_created: inner_acc.symlinks_created + 1
              }

            {:error, reason} ->
              %{
                inner_acc
                | errors: [
                    "Failed to create symlink #{dup.path} -> #{original.path}: #{reason}"
                    | inner_acc.errors
                  ]
              }
          end
        end)
      end
    )
  end

  defp create_symlink(original_path, link_path) do
    # Remove the duplicate file first
    with :ok <- File.rm(link_path),
         :ok <- File.ln_s(original_path, link_path) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_file_size(file_path) do
    case File.stat(file_path) do
      {:ok, %{size: size}} -> size
      {:error, _} -> 0
    end
  end
end
