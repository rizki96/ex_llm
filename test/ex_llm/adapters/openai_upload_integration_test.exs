defmodule ExLLM.Adapters.OpenAIUploadIntegrationTest do
  use ExUnit.Case, async: true
  alias ExLLM.Adapters.OpenAI

  @moduletag :integration
  @moduletag :openai
  @moduletag :upload
  @moduletag :skip

  describe "multipart upload workflow" do
    setup do
      unless OpenAI.configured?() do
        {:skip, "OpenAI API key not configured"}
      end

      # Create test data (2MB to test multipart)
      test_data = create_test_data(2 * 1024 * 1024)
      {:ok, test_data: test_data}
    end

    # 5 minutes for large upload
    @tag timeout: 300_000
    test "complete multipart upload workflow", %{test_data: test_data} do
      # 1. Create upload
      upload_params = [
        bytes: byte_size(test_data),
        filename: "test_multipart.jsonl",
        mime_type: "text/jsonl",
        purpose: "fine-tune"
      ]

      {:ok, upload} = OpenAI.create_upload(upload_params)

      assert upload["id"] =~ ~r/^upload_/
      assert upload["object"] == "upload"
      assert upload["status"] == "pending"
      assert upload["bytes"] == byte_size(test_data)
      assert is_integer(upload["expires_at"])

      upload_id = upload["id"]

      # 2. Upload parts (split into 1MB chunks)
      # 1MB chunks
      chunk_size = 1024 * 1024
      chunks = split_into_chunks(test_data, chunk_size)

      part_ids =
        Enum.map(chunks, fn chunk ->
          {:ok, part} = OpenAI.add_upload_part(upload_id, chunk)
          assert part["object"] == "upload.part"
          assert part["upload_id"] == upload_id
          part["id"]
        end)

      # 3. Complete upload
      {:ok, completed} = OpenAI.complete_upload(upload_id, part_ids)

      assert completed["id"] == upload_id
      assert completed["status"] == "completed"
      assert is_map(completed["file"])

      file = completed["file"]
      assert file["object"] == "file"
      assert file["bytes"] == byte_size(test_data)
      assert file["purpose"] == "fine-tune"

      # 4. Verify file is accessible
      file_id = file["id"]
      {:ok, file_info} = OpenAI.get_file(file_id)
      assert file_info["id"] == file_id

      # 5. Clean up
      {:ok, _} = OpenAI.delete_file(file_id)
    end

    @tag timeout: 120_000
    test "cancel upload workflow", %{test_data: test_data} do
      # Create upload
      upload_params = [
        bytes: byte_size(test_data),
        filename: "test_cancel.jsonl",
        mime_type: "text/jsonl",
        purpose: "fine-tune"
      ]

      {:ok, upload} = OpenAI.create_upload(upload_params)
      upload_id = upload["id"]

      # Add one part
      chunk = binary_part(test_data, 0, min(1024 * 1024, byte_size(test_data)))
      {:ok, _part} = OpenAI.add_upload_part(upload_id, chunk)

      # Cancel the upload
      {:ok, cancelled} = OpenAI.cancel_upload(upload_id)

      assert cancelled["id"] == upload_id
      assert cancelled["status"] == "cancelled"

      # Verify we cannot add more parts
      result = OpenAI.add_upload_part(upload_id, chunk)
      assert {:error, _} = result
    end

    test "upload with MD5 verification" do
      # Small test data for MD5
      test_data = """
      {"messages": [{"role": "user", "content": "test"}]}
      """

      md5_hash = :crypto.hash(:md5, test_data) |> Base.encode16(case: :lower)

      upload_params = [
        bytes: byte_size(test_data),
        filename: "test_md5.jsonl",
        mime_type: "text/jsonl",
        purpose: "fine-tune"
      ]

      {:ok, upload} = OpenAI.create_upload(upload_params)
      upload_id = upload["id"]

      # Upload single part
      {:ok, part} = OpenAI.add_upload_part(upload_id, test_data)

      # Complete with MD5
      {:ok, completed} =
        OpenAI.complete_upload(
          upload_id,
          [part["id"]],
          md5: md5_hash
        )

      assert completed["status"] == "completed"
      assert completed["file"]["id"]

      # Clean up
      OpenAI.delete_file(completed["file"]["id"])
    end

    test "upload part size limits" do
      # Test part size validation
      # 64MB
      max_part_size = 64 * 1024 * 1024

      # Create upload for testing
      upload_params = [
        bytes: max_part_size + 1,
        filename: "test_limits.jsonl",
        mime_type: "text/jsonl",
        purpose: "fine-tune"
      ]

      {:ok, upload} = OpenAI.create_upload(upload_params)
      upload_id = upload["id"]

      # Try to upload part that's too large (this should fail in our validation)
      large_data = :binary.copy("x", max_part_size + 1)
      result = OpenAI.add_upload_part(upload_id, large_data)
      assert {:error, %{type: :validation_error}} = result

      # Cancel the upload
      OpenAI.cancel_upload(upload_id)
    end
  end

  # Helper functions

  defp create_test_data(size) do
    # Create valid JSONL training data
    line =
      ~s({"messages": [{"role": "system", "content": "You are helpful"}, {"role": "user", "content": "Hi"}, {"role": "assistant", "content": "Hello!"}]}\n)

    line_size = byte_size(line)
    lines_needed = div(size, line_size) + 1

    data = for _ <- 1..lines_needed, do: line

    # Trim to exact size
    data
    |> Enum.join()
    |> binary_part(0, size)
  end

  defp split_into_chunks(data, chunk_size) do
    do_split_chunks(data, chunk_size, [])
    |> Enum.reverse()
  end

  defp do_split_chunks(<<>>, _chunk_size, acc), do: acc

  defp do_split_chunks(data, chunk_size, acc) when byte_size(data) <= chunk_size do
    [data | acc]
  end

  defp do_split_chunks(data, chunk_size, acc) do
    <<chunk::binary-size(chunk_size), rest::binary>> = data
    do_split_chunks(rest, chunk_size, [chunk | acc])
  end
end
