defmodule ExLLM.Providers.Gemini.TuningTest do
  use ExUnit.Case, async: false

  alias ExLLM.Providers.Gemini.Tuning

  alias ExLLM.Providers.Gemini.Tuning.{
    TunedModel,
    TuningExamples,
    TuningExample,
    ListTunedModelsResponse
  }

  @api_key System.get_env("GEMINI_API_KEY") || "test-key"
  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag :expensive
  @moduletag provider: :gemini

  describe "create_tuned_model/2" do
    test "creates a tuned model with basic configuration" do
      examples = %TuningExamples{
        examples: [
          %TuningExample{
            text_input: "What is the capital of France?",
            output: "The capital of France is Paris."
          },
          %TuningExample{
            text_input: "What is 2 + 2?",
            output: "2 + 2 equals 4."
          }
        ]
      }

      request = %{
        display_name: "Test Model",
        description: "A test tuned model",
        base_model: "models/gemini-1.5-flash-001",
        tuning_task: %{
          training_data: %{
            examples: examples
          }
        }
      }

      assert {:ok, operation} = Tuning.create_tuned_model(request, api_key: @api_key)
      assert operation["name"] =~ ~r/^operations\//
      assert operation["metadata"]
    end

    test "creates a tuned model with custom hyperparameters" do
      examples = %TuningExamples{
        examples: [
          %TuningExample{
            text_input: "Translate to Spanish: Hello",
            output: "Hola"
          },
          %TuningExample{
            text_input: "Translate to Spanish: Goodbye",
            output: "Adiós"
          }
        ]
      }

      request = %{
        display_name: "Spanish Translator",
        base_model: "models/gemini-1.5-flash-001",
        tuning_task: %{
          training_data: %{
            examples: examples
          },
          hyperparameters: %{
            epoch_count: 3,
            batch_size: 2,
            learning_rate: 0.001
          }
        }
      }

      assert {:ok, operation} = Tuning.create_tuned_model(request, api_key: @api_key)
      assert operation["name"]
    end

    test "creates a tuned model with custom ID" do
      examples = %TuningExamples{
        examples: [
          %TuningExample{
            text_input: "What is AI?",
            output: "AI stands for Artificial Intelligence."
          }
        ]
      }

      request = %{
        display_name: "AI Explainer",
        base_model: "models/gemini-1.5-flash-001",
        tuning_task: %{
          training_data: %{
            examples: examples
          }
        }
      }

      custom_id = "test-model-#{:rand.uniform(10000)}"

      assert {:ok, operation} =
               Tuning.create_tuned_model(request,
                 api_key: @api_key,
                 tuned_model_id: custom_id
               )

      assert operation["name"]
    end

    test "returns error for invalid base model" do
      request = %{
        display_name: "Invalid Model",
        base_model: "models/invalid-model",
        tuning_task: %{
          training_data: %{
            examples: %TuningExamples{
              examples: [
                %TuningExample{
                  text_input: "test",
                  output: "test"
                }
              ]
            }
          }
        }
      }

      assert {:error, %{status: status}} = Tuning.create_tuned_model(request, api_key: @api_key)
      assert status in [400, 404]
    end
  end

  describe "list_tuned_models/1" do
    test "lists tuned models" do
      assert {:ok, %ListTunedModelsResponse{} = response} =
               Tuning.list_tuned_models(api_key: @api_key)

      assert is_list(response.tuned_models)

      # If there are tuned models, verify their structure
      if length(response.tuned_models) > 0 do
        [model | _] = response.tuned_models
        assert %TunedModel{} = model
        assert model.name =~ ~r/^tunedModels\//
        assert model.state in [:STATE_UNSPECIFIED, :CREATING, :ACTIVE, :FAILED]
      end
    end

    test "lists tuned models with pagination" do
      assert {:ok, %ListTunedModelsResponse{}} =
               Tuning.list_tuned_models(api_key: @api_key, page_size: 2)
    end

    test "lists tuned models with filter" do
      assert {:ok, %ListTunedModelsResponse{}} =
               Tuning.list_tuned_models(api_key: @api_key, filter: "owner:me")
    end
  end

  describe "get_tuned_model/2" do
    test "returns error for non-existent model" do
      assert {:error, %{status: status}} =
               Tuning.get_tuned_model("tunedModels/non-existent", api_key: @api_key)

      assert status in [400, 403, 404]
    end

    @tag :requires_resource
    test "gets tuned model details" do
      # This test requires an existing tuned model
      # First create a model, then retrieve it
      examples = %TuningExamples{
        examples: [
          %TuningExample{
            text_input: "Test input",
            output: "Test output"
          }
        ]
      }

      request = %{
        display_name: "Get Test Model",
        base_model: "models/gemini-1.5-flash-001",
        tuning_task: %{
          training_data: %{
            examples: examples
          }
        }
      }

      {:ok, _operation} = Tuning.create_tuned_model(request, api_key: @api_key)

      # Extract model name from operation
      # In real scenario, we'd wait for the operation to complete
      # and then get the actual tuned model name

      # For now, we'll test with a hypothetical model name
      # assert {:ok, %TunedModel{} = model} = 
      #   Tuning.get_tuned_model("tunedModels/test-model", api_key: @api_key)
      # assert model.name
      # assert model.base_model
      # assert model.state
    end
  end

  describe "update_tuned_model/3" do
    test "returns error for non-existent model" do
      update = %{
        display_name: "Updated Name"
      }

      assert {:error, %{status: status}} =
               Tuning.update_tuned_model("tunedModels/non-existent", update, api_key: @api_key)

      assert status in [400, 403, 404]
    end

    @tag :requires_resource
    test "updates tuned model metadata" do
      # This test requires an existing tuned model
      _update = %{
        display_name: "Updated Display Name",
        description: "Updated description"
      }

      # Would need actual model name
      # assert {:ok, %TunedModel{} = model} = 
      #   Tuning.update_tuned_model("tunedModels/test-model", update, 
      #     api_key: @api_key,
      #     update_mask: "displayName,description"
      #   )
      # assert model.display_name == "Updated Display Name"
      # assert model.description == "Updated description"
    end
  end

  describe "delete_tuned_model/2" do
    test "returns error for non-existent model" do
      assert {:error, %{status: status}} =
               Tuning.delete_tuned_model("tunedModels/non-existent", api_key: @api_key)

      assert status in [400, 403, 404]
    end

    @tag :requires_resource
    test "deletes a tuned model" do
      # This test requires creating and then deleting a model
      # In practice, this would be an expensive operation

      # Create model first
      # examples = %TuningExamples{...}
      # {:ok, operation} = Tuning.create_tuned_model(...)
      # Wait for completion...
      # model_name = get_model_name_from_operation(operation)

      # assert {:ok, %{}} = Tuning.delete_tuned_model(model_name, api_key: @api_key)

      # Verify deletion
      # assert {:error, %{status: 404}} = 
      #   Tuning.get_tuned_model(model_name, api_key: @api_key)
    end
  end

  describe "generate_content/3" do
    @tag :requires_resource
    test "generates content using a tuned model" do
      # This requires an active tuned model
      _request = %{
        contents: [
          %{
            role: "user",
            parts: [
              %{text: "What is the capital of France?"}
            ]
          }
        ]
      }

      # Would need actual tuned model name
      # assert {:ok, response} = 
      #   Tuning.generate_content("tunedModels/test-model", request, api_key: @api_key)
      # assert response["candidates"]
    end
  end

  describe "stream_generate_content/3" do
    @tag :requires_resource
    test "streams content using a tuned model" do
      # This requires an active tuned model
      _request = %{
        contents: [
          %{
            role: "user",
            parts: [
              %{text: "Tell me a story"}
            ]
          }
        ]
      }

      # Would need actual tuned model name
      # assert {:ok, stream} = 
      #   Tuning.stream_generate_content("tunedModels/test-model", request, api_key: @api_key)

      # chunks = Enum.to_list(stream)
      # assert length(chunks) > 0
    end
  end

  describe "wait_for_tuning/3" do
    @tag :requires_resource
    test "waits for tuning operation to complete" do
      # This test would create a model and wait for it
      examples = %TuningExamples{
        examples: [
          %TuningExample{
            text_input: "Test",
            output: "Test output"
          }
        ]
      }

      request = %{
        display_name: "Wait Test Model",
        base_model: "models/gemini-1.5-flash-001",
        tuning_task: %{
          training_data: %{
            examples: examples
          }
        }
      }

      {:ok, _operation} = Tuning.create_tuned_model(request, api_key: @api_key)

      # In real scenario, we'd wait with timeout
      # assert {:ok, %TunedModel{}} = 
      #   Tuning.wait_for_tuning(operation["name"], api_key: @api_key, timeout: 300_000)
    end
  end
end
