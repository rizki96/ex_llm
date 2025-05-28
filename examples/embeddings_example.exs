# Embeddings Example with ExLLM
#
# This example demonstrates how to use ExLLM's embeddings API for:
# - Generating text embeddings
# - Semantic search
# - Document similarity
# - Clustering
# - Cost tracking for embeddings
#
# Run with: mix run examples/embeddings_example.exs

defmodule EmbeddingsExample do
  def run do
    IO.puts("\n🚀 ExLLM Embeddings Example\n")
    
    # Example 1: Basic Embeddings
    IO.puts("1️⃣ Basic Embeddings Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Single text embedding
    {:ok, response} = ExLLM.embeddings(:mock, ["Hello, world!"],
      mock_response: %{
        embeddings: [[0.123, -0.456, 0.789, 0.012, -0.345]],
        model: "text-embedding-3-small",
        usage: %{input_tokens: 3, output_tokens: 0}
      }
    )
    
    [embedding] = response.embeddings
    IO.puts("Text: 'Hello, world!'")
    IO.puts("Embedding (first 5 dims): #{inspect(Enum.take(embedding, 5))}")
    IO.puts("Dimensions: #{length(embedding)}")
    
    if response.cost do
      IO.puts("Cost: #{ExLLM.format_cost(response.cost.total_cost)}")
    end
    
    # Example 2: Multiple Embeddings
    IO.puts("\n\n2️⃣ Multiple Embeddings Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    documents = [
      "The quick brown fox jumps over the lazy dog",
      "A fast auburn canine leaps above a sleepy hound",
      "Machine learning is transforming technology",
      "AI and deep learning are revolutionizing tech",
      "Paris is the capital of France"
    ]
    
    # Generate mock embeddings (in real usage, remove mock_response)
    mock_embeddings = Enum.map(documents, fn _ ->
      Enum.map(1..384, fn _ -> :rand.uniform() * 2 - 1 end)
    end)
    
    {:ok, response} = ExLLM.embeddings(:mock, documents,
      model: "text-embedding-3-small",
      mock_response: %{
        embeddings: mock_embeddings,
        model: "text-embedding-3-small",
        usage: %{input_tokens: 50, output_tokens: 0}
      }
    )
    
    IO.puts("Generated embeddings for #{length(documents)} documents")
    IO.puts("Total tokens: #{response.usage.input_tokens}")
    
    # Example 3: Semantic Search
    IO.puts("\n\n3️⃣ Semantic Search Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Create a simple document store
    doc_store = Enum.zip(documents, response.embeddings)
    |> Enum.with_index()
    |> Enum.map(fn {{text, embedding}, idx} ->
      %{
        id: idx,
        text: text,
        embedding: embedding
      }
    end)
    
    # Search query
    query = "jumping animals"
    
    # Generate query embedding
    {:ok, query_response} = ExLLM.embeddings(:mock, [query],
      mock_response: %{
        embeddings: [Enum.map(1..384, fn _ -> :rand.uniform() * 2 - 1 end)],
        model: "text-embedding-3-small",
        usage: %{input_tokens: 2, output_tokens: 0}
      }
    )
    
    [query_embedding] = query_response.embeddings
    
    # Find similar documents
    results = ExLLM.find_similar(query_embedding, doc_store, top_k: 3)
    
    IO.puts("Query: '#{query}'")
    IO.puts("\nTop 3 results:")
    Enum.each(results, fn %{item: doc, similarity: sim} ->
      IO.puts("  #{Float.round(sim, 3)} - \"#{doc.text}\"")
    end)
    
    # Example 4: Document Similarity Matrix
    IO.puts("\n\n4️⃣ Document Similarity Matrix:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Calculate pairwise similarities
    similarities = for i <- 0..(length(documents) - 1),
                      j <- 0..(length(documents) - 1) do
      doc_i = Enum.at(doc_store, i)
      doc_j = Enum.at(doc_store, j)
      sim = ExLLM.cosine_similarity(doc_i.embedding, doc_j.embedding)
      {i, j, sim}
    end
    
    # Print similarity matrix
    IO.puts("Document similarity matrix:")
    IO.puts("     " <> Enum.map_join(0..4, "     ", fn i -> "D#{i}" end))
    
    for i <- 0..4 do
      row = for j <- 0..4 do
        {_, _, sim} = Enum.find(similarities, fn {x, y, _} -> x == i && y == j end)
        Float.round(sim, 2)
      end
      IO.puts("D#{i}  #{Enum.map_join(row, "  ", fn s -> String.pad_leading("#{s}", 4) end)}")
    end
    
    # Example 5: Clustering
    IO.puts("\n\n5️⃣ Simple Clustering Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Group similar documents (simple threshold-based clustering)
    threshold = 0.7
    
    clusters = Enum.reduce(doc_store, [], fn doc, clusters ->
      # Find if doc belongs to any existing cluster
      cluster_idx = Enum.find_index(clusters, fn cluster ->
        # Check similarity with cluster centroid (first doc)
        centroid = List.first(cluster)
        ExLLM.cosine_similarity(doc.embedding, centroid.embedding) > threshold
      end)
      
      if cluster_idx do
        # Add to existing cluster
        List.update_at(clusters, cluster_idx, &(&1 ++ [doc]))
      else
        # Create new cluster
        clusters ++ [[doc]]
      end
    end)
    
    IO.puts("Found #{length(clusters)} clusters (threshold: #{threshold}):")
    Enum.with_index(clusters) |> Enum.each(fn {cluster, idx} ->
      IO.puts("\nCluster #{idx + 1}:")
      Enum.each(cluster, fn doc ->
        IO.puts("  - \"#{doc.text}\"")
      end)
    end)
    
    # Example 6: Embedding Models Comparison
    IO.puts("\n\n6️⃣ Embedding Models Comparison:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    {:ok, models} = ExLLM.list_embedding_models(:openai)
    
    IO.puts("Available OpenAI embedding models:")
    Enum.each(models, fn model ->
      IO.puts("\n#{model.name}:")
      IO.puts("  Dimensions: #{model.dimensions}")
      IO.puts("  Description: #{model.description}")
      if model.pricing do
        cost_per_million = model.pricing.input_cost_per_token * 1_000_000
        IO.puts("  Cost: $#{Float.round(cost_per_million, 2)} per million tokens")
      end
    end)
    
    # Example 7: Caching Embeddings
    IO.puts("\n\n7️⃣ Caching Embeddings Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Start cache if not running
    ensure_cache_started()
    
    # First request - will generate embeddings
    cache_text = ["This text will be cached"]
    
    start_time = System.monotonic_time(:millisecond)
    {:ok, _} = ExLLM.embeddings(:mock, cache_text,
      cache: true,
      cache_ttl: :timer.minutes(60),
      mock_response: %{
        embeddings: [[0.1, 0.2, 0.3]],
        model: "text-embedding-3-small",
        usage: %{input_tokens: 5, output_tokens: 0}
      }
    )
    time1 = System.monotonic_time(:millisecond) - start_time
    
    # Second request - should use cache
    start_time = System.monotonic_time(:millisecond)
    {:ok, cached_response} = ExLLM.embeddings(:mock, cache_text,
      cache: true
    )
    time2 = System.monotonic_time(:millisecond) - start_time
    
    IO.puts("First request: #{time1}ms")
    IO.puts("Cached request: #{time2}ms") 
    IO.puts("Cache speedup: #{Float.round(time1 / max(time2, 1), 1)}x")
    
    # Example 8: Cost Analysis
    IO.puts("\n\n8️⃣ Cost Analysis Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Simulate embedding a large dataset
    num_documents = 10_000
    avg_tokens_per_doc = 50
    total_tokens = num_documents * avg_tokens_per_doc
    
    IO.puts("Scenario: Embedding #{num_documents} documents")
    IO.puts("Average tokens per document: #{avg_tokens_per_doc}")
    IO.puts("Total tokens: #{total_tokens}")
    IO.puts("\nCost comparison:")
    
    embedding_models = [
      {"text-embedding-3-small", 0.02},
      {"text-embedding-3-large", 0.13},
      {"text-embedding-ada-002", 0.10}
    ]
    
    Enum.each(embedding_models, fn {model, cost_per_million} ->
      total_cost = (total_tokens / 1_000_000) * cost_per_million
      IO.puts("  #{model}: $#{Float.round(total_cost, 4)}")
    end)
    
    IO.puts("\n\n✅ Embeddings examples completed!")
    IO.puts("\nKey takeaways:")
    IO.puts("- Embeddings enable semantic search and similarity")
    IO.puts("- Different models offer different dimensions and costs")
    IO.puts("- Caching can significantly reduce costs for repeated embeddings")
    IO.puts("- Cosine similarity is effective for comparing embeddings")
  end
  
  defp ensure_cache_started do
    case GenServer.whereis(ExLLM.Cache) do
      nil ->
        {:ok, _} = ExLLM.Cache.start_link()
      _ ->
        :ok
    end
  end
end

# Run the examples
EmbeddingsExample.run()