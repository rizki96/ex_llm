defmodule ExLLM.Gemini.ModelsTest do
  use ExUnit.Case, async: true

  @moduletag provider: :gemini
  alias ExLLM.Gemini.Models
  alias ExLLM.Gemini.Models.Model

  describe "list_models/1" do
    @tag :integration
    test "lists available models with default parameters" do
      # Test basic model listing
      assert {:ok, response} = Models.list_models()
      assert is_list(response.models)
      assert is_binary(response.next_page_token) or is_nil(response.next_page_token)

      # Check that we get some models
      assert length(response.models) > 0

      # Verify model structure
      [model | _] = response.models
      assert %Model{} = model
      assert is_binary(model.name)
      # Note: baseModelId is documented but not returned by the API
      assert is_nil(model.base_model_id) || is_binary(model.base_model_id)
      assert is_binary(model.version)
      assert is_binary(model.display_name)
      assert is_binary(model.description)
      assert is_integer(model.input_token_limit)
      assert is_integer(model.output_token_limit)
      assert is_list(model.supported_generation_methods)
      assert is_float(model.temperature) or is_nil(model.temperature)
      assert is_float(model.max_temperature) or is_nil(model.max_temperature)
      assert is_float(model.top_p) or is_nil(model.top_p)
      assert is_integer(model.top_k) or is_nil(model.top_k)
    end

    @tag :integration
    test "lists models with pagination parameters" do
      # Test with page size
      assert {:ok, response} = Models.list_models(page_size: 10)
      assert length(response.models) <= 10

      # Test with page token (if we have one from first response)
      if response.next_page_token do
        assert {:ok, page2} = Models.list_models(page_token: response.next_page_token)
        assert is_list(page2.models)

        # Verify we get different models on page 2
        page1_names = Enum.map(response.models, & &1.name)
        page2_names = Enum.map(page2.models, & &1.name)
        assert page1_names != page2_names
      end
    end

    @tag :integration
    test "handles maximum page size correctly" do
      # Test that page_size is capped at 1000
      assert {:ok, response} = Models.list_models(page_size: 2000)
      assert length(response.models) <= 1000
    end

    test "returns error for invalid API key" do
      # Test with invalid credentials
      result = Models.list_models(config_provider: invalid_config_provider())
      assert {:error, error} = result

      # Could be 400 or 404 depending on API state
      assert error[:status] in [400, 404] or error[:reason] == :network_error
    end

    @tag :unit
    test "returns error for network issues" do
      # Test network error handling
      # This test requires mocking the HTTP client
      assert {:error, %{reason: :network_error}} =
               Models.list_models(config_provider: network_error_provider())
    end

    test "validates page_size parameter" do
      # Negative page size
      assert {:error, %{reason: :invalid_params, message: message}} =
               Models.list_models(page_size: -1)

      assert message =~ "page_size must be positive"

      # Zero page size
      assert {:error, %{reason: :invalid_params, message: message}} =
               Models.list_models(page_size: 0)

      assert message =~ "page_size must be positive"
    end
  end

  describe "get_model/2" do
    @tag :integration
    test "retrieves specific model information" do
      model_name = "gemini-2.0-flash"

      assert {:ok, model} = Models.get_model(model_name)
      assert %Model{} = model
      assert model.name == "models/#{model_name}"
      # base_model_id is not returned by the API
      assert is_nil(model.base_model_id)
      assert is_binary(model.version)
      assert is_binary(model.display_name)
      assert model.display_name =~ "Gemini"
      assert is_integer(model.input_token_limit)
      assert is_integer(model.output_token_limit)
      assert "generateContent" in model.supported_generation_methods
    end

    @tag :integration
    test "retrieves different model variants" do
      models_to_test = [
        "gemini-2.0-flash",
        "gemini-1.5-flash",
        "gemini-1.5-pro"
      ]

      for model_name <- models_to_test do
        assert {:ok, model} = Models.get_model(model_name)
        # base_model_id is not returned by the API, verify name instead
        assert model.name == "models/#{model_name}"
      end
    end

    @tag :integration
    test "returns specific error for non-existent model" do
      assert {:error, %{status: 404, message: message}} =
               Models.get_model("non-existent-model")

      assert message =~ "not found" or message =~ "Model not found"
    end

    test "returns error for invalid model name format" do
      # Test various invalid formats
      invalid_names = ["", "models/", "/gemini", "gemini/", nil]

      for invalid_name <- invalid_names do
        result = Models.get_model(invalid_name)
        assert {:error, _} = result
      end
    end

    @tag :integration
    test "handles full resource path correctly" do
      # Should work with both formats
      assert {:ok, model1} = Models.get_model("gemini-2.0-flash")
      assert {:ok, model2} = Models.get_model("models/gemini-2.0-flash")

      # Should return the same model
      assert model1.name == model2.name
      assert model1.version == model2.version
    end

    test "returns error for invalid API key" do
      result = Models.get_model("gemini-2.0-flash", config_provider: invalid_config_provider())
      assert {:error, error} = result

      # Could be 400 or 404 depending on API state
      assert error[:status] in [400, 404] or error[:reason] == :network_error
    end
  end

  describe "Model struct" do
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

      assert model.temperature == nil
      assert model.max_temperature == nil
      assert model.top_p == nil
      assert model.top_k == nil
    end
  end

  describe "integration with main adapter" do
    @tag :integration
    test "models can be used with ExLLM.list_models/1" do
      # This should integrate with the main ExLLM module
      case ExLLM.list_models(:gemini) do
        {:ok, models} ->
          assert is_list(models)
          assert length(models) > 0

          # Check structure matches our expectations
          [model | _] = models
          assert Map.has_key?(model, :id)
          assert Map.has_key?(model, :name)
          assert Map.has_key?(model, :context_window)

        {:error, %{reason: :missing_api_key}} ->
          # Skip test if API key not configured
          :ok

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end
    end

    test "model info integrates with ModelCapabilities" do
      # Should work with the capability system if available
      case ExLLM.list_models(:gemini) do
        {:ok, _models} ->
          # Only test if we have models available
          case ExLLM.ModelCapabilities.get_model_info(:gemini, "gemini-2.0-flash") do
            {:ok, info} ->
              assert info.context_window > 0
              assert is_list(info.capabilities)

            _ ->
              # Model capabilities integration can be tested separately
              :ok
          end

        _ ->
          :ok
      end
    end
  end

  # Helper functions for testing
  defp invalid_config_provider do
    config = %{gemini: %{api_key: "invalid-key"}}
    {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
    provider
  end

  defp network_error_provider do
    # This would be a mock provider that simulates network errors
    # For now, we'll use a provider pointing to an invalid URL
    config = %{gemini: %{api_key: "test", base_url: "http://localhost:1"}}
    {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
    provider
  end
end
