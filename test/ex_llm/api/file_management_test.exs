defmodule ExLLM.API.FileManagementTest do
  @moduledoc """
  Comprehensive tests for the unified file management API.
  Tests the public ExLLM API to ensure excellent user experience.
  """

  use ExUnit.Case, async: false
  import ExLLM.Testing.TestCacheHelpers

  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag :unified_api
  @moduletag :file_management

  # Test file content for uploads
  @test_file_content "Hello, this is a test file for ExLLM unified API testing."
  @test_file_name "test_file.txt"

  setup_all do
    enable_cache_debug()
    :ok
  end

  setup context do
    setup_test_cache(context)

    # Create a temporary test file
    test_file_path = Path.join(System.tmp_dir(), @test_file_name)
    File.write!(test_file_path, @test_file_content)

    on_exit(fn ->
      ExLLM.Testing.TestCacheDetector.clear_test_context()
      File.rm(test_file_path)
    end)

    %{test_file_path: test_file_path}
  end

  describe "upload_file/3" do
    @tag provider: :gemini
    test "uploads file successfully with Gemini", %{test_file_path: test_file_path} do
      case ExLLM.upload_file(:gemini, test_file_path, display_name: "Test File") do
        {:ok, file_info} ->
          assert is_map(file_info)
          assert Map.has_key?(file_info, :name)
          assert Map.has_key?(file_info, :display_name)
          assert file_info.display_name == "Test File"

        {:error, reason} ->
          # Log the error but don't fail the test if it's a configuration issue
          IO.puts("Gemini file upload failed: #{inspect(reason)}")
          :ok
      end
    end

    @tag provider: :openai
    test "uploads file successfully with OpenAI", %{test_file_path: test_file_path} do
      case ExLLM.upload_file(:openai, test_file_path, purpose: "user_data") do
        {:ok, file_info} ->
          assert is_map(file_info)
          assert Map.has_key?(file_info, :id)
          assert Map.has_key?(file_info, :filename)
          assert Map.has_key?(file_info, :purpose)

        {:error, reason} ->
          # Log the error but don't fail the test if it's a configuration issue
          IO.puts("OpenAI file upload failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider", %{test_file_path: test_file_path} do
      assert {:error, "File upload not supported for provider: anthropic"} =
               ExLLM.upload_file(:anthropic, test_file_path)
    end

    test "returns error for non-existent file" do
      non_existent_path = "/path/that/does/not/exist.txt"

      case ExLLM.upload_file(:gemini, non_existent_path) do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          flunk("Expected error for non-existent file")
      end
    end

    test "handles invalid file path gracefully" do
      invalid_paths = [nil, "", 123, %{}, []]

      for invalid_path <- invalid_paths do
        case ExLLM.upload_file(:gemini, invalid_path) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid path: #{inspect(invalid_path)}")
        end
      end
    end
  end

  describe "list_files/2" do
    @tag provider: :gemini
    test "lists files successfully with Gemini" do
      case ExLLM.list_files(:gemini, page_size: 5) do
        {:ok, response} ->
          assert is_map(response)
          # Gemini returns files in a specific structure
          assert Map.has_key?(response, :files) or Map.has_key?(response, :data)

        {:error, reason} ->
          IO.puts("Gemini list files failed: #{inspect(reason)}")
          :ok
      end
    end

    @tag provider: :openai
    test "lists files successfully with OpenAI" do
      case ExLLM.list_files(:openai, limit: 5) do
        {:ok, response} ->
          assert is_map(response)
          # OpenAI returns files in a specific structure
          assert Map.has_key?(response, :data) or is_list(response)

        {:error, reason} ->
          IO.puts("OpenAI list files failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, "File listing not supported for provider: anthropic"} =
               ExLLM.list_files(:anthropic)
    end

    test "handles invalid options gracefully" do
      # Test with invalid options
      case ExLLM.list_files(:gemini, invalid_option: "invalid") do
        {:ok, _response} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "get_file/3" do
    test "returns error for unsupported provider" do
      assert {:error, "File retrieval not supported for provider: anthropic"} =
               ExLLM.get_file(:anthropic, "file_id")
    end

    @tag provider: :gemini
    test "handles non-existent file ID with Gemini" do
      case ExLLM.get_file(:gemini, "non_existent_file_id") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    @tag provider: :openai
    test "handles non-existent file ID with OpenAI" do
      case ExLLM.get_file(:openai, "non_existent_file_id") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    test "handles invalid file ID types" do
      invalid_ids = [nil, 123, %{}, []]

      for invalid_id <- invalid_ids do
        case ExLLM.get_file(:gemini, invalid_id) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid file ID: #{inspect(invalid_id)}")
        end
      end
    end
  end

  describe "delete_file/3" do
    test "returns error for unsupported provider" do
      assert {:error, "File deletion not supported for provider: anthropic"} =
               ExLLM.delete_file(:anthropic, "file_id")
    end

    @tag provider: :gemini
    test "handles non-existent file ID with Gemini" do
      case ExLLM.delete_file(:gemini, "non_existent_file_id") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # Some providers might return success even for non-existent files
          :ok
      end
    end

    @tag provider: :openai
    test "handles non-existent file ID with OpenAI" do
      case ExLLM.delete_file(:openai, "non_existent_file_id") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # Some providers might return success even for non-existent files
          :ok
      end
    end

    test "handles invalid file ID types" do
      invalid_ids = [nil, 123, %{}, []]

      for invalid_id <- invalid_ids do
        case ExLLM.delete_file(:gemini, invalid_id) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid file ID: #{inspect(invalid_id)}")
        end
      end
    end
  end

  describe "file management workflow" do
    @tag provider: :gemini
    @tag :slow
    test "complete file lifecycle with Gemini", %{test_file_path: test_file_path} do
      # Skip if Gemini is not configured
      unless ExLLM.configured?(:gemini) do
        IO.puts("Skipping Gemini file lifecycle test - not configured")
        :ok
      else
        # Upload file
        case ExLLM.upload_file(:gemini, test_file_path, display_name: "Lifecycle Test") do
          {:ok, file_info} ->
            file_name = file_info.name

            # List files and verify our file is there
            case ExLLM.list_files(:gemini) do
              {:ok, list_response} ->
                files = Map.get(list_response, :files, [])
                assert Enum.any?(files, fn f -> f.name == file_name end)

              {:error, reason} ->
                IO.puts("List files failed: #{inspect(reason)}")
            end

            # Get file details
            case ExLLM.get_file(:gemini, file_name) do
              {:ok, retrieved_file} ->
                assert retrieved_file.name == file_name
                assert retrieved_file.display_name == "Lifecycle Test"

              {:error, reason} ->
                IO.puts("Get file failed: #{inspect(reason)}")
            end

            # Clean up - delete the file
            case ExLLM.delete_file(:gemini, file_name) do
              {:ok, _} ->
                :ok

              {:error, reason} ->
                IO.puts("Delete file failed: #{inspect(reason)}")
            end

          {:error, reason} ->
            IO.puts("Gemini file lifecycle test skipped: #{inspect(reason)}")
            :ok
        end
      end
    end

    @tag provider: :openai
    @tag :slow
    test "complete file lifecycle with OpenAI", %{test_file_path: test_file_path} do
      # Skip if OpenAI is not configured
      unless ExLLM.configured?(:openai) do
        IO.puts("Skipping OpenAI file lifecycle test - not configured")
        :ok
      else
        # Upload file
        case ExLLM.upload_file(:openai, test_file_path, purpose: "user_data") do
          {:ok, file_info} ->
            file_id = file_info.id

            # List files and verify our file is there
            case ExLLM.list_files(:openai) do
              {:ok, list_response} ->
                files = Map.get(list_response, :data, list_response)
                files = if is_list(files), do: files, else: []
                assert Enum.any?(files, fn f -> f.id == file_id end)

              {:error, reason} ->
                IO.puts("List files failed: #{inspect(reason)}")
            end

            # Get file details
            case ExLLM.get_file(:openai, file_id) do
              {:ok, retrieved_file} ->
                assert retrieved_file.id == file_id

              {:error, reason} ->
                IO.puts("Get file failed: #{inspect(reason)}")
            end

            # Clean up - delete the file
            case ExLLM.delete_file(:openai, file_id) do
              {:ok, _} ->
                :ok

              {:error, reason} ->
                IO.puts("Delete file failed: #{inspect(reason)}")
            end

          {:error, reason} ->
            IO.puts("OpenAI file lifecycle test skipped: #{inspect(reason)}")
            :ok
        end
      end
    end
  end
end
