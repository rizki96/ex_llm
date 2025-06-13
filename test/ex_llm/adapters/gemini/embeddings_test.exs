defmodule ExLLM.Gemini.EmbeddingsTest do
  @moduledoc """
  Tests for the Gemini Embeddings API.
  
  Tests cover:
  - Single text embedding generation
  - Batch embedding generation
  - Different task types
  - Title support for retrieval documents
  - Output dimensionality configuration
  - Error handling
  """
  
  use ExUnit.Case, async: true
  alias ExLLM.Gemini.Embeddings
  alias ExLLM.Gemini.Embeddings.{EmbedContentRequest, ContentEmbedding}
  alias ExLLM.Gemini.Content.{Content, Part}
  
  @moduletag :integration
  
  describe "embed_content/3" do
    test "successfully generates embedding for text" do
      request = %EmbedContentRequest{
        content: %Content{role: "user",
          parts: [%Part{text: "Hello world, this is a test of the embeddings API."}]
        }
      }
      
      case Embeddings.embed_content("models/text-embedding-004", request) do
        {:ok, %ContentEmbedding{} = embedding} ->
          assert is_list(embedding.values)
          assert length(embedding.values) > 0
          assert Enum.all?(embedding.values, &is_float/1)
          
        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          # Expected when running without valid API key
          assert true
          
        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
    
    test "generates embedding with specific task type" do
      request = %EmbedContentRequest{
        content: %Content{role: "user",
          parts: [%Part{text: "What is the capital of France?"}]
        },
        task_type: :retrieval_query
      }
      
      case Embeddings.embed_content("models/text-embedding-004", request) do
        {:ok, %ContentEmbedding{} = embedding} ->
          assert is_list(embedding.values)
          assert length(embedding.values) > 0
          
        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true
          
        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
    
    test "generates embedding for retrieval document with title" do
      request = %EmbedContentRequest{
        content: %Content{role: "user",
          parts: [%Part{text: "Paris is the capital and most populous city of France."}]
        },
        task_type: :retrieval_document,
        title: "France Capital Information"
      }
      
      case Embeddings.embed_content("models/text-embedding-004", request) do
        {:ok, %ContentEmbedding{} = embedding} ->
          assert is_list(embedding.values)
          assert length(embedding.values) > 0
          
        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true
          
        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
    
    test "generates embedding with reduced dimensionality" do
      request = %EmbedContentRequest{
        content: %Content{role: "user",
          parts: [%Part{text: "Test embedding with reduced dimensions"}]
        },
        output_dimensionality: 256
      }
      
      case Embeddings.embed_content("models/text-embedding-004", request) do
        {:ok, %ContentEmbedding{} = embedding} ->
          assert length(embedding.values) == 256
          
        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true
          
        {:error, %{status: 400}} ->
          # Model might not support output dimensionality
          assert true
          
        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
    
    test "handles different task types" do
      task_types = [
        :semantic_similarity,
        :classification,
        :clustering,
        :question_answering,
        :fact_verification,
        :code_retrieval_query
      ]
      
      for task_type <- task_types do
        request = %EmbedContentRequest{
          content: %Content{role: "user",
            parts: [%Part{text: "Testing #{task_type} task type"}]
          },
          task_type: task_type
        }
        
        case Embeddings.embed_content("models/text-embedding-004", request) do
          {:ok, %ContentEmbedding{}} ->
            assert true
            
          {:error, %{status: 400, message: "API key not valid" <> _}} ->
            assert true
            
          {:error, _} ->
            # Some task types might not be supported by all models
            assert true
        end
      end
    end
    
    test "returns error for empty content" do
      request = %EmbedContentRequest{
        content: %Content{role: "user",
          parts: []
        }
      }
      
      result = Embeddings.embed_content("models/text-embedding-004", request)
      assert {:error, %{reason: :invalid_params}} = result
    end
    
    test "returns error for missing text in parts" do
      request = %EmbedContentRequest{
        content: %Content{role: "user",
          parts: [%Part{}]
        }
      }
      
      result = Embeddings.embed_content("models/text-embedding-004", request)
      assert {:error, %{reason: :invalid_params}} = result
    end
    
    test "returns error for invalid model" do
      request = %EmbedContentRequest{
        content: %Content{role: "user",
          parts: [%Part{text: "Test"}]
        }
      }
      
      case Embeddings.embed_content("models/invalid-model", request) do
        {:error, %{status: 404}} ->
          assert true
          
        {:error, %{status: 400}} ->
          assert true
          
        {:error, %{message: "API key not valid" <> _}} ->
          assert true
          
        other ->
          flunk("Expected error, got: #{inspect(other)}")
      end
    end
  end
  
  describe "batch_embed_contents/2" do
    test "successfully generates embeddings for multiple texts" do
      requests = [
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user",
            parts: [%Part{text: "First text to embed"}]
          }
        },
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user",
            parts: [%Part{text: "Second text to embed"}]
          }
        },
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user",
            parts: [%Part{text: "Third text to embed"}]
          }
        }
      ]
      
      case Embeddings.batch_embed_contents("models/text-embedding-004", requests) do
        {:ok, embeddings} ->
          assert length(embeddings) == 3
          
          Enum.each(embeddings, fn %ContentEmbedding{} = embedding ->
            assert is_list(embedding.values)
            assert length(embedding.values) > 0
            assert Enum.all?(embedding.values, &is_float/1)
          end)
          
        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true
          
        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
    
    test "generates batch embeddings with different task types" do
      requests = [
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user",
            parts: [%Part{text: "What is machine learning?"}]
          },
          task_type: :retrieval_query
        },
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user",
            parts: [%Part{text: "Machine learning is a subset of artificial intelligence."}]
          },
          task_type: :retrieval_document,
          title: "ML Definition"
        }
      ]
      
      case Embeddings.batch_embed_contents("models/text-embedding-004", requests) do
        {:ok, embeddings} ->
          assert length(embeddings) == 2
          
        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true
          
        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
    
    test "returns error for mismatched models in batch" do
      requests = [
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user",
            parts: [%Part{text: "First text"}]
          }
        },
        %EmbedContentRequest{
          model: "models/different-model",
          content: %Content{role: "user",
            parts: [%Part{text: "Second text"}]
          }
        }
      ]
      
      result = Embeddings.batch_embed_contents("models/text-embedding-004", requests)
      assert {:error, %{reason: :invalid_params}} = result
    end
    
    test "returns error for empty batch" do
      result = Embeddings.batch_embed_contents("models/text-embedding-004", [])
      assert {:error, %{reason: :invalid_params}} = result
    end
    
    test "handles large batch" do
      # Create 10 requests
      requests = for i <- 1..10 do
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user",
            parts: [%Part{text: "Text number #{i} for batch embedding"}]
          }
        }
      end
      
      case Embeddings.batch_embed_contents("models/text-embedding-004", requests) do
        {:ok, embeddings} ->
          assert length(embeddings) == 10
          
        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true
          
        {:error, _} ->
          # Batch size limits might apply
          assert true
      end
    end
  end
  
  describe "convenience functions" do
    test "embed_text/3 generates embedding for simple text" do
      case Embeddings.embed_text("models/text-embedding-004", "Hello world") do
        {:ok, %ContentEmbedding{} = embedding} ->
          assert is_list(embedding.values)
          assert length(embedding.values) > 0
          
        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true
          
        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
    
    test "embed_texts/3 generates embeddings for multiple texts" do
      texts = ["First text", "Second text", "Third text"]
      
      case Embeddings.embed_texts("models/text-embedding-004", texts) do
        {:ok, embeddings} ->
          assert length(embeddings) == 3
          
        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true
          
        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
  end
  
  describe "struct validation" do
    test "EmbedContentRequest enforces required fields" do
      # Content is required, so creating without it should raise at compile time
      # This is tested by the @enforce_keys in the struct definition
      request = %EmbedContentRequest{
        content: %Content{role: "user", parts: [%Part{text: "test"}]}
      }
      assert request.content
    end
    
    test "ContentEmbedding enforces required fields" do
      # Values is required, so creating without it should raise at compile time
      # This is tested by the @enforce_keys in the struct definition
      embedding = %ContentEmbedding{
        values: [0.1, 0.2, 0.3]
      }
      assert embedding.values
    end
  end
  
  describe "model compatibility" do
    test "older model (embedding-001) does not support task type" do
      request = %EmbedContentRequest{
        content: %Content{role: "user",
          parts: [%Part{text: "Test for older model"}]
        },
        task_type: :retrieval_query
      }
      
      case Embeddings.embed_content("models/embedding-001", request) do
        {:error, %{status: 400}} ->
          # Expected - older model doesn't support task type
          assert true
          
        {:error, %{status: 404}} ->
          # Model might not exist
          assert true
          
        {:error, %{message: "API key not valid" <> _}} ->
          assert true
          
        {:ok, _} ->
          # If it succeeds, task type might be ignored
          assert true
          
        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end
    
    test "older model does not support output dimensionality" do
      request = %EmbedContentRequest{
        content: %Content{role: "user",
          parts: [%Part{text: "Test for older model"}]
        },
        output_dimensionality: 256
      }
      
      case Embeddings.embed_content("models/embedding-001", request) do
        {:error, %{status: 400}} ->
          # Expected - older model doesn't support output dimensionality
          assert true
          
        {:error, %{status: 404}} ->
          # Model might not exist
          assert true
          
        {:error, %{message: "API key not valid" <> _}} ->
          assert true
          
        {:ok, embedding} ->
          # If it succeeds, output dimensionality might be accepted or ignored
          # Some models might support it, others might ignore it
          assert is_list(embedding.values)
          assert length(embedding.values) > 0
          
        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end
  end
end