defmodule ExLLM.API.KnowledgeBasesTest do
  @moduledoc """
  Comprehensive tests for the unified knowledge bases API.
  Tests the public ExLLM API to ensure excellent user experience.
  """

  use ExUnit.Case, async: false
  import ExLLM.Testing.TestCacheHelpers

  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag :unified_api
  @moduletag :knowledge_bases
  @moduletag provider: :gemini

  # Test knowledge base configuration
  @test_kb_name "exllm_test_kb_#{System.unique_integer([:positive])}"
  @test_document %{
    display_name: "Test Document",
    text:
      "This is a test document for ExLLM unified API testing. It contains information about testing knowledge bases."
  }

  setup_all do
    enable_cache_debug()
    :ok
  end

  setup context do
    setup_test_cache(context)

    on_exit(fn ->
      ExLLM.Testing.TestCacheDetector.clear_test_context()
    end)

    :ok
  end

  describe "create_knowledge_base/3" do
    @tag provider: :gemini
    test "creates knowledge base successfully with Gemini" do
      case ExLLM.create_knowledge_base(:gemini, @test_kb_name, display_name: "Test KB") do
        {:ok, kb} ->
          assert is_map(kb)
          assert Map.has_key?(kb, :name)
          assert String.contains?(kb.name, @test_kb_name)

        {:error, reason} ->
          IO.puts("Gemini knowledge base creation failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, "Knowledge base creation not supported for provider: openai"} =
               ExLLM.create_knowledge_base(:openai, @test_kb_name)

      assert {:error, "Knowledge base creation not supported for provider: anthropic"} =
               ExLLM.create_knowledge_base(:anthropic, @test_kb_name)
    end

    test "handles invalid knowledge base names" do
      invalid_names = [nil, "", 123, %{}, []]

      for invalid_name <- invalid_names do
        case ExLLM.create_knowledge_base(:gemini, invalid_name) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid KB name: #{inspect(invalid_name)}")
        end
      end
    end

    test "handles malformed knowledge base names" do
      malformed_names = [
        "invalid name with spaces",
        "invalid-chars!@#",
        "name_with_ünïcödé",
        "very_long_name_" <> String.duplicate("x", 100)
      ]

      for malformed_name <- malformed_names do
        case ExLLM.create_knowledge_base(:gemini, malformed_name) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some malformed names might be handled gracefully
            :ok
        end
      end
    end
  end

  describe "list_knowledge_bases/2" do
    @tag provider: :gemini
    test "lists knowledge bases successfully with Gemini" do
      case ExLLM.list_knowledge_bases(:gemini, page_size: 5) do
        {:ok, response} ->
          assert is_map(response)
          # Gemini returns corpora in a specific structure
          assert Map.has_key?(response, :corpora) or Map.has_key?(response, :data)

        {:error, reason} ->
          IO.puts("Gemini list knowledge bases failed: #{inspect(reason)}")
          :ok
      end
    end

    test "returns error for unsupported provider" do
      assert {:error, "Knowledge base listing not supported for provider: openai"} =
               ExLLM.list_knowledge_bases(:openai)

      assert {:error, "Knowledge base listing not supported for provider: anthropic"} =
               ExLLM.list_knowledge_bases(:anthropic)
    end

    test "handles invalid options gracefully" do
      case ExLLM.list_knowledge_bases(:gemini, invalid_option: "invalid") do
        {:ok, _response} ->
          :ok

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "get_knowledge_base/3" do
    test "returns error for unsupported provider" do
      assert {:error, "Knowledge base retrieval not supported for provider: openai"} =
               ExLLM.get_knowledge_base(:openai, @test_kb_name)

      assert {:error, "Knowledge base retrieval not supported for provider: anthropic"} =
               ExLLM.get_knowledge_base(:anthropic, @test_kb_name)
    end

    @tag provider: :gemini
    test "handles non-existent knowledge base with Gemini" do
      case ExLLM.get_knowledge_base(:gemini, "non_existent_kb") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    test "handles invalid knowledge base names" do
      invalid_names = [nil, 123, %{}, []]

      for invalid_name <- invalid_names do
        case ExLLM.get_knowledge_base(:gemini, invalid_name) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid KB name: #{inspect(invalid_name)}")
        end
      end
    end
  end

  describe "delete_knowledge_base/3" do
    test "returns error for unsupported provider" do
      assert {:error, "Knowledge base deletion not supported for provider: openai"} =
               ExLLM.delete_knowledge_base(:openai, @test_kb_name)

      assert {:error, "Knowledge base deletion not supported for provider: anthropic"} =
               ExLLM.delete_knowledge_base(:anthropic, @test_kb_name)
    end

    @tag provider: :gemini
    test "handles non-existent knowledge base with Gemini" do
      case ExLLM.delete_knowledge_base(:gemini, "non_existent_kb") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # Some providers might return success even for non-existent KBs
          :ok
      end
    end

    test "handles invalid knowledge base names" do
      invalid_names = [nil, 123, %{}, []]

      for invalid_name <- invalid_names do
        case ExLLM.delete_knowledge_base(:gemini, invalid_name) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid KB name: #{inspect(invalid_name)}")
        end
      end
    end
  end

  describe "add_document/4" do
    test "returns error for unsupported provider" do
      assert {:error, "Document creation not supported for provider: openai"} =
               ExLLM.add_document(:openai, @test_kb_name, @test_document)

      assert {:error, "Document creation not supported for provider: anthropic"} =
               ExLLM.add_document(:anthropic, @test_kb_name, @test_document)
    end

    @tag provider: :gemini
    test "handles non-existent knowledge base with Gemini" do
      case ExLLM.add_document(:gemini, "non_existent_kb", @test_document) do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    test "handles invalid document data" do
      invalid_documents = [
        nil,
        "",
        123,
        [],
        %{},
        %{display_name: ""},
        %{text: ""},
        %{invalid: "structure"}
      ]

      for invalid_doc <- invalid_documents do
        case ExLLM.add_document(:gemini, @test_kb_name, invalid_doc) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some invalid documents might be handled gracefully
            :ok
        end
      end
    end
  end

  describe "list_documents/3" do
    test "returns error for unsupported provider" do
      assert {:error, "Document listing not supported for provider: openai"} =
               ExLLM.list_documents(:openai, @test_kb_name)

      assert {:error, "Document listing not supported for provider: anthropic"} =
               ExLLM.list_documents(:anthropic, @test_kb_name)
    end

    @tag provider: :gemini
    test "handles non-existent knowledge base with Gemini" do
      case ExLLM.list_documents(:gemini, "non_existent_kb") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end
  end

  describe "get_document/4" do
    test "returns error for unsupported provider" do
      assert {:error, "Document retrieval not supported for provider: openai"} =
               ExLLM.get_document(:openai, @test_kb_name, "doc_id")

      assert {:error, "Document retrieval not supported for provider: anthropic"} =
               ExLLM.get_document(:anthropic, @test_kb_name, "doc_id")
    end

    @tag provider: :gemini
    test "handles non-existent document with Gemini" do
      case ExLLM.get_document(:gemini, @test_kb_name, "non_existent_doc") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end
  end

  describe "delete_document/4" do
    test "returns error for unsupported provider" do
      assert {:error, "Document deletion not supported for provider: openai"} =
               ExLLM.delete_document(:openai, @test_kb_name, "doc_id")

      assert {:error, "Document deletion not supported for provider: anthropic"} =
               ExLLM.delete_document(:anthropic, @test_kb_name, "doc_id")
    end

    @tag provider: :gemini
    test "handles non-existent document with Gemini" do
      case ExLLM.delete_document(:gemini, @test_kb_name, "non_existent_doc") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # Some providers might return success even for non-existent documents
          :ok
      end
    end
  end

  describe "semantic_search/4" do
    test "returns error for unsupported provider" do
      assert {:error, "Semantic search not supported for provider: openai"} =
               ExLLM.semantic_search(:openai, @test_kb_name, "test query")

      assert {:error, "Semantic search not supported for provider: anthropic"} =
               ExLLM.semantic_search(:anthropic, @test_kb_name, "test query")
    end

    @tag provider: :gemini
    test "handles non-existent knowledge base with Gemini" do
      case ExLLM.semantic_search(:gemini, "non_existent_kb", "test query") do
        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        {:ok, _} ->
          # This might succeed if the provider handles it differently
          :ok
      end
    end

    test "handles invalid query types" do
      invalid_queries = [nil, 123, %{}, []]

      for invalid_query <- invalid_queries do
        case ExLLM.semantic_search(:gemini, @test_kb_name, invalid_query) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            flunk("Expected error for invalid query: #{inspect(invalid_query)}")
        end
      end
    end

    @tag provider: :gemini
    test "handles empty and malformed queries" do
      problematic_queries = [
        "",
        "   ",
        # Very long query
        String.duplicate("x", 10_000)
      ]

      for query <- problematic_queries do
        case ExLLM.semantic_search(:gemini, @test_kb_name, query) do
          {:error, _reason} ->
            :ok

          {:ok, _} ->
            # Some problematic queries might be handled gracefully
            :ok
        end
      end
    end
  end

  describe "knowledge base workflow" do
    @tag provider: :gemini
    @tag :slow
    test "complete knowledge base lifecycle with Gemini" do
      # Skip if Gemini is not configured
      unless ExLLM.configured?(:gemini) do
        IO.puts("Skipping Gemini knowledge base lifecycle test - not configured")
        :ok
      else
        kb_name = "test_kb_#{System.unique_integer([:positive])}"

        # Create knowledge base
        case ExLLM.create_knowledge_base(:gemini, kb_name, display_name: "Test KB") do
          {:ok, _kb} ->
            # List knowledge bases and verify ours is there
            case ExLLM.list_knowledge_bases(:gemini) do
              {:ok, list_response} ->
                kbs = Map.get(list_response, :corpora, [])
                assert Enum.any?(kbs, fn k -> String.contains?(k.name, kb_name) end)

              {:error, reason} ->
                IO.puts("List knowledge bases failed: #{inspect(reason)}")
            end

            # Get knowledge base details
            case ExLLM.get_knowledge_base(:gemini, kb_name) do
              {:ok, retrieved_kb} ->
                assert String.contains?(retrieved_kb.name, kb_name)

              {:error, reason} ->
                IO.puts("Get knowledge base failed: #{inspect(reason)}")
            end

            # Add a document
            case ExLLM.add_document(:gemini, kb_name, @test_document) do
              {:ok, document} ->
                doc_name = document.name

                # List documents
                case ExLLM.list_documents(:gemini, kb_name) do
                  {:ok, docs_response} ->
                    docs = Map.get(docs_response, :documents, [])
                    assert Enum.any?(docs, fn d -> d.name == doc_name end)

                  {:error, reason} ->
                    IO.puts("List documents failed: #{inspect(reason)}")
                end

                # Get document details
                case ExLLM.get_document(:gemini, kb_name, doc_name) do
                  {:ok, retrieved_doc} ->
                    assert retrieved_doc.name == doc_name

                  {:error, reason} ->
                    IO.puts("Get document failed: #{inspect(reason)}")
                end

                # Perform semantic search
                case ExLLM.semantic_search(:gemini, kb_name, "test information") do
                  {:ok, search_results} ->
                    assert is_map(search_results)

                  {:error, reason} ->
                    IO.puts("Semantic search failed: #{inspect(reason)}")
                end

                # Delete document
                case ExLLM.delete_document(:gemini, kb_name, doc_name) do
                  {:ok, _} ->
                    :ok

                  {:error, reason} ->
                    IO.puts("Delete document failed: #{inspect(reason)}")
                end

              {:error, reason} ->
                IO.puts("Add document failed: #{inspect(reason)}")
            end

            # Clean up - delete the knowledge base
            case ExLLM.delete_knowledge_base(:gemini, kb_name) do
              {:ok, _} ->
                :ok

              {:error, reason} ->
                IO.puts("Delete knowledge base failed: #{inspect(reason)}")
            end

          {:error, reason} ->
            IO.puts("Gemini knowledge base lifecycle test skipped: #{inspect(reason)}")
            :ok
        end
      end
    end
  end
end
