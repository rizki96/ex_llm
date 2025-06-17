defmodule ExLLM.Infrastructure.Config.ProviderCapabilitiesTest do
  use ExUnit.Case, async: true
  alias ExLLM.Infrastructure.Config.ProviderCapabilities

  describe "get_capabilities/1" do
    test "returns capabilities for known providers" do
      assert {:ok, caps} = ProviderCapabilities.get_capabilities(:openai)
      assert caps.id == :openai
      assert caps.name == "OpenAI"
      assert :chat in caps.endpoints
      assert :embeddings in caps.endpoints
      assert :streaming in caps.features
    end

    test "returns error for unknown provider" do
      assert {:error, :not_found} = ProviderCapabilities.get_capabilities(:unknown_provider)
    end

    test "includes limitations for providers" do
      assert {:ok, ollama_caps} = ProviderCapabilities.get_capabilities(:ollama)
      assert ollama_caps.limitations[:no_cost_tracking] == true

      assert {:ok, openai_caps} = ProviderCapabilities.get_capabilities(:openai)
      assert is_number(openai_caps.limitations[:max_file_size])
    end

    test "returns capabilities for xai provider" do
      assert {:ok, caps} = ProviderCapabilities.get_capabilities(:xai)
      assert caps.id == :xai
      assert caps.name == "X.AI"
      assert :chat in caps.endpoints
      assert :streaming in caps.features
      assert :function_calling in caps.features
      assert :vision in caps.features
      assert :web_search in caps.features
      assert caps.authentication == [:api_key]
    end
  end

  describe "supports?/2" do
    test "checks endpoint support" do
      assert ProviderCapabilities.supports?(:openai, :embeddings) == true
      assert ProviderCapabilities.supports?(:anthropic, :embeddings) == false
      assert ProviderCapabilities.supports?(:ollama, :chat) == true
    end

    test "checks feature support" do
      assert ProviderCapabilities.supports?(:openai, :streaming) == true
      assert ProviderCapabilities.supports?(:openai, :function_calling) == true
      assert ProviderCapabilities.supports?(:ollama, :cost_tracking) == false
    end

    test "returns false for unknown provider" do
      assert ProviderCapabilities.supports?(:unknown, :chat) == false
    end
  end

  describe "find_providers_with_features/1" do
    test "finds providers with single feature" do
      providers = ProviderCapabilities.find_providers_with_features([:streaming])
      assert :openai in providers
      assert :anthropic in providers
      assert :ollama in providers
    end

    test "finds providers with multiple features" do
      providers = ProviderCapabilities.find_providers_with_features([:embeddings, :streaming])
      assert :openai in providers
      assert :ollama in providers
      refute :anthropic in providers
    end

    test "returns empty list when no providers match" do
      providers = ProviderCapabilities.find_providers_with_features([:impossible_feature])
      assert providers == []
    end

    test "handles endpoint requirements" do
      providers = ProviderCapabilities.find_providers_with_features([:images])
      assert :openai in providers
      refute :anthropic in providers
      refute :ollama in providers
    end
  end

  describe "get_auth_methods/1" do
    test "returns authentication methods for providers" do
      assert [:api_key, :bearer_token] = ProviderCapabilities.get_auth_methods(:openai)
      assert [:api_key, :bearer_token] = ProviderCapabilities.get_auth_methods(:anthropic)
      assert [] = ProviderCapabilities.get_auth_methods(:ollama)
      assert [] = ProviderCapabilities.get_auth_methods(:bumblebee)
    end

    test "returns empty list for unknown provider" do
      assert [] = ProviderCapabilities.get_auth_methods(:unknown)
    end
  end

  describe "get_endpoints/1" do
    test "returns available endpoints" do
      endpoints = ProviderCapabilities.get_endpoints(:openai)
      assert :chat in endpoints
      assert :embeddings in endpoints
      assert :images in endpoints
      assert :audio in endpoints
    end

    test "returns correct endpoints for different providers" do
      assert [:chat, :messages] = ProviderCapabilities.get_endpoints(:anthropic)
      endpoints = ProviderCapabilities.get_endpoints(:ollama)
      assert :chat in endpoints
      assert :embeddings in endpoints
    end
  end

  describe "list_providers/0" do
    test "returns all known providers sorted" do
      providers = ProviderCapabilities.list_providers()
      assert is_list(providers)
      assert :anthropic in providers
      assert :openai in providers
      assert :ollama in providers
      assert :xai in providers
      assert providers == Enum.sort(providers)
    end
  end

  describe "get_limitations/1" do
    test "returns provider limitations" do
      limitations = ProviderCapabilities.get_limitations(:ollama)
      assert limitations[:no_cost_tracking] == true
      assert limitations[:performance_depends_on_hardware] == true
    end

    test "returns empty map for providers without limitations" do
      assert %{} = ProviderCapabilities.get_limitations(:unknown)
    end
  end

  describe "compare_providers/1" do
    test "compares features across providers" do
      comparison = ProviderCapabilities.compare_providers([:openai, :anthropic, :ollama])

      assert :openai in comparison.providers
      assert :anthropic in comparison.providers
      assert :ollama in comparison.providers

      assert :streaming in comparison.features
      assert :chat in comparison.endpoints

      assert comparison.comparison[:openai].features != []
      assert comparison.comparison[:anthropic].features != []
    end

    test "handles unknown providers gracefully" do
      comparison = ProviderCapabilities.compare_providers([:openai, :unknown])
      assert comparison.providers == [:openai]
      refute :unknown in comparison.providers
    end
  end

  describe "recommend_providers/1" do
    test "recommends providers based on required features" do
      recommendations =
        ProviderCapabilities.recommend_providers(%{
          required_features: [:embeddings, :streaming]
        })

      assert is_list(recommendations)
      assert length(recommendations) > 0

      # All recommended providers should have required features
      Enum.each(recommendations, fn rec ->
        assert :embeddings in rec.matched_features
        assert :streaming in rec.matched_features
      end)
    end

    test "filters out excluded providers" do
      recommendations =
        ProviderCapabilities.recommend_providers(%{
          required_features: [:chat],
          exclude_providers: [:openai, :anthropic]
        })

      provider_ids = Enum.map(recommendations, & &1.provider)
      refute :openai in provider_ids
      refute :anthropic in provider_ids
    end

    test "prefers local providers when requested" do
      recommendations =
        ProviderCapabilities.recommend_providers(%{
          required_features: [:chat],
          prefer_local: true
        })

      # Local providers should have higher scores
      local_providers = [:ollama, :bumblebee]

      if length(recommendations) > 1 do
        top_providers = recommendations |> Enum.take(2) |> Enum.map(& &1.provider)
        assert Enum.any?(top_providers, &(&1 in local_providers))
      end
    end

    test "calculates scores based on matched features" do
      recommendations =
        ProviderCapabilities.recommend_providers(%{
          required_features: [:chat],
          preferred_features: [:streaming, :function_calling, :vision]
        })

      # Providers with more matched features should have higher scores
      assert length(recommendations) > 0
      scores = Enum.map(recommendations, & &1.score)
      assert scores == Enum.sort(scores, :desc)
    end
  end

  describe "get_adapter_module/1" do
    test "returns correct adapter modules" do
      assert ExLLM.Providers.OpenAI = ProviderCapabilities.get_adapter_module(:openai)
      assert ExLLM.Providers.Anthropic = ProviderCapabilities.get_adapter_module(:anthropic)
      assert ExLLM.Providers.Ollama = ProviderCapabilities.get_adapter_module(:ollama)
    end

    test "returns nil for unknown provider" do
      assert nil == ProviderCapabilities.get_adapter_module(:unknown)
    end
  end

  describe "is_local?/1" do
    test "identifies local providers" do
      assert ProviderCapabilities.is_local?(:bumblebee) == true
      assert ProviderCapabilities.is_local?(:ollama) == true
      assert ProviderCapabilities.is_local?(:mock) == true
    end

    test "identifies remote providers" do
      assert ProviderCapabilities.is_local?(:openai) == false
      assert ProviderCapabilities.is_local?(:anthropic) == false
      assert ProviderCapabilities.is_local?(:gemini) == false
    end
  end

  describe "requires_auth?/1" do
    test "identifies providers requiring authentication" do
      assert ProviderCapabilities.requires_auth?(:openai) == true
      assert ProviderCapabilities.requires_auth?(:anthropic) == true
      assert ProviderCapabilities.requires_auth?(:gemini) == true
    end

    test "identifies providers not requiring authentication" do
      assert ProviderCapabilities.requires_auth?(:bumblebee) == false
      assert ProviderCapabilities.requires_auth?(:ollama) == false
      assert ProviderCapabilities.requires_auth?(:mock) == false
    end

    test "returns false for unknown providers" do
      assert ProviderCapabilities.requires_auth?(:unknown) == false
    end
  end
end
