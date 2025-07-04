defmodule ExLLM.Integration.ComprehensiveFileTest do
  @moduledoc """
  Comprehensive file management tests that work with the current API implementation.
  """
  use ExUnit.Case
  alias ExLLM.FileManager

  describe "OpenAI File Management - Basic Operations" do
    @describetag :integration
    @describetag timeout: 30_000
    test "upload, retrieve, and delete text file" do
      # Create test file
      content = "Hello ExLLM File Test"
      file_path = "/tmp/comprehensive_test.txt"
      File.write!(file_path, content)

      try do
        # Upload file
        {:ok, file} = FileManager.upload_file(:openai, file_path, purpose: "assistants")

        assert file["id"] =~ ~r/^file-/
        assert file["filename"] == "comprehensive_test.txt"
        assert file["purpose"] == "assistants"
        assert file["status"] in ["uploaded", "processed"]
        assert file["bytes"] == byte_size(content)

        # Retrieve file metadata
        {:ok, retrieved} = FileManager.get_file(:openai, file["id"])
        assert retrieved["id"] == file["id"]
        assert retrieved["filename"] == file["filename"]
        assert retrieved["purpose"] == file["purpose"]

        # Delete file
        {:ok, delete_response} = FileManager.delete_file(:openai, file["id"])
        assert delete_response["deleted"] == true
        assert delete_response["id"] == file["id"]

        # Verify deletion
        result = FileManager.get_file(:openai, file["id"])
        assert {:error, _} = result
      after
        File.rm(file_path)
      end
    end

    test "multi-format file uploads" do
      files_to_test = [
        {"test.json", ~s|{"test": "data"}|, "assistants"},
        {"test.csv", "name,value\ntest,123", "assistants"},
        {"test.txt", "Simple text content", "assistants"}
      ]

      uploaded_files =
        for {filename, content, purpose} <- files_to_test, reduce: [] do
          acc ->
            file_path = "/tmp/#{filename}"
            File.write!(file_path, content)

            result =
              case FileManager.upload_file(:openai, file_path, purpose: purpose) do
                {:ok, file} ->
                  assert file["filename"] == filename
                  assert file["purpose"] == purpose
                  assert file["status"] in ["uploaded", "processed"]
                  [file | acc]

                {:error, error} ->
                  IO.puts("Upload failed for #{filename}: #{inspect(error)}")
                  # Skip this file but continue test
                  acc
              end

            File.rm!(file_path)
            result
        end

      # Verify all files uploaded successfully
      assert length(uploaded_files) == 3

      # Cleanup uploaded files
      for file <- uploaded_files do
        FileManager.delete_file(:openai, file["id"])
      end
    end

    test "file listing and filtering" do
      # Upload test files with different purposes
      test_files = [
        {"list_test1.txt", "Test content 1", "assistants"},
        {"list_test2.txt", "Test content 2", "assistants"},
        {"list_test3.jsonl", ~s|{"messages": [{"role": "user", "content": "test"}]}|, "fine-tune"}
      ]

      try do
        # Upload files
        uploaded_files =
          for {filename, content, purpose} <- test_files do
            file_path = "/tmp/#{filename}"
            File.write!(file_path, content)

            {:ok, file} = FileManager.upload_file(:openai, file_path, purpose: purpose)
            File.rm!(file_path)
            file
          end

        Process.put(:uploaded_files_listing, uploaded_files)

        # List all files
        {:ok, file_list} = FileManager.list_files(:openai)
        assert is_list(file_list["data"])
        assert file_list["object"] == "list"

        # Verify our files are in the list
        file_ids = Enum.map(uploaded_files, & &1["id"])
        listed_ids = Enum.map(file_list["data"], & &1["id"])

        for file_id <- file_ids do
          assert file_id in listed_ids
        end

        # Test filtering by purpose
        {:ok, assistants_list} = FileManager.list_files(:openai, purpose: "assistants")
        assistants_files = assistants_list["data"]

        # Should have at least our 2 assistant files
        our_assistant_files = Enum.filter(uploaded_files, &(&1["purpose"] == "assistants"))
        our_assistant_ids = Enum.map(our_assistant_files, & &1["id"])

        for id <- our_assistant_ids do
          assert Enum.any?(assistants_files, &(&1["id"] == id))
        end
      after
        # Cleanup
        case Process.get(:uploaded_files_listing, []) do
          files when is_list(files) ->
            for file <- files do
              FileManager.delete_file(:openai, file["id"])
            end

          _ ->
            :ok
        end
      end
    end

    test "error handling - file not found" do
      result =
        FileManager.upload_file(:openai, "/tmp/non_existent_file.txt", purpose: "assistants")

      assert {:error, error} = result
      assert error.message =~ "File not found"
      assert error.type == :file_not_found
    end

    test "error handling - invalid file purpose" do
      file_path = "/tmp/invalid_purpose_test.txt"
      File.write!(file_path, "test content")

      try do
        result = FileManager.upload_file(:openai, file_path, purpose: "invalid-purpose")
        assert {:error, _error} = result
      after
        File.rm(file_path)
      end
    end

    test "different file purposes" do
      valid_purposes = ["assistants", "fine-tune"]

      try do
        files =
          Enum.reduce(valid_purposes, [], fn purpose, acc ->
            content =
              if purpose == "fine-tune" do
                ~s|{"messages": [{"role": "user", "content": "test"}]}|
              else
                "Test content for #{purpose}"
              end

            ext = if purpose == "fine-tune", do: "jsonl", else: "txt"
            file_path = "/tmp/#{purpose}_test.#{ext}"
            File.write!(file_path, content)

            result =
              case FileManager.upload_file(:openai, file_path, purpose: purpose) do
                {:ok, file} ->
                  assert file["purpose"] == purpose
                  [file | acc]

                {:error, _} ->
                  # Some purposes might not be available for all accounts
                  acc
              end

            File.rm!(file_path)
            result
          end)

        Process.put(:uploaded_files, files)
      after
        # Cleanup
        case Process.get(:uploaded_files, []) do
          files when is_list(files) ->
            for file <- files do
              FileManager.delete_file(:openai, file["id"])
            end

          _ ->
            :ok
        end
      end
    end

    test "complete file lifecycle" do
      # Create a JSONL file for fine-tuning
      content =
        ~s|{"messages": [{"role": "user", "content": "Hello"}, {"role": "assistant", "content": "Hi there!"}]}|

      file_path = "/tmp/lifecycle_test.jsonl"
      File.write!(file_path, content)

      try do
        # Upload
        {:ok, file} = FileManager.upload_file(:openai, file_path, purpose: "fine-tune")
        assert file["status"] in ["uploaded", "processed"]

        # Wait for processing if needed
        if file["status"] == "uploaded" do
          Process.sleep(2000)
          {:ok, _file} = FileManager.get_file(:openai, file["id"])
        end

        # List files to verify it's there
        {:ok, list} = FileManager.list_files(:openai, purpose: "fine-tune")
        assert Enum.any?(list["data"], &(&1["id"] == file["id"]))

        # Get file details
        {:ok, details} = FileManager.get_file(:openai, file["id"])
        assert details["id"] == file["id"]
        assert details["purpose"] == "fine-tune"

        # Delete
        {:ok, delete_response} = FileManager.delete_file(:openai, file["id"])
        assert delete_response["deleted"] == true

        # Verify deletion
        assert {:error, _} = FileManager.get_file(:openai, file["id"])
      after
        File.rm(file_path)
      end
    end
  end

  describe "OpenAI File Management - Advanced Operations" do
    @describetag :integration
    @describetag :slow
    @describetag timeout: 60_000
    test "concurrent file uploads (sequential cleanup)" do
      # Create multiple files
      files_data =
        for i <- 1..3 do
          content = "Concurrent test file #{i}"
          file_path = "/tmp/concurrent#{i}.txt"
          File.write!(file_path, content)
          {file_path, "assistants", content}
        end

      try do
        # Upload concurrently
        tasks =
          Enum.map(files_data, fn {path, purpose, _content} ->
            Task.async(fn ->
              FileManager.upload_file(:openai, path, purpose: purpose)
            end)
          end)

        # Collect results
        results = Task.await_many(tasks, 30_000)

        # Filter successful uploads
        uploaded_files =
          results
          |> Enum.filter(fn result -> match?({:ok, _}, result) end)
          |> Enum.map(fn {:ok, file} -> file end)

        # Verify uploads succeeded
        # At least some should succeed
        assert length(uploaded_files) >= 1

        # Clean up uploaded files
        for file <- uploaded_files do
          FileManager.delete_file(:openai, file["id"])
        end
      after
        # Clean up local files
        for {path, _, _} <- files_data do
          File.rm(path)
        end
      end
    end

    test "large text file upload" do
      # Create a larger text file (10KB)
      content = String.duplicate("This is a test line of content for large file upload.\n", 200)
      file_path = "/tmp/large_test.txt"
      File.write!(file_path, content)

      try do
        {:ok, file} = FileManager.upload_file(:openai, file_path, purpose: "assistants")

        assert file["bytes"] == byte_size(content)
        assert file["bytes"] > 10_000
        assert file["status"] in ["uploaded", "processed"]

        # Cleanup
        FileManager.delete_file(:openai, file["id"])
      after
        File.rm(file_path)
      end
    end
  end
end
