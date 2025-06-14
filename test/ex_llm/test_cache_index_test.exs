defmodule ExLLM.TestCacheIndexTest do
  use ExUnit.Case, async: false
  alias ExLLM.TestCacheIndex

  setup do
    # Create a temporary test directory
    test_dir = "test/tmp/index_test_#{:rand.uniform(10000)}"
    File.mkdir_p!(test_dir)

    on_exit(fn -> File.rm_rf!(test_dir) end)

    {:ok, test_dir: test_dir}
  end

  describe "load_index/1" do
    test "returns empty index for non-existent file", %{test_dir: test_dir} do
      index = TestCacheIndex.load_index(test_dir)

      assert index.cache_key == Path.basename(test_dir)
      assert index.entries == []
      assert index.total_requests == 0
      assert index.cache_hits == 0
      assert index.last_accessed == nil
    end

    test "loads existing index from file", %{test_dir: test_dir} do
      # Create index file
      now = DateTime.utc_now()

      index_data = %{
        cache_key: "test_cache",
        entries: [
          %{
            timestamp: now,
            filename: "test.json",
            status: :success,
            size: 1024,
            content_hash: "abc123",
            response_time_ms: 100,
            api_version: nil,
            cost: nil
          }
        ],
        total_requests: 5,
        cache_hits: 3,
        last_accessed: now,
        access_count: 5,
        last_cleanup: nil,
        cleanup_before: nil
      }

      File.write!(
        Path.join(test_dir, "index.json"),
        Jason.encode!(index_data)
      )

      loaded_index = TestCacheIndex.load_index(test_dir)

      assert loaded_index.cache_key == "test_cache"
      assert length(loaded_index.entries) == 1
      assert loaded_index.total_requests == 5
      assert loaded_index.cache_hits == 3
    end

    test "handles corrupted index file gracefully", %{test_dir: test_dir} do
      File.write!(Path.join(test_dir, "index.json"), "invalid json")

      index = TestCacheIndex.load_index(test_dir)

      # Should return empty index on error
      assert index.cache_key == Path.basename(test_dir)
      assert index.entries == []
    end
  end

  describe "save_index/2" do
    test "saves index to file", %{test_dir: test_dir} do
      index = %{
        cache_key: "test_save",
        entries: [],
        total_requests: 10,
        cache_hits: 8,
        last_accessed: DateTime.utc_now(),
        access_count: 10,
        last_cleanup: nil,
        cleanup_before: nil
      }

      assert :ok = TestCacheIndex.save_index(test_dir, index)

      # Verify file exists and can be loaded
      assert File.exists?(Path.join(test_dir, "index.json"))

      loaded = TestCacheIndex.load_index(test_dir)
      assert loaded.cache_key == "test_save"
      assert loaded.total_requests == 10
    end

    test "creates directory if it doesn't exist", %{test_dir: test_dir} do
      nested_dir = Path.join(test_dir, "nested/deep/path")

      index = %{
        cache_key: "nested_test",
        entries: [],
        total_requests: 0,
        cache_hits: 0,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      assert :ok = TestCacheIndex.save_index(nested_dir, index)
      assert File.exists?(Path.join(nested_dir, "index.json"))
    end
  end

  describe "add_entry/3" do
    test "adds new entry to index", %{test_dir: test_dir} do
      initial_index = TestCacheIndex.load_index(test_dir)

      new_entry = %{
        timestamp: DateTime.utc_now(),
        filename: "new_entry.json",
        status: :success,
        size: 2048,
        content_hash: "def456",
        response_time_ms: 200,
        api_version: "v1",
        cost: %{input: 0.001, output: 0.002, total: 0.003}
      }

      updated_index = TestCacheIndex.add_entry(initial_index, new_entry, test_dir)

      assert length(updated_index.entries) == 1
      assert hd(updated_index.entries).filename == "new_entry.json"

      # Verify it was saved
      loaded = TestCacheIndex.load_index(test_dir)
      assert length(loaded.entries) == 1
    end

    test "sorts entries by timestamp (newest first)", %{test_dir: test_dir} do
      now = DateTime.utc_now()

      index = TestCacheIndex.load_index(test_dir)

      # Add entries out of order
      old_entry = %{
        timestamp: DateTime.add(now, -2, :hour),
        filename: "old.json",
        status: :success,
        size: 1024,
        content_hash: "old123",
        response_time_ms: 100,
        api_version: nil,
        cost: nil
      }

      new_entry = %{
        timestamp: now,
        filename: "new.json",
        status: :success,
        size: 1024,
        content_hash: "new123",
        response_time_ms: 100,
        api_version: nil,
        cost: nil
      }

      middle_entry = %{
        timestamp: DateTime.add(now, -1, :hour),
        filename: "middle.json",
        status: :success,
        size: 1024,
        content_hash: "mid123",
        response_time_ms: 100,
        api_version: nil,
        cost: nil
      }

      index = TestCacheIndex.add_entry(index, old_entry, test_dir)
      index = TestCacheIndex.add_entry(index, new_entry, test_dir)
      index = TestCacheIndex.add_entry(index, middle_entry, test_dir)

      # Should be sorted newest first
      assert Enum.at(index.entries, 0).filename == "new.json"
      assert Enum.at(index.entries, 1).filename == "middle.json"
      assert Enum.at(index.entries, 2).filename == "old.json"
    end

    test "enforces max entries limit", %{test_dir: test_dir} do
      index = TestCacheIndex.load_index(test_dir)

      # Add 5 entries using reduce to accumulate index updates
      index =
        Enum.reduce(1..5, index, fn i, acc_index ->
          entry = %{
            timestamp: DateTime.add(DateTime.utc_now(), -i, :minute),
            filename: "entry_#{i}.json",
            status: :success,
            size: 1024,
            content_hash: "hash#{i}",
            response_time_ms: 100,
            api_version: nil,
            cost: nil
          }

          TestCacheIndex.add_entry(acc_index, entry, test_dir)
        end)

      # Add one more with max_entries = 3
      newest_entry = %{
        timestamp: DateTime.utc_now(),
        filename: "newest.json",
        status: :success,
        size: 1024,
        content_hash: "newest",
        response_time_ms: 100,
        api_version: nil,
        cost: nil
      }

      index = TestCacheIndex.add_entry(index, newest_entry, test_dir, max_entries: 3)

      # Should keep only 3 newest entries
      assert length(index.entries) == 3
      assert Enum.at(index.entries, 0).filename == "newest.json"
      assert Enum.at(index.entries, 1).filename == "entry_1.json"
      assert Enum.at(index.entries, 2).filename == "entry_2.json"
    end
  end

  describe "update_stats/3" do
    test "updates cache hit statistics", %{test_dir: test_dir} do
      index = TestCacheIndex.load_index(test_dir)

      updated = TestCacheIndex.update_stats(index, :hit, test_dir)

      assert updated.total_requests == 1
      assert updated.cache_hits == 1
      assert updated.last_accessed != nil
      assert updated.access_count == 1

      # Another hit
      updated2 = TestCacheIndex.update_stats(updated, :hit, test_dir)

      assert updated2.total_requests == 2
      assert updated2.cache_hits == 2
      assert updated2.access_count == 2
    end

    test "updates cache miss statistics", %{test_dir: test_dir} do
      index = TestCacheIndex.load_index(test_dir)

      updated = TestCacheIndex.update_stats(index, :miss, test_dir)

      assert updated.total_requests == 1
      # Misses don't increment hits
      assert updated.cache_hits == 0
      assert updated.last_accessed != nil
    end

    test "persists stats updates", %{test_dir: test_dir} do
      index = TestCacheIndex.load_index(test_dir)

      TestCacheIndex.update_stats(index, :hit, test_dir)
      TestCacheIndex.update_stats(index, :hit, test_dir)
      TestCacheIndex.update_stats(index, :miss, test_dir)

      # Reload and verify
      reloaded = TestCacheIndex.load_index(test_dir)

      assert reloaded.total_requests == 3
      assert reloaded.cache_hits == 2
    end
  end

  describe "get_entry_by_filename/2" do
    test "finds entry by filename", %{test_dir: test_dir} do
      entry = %{
        timestamp: DateTime.utc_now(),
        filename: "target.json",
        status: :success,
        size: 1024,
        content_hash: "target123",
        response_time_ms: 100,
        api_version: nil,
        cost: nil
      }

      index = TestCacheIndex.load_index(test_dir)
      index = TestCacheIndex.add_entry(index, entry, test_dir)

      assert {:ok, found} = TestCacheIndex.get_entry_by_filename(index, "target.json")
      assert found.content_hash == "target123"
    end

    test "returns error when entry not found", %{test_dir: test_dir} do
      index = TestCacheIndex.load_index(test_dir)

      assert :error = TestCacheIndex.get_entry_by_filename(index, "missing.json")
    end
  end

  describe "remove_entry/3" do
    test "removes entry by filename", %{test_dir: test_dir} do
      entry1 = %{
        timestamp: DateTime.utc_now(),
        filename: "keep.json",
        status: :success,
        size: 1024,
        content_hash: "keep123",
        response_time_ms: 100,
        api_version: nil,
        cost: nil
      }

      entry2 = %{
        timestamp: DateTime.add(DateTime.utc_now(), -1, :minute),
        filename: "remove.json",
        status: :success,
        size: 1024,
        content_hash: "remove123",
        response_time_ms: 100,
        api_version: nil,
        cost: nil
      }

      index = TestCacheIndex.load_index(test_dir)
      index = TestCacheIndex.add_entry(index, entry1, test_dir)
      index = TestCacheIndex.add_entry(index, entry2, test_dir)

      assert length(index.entries) == 2

      updated = TestCacheIndex.remove_entry(index, "remove.json", test_dir)

      assert length(updated.entries) == 1
      assert hd(updated.entries).filename == "keep.json"

      # Verify persistence
      reloaded = TestCacheIndex.load_index(test_dir)
      assert length(reloaded.entries) == 1
    end

    test "handles removing non-existent entry", %{test_dir: test_dir} do
      index = TestCacheIndex.load_index(test_dir)

      # Should not crash
      updated = TestCacheIndex.remove_entry(index, "missing.json", test_dir)

      assert updated == index
    end
  end

  describe "cleanup_old_entries/3" do
    test "removes entries older than specified age", %{test_dir: test_dir} do
      now = DateTime.utc_now()

      entries = [
        %{
          timestamp: now,
          filename: "new.json",
          status: :success,
          size: 1024,
          content_hash: "new123",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        },
        %{
          timestamp: DateTime.add(now, -8, :day),
          filename: "old.json",
          status: :success,
          size: 1024,
          content_hash: "old123",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        }
      ]

      index = TestCacheIndex.load_index(test_dir)

      # Add entries using reduce to accumulate index updates
      index =
        Enum.reduce(entries, index, fn entry, acc_index ->
          TestCacheIndex.add_entry(acc_index, entry, test_dir)
        end)

      # Cleanup entries older than 7 days
      # 7 days in milliseconds
      max_age_ms = 7 * 24 * 60 * 60 * 1000
      updated = TestCacheIndex.cleanup_old_entries(index, max_age_ms, test_dir)

      assert length(updated.entries) == 1
      assert hd(updated.entries).filename == "new.json"
      assert updated.cleanup_before != nil
    end

    test "updates cleanup tracking fields", %{test_dir: test_dir} do
      index = TestCacheIndex.load_index(test_dir)

      assert index.last_cleanup == nil
      assert index.cleanup_before == nil

      updated = TestCacheIndex.cleanup_old_entries(index, 30 * 24 * 60 * 60 * 1000, test_dir)

      assert updated.last_cleanup != nil
      assert updated.cleanup_before != nil

      # cleanup_before should be approximately 30 days ago
      age = DateTime.diff(DateTime.utc_now(), updated.cleanup_before, :day)
      assert age >= 29 and age <= 31
    end
  end

  describe "get_entries_by_status/2" do
    test "filters entries by status", %{test_dir: test_dir} do
      entries = [
        %{
          timestamp: DateTime.utc_now(),
          filename: "success1.json",
          status: :success,
          size: 1024,
          content_hash: "s1",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -1, :minute),
          filename: "error1.json",
          status: :error,
          size: 512,
          content_hash: "e1",
          response_time_ms: 50,
          api_version: nil,
          cost: nil
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -2, :minute),
          filename: "success2.json",
          status: :success,
          size: 2048,
          content_hash: "s2",
          response_time_ms: 200,
          api_version: nil,
          cost: nil
        }
      ]

      index = TestCacheIndex.load_index(test_dir)

      # Use reduce to accumulate index updates across iterations
      index =
        Enum.reduce(entries, index, fn entry, acc_index ->
          TestCacheIndex.add_entry(acc_index, entry, test_dir)
        end)

      success_entries = TestCacheIndex.get_entries_by_status(index, :success)
      assert length(success_entries) == 2
      assert Enum.all?(success_entries, &(&1.status == :success))

      error_entries = TestCacheIndex.get_entries_by_status(index, :error)
      assert length(error_entries) == 1
      assert hd(error_entries).status == :error
    end
  end

  describe "find_duplicate_content/1" do
    test "identifies entries with duplicate content hashes", %{test_dir: test_dir} do
      entries = [
        %{
          timestamp: DateTime.utc_now(),
          filename: "file1.json",
          status: :success,
          size: 1024,
          content_hash: "duplicate_hash",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -1, :minute),
          filename: "file2.json",
          status: :success,
          size: 1024,
          content_hash: "unique_hash",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -2, :minute),
          filename: "file3.json",
          status: :success,
          size: 1024,
          content_hash: "duplicate_hash",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        }
      ]

      index = TestCacheIndex.load_index(test_dir)

      # Use reduce to accumulate index updates across iterations
      index =
        Enum.reduce(entries, index, fn entry, acc_index ->
          TestCacheIndex.add_entry(acc_index, entry, test_dir)
        end)

      duplicates = TestCacheIndex.find_duplicate_content(index)

      assert Map.has_key?(duplicates, "duplicate_hash")
      assert length(duplicates["duplicate_hash"]) == 2

      # Check that both files with duplicate hashes are in the list
      filenames = Enum.map(duplicates["duplicate_hash"], & &1.filename)
      assert "file1.json" in filenames
      assert "file3.json" in filenames

      # Unique hash should not be in duplicates
      assert not Map.has_key?(duplicates, "unique_hash")
    end

    test "returns empty map when no duplicates", %{test_dir: test_dir} do
      entries = [
        %{
          timestamp: DateTime.utc_now(),
          filename: "file1.json",
          status: :success,
          size: 1024,
          content_hash: "hash1",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        },
        %{
          timestamp: DateTime.add(DateTime.utc_now(), -1, :minute),
          filename: "file2.json",
          status: :success,
          size: 1024,
          content_hash: "hash2",
          response_time_ms: 100,
          api_version: nil,
          cost: nil
        }
      ]

      index = TestCacheIndex.load_index(test_dir)

      # Use reduce to accumulate index updates across iterations
      index =
        Enum.reduce(entries, index, fn entry, acc_index ->
          TestCacheIndex.add_entry(acc_index, entry, test_dir)
        end)

      duplicates = TestCacheIndex.find_duplicate_content(index)

      assert duplicates == %{}
    end
  end

  describe "calculate_hit_rate/1" do
    test "calculates correct hit rate", %{test_dir: test_dir} do
      index = %{
        cache_key: "test",
        entries: [],
        total_requests: 100,
        cache_hits: 85,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      assert TestCacheIndex.calculate_hit_rate(index) == 0.85
    end

    test "returns 0.0 when no requests", %{test_dir: test_dir} do
      index = TestCacheIndex.load_index(test_dir)

      assert TestCacheIndex.calculate_hit_rate(index) == 0.0
    end

    test "handles all hits correctly", %{test_dir: test_dir} do
      index = %{
        cache_key: "test",
        entries: [],
        total_requests: 50,
        cache_hits: 50,
        last_accessed: nil,
        access_count: 0,
        last_cleanup: nil,
        cleanup_before: nil
      }

      assert TestCacheIndex.calculate_hit_rate(index) == 1.0
    end
  end
end
