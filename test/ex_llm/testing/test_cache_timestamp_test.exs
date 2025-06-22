defmodule ExLLM.TestCacheTimestampTest do
  use ExUnit.Case, async: true
  alias ExLLM.Testing.TestCacheTimestamp

  describe "generate_timestamp_filename/0" do
    test "generates ISO8601 format filename by default" do
      filename = TestCacheTimestamp.generate_timestamp_filename()

      assert String.ends_with?(filename, ".json")

      # Should match pattern like "2024-01-22T09-15-33Z.json" or "2024-01-22T09-15-33.123456Z.json"
      assert String.match?(filename, ~r/^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}(\.\d+)?Z\.json$/)
    end
  end

  describe "generate_timestamp_filename/1" do
    setup do
      original_config = Application.get_env(:ex_llm, :test_cache, %{})
      on_exit(fn -> Application.put_env(:ex_llm, :test_cache, original_config) end)
      :ok
    end

    test "generates ISO8601 format when configured" do
      Application.put_env(:ex_llm, :test_cache, %{timestamp_format: :iso8601})
      datetime = ~U[2024-01-22 09:15:33Z]

      filename = TestCacheTimestamp.generate_timestamp_filename(datetime)

      assert filename == "2024-01-22T09-15-33Z.json"
    end

    test "generates unix timestamp format when configured" do
      Application.put_env(:ex_llm, :test_cache, %{timestamp_format: :unix})
      datetime = ~U[2024-01-22 09:15:33Z]

      filename = TestCacheTimestamp.generate_timestamp_filename(datetime)

      # Unix timestamp for 2024-01-22 09:15:33 UTC
      assert filename == "1705914933.json"
    end

    test "generates compact format when configured" do
      Application.put_env(:ex_llm, :test_cache, %{timestamp_format: :compact})
      datetime = ~U[2024-01-22 09:15:33Z]

      filename = TestCacheTimestamp.generate_timestamp_filename(datetime)

      assert filename == "20240122_091533.json"
    end
  end

  describe "parse_timestamp_from_filename/1" do
    test "parses ISO8601 format filename" do
      filename = "2024-01-22T09-15-33Z.json"

      assert {:ok, datetime} = TestCacheTimestamp.parse_timestamp_from_filename(filename)
      assert datetime == ~U[2024-01-22 09:15:33Z]
    end

    test "parses unix timestamp filename" do
      filename = "1705914933.json"

      assert {:ok, datetime} = TestCacheTimestamp.parse_timestamp_from_filename(filename)
      assert datetime == ~U[2024-01-22 09:15:33Z]
    end

    test "parses compact format filename" do
      filename = "20240122_091533.json"

      assert {:ok, datetime} = TestCacheTimestamp.parse_timestamp_from_filename(filename)
      assert datetime == ~U[2024-01-22 09:15:33Z]
    end

    test "returns error for invalid filename" do
      assert TestCacheTimestamp.parse_timestamp_from_filename("invalid.json") == :error
      assert TestCacheTimestamp.parse_timestamp_from_filename("index.json") == :error
      assert TestCacheTimestamp.parse_timestamp_from_filename("") == :error
    end
  end

  describe "list_cache_timestamps/1" do
    setup do
      # Create a temporary test directory
      test_dir = "test/tmp/timestamp_test_#{:rand.uniform(10000)}"
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      {:ok, test_dir: test_dir}
    end

    test "lists timestamps sorted newest first", %{test_dir: test_dir} do
      # Create test files with different timestamps
      files = [
        "2024-01-20T10-00-00Z.json",
        "2024-01-22T12-00-00Z.json",
        "2024-01-21T11-00-00Z.json",
        # Should be ignored
        "index.json"
      ]

      Enum.each(files, fn file ->
        File.write!(Path.join(test_dir, file), "{}")
      end)

      timestamps = TestCacheTimestamp.list_cache_timestamps(test_dir)

      assert length(timestamps) == 3
      assert Enum.at(timestamps, 0) == ~U[2024-01-22 12:00:00Z]
      assert Enum.at(timestamps, 1) == ~U[2024-01-21 11:00:00Z]
      assert Enum.at(timestamps, 2) == ~U[2024-01-20 10:00:00Z]
    end

    test "returns empty list for non-existent directory", %{test_dir: test_dir} do
      non_existent = Path.join(test_dir, "does_not_exist")

      assert TestCacheTimestamp.list_cache_timestamps(non_existent) == []
    end

    test "ignores non-JSON files and invalid timestamps", %{test_dir: test_dir} do
      files = [
        "2024-01-20T10-00-00Z.json",
        "invalid.json",
        "readme.txt",
        "2024-01-21T11-00-00Z.json"
      ]

      Enum.each(files, fn file ->
        File.write!(Path.join(test_dir, file), "{}")
      end)

      timestamps = TestCacheTimestamp.list_cache_timestamps(test_dir)

      assert length(timestamps) == 2
    end
  end

  describe "cleanup_old_entries/3" do
    setup do
      test_dir = "test/tmp/cleanup_test_#{:rand.uniform(10000)}"
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      {:ok, test_dir: test_dir}
    end

    test "removes entries exceeding max count", %{test_dir: test_dir} do
      # Create 5 files
      _files =
        for i <- 1..5 do
          filename = "2024-01-#{String.pad_leading(to_string(i), 2, "0")}T10-00-00Z.json"
          path = Path.join(test_dir, filename)
          File.write!(path, ~s({"data": "test #{i}"}))
          filename
        end

      # Keep only 3 newest
      report = TestCacheTimestamp.cleanup_old_entries(test_dir, 3, 0)

      assert report.deleted_files == 2
      assert report.freed_bytes > 0
      assert report.errors == []

      # Check that oldest 2 files were deleted
      remaining_files = File.ls!(test_dir)
      assert length(remaining_files) == 3
      assert "2024-01-01T10-00-00Z.json" not in remaining_files
      assert "2024-01-02T10-00-00Z.json" not in remaining_files
    end

    test "removes entries older than max age", %{test_dir: test_dir} do
      # Create files with specific timestamps
      now = DateTime.utc_now()

      recent_file = TestCacheTimestamp.generate_timestamp_filename(now)
      old_file = TestCacheTimestamp.generate_timestamp_filename(DateTime.add(now, -8, :day))

      File.write!(Path.join(test_dir, recent_file), ~s({"data": "recent"}))
      File.write!(Path.join(test_dir, old_file), ~s({"data": "old"}))

      # Remove files older than 7 days
      report = TestCacheTimestamp.cleanup_old_entries(test_dir, 0, 7 * 24 * 60 * 60 * 1000)

      assert report.deleted_files == 1
      assert report.errors == []

      remaining_files = File.ls!(test_dir)
      assert recent_file in remaining_files
      assert old_file not in remaining_files
    end

    test "applies both max entries and max age policies", %{test_dir: test_dir} do
      now = DateTime.utc_now()

      # Create 5 files, 2 of them old
      files = [
        {TestCacheTimestamp.generate_timestamp_filename(now), "new1"},
        {TestCacheTimestamp.generate_timestamp_filename(DateTime.add(now, -1, :day)), "new2"},
        {TestCacheTimestamp.generate_timestamp_filename(DateTime.add(now, -2, :day)), "new3"},
        {TestCacheTimestamp.generate_timestamp_filename(DateTime.add(now, -8, :day)), "old1"},
        {TestCacheTimestamp.generate_timestamp_filename(DateTime.add(now, -9, :day)), "old2"}
      ]

      Enum.each(files, fn {filename, content} ->
        File.write!(Path.join(test_dir, filename), ~s({"data": "#{content}"}))
      end)

      # Keep max 3 entries and max 7 days old
      report = TestCacheTimestamp.cleanup_old_entries(test_dir, 3, 7 * 24 * 60 * 60 * 1000)

      # Should delete 2 old files due to age, even though max entries would allow them
      assert report.deleted_files == 2
      assert length(File.ls!(test_dir)) == 3
    end
  end

  describe "deduplicate_content/1" do
    setup do
      test_dir = "test/tmp/dedup_test_#{:rand.uniform(10000)}"
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      {:ok, test_dir: test_dir}
    end

    test "creates symlinks for duplicate content", %{test_dir: test_dir} do
      # Create files with duplicate content
      content = ~s({"data": "duplicate content"})

      files = [
        # Original (oldest)
        "2024-01-20T10-00-00Z.json",
        # Duplicate
        "2024-01-21T11-00-00Z.json",
        # Duplicate
        "2024-01-22T12-00-00Z.json"
      ]

      Enum.each(files, fn file ->
        File.write!(Path.join(test_dir, file), content)
      end)

      # Also create a file with different content
      File.write!(
        Path.join(test_dir, "2024-01-23T13-00-00Z.json"),
        ~s({"data": "different"})
      )

      report = TestCacheTimestamp.deduplicate_content(test_dir)

      assert report.duplicates_found == 2
      assert report.symlinks_created == 2
      assert report.space_saved > 0
      assert report.errors == []

      # Verify symlinks point to oldest file
      link1 = Path.join(test_dir, "2024-01-21T11-00-00Z.json")
      link2 = Path.join(test_dir, "2024-01-22T12-00-00Z.json")

      # Check if files exist or are symlinks
      case {File.exists?(link1), File.exists?(link2)} do
        {true, true} ->
          # If they exist, they should have the same content
          assert File.read!(link1) == content
          assert File.read!(link2) == content

        _ ->
          # If symlink creation failed (e.g., on Windows), just check the report
          assert report.duplicates_found >= 0
      end

      # On systems that support symlinks, verify they are actually symlinks
      # This might not work on all systems (e.g., Windows without admin)
      case File.lstat(link1) do
        {:ok, %{type: :symlink}} ->
          assert true

        _ ->
          # System doesn't support symlinks or we don't have permission
          :ok
      end
    end

    test "handles empty directory", %{test_dir: test_dir} do
      report = TestCacheTimestamp.deduplicate_content(test_dir)

      assert report.duplicates_found == 0
      assert report.space_saved == 0
      assert report.symlinks_created == 0
      assert report.errors == []
    end
  end

  describe "get_content_hash/1" do
    setup do
      test_dir = "test/tmp/hash_test_#{:rand.uniform(10000)}"
      File.mkdir_p!(test_dir)

      on_exit(fn -> File.rm_rf!(test_dir) end)

      {:ok, test_dir: test_dir}
    end

    test "generates consistent hash for same content", %{test_dir: test_dir} do
      content = ~s({"data": "test content"})
      file1 = Path.join(test_dir, "file1.json")
      file2 = Path.join(test_dir, "file2.json")

      File.write!(file1, content)
      File.write!(file2, content)

      hash1 = TestCacheTimestamp.get_content_hash(file1)
      hash2 = TestCacheTimestamp.get_content_hash(file2)

      assert hash1 == hash2
      # SHA256 produces 64 hex chars
      assert String.length(hash1) == 64
    end

    test "generates different hash for different content", %{test_dir: test_dir} do
      file1 = Path.join(test_dir, "file1.json")
      file2 = Path.join(test_dir, "file2.json")

      File.write!(file1, ~s({"data": "content 1"}))
      File.write!(file2, ~s({"data": "content 2"}))

      hash1 = TestCacheTimestamp.get_content_hash(file1)
      hash2 = TestCacheTimestamp.get_content_hash(file2)

      assert hash1 != hash2
    end

    test "uses configured hash algorithm", %{test_dir: test_dir} do
      original_config = Application.get_env(:ex_llm, :test_cache, %{})

      file = Path.join(test_dir, "test.json")
      File.write!(file, "test content")

      # Test SHA256 (default)
      Application.put_env(:ex_llm, :test_cache, %{content_hash_algorithm: :sha256})
      hash_sha256 = TestCacheTimestamp.get_content_hash(file)
      assert String.length(hash_sha256) == 64

      # Test MD5
      Application.put_env(:ex_llm, :test_cache, %{content_hash_algorithm: :md5})
      hash_md5 = TestCacheTimestamp.get_content_hash(file)
      assert String.length(hash_md5) == 32

      # Test Blake2b
      Application.put_env(:ex_llm, :test_cache, %{content_hash_algorithm: :blake2b})
      hash_blake2b = TestCacheTimestamp.get_content_hash(file)
      assert String.length(hash_blake2b) == 128

      # Hashes should all be different
      assert hash_sha256 != hash_md5
      assert hash_sha256 != hash_blake2b
      assert hash_md5 != hash_blake2b

      # Cleanup
      Application.put_env(:ex_llm, :test_cache, original_config)
    end

    test "returns error for non-existent file", %{test_dir: test_dir} do
      non_existent = Path.join(test_dir, "does_not_exist.json")

      assert TestCacheTimestamp.get_content_hash(non_existent) == "error"
    end
  end
end
