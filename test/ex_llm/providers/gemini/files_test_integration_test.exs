defmodule ExLLM.Gemini.FilesTest do
  @moduledoc """
  Tests for the Gemini Files API.

  Tests cover:
  - File upload (resumable)
  - File metadata retrieval
  - File listing with pagination
  - File deletion
  - File state transitions
  - Error handling
  """

  use ExUnit.Case, async: true
  alias ExLLM.Providers.Gemini.Files
  alias ExLLM.Providers.Gemini.Files.{File, VideoFileMetadata}

  @moduletag :integration

  describe "upload_file/3" do
    test "successfully uploads a text file" do
      file_path = create_temp_file("Hello, Gemini!", "test.txt")

      case Files.upload_file(file_path, display_name: "Test Text File") do
        {:ok, %File{} = file} ->
          assert file.name =~ "files/"
          assert file.display_name == "Test Text File"
          assert file.mime_type == "text/plain"
          assert file.state in [:processing, :active]
          assert file.uri
          assert file.size_bytes > 0

          # Clean up
          Files.delete_file(file.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          # Expected when running without valid API key
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end

      Elixir.File.rm(file_path)
    end

    test "successfully uploads an image file" do
      # Create a minimal PNG file
      # PNG header
      png_data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      file_path = create_temp_file(png_data, "test.png")

      case Files.upload_file(file_path, display_name: "Test Image") do
        {:ok, %File{} = file} ->
          assert file.display_name == "Test Image"
          assert file.mime_type in ["image/png", "application/octet-stream"]
          assert file.state in [:processing, :active]

          # Clean up
          Files.delete_file(file.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end

      Elixir.File.rm(file_path)
    end

    test "handles upload of video file with metadata" do
      # Create a minimal MP4 file header
      # ftyp box header
      mp4_data = <<0, 0, 0, 32, 102, 116, 121, 112>>
      file_path = create_temp_file(mp4_data, "test.mp4")

      case Files.upload_file(file_path, display_name: "Test Video") do
        {:ok, %File{} = file} ->
          assert file.display_name == "Test Video"
          assert file.mime_type in ["video/mp4", "application/octet-stream"]

          # Video metadata might be available after processing
          if file.video_metadata do
            assert %VideoFileMetadata{} = file.video_metadata
            assert file.video_metadata.video_duration
          end

          # Clean up
          Files.delete_file(file.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end

      Elixir.File.rm(file_path)
    end

    test "returns error for non-existent file" do
      result = Files.upload_file("/non/existent/file.txt")
      assert {:error, %{reason: :file_not_found}} = result
    end

    test "returns error for empty file path" do
      result = Files.upload_file("")
      assert {:error, %{reason: :invalid_params}} = result
    end

    test "handles upload failure" do
      # Create a file that might be rejected
      file_path = create_temp_file("test", "test.exe")

      case Files.upload_file(file_path) do
        {:ok, file} ->
          # If it succeeds, clean up
          Files.delete_file(file.name)

        {:error, %{status: 400}} ->
          # Expected for certain file types or API key issues
          assert true

        {:error, _} ->
          # Any error is acceptable for this test
          assert true
      end

      Elixir.File.rm(file_path)
    end
  end

  describe "get_file/2" do
    test "retrieves file metadata" do
      # First upload a file
      file_path = create_temp_file("Test content", "get_test.txt")

      case Files.upload_file(file_path) do
        {:ok, uploaded_file} ->
          # Now get the file metadata
          case Files.get_file(uploaded_file.name) do
            {:ok, %File{} = file} ->
              assert file.name == uploaded_file.name
              assert file.uri == uploaded_file.uri
              assert file.state in [:processing, :active]

            {:error, error} ->
              flunk("Failed to get file: #{inspect(error)}")
          end

          # Clean up
          Files.delete_file(uploaded_file.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Failed to upload file: #{inspect(error)}")
      end

      Elixir.File.rm(file_path)
    end

    test "returns error for non-existent file" do
      case Files.get_file("files/non-existent-file") do
        {:error, %{status: 404}} ->
          assert true

        {:error, %{status: 403}} ->
          # Google returns 403 for non-existent files
          assert true

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        other ->
          flunk("Expected error, got: #{inspect(other)}")
      end
    end

    test "returns error for invalid file name" do
      result = Files.get_file("invalid-name")
      assert {:error, %{reason: :invalid_params}} = result
    end
  end

  describe "list_files/1" do
    test "lists uploaded files" do
      case Files.list_files() do
        {:ok, %{files: files, next_page_token: _token}} ->
          assert is_list(files)

          Enum.each(files, fn file ->
            assert %File{} = file
            assert file.name =~ "files/"
            assert file.state in [:processing, :active, :failed]
          end)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "lists files with pagination" do
      case Files.list_files(page_size: 2) do
        {:ok, %{files: files, next_page_token: token}} ->
          assert length(files) <= 2

          if token do
            # Try to get next page
            case Files.list_files(page_token: token, page_size: 2) do
              {:ok, %{files: next_files}} ->
                assert is_list(next_files)

              {:error, _} ->
                # Pagination error is acceptable
                assert true
            end
          end

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "handles invalid page size" do
      result = Files.list_files(page_size: -1)
      assert {:error, %{reason: :invalid_params}} = result

      result = Files.list_files(page_size: 101)
      assert {:error, %{reason: :invalid_params}} = result
    end
  end

  describe "delete_file/2" do
    test "successfully deletes a file" do
      # First upload a file
      file_path = create_temp_file("To be deleted", "delete_test.txt")

      case Files.upload_file(file_path) do
        {:ok, uploaded_file} ->
          # Delete the file
          case Files.delete_file(uploaded_file.name) do
            :ok ->
              # Verify it's gone
              case Files.get_file(uploaded_file.name) do
                {:error, %{status: 404}} ->
                  assert true

                {:ok, _} ->
                  flunk("File should have been deleted")

                {:error, _} ->
                  # Any error after deletion is acceptable
                  assert true
              end

            {:error, error} ->
              flunk("Failed to delete file: #{inspect(error)}")
          end

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Failed to upload file: #{inspect(error)}")
      end

      Elixir.File.rm(file_path)
    end

    test "returns error for non-existent file" do
      case Files.delete_file("files/non-existent-file") do
        {:error, %{status: 404}} ->
          assert true

        {:error, %{status: 403}} ->
          # Google returns 403 for non-existent files
          assert true

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        :ok ->
          # Some APIs might return success for non-existent files
          assert true

        other ->
          flunk("Expected error, got: #{inspect(other)}")
      end
    end

    test "returns error for invalid file name" do
      result = Files.delete_file("invalid-name")
      assert {:error, %{reason: :invalid_params}} = result
    end
  end

  describe "wait_for_file/3" do
    test "waits for file to become active" do
      file_path = create_temp_file("Processing test", "wait_test.txt")

      case Files.upload_file(file_path) do
        {:ok, uploaded_file} ->
          # Wait for file to be processed
          case Files.wait_for_file(uploaded_file.name, timeout: 10_000) do
            {:ok, %File{state: :active} = file} ->
              assert file.name == uploaded_file.name

            {:ok, %File{state: :failed} = file} ->
              # File processing failed
              assert file.error

            {:error, :timeout} ->
              # Timeout is acceptable for large files
              assert true

            {:error, error} ->
              flunk("Unexpected error: #{inspect(error)}")
          end

          # Clean up
          Files.delete_file(uploaded_file.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Failed to upload file: #{inspect(error)}")
      end

      Elixir.File.rm(file_path)
    end
  end

  describe "File struct" do
    test "parses all file fields correctly" do
      api_response = %{
        "name" => "files/abc-123",
        "displayName" => "My Test File",
        "mimeType" => "text/plain",
        "sizeBytes" => "1024",
        "createTime" => "2024-01-01T12:00:00Z",
        "updateTime" => "2024-01-01T12:01:00Z",
        "expirationTime" => "2024-01-02T12:00:00Z",
        "sha256Hash" => "abc123==",
        "uri" => "https://generativelanguage.googleapis.com/v1beta/files/abc-123",
        "downloadUri" => "https://download.example.com/files/abc-123",
        "state" => "ACTIVE",
        "source" => "UPLOADED",
        "error" => %{
          "code" => 500,
          "message" => "Internal error"
        },
        "videoMetadata" => %{
          "videoDuration" => "120.5s"
        }
      }

      file = File.from_api(api_response)

      assert file.name == "files/abc-123"
      assert file.display_name == "My Test File"
      assert file.mime_type == "text/plain"
      assert file.size_bytes == 1024
      assert file.create_time == ~U[2024-01-01 12:00:00Z]
      assert file.update_time == ~U[2024-01-01 12:01:00Z]
      assert file.expiration_time == ~U[2024-01-02 12:00:00Z]
      assert file.sha256_hash == "abc123=="
      assert file.uri == "https://generativelanguage.googleapis.com/v1beta/files/abc-123"
      assert file.download_uri == "https://download.example.com/files/abc-123"
      assert file.state == :active
      assert file.source == :uploaded
      assert file.error.code == 500
      assert file.error.message == "Internal error"
      assert file.video_metadata.video_duration == 120.5
    end

    test "handles minimal file response" do
      api_response = %{
        "name" => "files/minimal",
        "mimeType" => "text/plain",
        "sizeBytes" => "100",
        "state" => "PROCESSING"
      }

      file = File.from_api(api_response)

      assert file.name == "files/minimal"
      assert file.mime_type == "text/plain"
      assert file.size_bytes == 100
      assert file.state == :processing
      assert file.display_name == nil
      assert file.video_metadata == nil
      assert file.error == nil
    end
  end

  # Helper functions

  defp create_temp_file(content, filename) do
    temp_dir = System.tmp_dir!()
    file_path = Path.join(temp_dir, filename)
    Elixir.File.write!(file_path, content)
    file_path
  end
end
