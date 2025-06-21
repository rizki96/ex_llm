defmodule ExLLM.KnowledgeBase do
  @moduledoc """
  Knowledge Base management functionality for ExLLM.

  This module provides functions for working with knowledge bases (also called corpora),
  including creation, management, document handling, and semantic search capabilities.
  Knowledge bases enable semantic retrieval and question-answering over large document
  collections.

  ## Features

  - **Knowledge Base Management**: Create, list, get, and delete knowledge bases
  - **Document Management**: Add, list, get, and delete documents within knowledge bases
  - **Semantic Search**: Perform semantic search and question-answering over documents
  - **Provider Support**: Currently supports Google Gemini with extensible architecture

  ## Examples

      # Create a knowledge base
      {:ok, kb} = ExLLM.KnowledgeBase.create_knowledge_base(:gemini, "my_kb",
        display_name: "My Knowledge Base"
      )
      
      # Add a document
      {:ok, doc} = ExLLM.KnowledgeBase.add_document(:gemini, "my_kb", %{
        display_name: "Research Paper",
        text: "This is the content of my research paper..."
      })
      
      # Perform semantic search
      {:ok, results} = ExLLM.KnowledgeBase.semantic_search(:gemini, "my_kb", 
        "What are the key findings?")
  """

  alias ExLLM.API.Delegator

  @doc """
  Create a knowledge base (corpus) for semantic retrieval.

  Knowledge bases are collections of documents that can be searched semantically
  using natural language queries. They're ideal for building RAG (Retrieval
  Augmented Generation) applications.

  ## Parameters

    * `provider` - The provider to use (currently only `:gemini` supported)
    * `name` - Unique name for the knowledge base
    * `opts` - Configuration options for the knowledge base

  ## Options

    * `:display_name` - Human-readable name for the knowledge base
    * `:description` - Description of the knowledge base purpose
    * `:metadata` - Custom metadata for the knowledge base

  ## Examples

      # Create a basic knowledge base
      {:ok, kb} = ExLLM.KnowledgeBase.create_knowledge_base(:gemini, "research_papers",
        display_name: "Research Papers Collection"
      )

      # Create with description and metadata
      {:ok, kb} = ExLLM.KnowledgeBase.create_knowledge_base(:gemini, "product_docs",
        display_name: "Product Documentation",
        description: "Internal product documentation and guides",
        metadata: %{team: "engineering", version: "1.0"}
      )

  ## Response Format

      {:ok, %{
        name: "corpora/research_papers",
        display_name: "Research Papers Collection",
        description: "",
        create_time: "2024-01-01T00:00:00Z",
        update_time: "2024-01-01T00:00:00Z"
      }}
  """
  @spec create_knowledge_base(atom(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_knowledge_base(provider, name, opts \\ []) do
    case Delegator.delegate(:create_knowledge_base, provider, [name, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List available knowledge bases (corpora).

  Retrieves a paginated list of knowledge bases associated with your account.
  Useful for discovering existing knowledge bases and their metadata.

  ## Parameters

    * `provider` - The provider to use (currently only `:gemini` supported)
    * `opts` - Query options for filtering and pagination

  ## Options

    * `:page_size` - Number of knowledge bases per page (default: 10, max: 100)
    * `:page_token` - Token for pagination (from previous response)

  ## Examples

      # List all knowledge bases
      {:ok, response} = ExLLM.KnowledgeBase.list_knowledge_bases(:gemini)

      # List with pagination
      {:ok, response} = ExLLM.KnowledgeBase.list_knowledge_bases(:gemini, 
        page_size: 20,
        page_token: "next_page_token_here"
      )

  ## Response Format

      {:ok, %{
        corpora: [
          %{
            name: "corpora/research_papers",
            display_name: "Research Papers Collection",
            description: "Collection of research papers",
            create_time: "2024-01-01T00:00:00Z",
            update_time: "2024-01-01T00:00:00Z"
          }
        ],
        next_page_token: "token_for_next_page"
      }}
  """
  @spec list_knowledge_bases(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_knowledge_bases(provider, opts \\ []) do
    case Delegator.delegate(:list_knowledge_bases, provider, [opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get metadata for a specific knowledge base.

  Retrieves detailed information about a knowledge base including its
  configuration, statistics, and metadata.

  ## Parameters

    * `provider` - The provider to use (currently only `:gemini` supported)
    * `name` - Name of the knowledge base to retrieve
    * `opts` - Additional options (currently unused)

  ## Examples

      {:ok, kb} = ExLLM.KnowledgeBase.get_knowledge_base(:gemini, "research_papers")

  ## Response Format

      {:ok, %{
        name: "corpora/research_papers",
        display_name: "Research Papers Collection", 
        description: "Collection of research papers",
        create_time: "2024-01-01T00:00:00Z",
        update_time: "2024-01-01T00:00:00Z"
      }}
  """
  @spec get_knowledge_base(atom(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_knowledge_base(provider, name, opts \\ []) do
    case Delegator.delegate(:get_knowledge_base, provider, [name, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Delete a knowledge base.

  Permanently deletes a knowledge base and all its contained documents.
  This action cannot be undone.

  ## Parameters

    * `provider` - The provider to use (currently only `:gemini` supported)
    * `name` - Name of the knowledge base to delete
    * `opts` - Additional options (currently unused)

  ## Examples

      {:ok, result} = ExLLM.KnowledgeBase.delete_knowledge_base(:gemini, "old_research")

  ## Response Format

      {:ok, %{
        deleted: true,
        name: "corpora/old_research"
      }}
  """
  @spec delete_knowledge_base(atom(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def delete_knowledge_base(provider, name, opts \\ []) do
    case Delegator.delegate(:delete_knowledge_base, provider, [name, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Add a document to a knowledge base.

  Adds a new document to an existing knowledge base. Documents are automatically
  processed for semantic search and can include text content, metadata, and
  custom identifiers.

  ## Parameters

    * `provider` - The provider to use (currently only `:gemini` supported)
    * `knowledge_base` - Name of the knowledge base to add to
    * `document` - Document data (map with text and metadata)
    * `opts` - Additional options for document creation

  ## Document Format

  The document should be a map with the following structure:

      %{
        display_name: "Document Title",
        text: "Full text content of the document",
        metadata: %{
          author: "John Doe",
          category: "research",
          tags: ["AI", "machine learning"]
        }
      }

  ## Examples

      # Add a simple document
      {:ok, doc} = ExLLM.KnowledgeBase.add_document(:gemini, "research_papers", %{
        display_name: "AI Research Paper",
        text: "This paper explores the latest developments in AI..."
      })

      # Add document with metadata
      {:ok, doc} = ExLLM.KnowledgeBase.add_document(:gemini, "research_papers", %{
        display_name: "Machine Learning Survey",
        text: "A comprehensive survey of machine learning techniques...",
        metadata: %{
          author: "Dr. Smith",
          year: 2024,
          category: "survey"
        }
      })

  ## Response Format

      {:ok, %{
        name: "corpora/research_papers/documents/doc_123",
        display_name: "AI Research Paper",
        create_time: "2024-01-01T00:00:00Z",
        update_time: "2024-01-01T00:00:00Z"
      }}
  """
  @spec add_document(atom(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def add_document(provider, knowledge_base, document, opts \\ []) do
    case Delegator.delegate(:add_document, provider, [knowledge_base, document, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List documents in a knowledge base.

  Retrieves a paginated list of documents within a specific knowledge base.
  Useful for browsing document collections and managing content.

  ## Parameters

    * `provider` - The provider to use (currently only `:gemini` supported)
    * `knowledge_base` - Name of the knowledge base
    * `opts` - Query options for filtering and pagination

  ## Options

    * `:page_size` - Number of documents per page (default: 10, max: 100)
    * `:page_token` - Token for pagination (from previous response)

  ## Examples

      # List all documents
      {:ok, response} = ExLLM.KnowledgeBase.list_documents(:gemini, "research_papers")

      # List with pagination
      {:ok, response} = ExLLM.KnowledgeBase.list_documents(:gemini, "research_papers",
        page_size: 25,
        page_token: "next_token"
      )

  ## Response Format

      {:ok, %{
        documents: [
          %{
            name: "corpora/research_papers/documents/doc_123",
            display_name: "AI Research Paper",
            create_time: "2024-01-01T00:00:00Z",
            update_time: "2024-01-01T00:00:00Z"
          }
        ],
        next_page_token: "token_for_next_page"
      }}
  """
  @spec list_documents(atom(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_documents(provider, knowledge_base, opts \\ []) do
    case Delegator.delegate(:list_documents, provider, [knowledge_base, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get a specific document from a knowledge base.

  Retrieves detailed information about a document including its content,
  metadata, and processing status.

  ## Parameters

    * `provider` - The provider to use (currently only `:gemini` supported)
    * `knowledge_base` - Name of the knowledge base
    * `document_id` - ID of the document to retrieve
    * `opts` - Additional options (currently unused)

  ## Examples

      {:ok, doc} = ExLLM.KnowledgeBase.get_document(:gemini, "research_papers", "doc_123")

  ## Response Format

      {:ok, %{
        name: "corpora/research_papers/documents/doc_123",
        display_name: "AI Research Paper",
        create_time: "2024-01-01T00:00:00Z",
        update_time: "2024-01-01T00:00:00Z",
        custom_metadata: %{
          author: "Dr. Smith",
          category: "research"
        }
      }}
  """
  @spec get_document(atom(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_document(provider, knowledge_base, document_id, opts \\ []) do
    case Delegator.delegate(:get_document, provider, [knowledge_base, document_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Delete a document from a knowledge base.

  Permanently removes a document from the knowledge base. This action
  cannot be undone.

  ## Parameters

    * `provider` - The provider to use (currently only `:gemini` supported)
    * `knowledge_base` - Name of the knowledge base
    * `document_id` - ID of the document to delete
    * `opts` - Additional options (currently unused)

  ## Examples

      {:ok, result} = ExLLM.KnowledgeBase.delete_document(:gemini, "research_papers", "doc_123")

  ## Response Format

      {:ok, %{
        deleted: true,
        name: "corpora/research_papers/documents/doc_123"
      }}
  """
  @spec delete_document(atom(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def delete_document(provider, knowledge_base, document_id, opts \\ []) do
    case Delegator.delegate(:delete_document, provider, [knowledge_base, document_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Perform semantic search within a knowledge base.

  Searches for relevant documents using natural language queries. The search
  uses semantic understanding to find documents that are conceptually related
  to the query, not just exact keyword matches.

  ## Parameters

    * `provider` - The provider to use (currently only `:gemini` supported)
    * `knowledge_base` - Name of the knowledge base to search
    * `query` - Natural language search query
    * `opts` - Search configuration options

  ## Options

    * `:results_count` - Maximum number of results to return (default: 10)
    * `:metadata_filter` - Filter results by document metadata
    * `:answer_style` - Style of answer generation ("extractive", "abstractive")

  ## Examples

      # Basic semantic search
      {:ok, results} = ExLLM.KnowledgeBase.semantic_search(:gemini, "research_papers",
        "What are the latest developments in machine learning?"
      )

      # Search with result limit
      {:ok, results} = ExLLM.KnowledgeBase.semantic_search(:gemini, "research_papers",
        "neural network architectures",
        results_count: 5
      )

      # Search with metadata filter
      {:ok, results} = ExLLM.KnowledgeBase.semantic_search(:gemini, "research_papers",
        "AI applications",
        metadata_filter: %{category: "applications", year: 2024}
      )

  ## Response Format

      {:ok, %{
        answerable_probability: 0.95,
        answer: %{
          answer: "Machine learning has seen significant developments in...",
          grounding_attributions: [
            %{
              source_id: %{
                grounding_source: %{
                  semantic_retriever_source: %{
                    source: "corpora/research_papers/documents/doc_123"
                  }
                }
              },
              confidence_score: 0.85
            }
          ]
        }
      }}
  """
  @spec semantic_search(atom(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def semantic_search(provider, knowledge_base, query, opts \\ []) do
    case Delegator.delegate(:semantic_search, provider, [knowledge_base, query, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
