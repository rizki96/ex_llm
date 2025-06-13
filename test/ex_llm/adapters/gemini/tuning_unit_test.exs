defmodule ExLLM.Adapters.Gemini.TuningUnitTest do
  use ExUnit.Case

  alias ExLLM.Gemini.Tuning
  alias ExLLM.Gemini.Tuning.{
    TunedModel,
    TuningTask,
    TuningSnapshot,
    Dataset,
    TuningExamples,
    TuningExample,
    Hyperparameters,
    TunedModelSource,
    ListTunedModelsResponse
  }

  describe "structs" do
    test "TunedModel struct" do
      model = %TunedModel{
        name: "tunedModels/test-123",
        display_name: "Test Model",
        description: "A test model",
        state: :ACTIVE,
        create_time: "2025-06-01T10:00:00Z",
        update_time: "2025-06-01T11:00:00Z",
        tuning_task: %TuningTask{},
        base_model: "models/gemini-1.5-flash-001",
        temperature: 0.7,
        top_p: 0.9,
        top_k: 40,
        reader_project_numbers: ["123456"]
      }

      assert model.name == "tunedModels/test-123"
      assert model.state == :ACTIVE
      assert model.temperature == 0.7
    end

    test "TuningTask struct" do
      task = %TuningTask{
        start_time: "2025-06-01T10:00:00Z",
        complete_time: "2025-06-01T11:00:00Z",
        snapshots: [
          %TuningSnapshot{
            step: 1,
            epoch: 1,
            mean_loss: 0.5,
            compute_time: "2025-06-01T10:30:00Z"
          }
        ],
        training_data: %Dataset{
          examples: %TuningExamples{
            examples: []
          }
        },
        hyperparameters: %Hyperparameters{
          learning_rate: 0.001,
          epoch_count: 5,
          batch_size: 4
        }
      }

      assert task.start_time
      assert length(task.snapshots) == 1
      assert task.hyperparameters.epoch_count == 5
    end

    test "TuningExample struct" do
      example = %TuningExample{
        text_input: "What is AI?",
        output: "Artificial Intelligence"
      }

      assert example.text_input == "What is AI?"
      assert example.output == "Artificial Intelligence"
    end

    test "Hyperparameters struct with different options" do
      # With learning rate
      hyper1 = %Hyperparameters{
        learning_rate: 0.001,
        epoch_count: 5,
        batch_size: 4
      }

      assert hyper1.learning_rate == 0.001

      # With learning rate multiplier
      hyper2 = %Hyperparameters{
        learning_rate_multiplier: 1.5,
        epoch_count: 3,
        batch_size: 8
      }

      assert hyper2.learning_rate_multiplier == 1.5
    end

    test "TunedModelSource struct" do
      source = %TunedModelSource{
        tuned_model: "tunedModels/base-model-123",
        base_model: "models/gemini-1.5-flash-001"
      }

      assert source.tuned_model == "tunedModels/base-model-123"
      assert source.base_model == "models/gemini-1.5-flash-001"
    end
  end

  describe "to_json/1 conversions" do
    test "TuningExample to_json" do
      example = %TuningExample{
        text_input: "Test input",
        output: "Test output"
      }

      json = Tuning.TuningExample.to_json(example)
      
      assert json == %{
        "textInput" => "Test input",
        "output" => "Test output"
      }
    end

    test "TuningExamples to_json" do
      examples = %TuningExamples{
        examples: [
          %TuningExample{
            text_input: "Input 1",
            output: "Output 1"
          },
          %TuningExample{
            text_input: "Input 2",
            output: "Output 2"
          }
        ]
      }

      json = Tuning.TuningExamples.to_json(examples)
      
      assert json == %{
        "examples" => [
          %{"textInput" => "Input 1", "output" => "Output 1"},
          %{"textInput" => "Input 2", "output" => "Output 2"}
        ]
      }
    end

    test "Hyperparameters to_json with learning rate" do
      hyper = %Hyperparameters{
        learning_rate: 0.001,
        epoch_count: 5,
        batch_size: 4
      }

      json = Tuning.Hyperparameters.to_json(hyper)
      
      assert json == %{
        "learningRate" => 0.001,
        "epochCount" => 5,
        "batchSize" => 4
      }
    end

    test "Hyperparameters to_json with learning rate multiplier" do
      hyper = %Hyperparameters{
        learning_rate_multiplier: 1.5,
        epoch_count: 3
      }

      json = Tuning.Hyperparameters.to_json(hyper)
      
      assert json == %{
        "learningRateMultiplier" => 1.5,
        "epochCount" => 3
      }
    end

    test "Dataset to_json" do
      dataset = %Dataset{
        examples: %TuningExamples{
          examples: [
            %TuningExample{
              text_input: "Test",
              output: "Result"
            }
          ]
        }
      }

      json = Tuning.Dataset.to_json(dataset)
      
      assert json == %{
        "examples" => %{
          "examples" => [
            %{"textInput" => "Test", "output" => "Result"}
          ]
        }
      }
    end

    test "TuningTask to_json" do
      task = %TuningTask{
        training_data: %Dataset{
          examples: %TuningExamples{
            examples: []
          }
        },
        hyperparameters: %Hyperparameters{
          epoch_count: 5
        }
      }

      json = Tuning.TuningTask.to_json(task)
      
      assert json["trainingData"]
      assert json["hyperparameters"]["epochCount"] == 5
    end
  end

  describe "from_json/1 conversions" do
    test "TunedModel from_json" do
      json = %{
        "name" => "tunedModels/test-123",
        "displayName" => "Test Model",
        "description" => "Test description",
        "state" => "ACTIVE",
        "createTime" => "2025-06-01T10:00:00Z",
        "updateTime" => "2025-06-01T11:00:00Z",
        "baseModel" => "models/gemini-1.5-flash-001",
        "temperature" => 0.7,
        "topP" => 0.9,
        "topK" => 40,
        "tuningTask" => %{
          "startTime" => "2025-06-01T10:00:00Z",
          "completeTime" => "2025-06-01T11:00:00Z",
          "snapshots" => [],
          "trainingData" => %{
            "examples" => %{
              "examples" => []
            }
          }
        }
      }

      model = Tuning.TunedModel.from_json(json)
      
      assert %TunedModel{} = model
      assert model.name == "tunedModels/test-123"
      assert model.display_name == "Test Model"
      assert model.state == :ACTIVE
      assert model.temperature == 0.7
      assert model.base_model == "models/gemini-1.5-flash-001"
    end

    test "TunedModel from_json with tuned model source" do
      json = %{
        "name" => "tunedModels/derived-123",
        "tunedModelSource" => %{
          "tunedModel" => "tunedModels/base-123",
          "baseModel" => "models/gemini-1.5-flash-001"
        },
        "state" => "CREATING",
        "tuningTask" => %{
          "trainingData" => %{
            "examples" => %{
              "examples" => []
            }
          }
        }
      }

      model = Tuning.TunedModel.from_json(json)
      
      assert %TunedModel{} = model
      assert %TunedModelSource{} = model.tuned_model_source
      assert model.tuned_model_source.tuned_model == "tunedModels/base-123"
    end

    test "TuningSnapshot from_json" do
      json = %{
        "step" => 10,
        "epoch" => 2,
        "meanLoss" => 0.123,
        "computeTime" => "2025-06-01T10:30:00Z"
      }

      snapshot = Tuning.TuningSnapshot.from_json(json)
      
      assert %TuningSnapshot{} = snapshot
      assert snapshot.step == 10
      assert snapshot.epoch == 2
      assert snapshot.mean_loss == 0.123
    end

    test "ListTunedModelsResponse from_json" do
      json = %{
        "tunedModels" => [
          %{
            "name" => "tunedModels/model-1",
            "state" => "ACTIVE",
            "baseModel" => "models/gemini-1.5-flash-001",
            "tuningTask" => %{
              "trainingData" => %{
                "examples" => %{
                  "examples" => []
                }
              }
            }
          }
        ],
        "nextPageToken" => "token123"
      }

      response = Tuning.ListTunedModelsResponse.from_json(json)
      
      assert %ListTunedModelsResponse{} = response
      assert length(response.tuned_models) == 1
      assert response.next_page_token == "token123"
    end
  end

  describe "validate_create_request/1" do
    test "validates valid request" do
      request = %{
        base_model: "models/gemini-1.5-flash-001",
        tuning_task: %{
          training_data: %{
            examples: %TuningExamples{
              examples: [
                %TuningExample{
                  text_input: "Input",
                  output: "Output"
                }
              ]
            }
          }
        }
      }

      assert :ok = Tuning.validate_create_request(request)
    end

    test "validates request with display name" do
      request = %{
        display_name: "My Model",
        base_model: "models/gemini-1.5-flash-001",
        tuning_task: %{
          training_data: %{
            examples: %TuningExamples{
              examples: [
                %TuningExample{
                  text_input: "Input",
                  output: "Output"
                }
              ]
            }
          }
        }
      }

      assert :ok = Tuning.validate_create_request(request)
    end

    test "returns error for missing base_model" do
      request = %{
        tuning_task: %{
          training_data: %{
            examples: %TuningExamples{
              examples: []
            }
          }
        }
      }

      assert {:error, "base_model is required"} = Tuning.validate_create_request(request)
    end

    test "returns error for missing tuning_task" do
      request = %{
        base_model: "models/gemini-1.5-flash-001"
      }

      assert {:error, "tuning_task is required"} = Tuning.validate_create_request(request)
    end

    test "returns error for empty examples" do
      request = %{
        base_model: "models/gemini-1.5-flash-001",
        tuning_task: %{
          training_data: %{
            examples: %TuningExamples{
              examples: []
            }
          }
        }
      }

      assert {:error, "training_data must contain at least one example"} = 
        Tuning.validate_create_request(request)
    end
  end

  describe "validate_update_request/1" do
    test "validates valid update" do
      update = %{
        display_name: "Updated Name",
        description: "Updated description"
      }

      assert :ok = Tuning.validate_update_request(update)
    end

    test "validates update with temperature" do
      update = %{
        temperature: 0.8,
        top_p: 0.95
      }

      assert :ok = Tuning.validate_update_request(update)
    end

    test "returns error for invalid temperature" do
      update = %{
        temperature: 1.5
      }

      assert {:error, "temperature must be between 0.0 and 1.0"} = 
        Tuning.validate_update_request(update)
    end

    test "returns error for invalid top_p" do
      update = %{
        top_p: -0.1
      }

      assert {:error, "top_p must be between 0.0 and 1.0"} = 
        Tuning.validate_update_request(update)
    end
  end

  describe "create_request_body/1" do
    test "creates request body with all fields" do
      request = %{
        display_name: "Test Model",
        description: "A test model",
        base_model: "models/gemini-1.5-flash-001",
        temperature: 0.7,
        top_p: 0.9,
        top_k: 40,
        tuning_task: %{
          training_data: %{
            examples: %TuningExamples{
              examples: [
                %TuningExample{
                  text_input: "Input",
                  output: "Output"
                }
              ]
            }
          },
          hyperparameters: %Hyperparameters{
            epoch_count: 5,
            batch_size: 4
          }
        }
      }

      body = Tuning.create_request_body(request)
      
      assert body["displayName"] == "Test Model"
      assert body["description"] == "A test model"
      assert body["baseModel"] == "models/gemini-1.5-flash-001"
      assert body["temperature"] == 0.7
      assert body["topP"] == 0.9
      assert body["topK"] == 40
      assert body["tuningTask"]["trainingData"]["examples"]["examples"]
      assert body["tuningTask"]["hyperparameters"]["epochCount"] == 5
    end

    test "creates minimal request body" do
      request = %{
        base_model: "models/gemini-1.5-flash-001",
        tuning_task: %{
          training_data: %{
            examples: %TuningExamples{
              examples: [
                %TuningExample{
                  text_input: "Input",
                  output: "Output"
                }
              ]
            }
          }
        }
      }

      body = Tuning.create_request_body(request)
      
      assert body["baseModel"] == "models/gemini-1.5-flash-001"
      assert body["tuningTask"]["trainingData"]
      refute body["displayName"]
      refute body["temperature"]
    end
  end

  describe "update_request_body/2" do
    test "creates update body with mask" do
      update = %{
        display_name: "New Name",
        description: "New description",
        temperature: 0.8
      }

      body = Tuning.update_request_body(update, "displayName,description")
      
      assert body["displayName"] == "New Name"
      assert body["description"] == "New description"
      refute body["temperature"]  # Not in mask
    end

    test "creates update body without mask" do
      update = %{
        display_name: "New Name",
        temperature: 0.8
      }

      body = Tuning.update_request_body(update, nil)
      
      assert body["displayName"] == "New Name"
      assert body["temperature"] == 0.8
    end
  end
end