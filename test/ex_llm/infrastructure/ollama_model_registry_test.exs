defmodule ExLLM.Infrastructure.OllamaModelRegistryTest do
  use ExUnit.Case, async: false

  alias ExLLM.Infrastructure.OllamaModelRegistry

  setup do
    # Clear cache before each test
    OllamaModelRegistry.clear_cache()
    :ok
  end

  describe "get_model_details/1" do
    test "retrieves details from ModelConfig for known models" do
      # Test with a model that exists in ollama.yml
      assert {:ok, details} = OllamaModelRegistry.get_model_details("llama3.2:1b")

      assert details.context_window > 0
      assert "streaming" in details.capabilities
    end

    test "returns error for unknown models when API is not available" do
      # Test with a model that doesn't exist in config and API call will fail
      assert {:error, {:api_fetch_failed, _}} =
               OllamaModelRegistry.get_model_details("unknown-model-xyz")
    end

    test "caches successful lookups" do
      # First call should fetch from config
      assert {:ok, details1} = OllamaModelRegistry.get_model_details("llama3.2:1b")

      # Second call should be from cache (we can't easily test this directly,
      # but we can verify the result is the same)
      assert {:ok, details2} = OllamaModelRegistry.get_model_details("llama3.2:1b")

      assert details1 == details2
    end

    test "clear_cache removes cached entries" do
      # Populate cache
      assert {:ok, _} = OllamaModelRegistry.get_model_details("llama3.2:1b")

      # Clear cache
      OllamaModelRegistry.clear_cache()

      # Next call should fetch again (result should be the same)
      assert {:ok, details} = OllamaModelRegistry.get_model_details("llama3.2:1b")
      assert details.context_window > 0
    end
  end
end
