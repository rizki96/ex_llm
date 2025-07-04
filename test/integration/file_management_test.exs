defmodule ExLLM.Integration.FileManagementTest do
  @moduledoc """
  Integration tests for file management functionality across providers.

  Tests file upload, retrieval, listing, and deletion operations
  for providers that support file management (OpenAI, Gemini).
  """
  use ExLLM.Testing.IntegrationCase

  describe "file lifecycle" do
    @describetag :file_management
    @tag max_cost: 0.10
    test "upload, retrieve, and delete a file" do
      with_provider(:openai, fn ->
        # Use minimal text file
        file_path = text_file_path()

        # Upload file
        assert {:ok, file} =
                 ExLLM.FileManager.upload_file(:openai, file_path, purpose: "assistants")

        assert file.id
        assert file.filename == "sample.txt"
        assert file.purpose == "assistants"
        assert file.bytes == byte_size(minimal_text_content())

        # Track tokens for cost (estimate: 10 tokens each way)
        track_tokens(:openai, "gpt-3.5-turbo", 10, 10)

        # Retrieve file
        assert {:ok, retrieved} = ExLLM.FileManager.get_file(:openai, file.id)
        assert retrieved.id == file.id
        assert retrieved.filename == file.filename

        # Delete file
        assert {:ok, _} = ExLLM.FileManager.delete_file(:openai, file.id)

        # Verify deletion
        assert {:error, %{status: 404}} = ExLLM.FileManager.get_file(:openai, file.id)
      end)
    end
  end

  describe "file upload" do
    @tag max_cost: 0.20
    test "supports various file formats" do
      with_provider(:openai, fn ->
        # Test multiple formats
        formats = [
          {text_file_path(), "text/plain"},
          {json_file_path(), "application/json"},
          {csv_file_path(), "text/csv"}
        ]

        uploaded_files =
          Enum.map(formats, fn {path, _expected_type} ->
            assert {:ok, file} =
                     ExLLM.FileManager.upload_file(:openai, path, purpose: "assistants")

            # Cleanup on exit
            on_exit(fn ->
              ExLLM.FileManager.delete_file(:openai, file.id)
            end)

            file
          end)

        # Verify all uploaded successfully
        assert length(uploaded_files) == 3
        assert Enum.all?(uploaded_files, & &1.id)

        # Track estimated tokens
        track_tokens(:openai, "gpt-3.5-turbo", 30, 30)
      end)
    end

    test "handles upload errors gracefully" do
      with_provider(:openai, fn ->
        # Test with non-existent file
        assert {:error, error} =
                 ExLLM.FileManager.upload_file(
                   :openai,
                   "/tmp/non_existent_file.txt",
                   purpose: "assistants"
                 )

        assert error.message =~ "not found" or error.message =~ "does not exist"
      end)
    end
  end

  describe "file operations" do
    @tag max_cost: 0.15
    test "list uploaded files" do
      with_provider(:openai, fn ->
        # Upload a test file first
        file_path = text_file_path()
        {:ok, uploaded} = ExLLM.FileManager.upload_file(:openai, file_path, purpose: "assistants")

        on_exit(fn ->
          ExLLM.FileManager.delete_file(:openai, uploaded.id)
        end)

        # List files
        assert {:ok, files} = ExLLM.FileManager.list_files(:openai)
        assert is_list(files.data)

        # Our file should be in the list
        assert Enum.any?(files.data, &(&1.id == uploaded.id))

        track_tokens(:openai, "gpt-3.5-turbo", 20, 20)
      end)
    end

    @tag max_cost: 0.10
    test "retrieve file metadata" do
      with_provider(:openai, fn ->
        # Upload file
        {:ok, file} =
          ExLLM.FileManager.upload_file(:openai, text_file_path(), purpose: "assistants")

        on_exit(fn ->
          ExLLM.FileManager.delete_file(:openai, file.id)
        end)

        # Get metadata
        assert {:ok, metadata} = ExLLM.FileManager.get_file(:openai, file.id)

        assert metadata.id == file.id
        assert metadata.object == "file"
        assert metadata.created_at
        assert metadata.purpose == "assistants"

        track_tokens(:openai, "gpt-3.5-turbo", 10, 10)
      end)
    end
  end

  describe "file deletion" do
    @tag max_cost: 0.10
    test "delete file and verify removal" do
      with_provider(:openai, fn ->
        # Upload file
        {:ok, file} =
          ExLLM.FileManager.upload_file(:openai, text_file_path(), purpose: "assistants")

        # Delete it
        assert {:ok, deleted} = ExLLM.FileManager.delete_file(:openai, file.id)
        assert deleted.id == file.id
        assert deleted.deleted == true

        # Verify it's gone
        assert {:error, %{status: 404}} = ExLLM.FileManager.get_file(:openai, file.id)

        track_tokens(:openai, "gpt-3.5-turbo", 10, 10)
      end)
    end

    test "handle deletion of non-existent file" do
      with_provider(:openai, fn ->
        fake_id = "file_#{unique_id()}"

        assert {:error, error} = ExLLM.FileManager.delete_file(:openai, fake_id)
        assert error.status == 404
      end)
    end
  end

  describe "provider-specific features" do
    @tag max_cost: 0.20
    test "complete file management workflow" do
      with_provider(:openai, fn ->
        assert_api_lifecycle(
          :file,
          # Create
          fn ->
            ExLLM.FileManager.upload_file(:openai, json_file_path(), purpose: "assistants")
          end,
          # Get
          fn id ->
            ExLLM.FileManager.get_file(:openai, id)
          end,
          # Delete
          fn id ->
            ExLLM.FileManager.delete_file(:openai, id)
          end
        )

        track_tokens(:openai, "gpt-3.5-turbo", 20, 20)
      end)
    end
  end

  describe "OpenAI-specific file management" do
    @tag provider: :openai
    @tag max_cost: 0.15
    test "file purposes (assistants, fine-tune)" do
      with_provider(:openai, fn ->
        # Test different purposes
        purposes = ["assistants", "fine-tune"]

        for purpose <- purposes do
          file_path =
            if purpose == "fine-tune",
              do: jsonl_file_path(),
              else: text_file_path()

          assert {:ok, file} = ExLLM.FileManager.upload_file(:openai, file_path, purpose: purpose)

          assert file.purpose == purpose

          # Cleanup
          ExLLM.FileManager.delete_file(:openai, file.id)
        end

        track_tokens(:openai, "gpt-3.5-turbo", 20, 20)
      end)
    end
  end

  describe "Gemini-specific file management" do
    @tag provider: :gemini
    @tag max_cost: 0.10
    test "corpus file management" do
      with_provider(:gemini, fn ->
        # Gemini uses a different file management approach
        # Files are typically uploaded as part of corpus management

        # For now, we'll test basic file upload which is simpler
        # Note: Corpus management requires OAuth2 tokens, not just API keys
        file_path = text_file_path()

        assert {:ok, file} =
                 ExLLM.FileManager.upload_file(:gemini, file_path, display_name: "Test File")

        # Gemini returns name instead of id
        assert file.name
        assert file.display_name == "Test File"

        on_exit(fn ->
          # Gemini file cleanup
          ExLLM.FileManager.delete_file(:gemini, file.name)
        end)

        # Verify file exists
        assert {:ok, retrieved} = ExLLM.FileManager.get_file(:gemini, file.name)
        assert retrieved.name == file.name

        track_tokens(:gemini, "gemini-2.0-flash", 10, 10)
      end)
    end
  end

  describe "concurrent operations" do
    @tag max_cost: 0.30
    test "concurrent upload test" do
      with_provider(:openai, fn ->
        # Upload 3 files concurrently
        tasks =
          for i <- 1..3 do
            Task.async(fn ->
              # Create unique content for each file
              content = "Test file #{i}"
              path = Path.join(System.tmp_dir!(), "concurrent_#{i}.txt")
              File.write!(path, content)

              on_exit(fn -> File.rm(path) end)

              result = ExLLM.FileManager.upload_file(:openai, path, purpose: "assistants")

              case result do
                {:ok, file} ->
                  on_exit(fn ->
                    ExLLM.FileManager.delete_file(:openai, file.id)
                  end)

                  {:ok, file}

                error ->
                  error
              end
            end)
          end

        results = Task.await_many(tasks, 10_000)

        # All should succeed
        assert Enum.all?(results, fn
                 {:ok, _} -> true
                 _ -> false
               end)

        track_tokens(:openai, "gpt-3.5-turbo", 30, 30)
      end)
    end
  end
end
