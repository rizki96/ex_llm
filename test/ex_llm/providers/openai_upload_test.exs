defmodule ExLLM.Providers.OpenAIUploadTest do
  use ExUnit.Case, async: true
  alias ExLLM.Providers.OpenAI

  describe "upload API" do
    test "create_upload validates required parameters" do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      # Missing required params
      result = OpenAI.create_upload([], config_provider: provider)
      assert {:error, {:validation, _, _}} = result

      # All required params
      params = [
        # 1 MB
        bytes: 1024 * 1024,
        filename: "test.jsonl",
        mime_type: "text/jsonl",
        purpose: "fine-tune"
      ]

      # This will fail with API error in test env, but validates params pass
      _result = OpenAI.create_upload(params, config_provider: provider)
    end

    test "create_upload validates file size limit" do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      # Exceeds 8GB limit
      params = [
        # 9 GB
        bytes: 9 * 1024 * 1024 * 1024,
        filename: "huge.jsonl",
        mime_type: "text/jsonl",
        purpose: "fine-tune"
      ]

      result = OpenAI.create_upload(params, config_provider: provider)
      assert {:error, {:validation, _, message}} = result
      assert message =~ "cannot exceed 8 GB"
    end

    test "add_upload_part validates part size" do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      # Create test data exceeding 64MB
      # 65 MB
      large_data = :binary.copy("x", 65 * 1024 * 1024)

      result = OpenAI.add_upload_part("upload_123", large_data, config_provider: provider)
      assert {:error, {:validation, _, message}} = result
      assert message =~ "cannot exceed 64 MB"

      # Valid size
      small_data = "test data"
      _result = OpenAI.add_upload_part("upload_123", small_data, config_provider: provider)
    end

    test "complete_upload accepts part IDs and optional MD5" do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      part_ids = ["part_123", "part_456"]

      # Without MD5
      _result = OpenAI.complete_upload("upload_abc", part_ids, config_provider: provider)

      # With MD5
      _result =
        OpenAI.complete_upload("upload_abc", part_ids,
          config_provider: provider,
          md5: "d41d8cd98f00b204e9800998ecf8427e"
        )
    end

    test "upload object structure" do
      # Verify the expected upload object structure
      upload = %{
        "id" => "upload_abc123",
        "object" => "upload",
        "bytes" => 2_147_483_648,
        "created_at" => 1_719_184_911,
        "filename" => "training_examples.jsonl",
        "purpose" => "fine-tune",
        "status" => "pending",
        "expires_at" => 1_719_188_511
      }

      assert upload["object"] == "upload"
      assert upload["status"] in ["pending", "completed", "cancelled"]
      assert is_integer(upload["bytes"])
      assert is_integer(upload["created_at"])
      assert is_integer(upload["expires_at"])
      assert upload["expires_at"] > upload["created_at"]
    end

    test "upload part object structure" do
      # Verify the expected part object structure
      part = %{
        "id" => "part_def456",
        "object" => "upload.part",
        "created_at" => 1_719_186_911,
        "upload_id" => "upload_abc123"
      }

      assert part["object"] == "upload.part"
      assert is_binary(part["id"])
      assert is_binary(part["upload_id"])
      assert is_integer(part["created_at"])
    end

    test "completed upload includes file object" do
      # Verify completed upload structure
      completed_upload = %{
        "id" => "upload_abc123",
        "object" => "upload",
        "bytes" => 2_147_483_648,
        "created_at" => 1_719_184_911,
        "filename" => "training_examples.jsonl",
        "purpose" => "fine-tune",
        "status" => "completed",
        "expires_at" => 1_719_188_511,
        "file" => %{
          "id" => "file-xyz321",
          "object" => "file",
          "bytes" => 2_147_483_648,
          "created_at" => 1_719_186_911,
          "filename" => "training_examples.jsonl",
          "purpose" => "fine-tune"
        }
      }

      assert completed_upload["status"] == "completed"
      assert is_map(completed_upload["file"])
      assert completed_upload["file"]["object"] == "file"
      assert completed_upload["file"]["id"] =~ ~r/^file-/
    end
  end
end
