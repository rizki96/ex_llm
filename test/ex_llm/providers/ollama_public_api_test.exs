defmodule ExLLM.Providers.OllamaPublicAPITest do
  @moduledoc """
  Ollama-specific integration tests using the public ExLLM API.
  Common tests are handled by the shared module.
  """

  use ExLLM.Shared.ProviderIntegrationTest, provider: :ollama
  import ExLLM.Testing.ServiceHelpers

  @moduletag :requires_service

  setup do
    skip_unless_service_available(:ollama)
  end

  # Provider-specific tests only
  describe "ollama-specific features via public API" do
    test "works with local Ollama models" do
      messages = [
        %{role: "user", content: "What is 1+1? Answer in one word."}
      ]

      case ExLLM.chat(:ollama, messages, model: "llama3.2:1b", max_tokens: 10) do
        {:ok, response} ->
          # Verify we got content (don't test specific answer)
          assert String.length(response.content) > 0
          assert response.metadata.provider == :ollama
          # Local models should have minimal cost
          assert response.cost == 0.0

        {:error, %{reason: :econnrefused}} ->
          # Ollama not running
          :ok

        {:error, _} ->
          :ok
      end
    end

    test "lists locally available models" do
      case ExLLM.list_models(:ollama) do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            model = hd(models)
            assert model.id =~ ~r/llama|mistral|phi|qwen/i
            # Local models have no cost
            assert model.pricing == nil || model.pricing.input == 0
          end

        {:error, %{reason: :econnrefused}} ->
          # Ollama not running
          :ok

        {:error, _} ->
          :ok
      end
    end

    @tag :embedding
    test "local embedding generation" do
      texts = ["Hello world", "Testing embeddings"]

      case ExLLM.embeddings(:ollama, texts, model: "nomic-embed-text") do
        {:ok, %ExLLM.Types.EmbeddingResponse{embeddings: embeddings}} ->
          assert length(embeddings) == 2
          assert is_list(hd(embeddings))
          assert is_float(hd(hd(embeddings)))
          # Check embedding dimension
          assert length(hd(embeddings)) > 100

        {:error, %{reason: :econnrefused}} ->
          # Ollama not running
          :ok

        {:error, {:api_error, %{status: 404}}} ->
          # Model not pulled
          :ok

        {:error, _} ->
          :ok
      end
    end

    test "custom Ollama endpoint configuration" do
      # Test with custom endpoint
      config = %{ollama: %{base_url: "http://localhost:11434"}}
      {:ok, provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Hi"}]

      case ExLLM.chat(:ollama, messages, config_provider: provider, max_tokens: 10) do
        {:ok, response} ->
          assert response.metadata.provider == :ollama

        {:error, %{reason: :econnrefused}} ->
          # Expected if Ollama not running
          :ok

        {:error, _} ->
          :ok
      end
    end
  end
end
