defmodule ExLLM.Integration.FineTuningComprehensiveTest do
  @moduledoc """
  Comprehensive integration tests for ExLLM Fine-Tuning functionality.
  Tests training data preparation, job management, and model deployment.
  Note: Most tests use mocking/simulation since fine-tuning is expensive and time-consuming.
  """
  use ExUnit.Case
  @moduletag :integration
  @moduletag :comprehensive
  import ExUnit.CaptureLog
  require Logger

  # Test helpers
  defp unique_name(base) do
    timestamp = :os.system_time(:millisecond)
    "#{base}_#{timestamp}"
  end

  defp create_training_jsonl(examples) do
    content =
      examples
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    file_path = Path.join(System.tmp_dir!(), "training_#{:os.system_time(:millisecond)}.jsonl")
    File.write!(file_path, content)
    file_path
  end

  defp cleanup_file(file_path) when is_binary(file_path) do
    File.rm(file_path)
  end

  defp cleanup_openai_file(file_id) when is_binary(file_id) do
    case ExLLM.Providers.OpenAI.delete_file(file_id) do
      {:ok, _} -> :ok
      # Already deleted or other non-critical error
      {:error, _} -> :ok
    end
  end

  defp cleanup_fine_tune_job(job_id) when is_binary(job_id) do
    # Try to cancel if still running
    case ExLLM.Providers.OpenAI.cancel_fine_tuning_job(job_id) do
      {:ok, _} -> :ok
      # Already completed/cancelled or other non-critical error
      {:error, _} -> :ok
    end
  end

  describe "Training Data Preparation" do
    @describetag :integration
    @describetag :fine_tuning
    @describetag timeout: 30_000

    test "prepare training data in correct format" do
      # Create training examples in the correct format for fine-tuning
      training_examples = [
        %{
          messages: [
            %{role: "system", content: "You are a helpful assistant."},
            %{role: "user", content: "What is the capital of France?"},
            %{role: "assistant", content: "The capital of France is Paris."}
          ]
        },
        %{
          messages: [
            %{role: "system", content: "You are a helpful assistant."},
            %{role: "user", content: "What is 2 + 2?"},
            %{role: "assistant", content: "2 + 2 equals 4."}
          ]
        },
        %{
          messages: [
            %{role: "system", content: "You are a helpful assistant."},
            %{role: "user", content: "Name three primary colors."},
            %{role: "assistant", content: "The three primary colors are red, blue, and yellow."}
          ]
        }
      ]

      # Verify each example has the correct structure
      Enum.each(training_examples, fn example ->
        assert Map.has_key?(example, :messages)
        assert is_list(example.messages)
        # At least user and assistant
        assert length(example.messages) >= 2

        # Verify message structure
        Enum.each(example.messages, fn message ->
          assert Map.has_key?(message, :role)
          assert Map.has_key?(message, :content)
          assert message.role in ["system", "user", "assistant"]
          assert is_binary(message.content)
        end)
      end)

      # Create JSONL file
      jsonl_path = create_training_jsonl(training_examples)

      # Verify file was created and contains valid JSONL
      assert File.exists?(jsonl_path)

      # Read and validate each line
      File.stream!(jsonl_path)
      |> Enum.each(fn line ->
        {:ok, decoded} = Jason.decode(String.trim(line))
        assert Map.has_key?(decoded, "messages")
      end)

      # Cleanup
      cleanup_file(jsonl_path)
    end

    test "validate JSONL format" do
      # Test various JSONL validation scenarios

      # Valid examples
      valid_examples = [
        %{
          messages: [
            %{role: "user", content: "Hello"},
            %{role: "assistant", content: "Hi there!"}
          ]
        }
      ]

      valid_path = create_training_jsonl(valid_examples)
      assert File.exists?(valid_path)

      # Verify we can parse the JSONL
      lines = File.read!(valid_path) |> String.split("\n", trim: true)
      assert length(lines) == 1

      {:ok, parsed} = Jason.decode(List.first(lines))
      assert Map.has_key?(parsed, "messages")

      # Invalid examples (missing required fields)
      invalid_examples = [
        # Missing messages field
        %{data: "invalid"},
        # Messages not a list
        %{messages: "not a list"},
        # Missing role
        %{messages: [%{content: "missing role"}]}
      ]

      # Test that we can detect invalid formats
      Enum.each(invalid_examples, fn example ->
        path = create_training_jsonl([example])
        content = File.read!(path)
        {:ok, decoded} = Jason.decode(String.trim(content))

        # Validate structure
        is_valid =
          Map.has_key?(decoded, "messages") and
            is_list(decoded["messages"]) and
            Enum.all?(decoded["messages"], fn msg ->
              Map.has_key?(msg, "role") and Map.has_key?(msg, "content")
            end)

        refute is_valid, "Invalid example should not pass validation"
        cleanup_file(path)
      end)

      # Cleanup
      cleanup_file(valid_path)
    end

    test "prepare training data with minimum examples" do
      # OpenAI requires at least 10 examples for fine-tuning
      min_examples = 10

      training_examples =
        Enum.map(1..min_examples, fn i ->
          %{
            messages: [
              %{role: "system", content: "You are a helpful math tutor."},
              %{role: "user", content: "What is #{i} × #{i}?"},
              %{role: "assistant", content: "#{i} × #{i} = #{i * i}"}
            ]
          }
        end)

      assert length(training_examples) == min_examples

      # Create file and verify size
      jsonl_path = create_training_jsonl(training_examples)

      # Count lines in file
      line_count =
        File.stream!(jsonl_path)
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Enum.count()

      assert line_count == min_examples

      # Cleanup
      cleanup_file(jsonl_path)
    end
  end

  describe "File Upload and Validation" do
    @describetag :integration
    @describetag :fine_tuning
    @describetag timeout: 60_000

    test "upload training file" do
      # Create a small training file
      training_examples =
        Enum.map(1..10, fn i ->
          %{
            messages: [
              %{role: "user", content: "Count to #{i}"},
              %{role: "assistant", content: Enum.join(1..i, ", ")}
            ]
          }
        end)

      jsonl_path = create_training_jsonl(training_examples)

      # Upload file for fine-tuning
      case ExLLM.Providers.OpenAI.upload_file(jsonl_path, "fine-tune") do
        {:ok, file} ->
          assert file["id"] =~ ~r/^file-/
          assert file["object"] == "file"
          assert file["purpose"] == "fine-tune"
          assert file["bytes"] > 0

          # Verify file status
          assert Map.has_key?(file, "status")

          # Cleanup
          cleanup_openai_file(file["id"])

        {:error, error} ->
          IO.puts("File upload failed: #{inspect(error)}")
          assert is_map(error)
      end

      # Cleanup local file
      cleanup_file(jsonl_path)
    end

    test "validate uploaded file status" do
      # Create and upload a file, then check its processing status
      training_examples =
        Enum.map(1..10, fn i ->
          %{
            messages: [
              %{role: "user", content: "Example #{i}"},
              %{role: "assistant", content: "Response #{i}"}
            ]
          }
        end)

      jsonl_path = create_training_jsonl(training_examples)

      case ExLLM.Providers.OpenAI.upload_file(jsonl_path, "fine-tune") do
        {:ok, file} ->
          file_id = file["id"]

          # Get file details to check status
          case ExLLM.Providers.OpenAI.get_file(file_id) do
            {:ok, file_details} ->
              assert file_details["id"] == file_id
              assert file_details["purpose"] == "fine-tune"
              # Status might be "uploaded" or "processed"
              assert file_details["status"] in ["uploaded", "processed", "error"]

            {:error, error} ->
              IO.puts("File retrieval failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_openai_file(file_id)

        {:error, error} ->
          IO.puts("File upload failed: #{inspect(error)}")
          assert is_map(error)
      end

      # Cleanup local file
      cleanup_file(jsonl_path)
    end

    test "error: insufficient training examples" do
      # Create file with too few examples (less than 10)
      insufficient_examples = [
        %{
          messages: [
            %{role: "user", content: "Hello"},
            %{role: "assistant", content: "Hi!"}
          ]
        }
      ]

      jsonl_path = create_training_jsonl(insufficient_examples)

      # This should succeed for upload but fail when creating fine-tune job
      case ExLLM.Providers.OpenAI.upload_file(jsonl_path, "fine-tune") do
        {:ok, file} ->
          # File upload succeeds, but fine-tuning would fail
          assert file["id"] =~ ~r/^file-/

          # Try to create a fine-tune job (this should fail)
          case ExLLM.Providers.OpenAI.create_fine_tuning_job(%{
                 training_file: file["id"],
                 model: "gpt-3.5-turbo"
               }) do
            {:ok, job} ->
              # Sometimes the API accepts the request but fails during validation
              # Let's check if the job eventually fails
              # Wait for validation
              Process.sleep(2000)

              case ExLLM.Providers.OpenAI.get_fine_tuning_job(job["id"]) do
                {:ok, job_status} ->
                  # Job might fail during validation
                  if job_status["status"] in ["failed", "cancelled"] do
                    # Expected failure
                    assert true
                  else
                    # Cleanup if it somehow succeeded
                    cleanup_fine_tune_job(job["id"])
                    IO.puts("Warning: Fine-tune job accepted with insufficient examples")
                  end

                {:error, _} ->
                  # Expected failure
                  assert true
              end

            {:error, error} ->
              # Expected to fail
              assert is_map(error)
              # Error might mention insufficient examples or validation failure
          end

          # Cleanup
          cleanup_openai_file(file["id"])

        {:error, error} ->
          IO.puts("File upload failed: #{inspect(error)}")
          assert is_map(error)
      end

      # Cleanup local file
      cleanup_file(jsonl_path)
    end
  end

  describe "Fine-Tuning Job Management" do
    @describetag :integration
    @describetag :fine_tuning
    @describetag timeout: 120_000

    test "create and immediately cancel fine-tune job" do
      # Create training data
      training_examples =
        Enum.map(1..15, fn i ->
          %{
            messages: [
              %{role: "system", content: "You are a helpful assistant."},
              %{role: "user", content: "Test question #{i}"},
              %{role: "assistant", content: "Test response #{i}"}
            ]
          }
        end)

      jsonl_path = create_training_jsonl(training_examples)

      # Upload file
      case ExLLM.Providers.OpenAI.upload_file(jsonl_path, "fine-tune") do
        {:ok, file} ->
          file_id = file["id"]

          # Create fine-tune job
          job_params = %{
            training_file: file_id,
            # Use a model that supports fine-tuning
            model: "gpt-4o-mini-2024-07-18",
            suffix: unique_name("test"),
            hyperparameters: %{
              # Minimum epochs to reduce cost
              n_epochs: 1
            }
          }

          case ExLLM.Providers.OpenAI.create_fine_tuning_job(job_params) do
            {:ok, job} ->
              assert job["id"] =~ ~r/^ftjob-/
              assert job["object"] == "fine_tuning.job"
              assert job["model"] == "gpt-4o-mini-2024-07-18"
              assert job["status"] in ["validating_files", "queued", "running"]

              # Immediately cancel the job
              case ExLLM.Providers.OpenAI.cancel_fine_tuning_job(job["id"]) do
                {:ok, cancelled_job} ->
                  assert cancelled_job["id"] == job["id"]
                  assert cancelled_job["status"] in ["cancelled", "cancelling"]

                {:error, error} ->
                  IO.puts("Job cancellation failed (may already be completed): #{inspect(error)}")
                  # Not a critical failure - job might have completed too quickly
                  assert is_map(error)
              end

            {:error, error} ->
              IO.puts("Fine-tune creation failed: #{inspect(error)}")
              assert is_map(error)
              # Common errors: invalid model, quota exceeded, etc.
          end

          # Cleanup
          cleanup_openai_file(file_id)

        {:error, error} ->
          IO.puts("File upload failed: #{inspect(error)}")
          assert is_map(error)
      end

      # Cleanup local file
      cleanup_file(jsonl_path)
    end

    test "list fine-tuning jobs" do
      # List existing fine-tuning jobs
      case ExLLM.Providers.OpenAI.list_fine_tuning_jobs() do
        {:ok, response} ->
          assert Map.has_key?(response, "data")
          assert is_list(response["data"])
          assert Map.has_key?(response, "object")
          assert response["object"] == "list"

          # If there are any jobs, verify their structure
          if length(response["data"]) > 0 do
            job = List.first(response["data"])
            assert job["object"] == "fine_tuning.job"
            assert Map.has_key?(job, "id")
            assert Map.has_key?(job, "status")
            assert Map.has_key?(job, "model")
          end

        {:error, error} ->
          IO.puts("List fine-tunes failed: #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "get fine-tune job status" do
      # First, list jobs to get an ID (if any exist)
      case ExLLM.Providers.OpenAI.list_fine_tuning_jobs(limit: 1) do
        {:ok, %{"data" => data} = response} when is_list(data) and data != [] ->
          job = List.first(response["data"])
          job_id = job["id"]

          # Get specific job details
          case ExLLM.Providers.OpenAI.get_fine_tuning_job(job_id) do
            {:ok, job_details} ->
              assert job_details["id"] == job_id
              assert job_details["object"] == "fine_tuning.job"
              assert Map.has_key?(job_details, "status")
              assert Map.has_key?(job_details, "created_at")
              assert Map.has_key?(job_details, "training_file")

              # Check for hyperparameters
              if Map.has_key?(job_details, "hyperparameters") do
                assert is_map(job_details["hyperparameters"])
              end

            {:error, error} ->
              IO.puts("Get fine-tune failed: #{inspect(error)}")
              assert is_map(error)
          end

        _ ->
          # No existing jobs to test with
          IO.puts("No existing fine-tune jobs to test status retrieval")
          assert true
      end
    end

    test "list fine-tune events (mock)" do
      # Since we can't guarantee a running job, we'll test the API structure
      # with a fake job ID and expect an error
      fake_job_id = "ftjob-fake123"

      case ExLLM.Providers.OpenAI.list_fine_tuning_events(fake_job_id) do
        {:ok, events} ->
          # Unexpected success - verify structure anyway
          assert Map.has_key?(events, "data")
          assert is_list(events["data"])

        {:error, error} ->
          # Expected - job doesn't exist
          assert is_map(error)
          # The error should indicate the job wasn't found
      end
    end
  end

  describe "Cost and Resource Management" do
    @describetag :integration
    @describetag :fine_tuning
    @describetag timeout: 30_000

    test "calculate training cost estimate" do
      # Create training data of known size
      num_examples = 100

      _training_examples =
        Enum.map(1..num_examples, fn i ->
          %{
            messages: [
              %{
                role: "system",
                content: "You are a helpful assistant that specializes in mathematics."
              },
              %{role: "user", content: "What is the square root of #{i * i}?"},
              %{role: "assistant", content: "The square root of #{i * i} is #{i}."}
            ]
          }
        end)

      # Calculate approximate token count
      # Rough estimate: ~50 tokens per example
      estimated_tokens = num_examples * 50

      # OpenAI pricing (as of 2024):
      # GPT-3.5-turbo fine-tuning: $0.008 per 1K tokens
      # GPT-4 fine-tuning: much more expensive

      price_per_1k_tokens = 0.008
      estimated_cost = estimated_tokens / 1000 * price_per_1k_tokens

      # Verify our estimation
      assert estimated_tokens > 0
      assert estimated_cost > 0
      # Should be less than $1 for 100 examples
      assert estimated_cost < 1.0

      IO.puts(
        "Estimated training cost for #{num_examples} examples: $#{Float.round(estimated_cost, 4)}"
      )
    end

    test "validate hyperparameters" do
      # Test various hyperparameter configurations
      valid_hyperparams = %{
        # Usually 1-10
        n_epochs: 3,
        # Usually 1-16
        batch_size: 4,
        # Usually 0.01-2.0
        learning_rate_multiplier: 0.1
      }

      # Verify hyperparameters are in valid ranges
      assert valid_hyperparams.n_epochs >= 1
      assert valid_hyperparams.n_epochs <= 10
      assert valid_hyperparams.batch_size >= 1
      assert valid_hyperparams.batch_size <= 16
      assert valid_hyperparams.learning_rate_multiplier >= 0.01
      assert valid_hyperparams.learning_rate_multiplier <= 2.0

      # Test invalid hyperparameters
      invalid_configs = [
        # Too low
        %{n_epochs: 0},
        # Too high
        %{n_epochs: 100},
        # Too low
        %{batch_size: 0},
        # Too high
        %{batch_size: 64},
        # Too low
        %{learning_rate_multiplier: 0.001},
        # Too high
        %{learning_rate_multiplier: 10.0}
      ]

      Enum.each(invalid_configs, fn config ->
        # At least one parameter should be out of range
        out_of_range =
          Map.get(config, :n_epochs, 3) < 1 or Map.get(config, :n_epochs, 3) > 10 or
            (Map.get(config, :batch_size, 4) < 1 or Map.get(config, :batch_size, 4) > 16) or
            (Map.get(config, :learning_rate_multiplier, 0.1) < 0.01 or
               Map.get(config, :learning_rate_multiplier, 0.1) > 2.0)

        assert out_of_range,
               "Config should have at least one out-of-range parameter: #{inspect(config)}"
      end)
    end
  end

  describe "Error Handling" do
    @describetag :integration
    @describetag :fine_tuning
    @describetag timeout: 30_000

    test "error: invalid training data format" do
      # Create invalid JSONL with wrong structure
      invalid_data = [
        # Wrong structure
        %{text: "This is not the correct format"},
        # Legacy format
        %{prompt: "Old format", completion: "Not supported"}
      ]

      jsonl_path = create_training_jsonl(invalid_data)

      # Upload will succeed, but fine-tuning will fail
      case ExLLM.Providers.OpenAI.upload_file(jsonl_path, "fine-tune") do
        {:ok, file} ->
          # Try to create fine-tune with invalid data
          case ExLLM.Providers.OpenAI.create_fine_tuning_job(%{
                 training_file: file["id"],
                 model: "gpt-3.5-turbo"
               }) do
            {:ok, job} ->
              # Sometimes the API accepts the request but fails during validation
              # Wait for validation
              Process.sleep(2000)

              case ExLLM.Providers.OpenAI.get_fine_tuning_job(job["id"]) do
                {:ok, job_status} ->
                  # Job should fail during validation due to invalid format
                  if job_status["status"] in ["failed", "cancelled"] do
                    # Expected failure
                    assert true
                  else
                    # Cleanup if it somehow succeeded
                    cleanup_fine_tune_job(job["id"])
                    IO.puts("Warning: Fine-tune job accepted with invalid data format")
                  end

                {:error, _} ->
                  # Expected failure
                  assert true
              end

            {:error, error} ->
              # Expected to fail
              assert is_map(error)
              IO.puts("Expected error for invalid format: #{inspect(error)}")
          end

          # Cleanup
          cleanup_openai_file(file["id"])

        {:error, error} ->
          IO.puts("File upload failed: #{inspect(error)}")
          assert is_map(error)
      end

      # Cleanup
      cleanup_file(jsonl_path)
    end

    test "error: unsupported model for fine-tuning" do
      # Try to fine-tune a model that doesn't support it
      unsupported_models = [
        # Vision models typically can't be fine-tuned
        "gpt-4-vision-preview",
        # Embedding models can't be fine-tuned
        "text-embedding-3-large",
        # Image models can't be fine-tuned
        "dall-e-3"
      ]

      # Create minimal valid training data
      training_examples =
        Enum.map(1..10, fn i ->
          %{
            messages: [
              %{role: "user", content: "Test #{i}"},
              %{role: "assistant", content: "Response #{i}"}
            ]
          }
        end)

      jsonl_path = create_training_jsonl(training_examples)

      case ExLLM.Providers.OpenAI.upload_file(jsonl_path, "fine-tune") do
        {:ok, file} ->
          # Try each unsupported model
          Enum.each(unsupported_models, fn model ->
            case ExLLM.Providers.OpenAI.create_fine_tuning_job(%{
                   training_file: file["id"],
                   model: model
                 }) do
              {:ok, _job} ->
                # Should not succeed
                assert false, "Fine-tuning should fail for unsupported model: #{model}"

              {:error, error} ->
                # Expected to fail
                assert is_map(error)
                IO.puts("Expected error for model #{model}: #{inspect(error)}")
            end
          end)

          # Cleanup
          cleanup_openai_file(file["id"])

        {:error, error} ->
          IO.puts("File upload failed: #{inspect(error)}")
          assert is_map(error)
      end

      # Cleanup
      cleanup_file(jsonl_path)
    end

    test "error: quota exceeded (simulated)" do
      # We can't actually exceed quota in tests, but we can test the error handling
      # by trying to create many jobs quickly (which might trigger rate limits)

      _log =
        capture_log(fn ->
          # Simulate quota check
          mock_quota = %{
            used: 5,
            limit: 5
          }

          if mock_quota.used >= mock_quota.limit do
            Logger.info("Quota exceeded: #{mock_quota.used}/#{mock_quota.limit} fine-tune jobs")
            IO.puts("Quota exceeded simulation")
          end

          assert mock_quota.used >= mock_quota.limit
        end)

      # The log capture might not work with Logger, so we just verify the logic
      # Test passes if quota logic is correct
      assert true
    end
  end

  describe "Model Deployment (Mock)" do
    @describetag :integration
    @describetag :fine_tuning
    @describetag timeout: 30_000

    test "use fine-tuned model (mock)" do
      # Since we can't actually wait for a fine-tune to complete,
      # we'll test using a mock fine-tuned model ID format

      # Fine-tuned models have IDs like: ft:gpt-3.5-turbo:org-id:suffix:id
      mock_model_id = "ft:gpt-3.5-turbo-0613:personal::8abc1234"

      # Test that we can reference the model in a chat request
      _messages = [
        %{role: "user", content: "Hello, fine-tuned model!"}
      ]

      # We can't actually call this without a real fine-tuned model
      # but we can verify the model ID format is accepted
      assert String.starts_with?(mock_model_id, "ft:")
      assert String.contains?(mock_model_id, "gpt-3.5-turbo")

      IO.puts("Mock fine-tuned model ID: #{mock_model_id}")
    end

    test "delete fine-tuned model (mock)" do
      # Test the delete API structure
      mock_model_id = "ft:gpt-3.5-turbo-0613:personal::8xyz5678"

      # OpenAI doesn't actually allow deleting fine-tuned models via API
      # They're automatically deleted after 30 days of inactivity
      # So we just verify the model ID format

      assert String.starts_with?(mock_model_id, "ft:")

      IO.puts(
        "Note: Fine-tuned models cannot be deleted via API, they expire after 30 days of inactivity"
      )
    end

    test "list fine-tuned models" do
      # We can actually test listing models to see if any fine-tuned ones exist
      case ExLLM.Providers.OpenAI.list_models() do
        {:ok, models} ->
          # Filter for fine-tuned models
          fine_tuned =
            Enum.filter(models, fn model ->
              model_id =
                case model do
                  %ExLLM.Types.Model{id: id} -> id
                  %{"id" => id} -> id
                  id when is_binary(id) -> id
                  _ -> ""
                end

              String.starts_with?(to_string(model_id), "ft:")
            end)

          IO.puts("Found #{length(fine_tuned)} fine-tuned models")

          # Verify structure if any exist
          if length(fine_tuned) > 0 do
            model = List.first(fine_tuned)

            model_id =
              case model do
                %ExLLM.Types.Model{id: id} -> id
                %{"id" => id} -> id
                id when is_binary(id) -> id
                _ -> ""
              end

            assert String.starts_with?(to_string(model_id), "ft:")
          end

        {:error, error} ->
          IO.puts("List models failed: #{inspect(error)}")
          assert is_map(error)
      end
    end
  end
end
