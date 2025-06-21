defmodule ExLLM.API.TransformersTest do
  use ExUnit.Case, async: true

  alias ExLLM.API.Transformers

  describe "transform_upload_args/1" do
    test "transforms keyword list arguments correctly" do
      args = ["/path/to/file.txt", [purpose: "fine-tune", timeout: 30_000]]
      result = Transformers.transform_upload_args(args)

      assert result == ["/path/to/file.txt", "fine-tune", [timeout: 30_000]]
    end

    test "uses default purpose when not specified" do
      args = ["/path/to/file.txt", [timeout: 30_000]]
      result = Transformers.transform_upload_args(args)

      assert result == ["/path/to/file.txt", "user_data", [timeout: 30_000]]
    end

    test "handles empty options" do
      args = ["/path/to/file.txt", []]
      result = Transformers.transform_upload_args(args)

      assert result == ["/path/to/file.txt", "user_data", []]
    end

    test "transforms map arguments correctly" do
      args = ["/path/to/file.txt", %{purpose: "assistants", timeout: 30_000}]
      result = Transformers.transform_upload_args(args)

      assert result == ["/path/to/file.txt", "assistants", %{timeout: 30_000}]
    end

    test "handles fallback for unexpected format" do
      args = ["/path/to/file.txt", "unexpected"]
      result = Transformers.transform_upload_args(args)

      # Should return as-is for unexpected format
      assert result == args
    end
  end

  describe "preprocess_gemini_tuning/1" do
    test "builds basic Gemini tuning request" do
      dataset = [
        %{input: "Hello", output: "Hi there!"},
        %{input: "Goodbye", output: "See you later!"}
      ]

      opts = [base_model: "gemini-1.5-pro", display_name: "Test Model"]

      result = Transformers.preprocess_gemini_tuning([dataset, opts])

      assert [tuning_request, config_opts] = result
      assert tuning_request.base_model == "models/gemini-1.5-pro"
      assert tuning_request.display_name == "Test Model"

      assert tuning_request.tuning_task.training_data.examples.examples == [
               %{text_input: "Hello", output: "Hi there!"},
               %{text_input: "Goodbye", output: "See you later!"}
             ]

      assert config_opts == []
    end

    test "uses default base model when not specified" do
      dataset = [%{input: "Test", output: "Response"}]
      opts = []

      result = Transformers.preprocess_gemini_tuning([dataset, opts])

      assert [tuning_request, _config_opts] = result
      assert tuning_request.base_model == "models/gemini-1.5-flash"
    end

    test "includes hyperparameters when specified" do
      dataset = [%{input: "Test", output: "Response"}]
      opts = [temperature: 0.8, top_p: 0.9, top_k: 40]

      result = Transformers.preprocess_gemini_tuning([dataset, opts])

      assert [tuning_request, _config_opts] = result
      assert tuning_request.tuning_task.hyperparameters.learning_rate == 0.8
      assert tuning_request.tuning_task.hyperparameters.batch_size == 0.9
      assert tuning_request.tuning_task.hyperparameters.epoch_count == 40
    end

    test "filters out tuning-specific options from config" do
      dataset = [%{input: "Test", output: "Response"}]
      opts = [base_model: "gemini-1.5-pro", timeout: 60_000, api_key: "test"]

      result = Transformers.preprocess_gemini_tuning([dataset, opts])

      assert [_tuning_request, config_opts] = result
      assert config_opts == [timeout: 60_000, api_key: "test"]
      refute Keyword.has_key?(config_opts, :base_model)
    end
  end

  describe "preprocess_openai_tuning/1" do
    test "builds basic OpenAI tuning parameters" do
      training_file = "file-abc123"
      opts = [model: "gpt-3.5-turbo", suffix: "test-model"]

      result = Transformers.preprocess_openai_tuning([training_file, opts])

      assert [tuning_params, config_opts] = result
      assert tuning_params.model == "gpt-3.5-turbo"
      assert tuning_params.training_file == "file-abc123"
      assert tuning_params.suffix == "test-model"
      assert config_opts == []
    end

    test "uses default model when not specified" do
      training_file = "file-abc123"
      opts = []

      result = Transformers.preprocess_openai_tuning([training_file, opts])

      assert [tuning_params, _config_opts] = result
      assert tuning_params.model == "gpt-3.5-turbo"
      assert tuning_params.training_file == "file-abc123"
    end

    test "includes optional parameters when specified" do
      training_file = "file-abc123"

      opts = [
        validation_file: "file-def456",
        n_epochs: 3,
        batch_size: 8,
        learning_rate_multiplier: 0.1
      ]

      result = Transformers.preprocess_openai_tuning([training_file, opts])

      assert [tuning_params, _config_opts] = result
      assert tuning_params.validation_file == "file-def456"
      assert tuning_params.n_epochs == 3
      assert tuning_params.batch_size == 8
      assert tuning_params.learning_rate_multiplier == 0.1
    end

    test "excludes auto values from parameters" do
      training_file = "file-abc123"
      opts = [n_epochs: "auto", batch_size: "auto"]

      result = Transformers.preprocess_openai_tuning([training_file, opts])

      assert [tuning_params, _config_opts] = result
      refute Map.has_key?(tuning_params, :n_epochs)
      refute Map.has_key?(tuning_params, :batch_size)
    end

    test "filters out tuning-specific options from config" do
      training_file = "file-abc123"
      opts = [model: "gpt-4", timeout: 60_000, api_key: "test"]

      result = Transformers.preprocess_openai_tuning([training_file, opts])

      assert [_tuning_params, config_opts] = result
      assert config_opts == [timeout: 60_000, api_key: "test"]
      refute Keyword.has_key?(config_opts, :model)
    end
  end

  describe "dataset conversion helpers" do
    test "converts standard input/output format to Gemini format" do
      dataset = [
        %{"input" => "Question 1", "output" => "Answer 1"},
        %{input: "Question 2", output: "Answer 2"}
      ]

      result = Transformers.preprocess_gemini_tuning([dataset, []])
      assert [tuning_request, _] = result

      examples = tuning_request.tuning_task.training_data.examples.examples

      assert examples == [
               %{text_input: "Question 1", output: "Answer 1"},
               %{text_input: "Question 2", output: "Answer 2"}
             ]
    end

    test "handles already formatted Gemini examples" do
      dataset = [
        %{text_input: "Question 1", output: "Answer 1"},
        %{"text_input" => "Question 2", "output" => "Answer 2"}
      ]

      result = Transformers.preprocess_gemini_tuning([dataset, []])
      assert [tuning_request, _] = result

      examples = tuning_request.tuning_task.training_data.examples.examples

      assert examples == [
               %{text_input: "Question 1", output: "Answer 1"},
               %{"text_input" => "Question 2", "output" => "Answer 2"}
             ]
    end

    test "handles single example as map" do
      dataset = %{input: "Single question", output: "Single answer"}

      result = Transformers.preprocess_gemini_tuning([dataset, []])
      assert [tuning_request, _] = result

      examples = tuning_request.tuning_task.training_data.examples.examples
      assert examples == [%{text_input: "Single question", output: "Single answer"}]
    end
  end
end
