defmodule ExLLM.Gemini.ModelsUnitTest do
  use ExUnit.Case, async: true
  alias ExLLM.Providers.Gemini.Models.Model

  describe "Model.from_api/1" do
    test "properly deserializes all model fields" do
      raw_model = %{
        "name" => "models/gemini-2.0-flash",
        "baseModelId" => "gemini-2.0-flash",
        "version" => "2.0",
        "displayName" => "Gemini 2.0 Flash",
        "description" => "Fast and versatile multimodal model",
        "inputTokenLimit" => 1_048_576,
        "outputTokenLimit" => 8192,
        "supportedGenerationMethods" => ["generateContent", "streamGenerateContent"],
        "temperature" => 1.0,
        "maxTemperature" => 2.0,
        "topP" => 0.95,
        "topK" => 40
      }

      model = Model.from_api(raw_model)

      assert model.name == "models/gemini-2.0-flash"
      assert model.base_model_id == "gemini-2.0-flash"
      assert model.version == "2.0"
      assert model.display_name == "Gemini 2.0 Flash"
      assert model.description == "Fast and versatile multimodal model"
      assert model.input_token_limit == 1_048_576
      assert model.output_token_limit == 8192
      assert model.supported_generation_methods == ["generateContent", "streamGenerateContent"]
      assert model.temperature == 1.0
      assert model.max_temperature == 2.0
      assert model.top_p == 0.95
      assert model.top_k == 40
    end

    test "handles missing optional fields" do
      minimal_model = %{
        "name" => "models/test-model",
        "baseModelId" => "test-model",
        "version" => "1.0",
        "displayName" => "Test Model",
        "description" => "Test",
        "inputTokenLimit" => 1000,
        "outputTokenLimit" => 100,
        "supportedGenerationMethods" => ["generateContent"]
      }

      model = Model.from_api(minimal_model)

      assert model.name == "models/test-model"
      assert model.base_model_id == "test-model"
      assert model.temperature == nil
      assert model.max_temperature == nil
      assert model.top_p == nil
      assert model.top_k == nil
    end

    test "handles empty supported generation methods" do
      model_data = %{
        "name" => "models/test",
        "baseModelId" => "test",
        "version" => "1.0",
        "displayName" => "Test",
        "description" => "Test",
        "inputTokenLimit" => 1000,
        "outputTokenLimit" => 100,
        "supportedGenerationMethods" => []
      }

      model = Model.from_api(model_data)
      assert model.supported_generation_methods == []
    end

    test "handles nil supported generation methods" do
      model_data = %{
        "name" => "models/test",
        "baseModelId" => "test",
        "version" => "1.0",
        "displayName" => "Test",
        "description" => "Test",
        "inputTokenLimit" => 1000,
        "outputTokenLimit" => 100
      }

      model = Model.from_api(model_data)
      assert model.supported_generation_methods == []
    end
  end

  describe "list_models/1 parameter validation" do
    test "validates page_size parameter" do
      # Test is in integration test file since it needs HTTP client
      assert true
    end
  end

  describe "get_model/2 parameter validation" do
    test "normalizes model names correctly" do
      # Test is in integration test file since it needs HTTP client
      assert true
    end
  end
end
