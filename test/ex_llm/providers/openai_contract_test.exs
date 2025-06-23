defmodule ExLLM.Providers.OpenAIContractTest do
  use ExUnit.Case, async: true

  alias ExLLM.Providers.OpenAI

  # This test suite serves as a contract for the public API of the OpenAI provider.
  # It tests that function signatures and basic interactions remain consistent during
  # refactoring. It intentionally uses a dummy API key to ensure that all public
  # functions can be called with their expected arguments and return a correctly
  # formatted result ({:ok, _} or {:error, _}) without relying on complex HTTP mocking.

  setup do
    # Provide a dummy API key to pass the provider's validation checks.
    System.put_env("OPENAI_API_KEY", "test-key-dummy")

    on_exit(fn ->
      # Clean up environment variables to not interfere with other tests.
      System.delete_env("OPENAI_API_KEY")
    end)

    :ok
  end

  # Helper to create and clean up a dummy file for tests that require file uploads.
  defp with_dummy_file(fun) do
    path = Path.join(System.tmp_dir!(), "dummy_file_for_contract_test.tmp")
    File.write!(path, "dummy content")

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  describe "OpenAI Provider Public API Contract" do
    test "chat/2 function exists and accepts correct parameters" do
      messages = [%{role: "user", content: "Hello"}]
      options = [model: "gpt-4"]

      # The function should exist and return either {:ok, _} or {:error, _}
      # We expect an error due to invalid API key, but that proves the function signature works
      result = OpenAI.chat(messages, options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "stream_chat/2 signature" do
      messages = [%{role: "user", content: "Hello"}]
      options = [model: "gpt-4"]

      result = OpenAI.stream_chat(messages, options)
      # Stream.resource/3 returns a function, not a %Stream{} struct
      assert match?({:ok, stream} when is_function(stream), result) or match?({:error, _}, result)
    end

    test "embeddings/2 signature" do
      inputs = ["some text"]
      options = [model: "text-embedding-ada-002"]

      result = OpenAI.embeddings(inputs, options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "list_models/1 signature" do
      result = OpenAI.list_models()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "moderate_content/2 signature" do
      input = "some content"

      result = OpenAI.moderate_content(input)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "generate_image/2 signature" do
      prompt = "a cat"

      result = OpenAI.generate_image(prompt)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "create_assistant/2 signature" do
      params = %{model: "gpt-4"}

      result = OpenAI.create_assistant(params)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "create_thread/1 signature" do
      result = OpenAI.create_thread()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "create_message/3 signature" do
      thread_id = "thread_123"
      params = %{role: "user", content: "hello"}

      result = OpenAI.create_message(thread_id, params)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "create_run/3 signature" do
      thread_id = "thread_123"
      params = %{assistant_id: "asst_123"}

      result = OpenAI.create_run(thread_id, params)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "text_to_speech/2 signature" do
      text = "hello world"

      result = OpenAI.text_to_speech(text)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "transcribe_audio/2 signature" do
      with_dummy_file(fn file_path ->
        result = OpenAI.transcribe_audio(file_path)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "create_vector_store/2 signature" do
      params = %{name: "My Store"}

      result = OpenAI.create_vector_store(params)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "configured?/1 signature" do
      System.put_env("OPENAI_API_KEY", "test-key")
      assert OpenAI.configured?()
      assert OpenAI.configured?([])

      System.put_env("OPENAI_API_KEY", "")
      refute OpenAI.configured?()

      System.delete_env("OPENAI_API_KEY")
      refute OpenAI.configured?()
    end

    test "default_model/0 signature" do
      assert is_binary(OpenAI.default_model())
    end
  end
end
