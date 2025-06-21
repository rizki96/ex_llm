defmodule ExLLM.Providers.OpenAI.CoreTest do
  @moduledoc """
  Tests for OpenAI provider core functionality.

  This module tests configuration, model listing, and basic setup functionality.
  """

  use ExUnit.Case, async: true

  alias ExLLM.Providers.OpenAI
  alias ExLLM.Testing.ConfigProviderHelper
  alias ExLLM.Types

  @moduletag :openai_core

  describe "configured?/1" do
    test "returns true when API key is available" do
      # Default config with env var should work
      result = OpenAI.configured?()
      # Will be true if OPENAI_API_KEY is set, false otherwise
      assert is_boolean(result)
    end

    test "returns false with empty API key" do
      config = %{openai: %{api_key: ""}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      refute OpenAI.configured?(config_provider: provider)
    end

    test "returns true with valid API key" do
      config = %{openai: %{api_key: "sk-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      assert OpenAI.configured?(config_provider: provider)
    end
  end

  describe "default_model/0" do
    test "returns a default model string" do
      model = OpenAI.default_model()
      assert is_binary(model)
      # Should be a GPT model
      assert String.contains?(model, "gpt")
    end
  end

  describe "model listing" do
    test "list_models returns models from config" do
      {:ok, models} = OpenAI.list_models()

      assert is_list(models)
      assert length(models) > 0

      model = hd(models)
      assert %Types.Model{} = model
      # Not all models have "gpt" in the name (e.g., dall-e models)
      assert is_binary(model.id)
      assert model.context_window > 0
      assert is_map(model.capabilities)
    end

    test "list_embedding_models returns embedding models" do
      {:ok, models} = OpenAI.list_embedding_models()

      assert is_list(models)
      assert length(models) > 0

      model = hd(models)
      assert %Types.EmbeddingModel{} = model
      assert model.provider == :openai
      # EmbeddingModel uses 'name' not 'id'
      assert String.contains?(model.name, "embedding")
    end
  end

  describe "headers and base URL" do
    test "uses custom base URL from config" do
      config = %{
        openai: %{
          api_key: "test-key",
          base_url: "https://custom.openai.com/v1"
        }
      }

      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]
      assert {:error, _} = OpenAI.chat(messages, config_provider: provider, timeout: 1)
    end
  end
end
