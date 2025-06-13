defmodule ExLLM.Gemini.FilesUnitTest do
  @moduledoc """
  Unit tests for the Gemini Files API.
  
  Tests internal functions and behavior without making actual API calls.
  """
  
  use ExUnit.Case, async: true
  alias ExLLM.Gemini.Files
  alias ExLLM.Gemini.Files.{File, VideoFileMetadata, Status}
  
  describe "File struct" do
    test "creates file with all fields" do
      file = %File{
        name: "files/test-123",
        display_name: "Test File",
        mime_type: "text/plain",
        size_bytes: 1024,
        create_time: ~U[2024-01-01 12:00:00Z],
        update_time: ~U[2024-01-01 12:01:00Z],
        expiration_time: ~U[2024-01-02 12:00:00Z],
        sha256_hash: "abc123==",
        uri: "https://example.com/files/test-123",
        download_uri: "https://download.example.com/files/test-123",
        state: :active,
        source: :uploaded,
        error: %Status{code: 0, message: nil, details: []},
        video_metadata: %VideoFileMetadata{video_duration: 120.5}
      }
      
      assert file.name == "files/test-123"
      assert file.state == :active
      assert file.source == :uploaded
      assert file.video_metadata.video_duration == 120.5
    end
    
    test "creates minimal file" do
      file = %File{
        name: "files/minimal",
        mime_type: "text/plain",
        size_bytes: 100,
        state: :processing
      }
      
      assert file.name == "files/minimal"
      assert file.display_name == nil
      assert file.error == nil
      assert file.video_metadata == nil
    end
  end
  
  describe "VideoFileMetadata struct" do
    test "creates video metadata" do
      metadata = %VideoFileMetadata{
        video_duration: 60.5
      }
      
      assert metadata.video_duration == 60.5
    end
  end
  
  describe "Status struct" do
    test "creates status with all fields" do
      status = %Status{
        code: 404,
        message: "Not found",
        details: [%{"@type" => "type.googleapis.com/google.rpc.ErrorInfo"}]
      }
      
      assert status.code == 404
      assert status.message == "Not found"
      assert length(status.details) == 1
    end
  end
  
  describe "validate_file_path/1" do
    test "validates existing file path" do
      temp_file = Path.join(System.tmp_dir!(), "test_validate.txt")
      Elixir.File.write!(temp_file, "test")
      
      assert Files.validate_file_path(temp_file) == :ok
      
      Elixir.File.rm!(temp_file)
    end
    
    test "returns error for non-existent file" do
      assert {:error, %{reason: :file_not_found}} = Files.validate_file_path("/non/existent/file.txt")
    end
    
    test "returns error for empty path" do
      assert {:error, %{reason: :invalid_params}} = Files.validate_file_path("")
    end
    
    test "returns error for nil path" do
      assert {:error, %{reason: :invalid_params}} = Files.validate_file_path(nil)
    end
  end
  
  describe "validate_file_name/1" do
    test "validates proper file names" do
      assert Files.validate_file_name("files/abc-123") == :ok
      assert Files.validate_file_name("files/test-file-123") == :ok
    end
    
    test "returns error for invalid formats" do
      assert {:error, %{reason: :invalid_params}} = Files.validate_file_name("abc-123")
      assert {:error, %{reason: :invalid_params}} = Files.validate_file_name("files/")
      assert {:error, %{reason: :invalid_params}} = Files.validate_file_name("")
      assert {:error, %{reason: :invalid_params}} = Files.validate_file_name(nil)
    end
  end
  
  describe "validate_page_size/1" do
    test "validates valid page sizes" do
      assert Files.validate_page_size(1) == :ok
      assert Files.validate_page_size(50) == :ok
      assert Files.validate_page_size(100) == :ok
    end
    
    test "returns error for invalid page sizes" do
      assert {:error, %{reason: :invalid_params}} = Files.validate_page_size(0)
      assert {:error, %{reason: :invalid_params}} = Files.validate_page_size(-1)
      assert {:error, %{reason: :invalid_params}} = Files.validate_page_size(101)
      assert {:error, %{reason: :invalid_params}} = Files.validate_page_size("10")
    end
  end
  
  describe "mime_type_from_extension/1" do
    test "returns correct mime types for common extensions" do
      assert Files.mime_type_from_extension(".txt") == "text/plain"
      assert Files.mime_type_from_extension(".png") == "image/png"
      assert Files.mime_type_from_extension(".jpg") == "image/jpeg"
      assert Files.mime_type_from_extension(".jpeg") == "image/jpeg"
      assert Files.mime_type_from_extension(".gif") == "image/gif"
      assert Files.mime_type_from_extension(".webp") == "image/webp"
      assert Files.mime_type_from_extension(".mp4") == "video/mp4"
      assert Files.mime_type_from_extension(".mp3") == "audio/mp3"
      assert Files.mime_type_from_extension(".wav") == "audio/wav"
      assert Files.mime_type_from_extension(".pdf") == "application/pdf"
    end
    
    test "returns octet-stream for unknown extensions" do
      assert Files.mime_type_from_extension(".xyz") == "application/octet-stream"
      assert Files.mime_type_from_extension("") == "application/octet-stream"
    end
    
    test "handles extensions without dots" do
      assert Files.mime_type_from_extension("txt") == "text/plain"
      assert Files.mime_type_from_extension("png") == "image/png"
    end
  end
  
  describe "parse_state/1" do
    test "parses valid states" do
      assert Files.parse_state("STATE_UNSPECIFIED") == :state_unspecified
      assert Files.parse_state("PROCESSING") == :processing
      assert Files.parse_state("ACTIVE") == :active
      assert Files.parse_state("FAILED") == :failed
    end
    
    test "returns atom for unknown states" do
      assert Files.parse_state("UNKNOWN") == :unknown
      assert Files.parse_state(nil) == nil
    end
  end
  
  describe "parse_source/1" do
    test "parses valid sources" do
      assert Files.parse_source("SOURCE_UNSPECIFIED") == :source_unspecified
      assert Files.parse_source("UPLOADED") == :uploaded
      assert Files.parse_source("GENERATED") == :generated
    end
    
    test "returns atom for unknown sources" do
      assert Files.parse_source("UNKNOWN") == :unknown
      assert Files.parse_source(nil) == nil
    end
  end
  
  describe "parse_timestamp/1" do
    test "parses valid RFC3339 timestamps" do
      assert Files.parse_timestamp("2024-01-01T12:00:00Z") == ~U[2024-01-01 12:00:00Z]
      assert Files.parse_timestamp("2024-01-01T12:00:00.123Z") == ~U[2024-01-01 12:00:00.123Z]
    end
    
    test "handles timestamps with timezone offsets" do
      # These should be converted to UTC
      timestamp = Files.parse_timestamp("2024-01-01T12:00:00+05:30")
      assert timestamp.hour == 6  # 12:00 + 5:30 offset = 06:30 UTC
      assert timestamp.minute == 30
    end
    
    test "returns nil for invalid timestamps" do
      assert Files.parse_timestamp("invalid") == nil
      assert Files.parse_timestamp(nil) == nil
      assert Files.parse_timestamp("") == nil
    end
  end
  
  describe "parse_duration/1" do
    test "parses valid duration strings" do
      assert Files.parse_duration("3.5s") == 3.5
      assert Files.parse_duration("120s") == 120.0
      assert Files.parse_duration("0.001s") == 0.001
    end
    
    test "returns nil for invalid durations" do
      assert Files.parse_duration("3.5") == nil
      assert Files.parse_duration("invalid") == nil
      assert Files.parse_duration(nil) == nil
    end
  end
  
  describe "build_upload_metadata/2" do
    test "builds metadata with display name" do
      metadata = Files.build_upload_metadata("test.txt", display_name: "My Test File")
      
      assert metadata == %{
        "file" => %{
          "displayName" => "My Test File"
        }
      }
    end
    
    test "builds empty metadata without options" do
      metadata = Files.build_upload_metadata("test.txt", [])
      
      assert metadata == %{
        "file" => %{}
      }
    end
  end
  
  describe "extract_upload_url/1" do
    test "extracts URL from headers" do
      headers = [
        {"x-goog-upload-url", "https://upload.example.com/path"},
        {"content-type", "application/json"}
      ]
      
      assert Files.extract_upload_url(headers) == {:ok, "https://upload.example.com/path"}
    end
    
    test "handles case-insensitive headers" do
      headers = [
        {"X-Goog-Upload-URL", "https://upload.example.com/path"}
      ]
      
      assert Files.extract_upload_url(headers) == {:ok, "https://upload.example.com/path"}
    end
    
    test "returns error when header not found" do
      headers = [
        {"content-type", "application/json"}
      ]
      
      assert {:error, %{reason: :upload_url_not_found}} = Files.extract_upload_url(headers)
    end
  end
end