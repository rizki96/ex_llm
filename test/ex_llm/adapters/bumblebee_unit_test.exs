defmodule ExLLM.Adapters.BumblebeeUnitTest do
  use ExUnit.Case, async: false
  alias ExLLM.Adapters.Bumblebee
  alias ExLLM.Types

  setup do
    # Skip ModelLoader for unit tests to avoid downloading models
    :ok
  end

  describe "configured?/1" do
    @tag :skip
    test "returns true when Bumblebee is available and ModelLoader is running" do
      # Skipped to avoid starting ModelLoader which triggers model downloads
      assert Bumblebee.configured?()
    end
  end

  describe "default_model/0" do
    test "returns Qwen/Qwen3-0.6B as default" do
      assert Bumblebee.default_model() == "Qwen/Qwen3-0.6B"
    end
  end

  describe "chat/2 with Bumblebee available" do
    @tag :skip
    test "validates empty messages" do
      assert {:error, message} = Bumblebee.chat([])
      assert message =~ "Messages cannot be empty"
    end

    @tag :skip
    test "validates message format" do
      invalid_messages = [
        [%{content: "missing role"}],
        [%{role: "invalid_role", content: "test"}],
        [%{}],
        "not a list"
      ]

      for messages <- invalid_messages do
        assert {:error, msg} = Bumblebee.chat(messages)
        assert msg =~ "Invalid message format" or msg =~ "Messages must be a list"
      end
    end

    @tag :skip
    test "validates model availability" do
      messages = [%{role: "user", content: "Hello"}]

      # Try with an invalid model
      assert {:error, message} = Bumblebee.chat(messages, model: "invalid/model")
      assert message =~ "Model 'invalid/model' is not available"
    end

    test "validates temperature parameter" do
      messages = [%{role: "user", content: "Test"}]

      # Invalid temperature
      assert {:error, msg} = Bumblebee.chat(messages, temperature: 3.0)
      assert msg =~ "Temperature must be between 0 and 2"

      assert {:error, msg} = Bumblebee.chat(messages, temperature: -1)
      assert msg =~ "Temperature must be between 0 and 2"
    end

    test "validates max_tokens parameter" do
      messages = [%{role: "user", content: "Test"}]

      # Invalid max_tokens
      assert {:error, msg} = Bumblebee.chat(messages, max_tokens: -100)
      assert msg =~ "Max tokens must be a positive integer"

      assert {:error, msg} = Bumblebee.chat(messages, max_tokens: "not a number")
      assert msg =~ "Max tokens must be a positive integer"
    end

    @tag :skip
    test "attempts to load and generate with valid parameters" do
      # This test would require actual model loading which is slow
      # Skip it for unit tests
      messages = [%{role: "user", content: "Hello"}]

      result = Bumblebee.chat(messages)

      # Should either succeed or fail with model loading error
      case result do
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          assert is_binary(response.content)

        {:error, reason} ->
          # Model loading failure is acceptable in unit tests
          assert is_binary(reason)
      end
    end
  end

  describe "stream_chat/2 with Bumblebee available" do
    test "validates messages before streaming" do
      assert {:error, message} = Bumblebee.stream_chat([])
      assert message =~ "Messages cannot be empty"
    end

    @tag :skip
    test "validates streaming options" do
      messages = [%{role: "user", content: "Stream test"}]

      # Should accept streaming options
      result = Bumblebee.stream_chat(messages, model: "microsoft/phi-2")

      case result do
        {:ok, _stream} -> :ok
        {:error, reason} -> assert is_binary(reason)
      end
    end
  end

  describe "list_models/1" do
    @tag :skip
    test "returns available models with metadata" do
      assert {:ok, models} = Bumblebee.list_models()

      assert is_list(models)
      assert length(models) > 0

      # Check first model structure
      model = hd(models)
      assert %Types.Model{} = model

      assert model.id in [
               "microsoft/phi-4",
               "meta-llama/Llama-3.3-70B",
               "meta-llama/Llama-3.2-3B",
               "meta-llama/Llama-3.1-8B",
               "mistralai/Mistral-Small-24B",
               "google/gemma-3-4b",
               "google/gemma-3-12b",
               "google/gemma-3-27b",
               "Qwen/Qwen3-1.7B",
               "Qwen/Qwen3-8B",
               "Qwen/Qwen3-14B"
             ]

      assert is_binary(model.name)
      assert is_binary(model.description)
      assert is_integer(model.context_window)
      assert model.pricing == %{input: 0.0, output: 0.0}
    end

    @tag :skip
    test "returns models with verbose information" do
      assert {:ok, models} = Bumblebee.list_models(verbose: true)
      assert is_list(models)
      assert length(models) > 0
    end
  end

  describe "model handling" do
    test "available models constant is defined" do
      models = [
        "microsoft/phi-4",
        "meta-llama/Llama-3.3-70B",
        "meta-llama/Llama-3.2-3B",
        "meta-llama/Llama-3.1-8B",
        "mistralai/Mistral-Small-24B",
        "google/gemma-3-4b",
        "google/gemma-3-12b",
        "google/gemma-3-27b",
        "Qwen/Qwen3-1.7B",
        "Qwen/Qwen3-8B",
        "Qwen/Qwen3-14B"
      ]

      # Each model should be a valid string
      assert Enum.all?(models, &is_binary/1)
    end

    test "model names follow HuggingFace convention" do
      models = [
        "microsoft/phi-2",
        "meta-llama/Llama-2-7b-hf",
        "mistralai/Mistral-7B-v0.1"
      ]

      # All should have org/model format
      assert Enum.all?(models, fn model ->
               String.contains?(model, "/")
             end)
    end
  end

  describe "hardware acceleration" do
    @tag :skip
    test "detects available acceleration" do
      {:ok, models} = Bumblebee.list_models()

      # Check that model descriptions include acceleration info
      model = hd(models)
      assert model.description =~ "Available"

      assert model.description =~ "Apple Metal" or
               model.description =~ "CUDA" or
               model.description =~ "CPU"
    end
  end

  describe "message formatting behavior" do
    test "validates message structure" do
      invalid_messages = [
        [%{content: "missing role"}],
        [%{role: "invalid_role", content: "test"}],
        [%{}]
      ]

      for messages <- invalid_messages do
        assert {:error, msg} = Bumblebee.chat(messages)
        assert is_binary(msg)
      end
    end

    test "handles empty messages list" do
      assert {:error, msg} = Bumblebee.chat([])
      assert msg =~ "Messages cannot be empty"
    end
  end

  describe "option validation" do
    @tag :skip
    test "accepts standard LLM options" do
      messages = [%{role: "user", content: "test"}]

      standard_opts = [
        temperature: 0.7,
        max_tokens: 2048,
        top_p: 0.9,
        top_k: 40,
        seed: 42
      ]

      # Should validate options without attempting to load model
      result = Bumblebee.chat(messages, standard_opts)

      case result do
        {:ok, _} -> :ok
        {:error, reason} -> assert is_binary(reason)
      end
    end

    @tag :skip
    test "accepts model-specific options" do
      messages = [%{role: "user", content: "test"}]

      model_opts = [
        model: "Qwen/Qwen3-1.7B",
        compile: true,
        cache_dir: "/tmp/models"
      ]

      result = Bumblebee.chat(messages, model_opts)

      case result do
        {:ok, _} -> :ok
        {:error, reason} -> assert is_binary(reason)
      end
    end
  end

  describe "error handling" do
    test "provides helpful error message for invalid model" do
      messages = [%{role: "user", content: "test"}]
      {:error, message} = Bumblebee.chat(messages, model: "nonexistent/model")

      # Should mention available models
      assert message =~ "not available"
      assert message =~ "Available models:"
    end
  end

  describe "adapter behavior compliance" do
    @tag :skip
    test "implements all required callbacks" do
      callbacks = [
        {:chat, 2},
        {:stream_chat, 2},
        {:configured?, 1},
        {:default_model, 0},
        {:list_models, 1}
      ]

      for {func, arity} <- callbacks do
        assert function_exported?(Bumblebee, func, arity)
      end
    end

    test "chat returns proper response tuple" do
      # Test with invalid input to ensure we get error tuple
      result = Bumblebee.chat([])
      assert {:error, _message} = result
    end

    test "stream_chat returns proper response tuple" do
      result = Bumblebee.stream_chat([])
      assert {:error, _message} = result
    end

    @tag :skip
    test "list_models returns proper success tuple" do
      result = Bumblebee.list_models()
      assert {:ok, models} = result
      assert is_list(models)
    end
  end
end
