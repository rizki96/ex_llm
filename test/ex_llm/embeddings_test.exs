defmodule ExLLM.EmbeddingsTest do
  use ExUnit.Case, async: true
  alias ExLLM

  describe "cosine_similarity/2" do
    test "calculates similarity between identical vectors" do
      vec = [1.0, 0.0, 0.0]
      assert ExLLM.cosine_similarity(vec, vec) == 1.0
    end

    test "calculates similarity between orthogonal vectors" do
      vec1 = [1.0, 0.0, 0.0]
      vec2 = [0.0, 1.0, 0.0]
      assert ExLLM.cosine_similarity(vec1, vec2) == 0.0
    end

    test "calculates similarity between opposite vectors" do
      vec1 = [1.0, 0.0, 0.0]
      vec2 = [-1.0, 0.0, 0.0]
      assert ExLLM.cosine_similarity(vec1, vec2) == -1.0
    end

    test "calculates similarity between arbitrary vectors" do
      vec1 = [1.0, 2.0, 3.0]
      vec2 = [4.0, 5.0, 6.0]

      # Manual calculation:
      # dot_product = 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
      # mag1 = sqrt(1 + 4 + 9) = sqrt(14)
      # mag2 = sqrt(16 + 25 + 36) = sqrt(77)
      # similarity = 32 / (sqrt(14) * sqrt(77)) ≈ 0.9746

      similarity = ExLLM.cosine_similarity(vec1, vec2)
      assert_in_delta similarity, 0.9746, 0.0001
    end

    test "handles zero vectors" do
      vec1 = [0.0, 0.0, 0.0]
      vec2 = [1.0, 2.0, 3.0]
      assert ExLLM.cosine_similarity(vec1, vec2) == 0.0
    end

    test "raises error for vectors of different lengths" do
      vec1 = [1.0, 2.0]
      vec2 = [1.0, 2.0, 3.0]

      assert_raise ArgumentError, "Embeddings must have the same dimension", fn ->
        ExLLM.cosine_similarity(vec1, vec2)
      end
    end

    test "normalizes similarity to [-1, 1] range" do
      # Test with large values
      vec1 = [1000.0, 2000.0, 3000.0]
      vec2 = [4000.0, 5000.0, 6000.0]

      similarity = ExLLM.cosine_similarity(vec1, vec2)
      assert similarity >= -1.0
      assert similarity <= 1.0
    end
  end

  describe "find_similar/3" do
    setup do
      # Items must have an embedding field
      items_with_embeddings = [
        %{id: 1, text: "cats", embedding: [1.0, 0.0, 0.0]},
        %{id: 2, text: "kittens", embedding: [0.9, 0.1, 0.0]},
        %{id: 3, text: "dogs", embedding: [0.0, 1.0, 0.0]},
        %{id: 4, text: "puppies", embedding: [0.0, 0.9, 0.1]},
        %{id: 5, text: "opposite", embedding: [-1.0, 0.0, 0.0]}
      ]

      {:ok, items: items_with_embeddings}
    end

    test "finds most similar embedding", %{items: items} do
      query = [1.0, 0.0, 0.0]
      results = ExLLM.find_similar(query, items, top_k: 1)

      assert length(results) == 1
      [%{item: item, similarity: similarity}] = results
      assert item.id == 1
      assert item.text == "cats"
      assert similarity == 1.0
    end

    test "returns top k similar embeddings", %{items: items} do
      query = [1.0, 0.0, 0.0]
      results = ExLLM.find_similar(query, items, top_k: 3)

      assert length(results) == 3

      # Check ordering (most similar first)
      similarities = Enum.map(results, fn %{similarity: sim} -> sim end)
      assert similarities == Enum.sort(similarities, :desc)

      # Check expected order - cat (1.0), kittens (~0.89), dogs (0.0)
      ids = Enum.map(results, fn %{item: item} -> item.id end)
      # dogs and puppies both have 0.0 similarity
      assert ids == [1, 2, 3] or ids == [1, 2, 4]
    end

    test "filters by threshold", %{items: items} do
      query = [1.0, 0.0, 0.0]
      results = ExLLM.find_similar(query, items, top_k: 10, threshold: 0.5)

      # Should only return embeddings with similarity >= 0.5
      assert length(results) == 2

      Enum.each(results, fn %{similarity: similarity} ->
        assert similarity >= 0.5
      end)
    end

    test "returns empty list when no embeddings meet threshold", %{items: items} do
      # Orthogonal to all embeddings in the dataset
      query = [0.0, 0.0, 1.0]
      results = ExLLM.find_similar(query, items, threshold: 0.5)

      assert results == []
    end

    test "handles empty items list" do
      query = [1.0, 0.0, 0.0]
      results = ExLLM.find_similar(query, [], top_k: 5)

      assert results == []
    end

    test "handles top_k larger than items list", %{items: items} do
      query = [1.0, 0.0, 0.0]
      results = ExLLM.find_similar(query, items, top_k: 100)

      # One item has negative similarity (opposite vector), which might be filtered
      # by default threshold of 0.0
      # Excludes the "opposite" item with -1.0 similarity
      assert length(results) == 4
    end
  end

  # Integration tests with mock adapter
  describe "embeddings/3 integration" do
    setup do
      # Ensure Mock adapter is started
      case GenServer.whereis(ExLLM.Adapters.Mock) do
        nil -> 
          {:ok, _pid} = ExLLM.Adapters.Mock.start_link([])
        _pid -> 
          :ok
      end
      
      # Configure mock adapter for embeddings
      original_config = Application.get_env(:ex_llm, :mock_responses, %{})

      mock_config = %{
        embeddings: %ExLLM.Types.EmbeddingResponse{
          embeddings: [[0.1, 0.2, 0.3]],
          model: "text-embedding-ada-002",
          usage: %{input_tokens: 10, output_tokens: 0}
        }
      }

      Application.put_env(:ex_llm, :mock_responses, mock_config)

      on_exit(fn ->
        Application.put_env(:ex_llm, :mock_responses, original_config)
      end)

      :ok
    end

    test "generates embeddings for text input" do
      {:ok, response} = ExLLM.embeddings(:mock, ["Hello world"], cache: false)

      assert response.embeddings == [[0.1, 0.2, 0.3]]
      assert response.model == "text-embedding-ada-002"
      assert response.usage.input_tokens == 10
    end

    test "generates embeddings for multiple inputs" do
      # Update mock config for multiple inputs
      Application.put_env(:ex_llm, :mock_responses, %{
        embeddings: %ExLLM.Types.EmbeddingResponse{
          embeddings: [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]],
          model: "text-embedding-ada-002",
          usage: %{input_tokens: 10, output_tokens: 0}
        }
      })

      {:ok, response} = ExLLM.embeddings(:mock, ["Hello", "World"], cache: false)

      assert length(response.embeddings) == 2
      assert Enum.at(response.embeddings, 0) == [0.1, 0.2, 0.3]
      assert Enum.at(response.embeddings, 1) == [0.4, 0.5, 0.6]
    end

    test "handles provider errors" do
      Application.put_env(:ex_llm, :mock_responses, %{
        embeddings: {:error, "API error"}
      })

      assert {:error, "API error"} = ExLLM.embeddings(:mock, ["test"], cache: false)
    end
  end

  describe "list_embedding_models/2" do
    test "returns models for mock provider with embeddings support" do
      # Configure mock to return embedding models
      Application.put_env(:ex_llm, :mock_responses, %{
        list_embedding_models: [
          %ExLLM.Types.EmbeddingModel{
            name: "mock-embedding-small",
            dimensions: 384,
            max_inputs: 100,
            provider: :mock,
            description: "Small mock embedding model"
          },
          %ExLLM.Types.EmbeddingModel{
            name: "mock-embedding-large",
            dimensions: 1536,
            max_inputs: 100,
            provider: :mock,
            description: "Large mock embedding model"
          }
        ]
      })

      {:ok, models} = ExLLM.list_embedding_models(:mock)

      assert is_list(models)
      assert length(models) == 2

      # Check model structure
      model = hd(models)
      assert model.name == "mock-embedding-small"
      assert model.dimensions == 384
      assert model.max_inputs == 100

      Application.delete_env(:ex_llm, :mock_responses)
    end

    test "returns empty list for provider without embeddings support" do
      {:ok, models} = ExLLM.list_embedding_models(:anthropic)
      assert models == []

      {:ok, models} = ExLLM.list_embedding_models(:gemini)
      assert models == []
    end

    test "returns error for unknown provider" do
      assert {:error, {:unsupported_provider, :unknown}} =
               ExLLM.list_embedding_models(:unknown)
    end
  end
end
