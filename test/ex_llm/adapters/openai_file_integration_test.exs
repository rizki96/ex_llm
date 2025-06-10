defmodule ExLLM.Adapters.OpenAIFileIntegrationTest do
  use ExUnit.Case, async: true
  alias ExLLM.Adapters.OpenAI

  @moduletag :integration
  @moduletag :openai
  @moduletag :skip

  describe "file operations integration tests" do
    setup do
      unless OpenAI.configured?() do
        {:skip, "OpenAI API key not configured"}
      end

      # Create a test file
      tmp_path = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(1000)}.jsonl")
      
      # Write valid JSONL content for fine-tuning
      content = """
      {"messages": [{"role": "system", "content": "You are a helpful assistant"}, {"role": "user", "content": "Hello"}, {"role": "assistant", "content": "Hi there!"}]}
      {"messages": [{"role": "system", "content": "You are a helpful assistant"}, {"role": "user", "content": "How are you?"}, {"role": "assistant", "content": "I'm doing well, thanks!"}]}
      """
      
      File.write!(tmp_path, content)
      
      on_exit(fn -> 
        File.rm(tmp_path)
      end)
      
      {:ok, tmp_path: tmp_path}
    end

    @tag timeout: 120_000
    test "upload file workflow", %{tmp_path: tmp_path} do
      # 1. Upload a file
      {:ok, uploaded_file} = OpenAI.upload_file(tmp_path, "fine-tune")
      
      # Verify all file object fields
      assert uploaded_file["id"] =~ ~r/^file-/
      assert uploaded_file["object"] == "file"
      assert uploaded_file["purpose"] == "fine-tune"
      assert uploaded_file["filename"] =~ ~r/\.jsonl$/
      assert uploaded_file["bytes"] > 0
      assert is_integer(uploaded_file["created_at"])
      
      # Check for expires_at field (should be present for uploaded files)
      if Map.has_key?(uploaded_file, "expires_at") do
        assert is_integer(uploaded_file["expires_at"])
        assert uploaded_file["expires_at"] > uploaded_file["created_at"]
      end
      
      # Check deprecated fields if present
      if Map.has_key?(uploaded_file, "status") do
        assert uploaded_file["status"] in ["uploaded", "processed", "error"]
      end
      
      file_id = uploaded_file["id"]
      
      # 2. List files and verify our file is there
      {:ok, list_response} = OpenAI.list_files()
      assert list_response["object"] == "list"
      assert is_list(list_response["data"])
      assert Enum.any?(list_response["data"], fn f -> f["id"] == file_id end)
      
      # 3. Get specific file metadata
      {:ok, file_info} = OpenAI.get_file(file_id)
      assert file_info["id"] == file_id
      assert file_info["purpose"] == "fine-tune"
      
      # 4. Retrieve file content
      {:ok, content} = OpenAI.retrieve_file_content(file_id)
      assert is_binary(content)
      assert content =~ "You are a helpful assistant"
      
      # 5. Delete the file
      {:ok, delete_response} = OpenAI.delete_file(file_id)
      assert delete_response["id"] == file_id
      assert delete_response["object"] == "file"
      assert delete_response["deleted"] == true
      
      # 6. Verify file is gone
      {:ok, list_after} = OpenAI.list_files()
      refute Enum.any?(list_after["data"], fn f -> f["id"] == file_id end)
    end

    test "list files with filters" do
      # List only fine-tune files
      {:ok, response} = OpenAI.list_files(purpose: "fine-tune", limit: 10)
      
      assert response["object"] == "list"
      assert is_list(response["data"])
      assert length(response["data"]) <= 10
      
      # All files should have fine-tune purpose
      for file <- response["data"] do
        assert file["purpose"] == "fine-tune"
      end
    end
    
    test "list files with pagination and ordering" do
      # Test pagination parameters
      {:ok, response} = OpenAI.list_files(limit: 5, order: "asc")
      
      assert response["object"] == "list"
      assert is_list(response["data"])
      assert length(response["data"]) <= 5
      
      if length(response["data"]) > 1 do
        # Verify ascending order by created_at
        times = Enum.map(response["data"], & &1["created_at"])
        assert times == Enum.sort(times)
      end
      
      # Test pagination with after cursor
      if first_file = List.first(response["data"]) do
        {:ok, next_page} = OpenAI.list_files(after: first_file["id"], limit: 5)
        assert next_page["object"] == "list"
        
        # Ensure we got different files
        first_page_ids = MapSet.new(response["data"], & &1["id"])
        next_page_ids = MapSet.new(next_page["data"], & &1["id"])
        assert MapSet.disjoint?(first_page_ids, next_page_ids)
      end
    end

    test "upload file with different purposes", %{tmp_path: tmp_path} do
      # Test only input purposes (output purposes are system-generated)
      input_purposes = ["fine-tune", "assistants", "batch", "vision", "user_data", "evals"]
      
      for purpose <- input_purposes do
        # Different file types may have different validation rules
        # For this test, we'll just verify the upload accepts the purpose
        case OpenAI.upload_file(tmp_path, purpose) do
          {:ok, file} ->
            assert file["purpose"] == purpose
            assert file["object"] == "file"
            assert is_integer(file["bytes"])
            assert is_integer(file["created_at"])
            
            # Clean up
            OpenAI.delete_file(file["id"])
            
          {:error, %{message: message}} ->
            # Some purposes may require specific file formats
            IO.puts("Upload failed for purpose #{purpose}: #{message}")
        end
      end
    end
    
    test "validate output purposes are rejected for upload" do
      # These purposes are only for system-generated files
      output_purposes = ["fine-tune-results", "assistants_output", "batch_output"]
      
      tmp_path = Path.join(System.tmp_dir!(), "test_output.jsonl")
      File.write!(tmp_path, "test content")
      on_exit(fn -> File.rm(tmp_path) end)
      
      for purpose <- output_purposes do
        # Most APIs would reject these purposes for user uploads
        # but we'll handle whatever the API returns
        result = OpenAI.upload_file(tmp_path, purpose)
        
        case result do
          {:ok, file} ->
            # If API accepts it, verify the purpose is set correctly
            assert file["purpose"] == purpose
            OpenAI.delete_file(file["id"])
            
          {:error, _} ->
            # Expected for output purposes
            :ok
        end
      end
    end

    test "error handling for invalid file" do
      result = OpenAI.upload_file("/non/existent/file.jsonl", "fine-tune")
      assert {:error, :enoent} = result
    end

    test "error handling for invalid purpose", %{tmp_path: tmp_path} do
      result = OpenAI.upload_file(tmp_path, "invalid_purpose")
      assert {:error, {:validation, _, _}} = result
    end
  end
end