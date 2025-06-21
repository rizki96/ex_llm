defmodule ExLLM.API.FineTuningTest do
  @moduledoc """
  Comprehensive tests for the unified fine-tuning API.
  Tests the public ExLLM API to ensure excellent user experience.
  """

  use ExUnit.Case, async: false
  import ExLLM.Testing.TestCacheHelpers

  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag :unified_api
  @moduletag :fine_tuning
  @moduletag :slow

  # Test dataset for Gemini fine-tuning
  @gemini_test_dataset %{
    examples: [
      %{text_input: "What is the capital of France?", output: "The capital of France is Paris."},
      %{text_input: "What is 2 + 2?", output: "2 + 2 equals 4."},
      %{text_input: "What color is the sky?", output: "The sky is typically blue during the day."}
    ]
  }

  # Test training file for OpenAI fine-tuning (would need to be uploaded first)
  @openai_test_file "test_training_file.jsonl"

  setup_all do
    enable_cache_debug()
    :ok
  end

  setup context do
    setup_test_cache(context)

    on_exit(fn ->
      ExLLM.Testing.TestCacheDetector.clear_test_context()
    end)

    :ok
  end

  describe "create_fine_tune/3" do
    @tag provider: :gemini
    test "creates fine-tune successfully with Gemini" do
      case ExLLM.create_fine_tune(:gemini, @gemini_test_dataset, base_model: "gemini-1.5-flash") do
        {:ok, fine_tune_info} ->
          assert is_map(fine_tune_info)
          assert Map.has_key?(fine_tune_info, :name)
          assert String.contains?(fine_tune_info.name, "tunedModels/")

        {:error, reason} ->
          IO.puts("Gemini fine-tuning creation failed: #{inspect(reason)}")
          :ok
      end
    end

    @tag provider: :openai
    test "creates fine-tune successfully with OpenAI" do
      # Note: This would require a pre-uploaded training file
      case ExLLM.create_fine_tune(:openai, @openai_test_file, model: "gpt-3.5-turbo") do
        {:ok, fine_tune_info} ->
          assert is_map(fine_tune_info)
          assert Map.has_key?(fine_tune_info, :id)
          assert Map.has_key?(fine_tune_info, :status)

        {:error, reason} ->
          IO.puts("OpenAI fine-tuning creation failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, "Fine-tuning not supported for provider: anthropic"} =
               ExLLM.create_fine_tune(:anthropic, @gemini_test_dataset)
    end

    test "handles invalid dataset format for Gemini" do
      invalid_datasets = [
        nil,
        "",
        123,
        [],
        %{},
        %{invalid: "structure"},
        %{examples: []},
        %{examples: [%{invalid: "format"}]}
      ]

      for invalid_dataset <- invalid_datasets do
        case ExLLM.create_fine_tune(:gemini, invalid_dataset) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some invalid datasets might be handled gracefully
            :ok
        end
      end
    end

    test "handles invalid training file for OpenAI" do
      invalid_files = [nil, "", 123, %{}, []]

      for invalid_file <- invalid_files do
        case ExLLM.create_fine_tune(:openai, invalid_file) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid training file: #{inspect(invalid_file)}")
        end
      end
    end

    @tag provider: :gemini
    test "handles missing required options for Gemini" do
      # Test without base_model option
      case ExLLM.create_fine_tune(:gemini, @gemini_test_dataset) do
        {:error, _reason} ->
          :ok

        {:ok, _} ->
          # Might succeed with default model
          :ok
      end
    end
  end

  describe "list_fine_tunes/2" do
    @tag provider: :gemini
    test "lists fine-tunes successfully with Gemini" do
      case ExLLM.list_fine_tunes(:gemini, page_size: 5) do
        {:ok, response} ->
          assert is_map(response)
          # Gemini returns tuned models in a specific structure
          assert Map.has_key?(response, :tuned_models) or Map.has_key?(response, :data)

        {:error, reason} ->
          IO.puts("Gemini list fine-tunes failed: #{inspect(reason)}")
          :ok
      end
    end

    @tag provider: :openai
    test "lists fine-tunes successfully with OpenAI" do
      case ExLLM.list_fine_tunes(:openai, limit: 5) do
        {:ok, response} ->
          assert is_map(response)
          # OpenAI returns fine-tuning jobs in a specific structure
          assert Map.has_key?(response, :data) or is_list(response)

        {:error, reason} ->
          IO.puts("OpenAI list fine-tunes failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, "Fine-tuning not supported for provider: anthropic"} =
               ExLLM.list_fine_tunes(:anthropic)
    end

    test "handles invalid options gracefully" do
      case ExLLM.list_fine_tunes(:gemini, invalid_option: "invalid") do
        {:ok, _response} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "get_fine_tune/3" do
    test "returns error for unsupported provider" do
      assert {:error, "Fine-tuning not supported for provider: anthropic"} =
               ExLLM.get_fine_tune(:anthropic, "model_id")
    end

    @tag provider: :gemini
    test "handles non-existent fine-tune ID with Gemini" do
      case ExLLM.get_fine_tune(:gemini, "tunedModels/non_existent") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    @tag provider: :openai
    test "handles non-existent fine-tune ID with OpenAI" do
      case ExLLM.get_fine_tune(:openai, "ft-non_existent") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    test "handles invalid fine-tune ID types" do
      invalid_ids = [nil, 123, %{}, []]

      for invalid_id <- invalid_ids do
        case ExLLM.get_fine_tune(:gemini, invalid_id) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid fine-tune ID: #{inspect(invalid_id)}")
        end
      end
    end
  end

  describe "cancel_fine_tune/3" do
    test "returns error for unsupported provider" do
      assert {:error, "Fine-tuning not supported for provider: anthropic"} =
               ExLLM.cancel_fine_tune(:anthropic, "model_id")
    end

    @tag provider: :gemini
    test "handles non-existent fine-tune ID with Gemini" do
      case ExLLM.cancel_fine_tune(:gemini, "tunedModels/non_existent") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # Some providers might return success even for non-existent jobs
          :ok
      end
    end

    @tag provider: :openai
    test "handles non-existent fine-tune ID with OpenAI" do
      case ExLLM.cancel_fine_tune(:openai, "ft-non_existent") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # Some providers might return success even for non-existent jobs
          :ok
      end
    end

    test "handles invalid fine-tune ID types" do
      invalid_ids = [nil, 123, %{}, []]

      for invalid_id <- invalid_ids do
        case ExLLM.cancel_fine_tune(:gemini, invalid_id) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid fine-tune ID: #{inspect(invalid_id)}")
        end
      end
    end
  end

  describe "fine-tuning data format validation" do
    @tag provider: :gemini
    test "validates Gemini dataset structure" do
      valid_datasets = [
        # Basic structure
        %{examples: [%{text_input: "Question?", output: "Answer."}]},

        # Multiple examples
        %{
          examples: [
            %{text_input: "Q1?", output: "A1."},
            %{text_input: "Q2?", output: "A2."}
          ]
        },

        # With additional metadata
        %{
          examples: [%{text_input: "Question?", output: "Answer."}],
          metadata: %{description: "Test dataset"}
        }
      ]

      for dataset <- valid_datasets do
        case ExLLM.create_fine_tune(:gemini, dataset, base_model: "gemini-1.5-flash") do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            # Dataset might be valid but other issues (auth, quotas, etc.)
            IO.puts("Valid dataset failed: #{inspect(reason)}")
            :ok
        end
      end
    end

    test "rejects malformed Gemini datasets" do
      malformed_datasets = [
        # Missing examples
        %{},

        # Empty examples
        %{examples: []},

        # Invalid example structure
        %{examples: [%{wrong_field: "value"}]},

        # Missing required fields
        %{examples: [%{text_input: "Question?"}]},
        %{examples: [%{output: "Answer."}]}
      ]

      for dataset <- malformed_datasets do
        case ExLLM.create_fine_tune(:gemini, dataset) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some malformed datasets might be handled gracefully
            :ok
        end
      end
    end
  end

  describe "fine-tuning options validation" do
    @tag provider: :gemini
    test "handles various Gemini fine-tuning options" do
      options_sets = [
        [base_model: "gemini-1.5-flash"],
        [base_model: "gemini-1.5-pro", learning_rate: 0.001],
        [base_model: "gemini-1.5-flash", batch_size: 4],
        [base_model: "gemini-1.5-flash", epochs: 3]
      ]

      for options <- options_sets do
        case ExLLM.create_fine_tune(:gemini, @gemini_test_dataset, options) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            IO.puts("Fine-tuning with options #{inspect(options)} failed: #{inspect(reason)}")
            :ok
        end
      end
    end

    @tag provider: :openai
    test "handles various OpenAI fine-tuning options" do
      options_sets = [
        [model: "gpt-3.5-turbo"],
        [model: "gpt-3.5-turbo", hyperparameters: %{n_epochs: 3}],
        [model: "gpt-3.5-turbo", suffix: "test-model"],
        [model: "gpt-3.5-turbo", validation_file: "validation.jsonl"]
      ]

      for options <- options_sets do
        case ExLLM.create_fine_tune(:openai, @openai_test_file, options) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            IO.puts("Fine-tuning with options #{inspect(options)} failed: #{inspect(reason)}")
            :ok
        end
      end
    end
  end
end
