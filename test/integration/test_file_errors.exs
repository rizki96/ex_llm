defmodule TestFileErrors do
  use ExUnit.Case

  test "file upload error - file not found" do
    result =
      ExLLM.FileManager.upload_file(:openai, "/tmp/non_existent_file.txt", purpose: "assistants")

    assert {:error, error} = result
    assert error.message =~ "File not found"
  end
end
