defmodule ExLLM.ModelCapabilitiesTest do
  use ExUnit.Case, async: true

  alias ExLLM.ModelCapabilities
  alias ExLLM.ModelCapabilities.{Capability, ModelInfo}

  setup do
    # Ensure the model config cache exists before running tests
    ExLLM.ModelConfig.ensure_cache_table()
    :ok
  end

  describe "get_capabilities/2" do
    test "returns model info for known models" do
      assert {:ok, %ModelInfo{} = info} =
               ModelCapabilities.get_capabilities(:openai, "gpt-4-turbo")

      assert info.provider == :openai
      assert info.model_id == "gpt-4-turbo"
      assert info.context_window == 128_000
      assert info.max_output_tokens == 4_096
    end

    test "returns error for unknown models" do
      assert {:error, :not_found} = ModelCapabilities.get_capabilities(:openai, "gpt-5-super")
    end

    test "includes capability details" do
      {:ok, info} = ModelCapabilities.get_capabilities(:anthropic, "claude-3-opus-20240229")

      assert %Capability{feature: :vision, supported: true} = info.capabilities.vision

      assert %Capability{feature: :function_calling, supported: true} =
               info.capabilities.function_calling

      assert info.capabilities.vision.details.formats
    end
  end

  describe "supports?/3" do
    setup do
      ExLLM.ModelConfig.ensure_cache_table()
      :ok
    end

    test "returns true for supported features" do
      assert ModelCapabilities.supports?(:openai, "gpt-4-turbo", :vision)
      assert ModelCapabilities.supports?(:anthropic, "claude-3-opus-20240229", :function_calling)
      assert ModelCapabilities.supports?(:local, "microsoft/phi-2", :streaming)
    end

    test "returns false for unsupported features" do
      assert not ModelCapabilities.supports?(:openai, "gpt-3.5-turbo", :vision)
      assert not ModelCapabilities.supports?(:gemini, "gemini-pro-vision", :multi_turn)
      assert not ModelCapabilities.supports?(:local, "microsoft/phi-2", :vision)
    end

    test "returns false for unknown models" do
      assert not ModelCapabilities.supports?(:openai, "unknown-model", :vision)
    end
  end

  describe "get_capability_details/3" do
    test "returns detailed capability information" do
      assert {:ok, %Capability{} = cap} =
               ModelCapabilities.get_capability_details(
                 :anthropic,
                 "claude-3-opus-20240229",
                 :vision
               )

      assert cap.supported == true
      assert cap.details.formats
      assert "image/jpeg" in cap.details.formats
    end

    test "returns error for unsupported capability" do
      assert {:error, :not_supported} =
               ModelCapabilities.get_capability_details(:local, "microsoft/phi-2", :vision)
    end

    test "returns error for unknown model" do
      assert {:error, :not_found} =
               ModelCapabilities.get_capability_details(:openai, "unknown", :vision)
    end
  end

  describe "find_models_with_features/1" do
    setup do
      ExLLM.ModelConfig.ensure_cache_table()
      :ok
    end

    test "finds models with single feature" do
      models = ModelCapabilities.find_models_with_features([:vision])

      assert {:openai, "gpt-4-turbo"} in models
      assert {:anthropic, "claude-3-opus-20240229"} in models
      assert {:gemini, "gemini-pro-vision"} in models
      assert {:mock, "mock-model"} in models
    end

    test "finds models with multiple features" do
      models = ModelCapabilities.find_models_with_features([:vision, :function_calling])

      assert {:openai, "gpt-4-turbo"} in models
      assert {:anthropic, "claude-3-opus-20240229"} in models

      # Should not include models without both features
      assert {:gemini, "gemini-pro-vision"} not in models
    end

    test "returns empty list for impossible feature combination" do
      models = ModelCapabilities.find_models_with_features([:vision, :embeddings, :fine_tuning])
      assert models == []
    end
  end

  describe "compare_models/1" do
    test "compares features across models" do
      comparison =
        ModelCapabilities.compare_models([
          {:openai, "gpt-4-turbo"},
          {:anthropic, "claude-3-5-sonnet-20241022"},
          {:local, "microsoft/phi-2"}
        ])

      assert length(comparison.models) == 3
      assert is_map(comparison.features)

      # Check vision support comparison
      vision_support = comparison.features.vision
      assert [%{supported: true}, %{supported: true}, %{supported: false}] = vision_support
    end

    test "handles unknown models gracefully" do
      comparison =
        ModelCapabilities.compare_models([
          {:openai, "gpt-4-turbo"},
          {:unknown, "unknown-model"}
        ])

      # Should only include valid model
      assert length(comparison.models) == 1
      assert hd(comparison.models).model_id == "gpt-4-turbo"
    end
  end

  describe "models_by_capability/1" do
    test "groups models by capability support" do
      groups = ModelCapabilities.models_by_capability(:vision)

      assert is_list(groups.supported)
      assert is_list(groups.not_supported)

      assert {:openai, "gpt-4-turbo"} in groups.supported
      assert {:anthropic, "claude-3-opus-20240229"} in groups.supported
      assert {:local, "microsoft/phi-2"} in groups.not_supported
    end
  end

  describe "recommend_models/1" do
    test "recommends models based on features" do
      recommendations =
        ModelCapabilities.recommend_models(
          features: [:vision, :streaming],
          limit: 3
        )

      assert length(recommendations) <= 3

      # All recommended models should have the required features
      Enum.each(recommendations, fn {provider, model, _meta} ->
        assert ModelCapabilities.supports?(provider, model, :vision)
        assert ModelCapabilities.supports?(provider, model, :streaming)
      end)
    end

    test "filters by context window" do
      recommendations =
        ModelCapabilities.recommend_models(
          features: [:streaming],
          min_context_window: 100_000,
          limit: 5
        )

      # All recommended models should have large context windows
      Enum.each(recommendations, fn {provider, model, _meta} ->
        {:ok, info} = ModelCapabilities.get_capabilities(provider, model)
        assert info.context_window >= 100_000
      end)
    end

    test "prefers local models when requested" do
      recommendations =
        ModelCapabilities.recommend_models(
          features: [:streaming],
          prefer_local: true,
          limit: 10
        )

      # Local models should appear first (higher score)
      local_models =
        recommendations
        |> Enum.filter(fn {provider, _model, _meta} -> provider == :local end)

      if length(local_models) > 0 do
        {_provider, _model, %{score: local_score}} = hd(local_models)

        # Find first non-local model
        non_local = Enum.find(recommendations, fn {p, _, _} -> p != :local end)

        if non_local do
          {_provider, _model, %{score: non_local_score}} = non_local
          assert local_score > non_local_score
        end
      end
    end
  end

  describe "list_features/0" do
    test "returns list of all features" do
      features = ModelCapabilities.list_features()

      assert :streaming in features
      assert :function_calling in features
      assert :vision in features
      assert :multi_turn in features
      assert is_list(features)
      assert length(features) > 10
    end
  end

  describe "integration with main API" do
    setup do
      # Reload config to pick up any YAML changes
      ExLLM.ModelConfig.reload_config()
      :ok
    end

    test "get_model_info/2 works through ExLLM" do
      assert {:ok, info} = ExLLM.get_model_info(:openai, "gpt-4-turbo")
      assert info.display_name == "GPT-4 Turbo"
    end

    test "model_supports?/3 works through ExLLM" do
      assert ExLLM.model_supports?(:anthropic, "claude-3-opus-20240229", :vision)
      assert not ExLLM.model_supports?(:local, "microsoft/phi-2", :vision)
    end

    test "find_models_with_features/1 works through ExLLM" do
      models = ExLLM.find_models_with_features([:function_calling])
      assert is_list(models)
      assert length(models) > 0
    end

    test "compare_models/1 works through ExLLM" do
      comparison =
        ExLLM.compare_models([
          {:openai, "gpt-4"},
          {:anthropic, "claude-3-haiku-20240307"}
        ])

      assert is_map(comparison)
      assert is_list(comparison.models)
      assert is_map(comparison.features)
    end

    test "recommend_models/1 works through ExLLM" do
      recommendations = ExLLM.recommend_models(features: [:streaming])
      assert is_list(recommendations)
      assert length(recommendations) > 0
    end

    test "models_by_capability/1 works through ExLLM" do
      groups = ExLLM.models_by_capability(:function_calling)
      assert is_map(groups)
      assert Map.has_key?(groups, :supported)
      assert Map.has_key?(groups, :not_supported)
    end
  end
end
