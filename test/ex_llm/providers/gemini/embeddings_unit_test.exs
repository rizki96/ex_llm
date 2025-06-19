defmodule ExLLM.Gemini.EmbeddingsUnitTest do
  @moduledoc """
  Unit tests for the Gemini Embeddings API.

  Tests internal functions and behavior without making actual API calls.
  """

  use ExUnit.Case, async: true
  alias ExLLM.Providers.Gemini.Embeddings
  alias ExLLM.Providers.Gemini.Embeddings.{EmbedContentRequest, ContentEmbedding}
  alias ExLLM.Providers.Gemini.Content.{Content, Part}

  describe "EmbedContentRequest struct" do
    test "creates request with all fields" do
      request = %EmbedContentRequest{
        model: "models/text-embedding-004",
        content: %Content{role: "user", parts: [%Part{text: "Test text"}]},
        task_type: :retrieval_query,
        title: "Test Title",
        output_dimensionality: 256
      }

      assert request.model == "models/text-embedding-004"
      assert request.content.parts |> List.first() |> Map.get(:text) == "Test text"
      assert request.task_type == :retrieval_query
      assert request.title == "Test Title"
      assert request.output_dimensionality == 256
    end

    test "creates minimal request" do
      request = %EmbedContentRequest{
        content: %Content{role: "user", parts: [%Part{text: "Test text"}]}
      }

      assert request.content
      assert request.model == nil
      assert request.task_type == nil
      assert request.title == nil
      assert request.output_dimensionality == nil
    end
  end

  describe "ContentEmbedding struct" do
    @tag :embedding
    test "creates embedding with values" do
      embedding = %ContentEmbedding{
        values: [0.1, 0.2, 0.3, 0.4, 0.5]
      }

      assert embedding.values == [0.1, 0.2, 0.3, 0.4, 0.5]
      assert length(embedding.values) == 5
    end
  end

  describe "validate_embed_request/1" do
    test "validates complete request" do
      request = %EmbedContentRequest{
        content: %Content{role: "user", parts: [%Part{text: "Valid text"}]}
      }

      assert Embeddings.validate_embed_request(request) == :ok
    end

    test "returns error for missing content" do
      request = %{model: "models/text-embedding-004"}

      assert {:error, %{reason: :invalid_params}} = Embeddings.validate_embed_request(request)
    end

    test "returns error for empty parts" do
      request = %EmbedContentRequest{
        content: %Content{role: "user", parts: []}
      }

      assert {:error, %{reason: :invalid_params, message: message}} =
               Embeddings.validate_embed_request(request)

      assert message =~ "parts"
    end

    test "returns error for parts without text" do
      request = %EmbedContentRequest{
        content: %Content{role: "user", parts: [%Part{inline_data: %{}}]}
      }

      assert {:error, %{reason: :invalid_params, message: message}} =
               Embeddings.validate_embed_request(request)

      assert message =~ "text"
    end

    test "returns error for invalid task type with title" do
      request = %EmbedContentRequest{
        content: %Content{role: "user", parts: [%Part{text: "Test"}]},
        task_type: :semantic_similarity,
        title: "Should not have title"
      }

      assert {:error, %{reason: :invalid_params, message: message}} =
               Embeddings.validate_embed_request(request)

      assert message =~ "title"
    end
  end

  describe "validate_batch_requests/2" do
    test "validates matching models" do
      requests = [
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user", parts: [%Part{text: "Text 1"}]}
        },
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user", parts: [%Part{text: "Text 2"}]}
        }
      ]

      assert Embeddings.validate_batch_requests("models/text-embedding-004", requests) == :ok
    end

    test "returns error for mismatched models" do
      requests = [
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user", parts: [%Part{text: "Text 1"}]}
        },
        %EmbedContentRequest{
          model: "models/different-model",
          content: %Content{role: "user", parts: [%Part{text: "Text 2"}]}
        }
      ]

      assert {:error, %{reason: :invalid_params}} =
               Embeddings.validate_batch_requests("models/text-embedding-004", requests)
    end

    test "returns error for empty batch" do
      assert {:error, %{reason: :invalid_params}} =
               Embeddings.validate_batch_requests("models/text-embedding-004", [])
    end
  end

  describe "task_type_to_string/1" do
    test "converts task type atoms to strings" do
      assert Embeddings.task_type_to_string(:retrieval_query) == "RETRIEVAL_QUERY"
      assert Embeddings.task_type_to_string(:retrieval_document) == "RETRIEVAL_DOCUMENT"
      assert Embeddings.task_type_to_string(:semantic_similarity) == "SEMANTIC_SIMILARITY"
      assert Embeddings.task_type_to_string(:classification) == "CLASSIFICATION"
      assert Embeddings.task_type_to_string(:clustering) == "CLUSTERING"
      assert Embeddings.task_type_to_string(:question_answering) == "QUESTION_ANSWERING"
      assert Embeddings.task_type_to_string(:fact_verification) == "FACT_VERIFICATION"
      assert Embeddings.task_type_to_string(:code_retrieval_query) == "CODE_RETRIEVAL_QUERY"
    end

    test "returns nil for nil" do
      assert Embeddings.task_type_to_string(nil) == nil
    end
  end

  describe "build_embed_request_body/1" do
    test "builds request with all fields" do
      request = %EmbedContentRequest{
        model: "models/text-embedding-004",
        content: %Content{role: "user", parts: [%Part{text: "Test text"}]},
        task_type: :retrieval_document,
        title: "Document Title",
        output_dimensionality: 512
      }

      body = Embeddings.build_embed_request_body(request)

      assert body["model"] == "models/text-embedding-004"
      assert body["content"]["parts"] == [%{"text" => "Test text"}]
      assert body["taskType"] == "RETRIEVAL_DOCUMENT"
      assert body["title"] == "Document Title"
      assert body["outputDimensionality"] == 512
    end

    test "builds minimal request" do
      request = %EmbedContentRequest{
        content: %Content{role: "user", parts: [%Part{text: "Test text"}]}
      }

      body = Embeddings.build_embed_request_body(request)

      assert body["content"]["parts"] == [%{"text" => "Test text"}]
      refute Map.has_key?(body, "model")
      refute Map.has_key?(body, "taskType")
      refute Map.has_key?(body, "title")
      refute Map.has_key?(body, "outputDimensionality")
    end
  end

  describe "build_batch_request_body/1" do
    test "builds batch request body" do
      requests = [
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user", parts: [%Part{text: "Text 1"}]}
        },
        %EmbedContentRequest{
          model: "models/text-embedding-004",
          content: %Content{role: "user", parts: [%Part{text: "Text 2"}]},
          task_type: :retrieval_query
        }
      ]

      body = Embeddings.build_batch_request_body(requests)

      assert body["requests"]
      assert length(body["requests"]) == 2
      assert Enum.at(body["requests"], 0)["content"]["parts"] == [%{"text" => "Text 1"}]
      assert Enum.at(body["requests"], 1)["taskType"] == "RETRIEVAL_QUERY"
    end
  end

  describe "parse_embedding_response/1" do
    @tag :embedding
    test "parses single embedding response" do
      response = %{
        "embedding" => %{
          "values" => [0.1, 0.2, 0.3, 0.4, 0.5]
        }
      }

      {:ok, embedding} = Embeddings.parse_embedding_response(response)

      assert %ContentEmbedding{} = embedding
      assert embedding.values == [0.1, 0.2, 0.3, 0.4, 0.5]
    end

    test "returns error for invalid response" do
      response = %{"error" => "Invalid"}

      assert {:error, %{reason: :invalid_response}} =
               Embeddings.parse_embedding_response(response)
    end
  end

  describe "parse_batch_response/1" do
    @tag :embedding
    test "parses batch embedding response" do
      response = %{
        "embeddings" => [
          %{"values" => [0.1, 0.2, 0.3]},
          %{"values" => [0.4, 0.5, 0.6]}
        ]
      }

      {:ok, embeddings} = Embeddings.parse_batch_response(response)

      assert length(embeddings) == 2
      assert Enum.at(embeddings, 0).values == [0.1, 0.2, 0.3]
      assert Enum.at(embeddings, 1).values == [0.4, 0.5, 0.6]
    end

    test "returns error for invalid batch response" do
      response = %{"error" => "Invalid"}

      assert {:error, %{reason: :invalid_response}} =
               Embeddings.parse_batch_response(response)
    end
  end

  describe "normalize_model_name/1" do
    test "handles various model name formats" do
      assert Embeddings.normalize_model_name("text-embedding-004") == "models/text-embedding-004"

      assert Embeddings.normalize_model_name("models/text-embedding-004") ==
               "models/text-embedding-004"

      assert Embeddings.normalize_model_name("gemini/text-embedding-004") ==
               "models/text-embedding-004"
    end

    test "handles nil" do
      assert Embeddings.normalize_model_name(nil) == nil
    end
  end
end
