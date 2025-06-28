defmodule ExLLM.Providers.OpenAIContractTest do
  use ExUnit.Case, async: false

  alias ExLLM.Providers.OpenAI

  @moduletag :integration
  @moduletag :provider_openai

  # This test suite serves as a contract for the public API of the OpenAI provider.
  # It tests that function signatures and basic interactions remain consistent during
  # refactoring. It intentionally uses a dummy API key to ensure that all public
  # functions can be called with their expected arguments and return a correctly
  # formatted result ({:ok, _} or {:error, _}) without relying on complex HTTP mocking.

  setup do
    # Create a static config provider with dummy API key
    # This avoids modifying global environment variables
    config = %{openai: %{api_key: "test-key-dummy"}}
    {:ok, config_provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)

    {:ok, config_provider: config_provider}
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
    test "chat/2 function exists and accepts correct parameters", %{
      config_provider: config_provider
    } do
      messages = [%{role: "user", content: "Hello"}]
      options = [model: "gpt-4", config_provider: config_provider]

      # The function should exist and return either {:ok, _} or {:error, _}
      # We expect an error due to invalid API key, but that proves the function signature works
      result = OpenAI.chat(messages, options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "stream_chat/2 signature", %{config_provider: config_provider} do
      messages = [%{role: "user", content: "Hello"}]
      options = [model: "gpt-4", config_provider: config_provider]

      result = OpenAI.stream_chat(messages, options)
      # Stream.resource/3 returns a function, not a %Stream{} struct
      assert match?({:ok, stream} when is_function(stream), result) or match?({:error, _}, result)
    end

    test "embeddings/2 signature", %{config_provider: config_provider} do
      inputs = ["some text"]
      options = [model: "text-embedding-ada-002", config_provider: config_provider]

      result = OpenAI.embeddings(inputs, options)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "list_models/1 signature", %{config_provider: config_provider} do
      result = OpenAI.list_models(config_provider: config_provider)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "moderate_content/2 signature", %{config_provider: config_provider} do
      input = "some content"

      result = OpenAI.moderate_content(input, config_provider: config_provider)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "generate_image/2 signature", %{config_provider: config_provider} do
      prompt = "a cat"

      result = OpenAI.generate_image(prompt, config_provider: config_provider)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "create_assistant/2 signature", %{config_provider: config_provider} do
      params = %{model: "gpt-4"}

      result = OpenAI.create_assistant(params, config_provider: config_provider)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "create_thread/1 signature", %{config_provider: config_provider} do
      result = OpenAI.create_thread(config_provider: config_provider)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "create_message/3 signature", %{config_provider: config_provider} do
      thread_id = "thread_123"
      params = %{role: "user", content: "hello"}

      result = OpenAI.create_message(thread_id, params, config_provider: config_provider)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "create_run/3 signature", %{config_provider: config_provider} do
      thread_id = "thread_123"
      params = %{assistant_id: "asst_123"}

      result = OpenAI.create_run(thread_id, params, config_provider: config_provider)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "text_to_speech/2 signature", %{config_provider: config_provider} do
      text = "hello world"

      result = OpenAI.text_to_speech(text, config_provider: config_provider)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "transcribe_audio/2 signature", %{config_provider: config_provider} do
      with_dummy_file(fn file_path ->
        result = OpenAI.transcribe_audio(file_path, config_provider: config_provider)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "create_vector_store/2 signature", %{config_provider: config_provider} do
      params = %{name: "My Store"}

      result = OpenAI.create_vector_store(params, config_provider: config_provider)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "configured?/1 signature", %{config_provider: config_provider} do
      # Save current env var value
      original_key = System.get_env("OPENAI_API_KEY")

      try do
        # Test with config provider that has API key
        assert OpenAI.configured?(config_provider: config_provider)

        # Temporarily clear the environment variable
        System.delete_env("OPENAI_API_KEY")

        # Test with empty config provider
        {:ok, empty_config} =
          ExLLM.Infrastructure.ConfigProvider.Static.start_link(%{openai: %{}})

        refute OpenAI.configured?(config_provider: empty_config)

        # Test with config provider that has empty API key
        {:ok, empty_key_config} =
          ExLLM.Infrastructure.ConfigProvider.Static.start_link(%{openai: %{api_key: ""}})

        refute OpenAI.configured?(config_provider: empty_key_config)
      after
        # Restore the environment variable if it existed
        if original_key, do: System.put_env("OPENAI_API_KEY", original_key)
      end
    end

    test "default_model/0 signature" do
      assert is_binary(OpenAI.default_model())
    end
  end
end
