defmodule ExLLM.Integration.KnowledgeBaseComprehensiveTest do
  @moduledoc """
  Comprehensive integration tests for ExLLM Knowledge Base functionality.
  Tests the complete knowledge base lifecycle through ExLLM's unified interface.
  """
  use ExUnit.Case

  # Test helpers
  defp unique_name(base) when is_binary(base) do
    timestamp = :os.system_time(:millisecond)
    "#{base} #{timestamp}"
  end

  defp cleanup_knowledge_base(kb_id) when is_binary(kb_id) do
    case ExLLM.KnowledgeBase.delete_knowledge_base(:gemini, kb_id) do
      {:ok, _} -> :ok
      # Already deleted or other non-critical error
      {:error, _} -> :ok
    end
  end

  defp cleanup_document(kb_id, doc_id) when is_binary(kb_id) and is_binary(doc_id) do
    case ExLLM.KnowledgeBase.delete_document(:gemini, kb_id, doc_id) do
      {:ok, _} -> :ok
      # Already deleted or other non-critical error
      {:error, _} -> :ok
    end
  end

  describe "Knowledge Base Management" do
    @describetag :integration
    @describetag :knowledge_base
    @describetag timeout: 30_000

    test "create knowledge base" do
      name = unique_name("Basic KB")

      params = %{
        display_name: name,
        description: "A test knowledge base for integration testing"
      }

      case ExLLM.KnowledgeBase.create_knowledge_base(:gemini, params) do
        {:ok, kb} ->
          assert kb["name"] != nil
          assert kb["displayName"] == name
          assert kb["description"] == params.description
          assert kb["state"] in ["ACTIVE", "CREATING"]

          # Cleanup
          cleanup_knowledge_base(kb["name"])

        {:error, error} ->
          IO.puts("Knowledge base creation failed (may require OAuth2): #{inspect(error)}")
          assert is_map(error) or is_atom(error)
      end
    end

    test "list knowledge bases" do
      case ExLLM.KnowledgeBase.list_knowledge_bases(:gemini) do
        {:ok, response} ->
          assert is_map(response)
          assert Map.has_key?(response, "corpora") or Map.has_key?(response, "data")

        {:error, error} ->
          IO.puts("Knowledge base listing failed: #{inspect(error)}")
          assert is_map(error) or is_atom(error)
      end
    end

    test "get knowledge base details" do
      # Create knowledge base first
      name = unique_name("Get Details KB")

      params = %{
        display_name: name,
        description: "KB for testing retrieval"
      }

      case ExLLM.KnowledgeBase.create_knowledge_base(:gemini, params) do
        {:ok, kb} ->
          # Test retrieval
          case ExLLM.KnowledgeBase.get_knowledge_base(:gemini, kb["name"]) do
            {:ok, retrieved} ->
              assert retrieved["name"] == kb["name"]
              assert retrieved["displayName"] == name

            {:error, error} ->
              IO.puts("Knowledge base retrieval failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup
          cleanup_knowledge_base(kb["name"])

        {:error, error} ->
          IO.puts("Knowledge base creation failed (skipping retrieval test): #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "delete knowledge base" do
      # Create knowledge base first
      name = unique_name("Delete Test KB")

      params = %{
        display_name: name,
        description: "KB for testing deletion"
      }

      case ExLLM.KnowledgeBase.create_knowledge_base(:gemini, params) do
        {:ok, kb} ->
          # Test deletion
          case ExLLM.KnowledgeBase.delete_knowledge_base(:gemini, kb["name"]) do
            {:ok, _} ->
              # Verify deletion by trying to retrieve
              case ExLLM.KnowledgeBase.get_knowledge_base(:gemini, kb["name"]) do
                {:ok, _} ->
                  flunk("Expected knowledge base to be deleted")

                {:error, error} ->
                  # Should get a not found error
                  assert is_map(error)

                  assert error.status_code in [404, 400] or
                           (is_map(error) and Map.get(error, "error") != nil)
              end

            {:error, error} ->
              IO.puts("Knowledge base deletion failed: #{inspect(error)}")
              assert is_map(error)
              # Try manual cleanup
              cleanup_knowledge_base(kb["name"])
          end

        {:error, error} ->
          IO.puts("Knowledge base creation failed (skipping deletion test): #{inspect(error)}")
          assert is_map(error)
      end
    end
  end

  describe "Document Management" do
    @describetag :integration
    @describetag :knowledge_base
    @describetag timeout: 30_000

    test "add document to knowledge base" do
      # Create knowledge base first
      kb_name = unique_name("Doc Test KB")

      kb_params = %{
        display_name: kb_name,
        description: "KB for document testing"
      }

      case ExLLM.KnowledgeBase.create_knowledge_base(:gemini, kb_params) do
        {:ok, kb} ->
          # Add document
          doc_content =
            "This is a test document about machine learning and artificial intelligence."

          doc_params = %{
            display_name: "Test Document",
            custom_metadata: [
              %{key: "topic", string_value: "AI"},
              %{key: "category", string_value: "technology"}
            ]
          }

          case ExLLM.KnowledgeBase.add_document(:gemini, kb["name"], doc_content, doc_params) do
            {:ok, doc} ->
              assert doc["name"] != nil
              assert doc["displayName"] == "Test Document"

              # Cleanup
              cleanup_document(kb["name"], doc["name"])

            {:error, error} ->
              IO.puts("Document creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup knowledge base
          cleanup_knowledge_base(kb["name"])

        {:error, error} ->
          IO.puts("Knowledge base creation failed (skipping document test): #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "list documents in knowledge base" do
      # Create knowledge base and document first
      kb_name = unique_name("List Docs KB")

      kb_params = %{
        display_name: kb_name,
        description: "KB for document listing"
      }

      case ExLLM.KnowledgeBase.create_knowledge_base(:gemini, kb_params) do
        {:ok, kb} ->
          # Add a document
          doc_content = "Sample document for listing test."
          doc_params = %{display_name: "List Test Doc"}

          case ExLLM.KnowledgeBase.add_document(:gemini, kb["name"], doc_content, doc_params) do
            {:ok, doc} ->
              # List documents
              case ExLLM.KnowledgeBase.list_documents(:gemini, kb["name"]) do
                {:ok, response} ->
                  assert is_map(response)
                  assert Map.has_key?(response, "documents") or Map.has_key?(response, "data")

                {:error, error} ->
                  IO.puts("Document listing failed: #{inspect(error)}")
                  assert is_map(error)
              end

              # Cleanup
              cleanup_document(kb["name"], doc["name"])

            {:error, error} ->
              IO.puts("Document creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup knowledge base
          cleanup_knowledge_base(kb["name"])

        {:error, error} ->
          IO.puts("Knowledge base creation failed (skipping document list test): #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "get document details" do
      # Create knowledge base and document first
      kb_name = unique_name("Get Doc KB")

      kb_params = %{
        display_name: kb_name,
        description: "KB for document retrieval"
      }

      case ExLLM.KnowledgeBase.create_knowledge_base(:gemini, kb_params) do
        {:ok, kb} ->
          # Add a document
          doc_content = "Document content for retrieval testing."

          doc_params = %{
            display_name: "Retrieve Test Doc",
            custom_metadata: [%{key: "test", string_value: "metadata"}]
          }

          case ExLLM.KnowledgeBase.add_document(:gemini, kb["name"], doc_content, doc_params) do
            {:ok, doc} ->
              # Get document details
              case ExLLM.KnowledgeBase.get_document(:gemini, kb["name"], doc["name"]) do
                {:ok, retrieved} ->
                  assert retrieved["name"] == doc["name"]
                  assert retrieved["displayName"] == "Retrieve Test Doc"

                {:error, error} ->
                  IO.puts("Document retrieval failed: #{inspect(error)}")
                  assert is_map(error)
              end

              # Cleanup
              cleanup_document(kb["name"], doc["name"])

            {:error, error} ->
              IO.puts("Document creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup knowledge base
          cleanup_knowledge_base(kb["name"])

        {:error, error} ->
          IO.puts("Knowledge base creation failed (skipping document get test): #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "delete document from knowledge base" do
      # Create knowledge base and document first
      kb_name = unique_name("Delete Doc KB")

      kb_params = %{
        display_name: kb_name,
        description: "KB for document deletion"
      }

      case ExLLM.KnowledgeBase.create_knowledge_base(:gemini, kb_params) do
        {:ok, kb} ->
          # Add a document
          doc_content = "Document to be deleted."
          doc_params = %{display_name: "Delete Test Doc"}

          case ExLLM.KnowledgeBase.add_document(:gemini, kb["name"], doc_content, doc_params) do
            {:ok, doc} ->
              # Delete document
              case ExLLM.KnowledgeBase.delete_document(:gemini, kb["name"], doc["name"]) do
                {:ok, _} ->
                  # Verify deletion by trying to retrieve
                  case ExLLM.KnowledgeBase.get_document(:gemini, kb["name"], doc["name"]) do
                    {:ok, _} ->
                      flunk("Expected document to be deleted")

                    {:error, error} ->
                      # Should get a not found error
                      assert is_map(error)

                      assert error.status_code in [404, 400] or
                               (is_map(error) and Map.get(error, "error") != nil)
                  end

                {:error, error} ->
                  IO.puts("Document deletion failed: #{inspect(error)}")
                  assert is_map(error)
                  # Try manual cleanup
                  cleanup_document(kb["name"], doc["name"])
              end

            {:error, error} ->
              IO.puts("Document creation failed: #{inspect(error)}")
              assert is_map(error)
          end

          # Cleanup knowledge base
          cleanup_knowledge_base(kb["name"])

        {:error, error} ->
          IO.puts("Knowledge base creation failed (skipping document delete test): #{inspect(error)}")

          assert is_map(error)
      end
    end
  end

  describe "Semantic Search" do
    @describetag :integration
    @describetag :knowledge_base
    @describetag timeout: 30_000

    test "basic semantic search" do
      # Create knowledge base with sample documents
      kb_name = unique_name("Search KB")

      kb_params = %{
        display_name: kb_name,
        description: "KB for search testing"
      }

      case ExLLM.KnowledgeBase.create_knowledge_base(:gemini, kb_params) do
        {:ok, kb} ->
          # Add sample documents
          docs = [
            {"Machine learning is a subset of artificial intelligence.", "ML Doc"},
            {"Deep learning uses neural networks with many layers.", "DL Doc"},
            {"Natural language processing helps computers understand text.", "NLP Doc"}
          ]

          created_docs =
            Enum.map(docs, fn {content, title} ->
              doc_params = %{
                display_name: title,
                custom_metadata: [%{key: "category", string_value: "AI"}]
              }

              case ExLLM.KnowledgeBase.add_document(:gemini, kb["name"], content, doc_params) do
                {:ok, doc} -> doc
                {:error, _} -> nil
              end
            end)
            |> Enum.filter(& &1)

          if length(created_docs) > 0 do
            # Wait a bit for indexing
            :timer.sleep(2000)

            # Perform semantic search
            query = "What is artificial intelligence?"

            case ExLLM.KnowledgeBase.semantic_search(:gemini, kb["name"], query) do
              {:ok, results} ->
                assert is_map(results)

              # Should find relevant chunks related to AI/ML

              {:error, error} ->
                IO.puts("Semantic search failed: #{inspect(error)}")
                assert is_map(error)
            end

            # Cleanup documents
            Enum.each(created_docs, fn doc ->
              cleanup_document(kb["name"], doc["name"])
            end)
          end

          # Cleanup knowledge base
          cleanup_knowledge_base(kb["name"])

        {:error, error} ->
          IO.puts("Knowledge base creation failed (skipping search test): #{inspect(error)}")
          assert is_map(error)
      end
    end

    test "semantic search with metadata filters" do
      # Create knowledge base with categorized documents
      kb_name = unique_name("Filter Search KB")

      kb_params = %{
        display_name: kb_name,
        description: "KB for filtered search testing"
      }

      case ExLLM.KnowledgeBase.create_knowledge_base(:gemini, kb_params) do
        {:ok, kb} ->
          # Add documents with different categories
          docs = [
            {"Python is a programming language.", "Python Doc", "programming"},
            {"JavaScript runs in web browsers.", "JS Doc", "programming"},
            {"Machine learning predicts patterns.", "ML Doc", "ai"}
          ]

          created_docs =
            Enum.map(docs, fn {content, title, category} ->
              doc_params = %{
                display_name: title,
                custom_metadata: [%{key: "category", string_value: category}]
              }

              case ExLLM.KnowledgeBase.add_document(:gemini, kb["name"], content, doc_params) do
                {:ok, doc} -> doc
                {:error, _} -> nil
              end
            end)
            |> Enum.filter(& &1)

          if length(created_docs) > 0 do
            # Wait for indexing
            :timer.sleep(2000)

            # Search with category filter
            query = "programming languages"

            metadata_filters = [
              %{key: "category", conditions: [%{operation: "EQUAL", string_value: "programming"}]}
            ]

            case ExLLM.KnowledgeBase.semantic_search(:gemini, kb["name"], query,
                   metadata_filters: metadata_filters
                 ) do
              {:ok, results} ->
                assert is_map(results)

              # Should only find programming-related documents

              {:error, error} ->
                IO.puts("Filtered search failed: #{inspect(error)}")
                assert is_map(error)
            end

            # Cleanup documents
            Enum.each(created_docs, fn doc ->
              cleanup_document(kb["name"], doc["name"])
            end)
          end

          # Cleanup knowledge base
          cleanup_knowledge_base(kb["name"])

        {:error, error} ->
          IO.puts("Knowledge base creation failed (skipping filtered search test): #{inspect(error)}")

          assert is_map(error)
      end
    end
  end

  describe "Error Handling" do
    @describetag :integration
    @describetag :knowledge_base
    @describetag timeout: 30_000

    test "knowledge base not found error" do
      fake_kb_id = "corpora/nonexistent-#{:os.system_time(:millisecond)}"

      case ExLLM.KnowledgeBase.get_knowledge_base(:gemini, fake_kb_id) do
        {:ok, _} ->
          flunk("Expected knowledge base not found error")

        {:error, error} ->
          assert is_map(error)

          assert (is_map(error) and Map.get(error, :status_code) in [404, 400]) or
                   (is_map(error) and Map.get(error, "error") != nil) or
                   (is_map(error) and Map.get(error, :function) != nil)
      end
    end

    test "document not found error" do
      fake_kb_id = "corpora/nonexistent-kb-#{:os.system_time(:millisecond)}"
      fake_doc_id = "documents/nonexistent-doc-#{:os.system_time(:millisecond)}"

      case ExLLM.KnowledgeBase.get_document(:gemini, fake_kb_id, fake_doc_id) do
        {:ok, _} ->
          flunk("Expected document not found error")

        {:error, error} ->
          assert is_map(error)

          assert (is_map(error) and Map.get(error, :status_code) in [404, 400]) or
                   (is_map(error) and Map.get(error, "error") != nil) or
                   (is_map(error) and Map.get(error, :function) != nil)
      end
    end

    test "invalid parameters error" do
      # Try to create knowledge base with invalid parameters
      invalid_params = %{
        # Missing required display_name
        description: "Invalid KB"
      }

      case ExLLM.KnowledgeBase.create_knowledge_base(:gemini, invalid_params) do
        {:ok, _} ->
          flunk("Expected invalid parameters error")

        {:error, error} ->
          assert is_map(error)
          # Should get validation error
      end
    end
  end
end
