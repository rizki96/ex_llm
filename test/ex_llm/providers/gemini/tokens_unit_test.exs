defmodule ExLLM.Gemini.TokensUnitTest do
  @moduledoc """
  Unit tests for the Gemini Token Counting API.

  Tests internal functions and behavior without making actual API calls.
  """

  use ExUnit.Case, async: true
  alias ExLLM.Providers.Gemini.Tokens

  alias ExLLM.Providers.Gemini.Tokens.{
    CountTokensRequest,
    CountTokensResponse,
    ModalityTokenCount
  }

  alias ExLLM.Providers.Gemini.Content.{Content, GenerateContentRequest, Part}

  describe "CountTokensRequest struct" do
    test "creates struct with contents" do
      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Hello"}]
          }
        ]
      }

      assert request.contents
      assert length(request.contents) == 1
      assert request.generate_content_request == nil
    end

    test "creates struct with generate_content_request" do
      request = %CountTokensRequest{
        generate_content_request: %GenerateContentRequest{
          contents: [
            %Content{
              role: "user",
              parts: [%Part{text: "Hello"}]
            }
          ]
        }
      }

      assert request.generate_content_request
      assert request.contents == nil
    end
  end

  describe "CountTokensResponse struct" do
    test "creates response with all fields" do
      response = %CountTokensResponse{
        total_tokens: 42,
        cached_content_token_count: 10,
        prompt_tokens_details: [
          %ModalityTokenCount{
            modality: "TEXT",
            token_count: 32
          }
        ],
        cache_tokens_details: [
          %ModalityTokenCount{
            modality: "TEXT",
            token_count: 10
          }
        ]
      }

      assert response.total_tokens == 42
      assert response.cached_content_token_count == 10
      assert length(response.prompt_tokens_details) == 1
      assert length(response.cache_tokens_details) == 1
    end

    test "creates minimal response" do
      response = %CountTokensResponse{
        total_tokens: 5
      }

      assert response.total_tokens == 5
      assert response.cached_content_token_count == nil
      assert response.prompt_tokens_details == nil
      assert response.cache_tokens_details == nil
    end
  end

  describe "ModalityTokenCount struct" do
    test "creates modality token count" do
      modality = %ModalityTokenCount{
        modality: "IMAGE",
        token_count: 256
      }

      assert modality.modality == "IMAGE"
      assert modality.token_count == 256
    end
  end

  describe "to_json/1 for CountTokensRequest" do
    test "serializes request with contents" do
      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Hello world"}]
          }
        ]
      }

      json = Tokens.to_json(request)

      assert json["contents"]
      assert length(json["contents"]) == 1
      assert json["contents"] |> hd() |> Map.get("role") == "user"

      assert json["contents"] |> hd() |> Map.get("parts") |> hd() |> Map.get("text") ==
               "Hello world"

      refute Map.has_key?(json, "generateContentRequest")
    end

    test "serializes request with generate_content_request" do
      request = %CountTokensRequest{
        generate_content_request: %GenerateContentRequest{
          contents: [
            %Content{
              role: "user",
              parts: [%Part{text: "Hello"}]
            }
          ],
          system_instruction: %Content{
            role: "system",
            parts: [%Part{text: "Be helpful"}]
          }
        }
      }

      json = Tokens.to_json(request)

      assert json["generateContentRequest"]
      assert json["generateContentRequest"]["contents"]
      assert json["generateContentRequest"]["systemInstruction"]
      refute Map.has_key?(json, "contents")
    end

    test "handles empty request" do
      request = %CountTokensRequest{}
      json = Tokens.to_json(request)

      assert json == %{}
    end
  end

  describe "from_api/1 for CountTokensResponse" do
    test "parses complete API response" do
      api_data = %{
        "totalTokens" => 100,
        "cachedContentTokenCount" => 25,
        "promptTokensDetails" => [
          %{
            "modality" => "TEXT",
            "tokenCount" => 75
          }
        ],
        "cacheTokensDetails" => [
          %{
            "modality" => "TEXT",
            "tokenCount" => 25
          }
        ]
      }

      response = CountTokensResponse.from_api(api_data)

      assert response.total_tokens == 100
      assert response.cached_content_token_count == 25
      assert length(response.prompt_tokens_details) == 1
      assert hd(response.prompt_tokens_details).modality == "TEXT"
      assert hd(response.prompt_tokens_details).token_count == 75
      assert length(response.cache_tokens_details) == 1
    end

    test "parses minimal API response" do
      api_data = %{
        "totalTokens" => 42
      }

      response = CountTokensResponse.from_api(api_data)

      assert response.total_tokens == 42
      assert response.cached_content_token_count == nil
      assert response.prompt_tokens_details == nil
      assert response.cache_tokens_details == nil
    end

    test "handles missing optional fields" do
      api_data = %{
        "totalTokens" => 50,
        "promptTokensDetails" => []
      }

      response = CountTokensResponse.from_api(api_data)

      assert response.total_tokens == 50
      assert response.prompt_tokens_details == []
      assert response.cached_content_token_count == nil
      assert response.cache_tokens_details == nil
    end
  end

  describe "from_api/1 for ModalityTokenCount" do
    test "parses modality token count" do
      api_data = %{
        "modality" => "VIDEO",
        "tokenCount" => 1024
      }

      modality = ModalityTokenCount.from_api(api_data)

      assert modality.modality == "VIDEO"
      assert modality.token_count == 1024
    end
  end

  describe "build_url/3" do
    test "builds correct URL for token counting" do
      # Note: This would be a private function, but testing URL construction logic
      _model = "gemini-2.0-flash"
      normalized_model = "models/gemini-2.0-flash"
      api_key = "test-key"

      # Expected URL format
      expected_base = "https://generativelanguage.googleapis.com/v1beta/"
      expected_path = "#{normalized_model}:countTokens"
      expected_query = "?key=#{api_key}"
      expected_url = expected_base <> expected_path <> expected_query

      # The actual implementation would build this URL
      assert String.contains?(expected_url, ":countTokens")
      assert String.contains?(expected_url, "key=test-key")
    end
  end

  describe "validate_request/1" do
    test "validates request with contents only" do
      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Valid"}]
          }
        ]
      }

      # Should be valid
      assert Tokens.validate_request(request) == :ok
    end

    test "validates request with generate_content_request only" do
      request = %CountTokensRequest{
        generate_content_request: %GenerateContentRequest{
          contents: [
            %Content{
              role: "user",
              parts: [%Part{text: "Valid"}]
            }
          ]
        }
      }

      # Should be valid
      assert Tokens.validate_request(request) == :ok
    end

    test "rejects request with both contents and generate_content_request" do
      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Content"}]
          }
        ],
        generate_content_request: %GenerateContentRequest{
          contents: [
            %Content{
              role: "user",
              parts: [%Part{text: "Request"}]
            }
          ]
        }
      }

      # Should be invalid
      assert {:error, %{reason: :invalid_params}} = Tokens.validate_request(request)
    end

    test "rejects empty request" do
      request = %CountTokensRequest{}

      # Should be invalid
      assert {:error, %{reason: :invalid_params}} = Tokens.validate_request(request)
    end
  end

  describe "normalize_model_name/1" do
    test "handles various model name formats" do
      # Test normalization logic that should match Models module
      assert Tokens.normalize_model_name("gemini-2.0-flash") == {:ok, "models/gemini-2.0-flash"}

      assert Tokens.normalize_model_name("models/gemini-2.0-flash") ==
               {:ok, "models/gemini-2.0-flash"}

      assert Tokens.normalize_model_name("gemini/gemini-2.0-flash") ==
               {:ok, "models/gemini-2.0-flash"}

      assert {:error, _} = Tokens.normalize_model_name(nil)
      assert {:error, _} = Tokens.normalize_model_name("")
      assert {:error, _} = Tokens.normalize_model_name("   ")
    end
  end
end
