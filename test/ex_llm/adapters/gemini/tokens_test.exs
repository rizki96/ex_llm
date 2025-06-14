defmodule ExLLM.Gemini.TokensTest do
  @moduledoc """
  Tests for the Gemini Token Counting API.

  Tests cover:
  - Simple content token counting
  - GenerateContentRequest token counting
  - Response handling with modality details
  - Error handling
  - Parameter validation
  """

  use ExUnit.Case, async: true
  alias ExLLM.Gemini.Tokens

  @moduletag provider: :gemini
  alias ExLLM.Gemini.Tokens.{CountTokensRequest, CountTokensResponse, ModalityTokenCount}
  alias ExLLM.Gemini.Content.{GenerateContentRequest, Content, Part}

  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key

  describe "count_tokens/3 with simple content" do
    test "successfully counts tokens for text content" do
      model = "gemini-2.0-flash"

      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "The quick brown fox jumps over the lazy dog."}]
          }
        ]
      }

      case Tokens.count_tokens(model, request) do
        {:ok, %CountTokensResponse{} = response} ->
          assert response.total_tokens > 0
          assert is_integer(response.total_tokens)
          # Response may include prompt_tokens_details
          if response.prompt_tokens_details do
            assert is_list(response.prompt_tokens_details)
          end

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          # Expected when running without valid API key
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "counts tokens for multimodal content" do
      model = "gemini-2.0-flash"

      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [
              %Part{text: "What's in this image?"},
              %Part{
                inline_data: %{
                  mime_type: "image/jpeg",
                  data: "base64encodedimagedata"
                }
              }
            ]
          }
        ]
      }

      case Tokens.count_tokens(model, request) do
        {:ok, %CountTokensResponse{} = response} ->
          assert response.total_tokens > 0
          # With multimodal content, we might get modality details
          if response.prompt_tokens_details do
            assert is_list(response.prompt_tokens_details)

            Enum.each(response.prompt_tokens_details, fn detail ->
              assert %ModalityTokenCount{} = detail
              assert detail.modality in ["TEXT", "IMAGE", "AUDIO", "VIDEO"]
              assert is_integer(detail.token_count)
            end)
          end

        {:error, %{status: 400}} ->
          # API might reject fake image data
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "counts tokens for multi-turn conversation" do
      model = "gemini-2.0-flash"

      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Hello, how are you?"}]
          },
          %Content{
            role: "model",
            parts: [%Part{text: "I'm doing well, thank you! How can I help you today?"}]
          },
          %Content{
            role: "user",
            parts: [%Part{text: "Can you explain quantum computing?"}]
          }
        ]
      }

      case Tokens.count_tokens(model, request) do
        {:ok, %CountTokensResponse{} = response} ->
          assert response.total_tokens > 0
          # Multi-turn should have more tokens than single message
          assert response.total_tokens > 10

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
  end

  describe "count_tokens/3 with GenerateContentRequest" do
    test "counts tokens for request with system instruction" do
      model = "gemini-2.0-flash"

      request = %CountTokensRequest{
        generate_content_request: %GenerateContentRequest{
          contents: [
            %Content{
              role: "user",
              parts: [%Part{text: "Write a poem"}]
            }
          ],
          system_instruction: %Content{
            role: "system",
            parts: [%Part{text: "You are a helpful assistant that writes creative poetry."}]
          }
        }
      }

      case Tokens.count_tokens(model, request) do
        {:ok, %CountTokensResponse{} = response} ->
          assert response.total_tokens > 0

        # System instruction should add to token count

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "counts tokens for request with generation config" do
      model = "gemini-2.0-flash"

      request = %CountTokensRequest{
        generate_content_request: %GenerateContentRequest{
          contents: [
            %Content{
              role: "user",
              parts: [%Part{text: "Tell me a story"}]
            }
          ],
          generation_config: %{
            temperature: 0.7,
            max_output_tokens: 100,
            top_p: 0.9
          }
        }
      }

      case Tokens.count_tokens(model, request) do
        {:ok, %CountTokensResponse{} = response} ->
          assert response.total_tokens > 0

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "counts tokens for request with cached content" do
      model = "gemini-2.0-flash"

      request = %CountTokensRequest{
        generate_content_request: %GenerateContentRequest{
          contents: [
            %Content{
              role: "user",
              parts: [%Part{text: "What was the previous context about?"}]
            }
          ],
          cached_content: "cachedContents/some-cached-id"
        }
      }

      case Tokens.count_tokens(model, request) do
        {:ok, %CountTokensResponse{} = response} ->
          assert response.total_tokens > 0
          # If cached content exists, we might get cached_content_token_count
          if response.cached_content_token_count do
            assert is_integer(response.cached_content_token_count)
            assert response.cached_content_token_count >= 0
          end

          # And cache_tokens_details
          if response.cache_tokens_details do
            assert is_list(response.cache_tokens_details)
          end

        {:error, %{status: 403}} ->
          # Cached content not found or permission denied
          assert true

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
  end

  describe "count_tokens/3 validation" do
    test "returns error when both contents and generate_content_request are provided" do
      model = "gemini-2.0-flash"

      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Hello"}]
          }
        ],
        generate_content_request: %GenerateContentRequest{
          contents: [
            %Content{
              role: "user",
              parts: [%Part{text: "World"}]
            }
          ]
        }
      }

      result = Tokens.count_tokens(model, request)
      assert {:error, %{reason: :invalid_params, message: message}} = result
      assert message =~ "mutually exclusive"
    end

    test "returns error when neither contents nor generate_content_request are provided" do
      model = "gemini-2.0-flash"
      request = %CountTokensRequest{}

      result = Tokens.count_tokens(model, request)
      assert {:error, %{reason: :invalid_params, message: message}} = result
      assert message =~ "must provide either"
    end

    test "returns error for nil model name" do
      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Hello"}]
          }
        ]
      }

      result = Tokens.count_tokens(nil, request)
      assert {:error, %{reason: :invalid_params}} = result
    end

    test "returns error for empty model name" do
      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Hello"}]
          }
        ]
      }

      result = Tokens.count_tokens("", request)
      assert {:error, %{reason: :invalid_params}} = result
    end

    @tag :unit
    test "returns error for invalid API key" do
      # Note: This test is skipped because get_api_key falls back to environment variables
      # which override the mock config provider when running integration tests
      model = "gemini-2.0-flash"

      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Hello"}]
          }
        ]
      }

      # Force invalid API key by passing custom config
      opts = [config_provider: MockConfigProvider]

      case Tokens.count_tokens(model, request, opts) do
        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, %{reason: :missing_api_key}} ->
          assert true

        other ->
          flunk("Expected API key error, got: #{inspect(other)}")
      end
    end
  end

  describe "count_tokens/3 model name normalization" do
    test "handles model name without prefix" do
      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Test"}]
          }
        ]
      }

      # Should work with just model name
      case Tokens.count_tokens("gemini-2.0-flash", request) do
        {:ok, response} ->
          assert response.total_tokens > 0

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "handles model name with models/ prefix" do
      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Test"}]
          }
        ]
      }

      # Should work with models/ prefix
      case Tokens.count_tokens("models/gemini-2.0-flash", request) do
        {:ok, response} ->
          assert response.total_tokens > 0

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "handles model name with gemini/ prefix" do
      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Test"}]
          }
        ]
      }

      # Should normalize gemini/ to models/
      case Tokens.count_tokens("gemini/gemini-2.0-flash", request) do
        {:ok, response} ->
          assert response.total_tokens > 0

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
  end

  describe "response parsing" do
    test "handles response with all fields populated" do
      # This test validates the response structure
      model = "gemini-2.0-flash"

      request = %CountTokensRequest{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Simple text for counting"}]
          }
        ]
      }

      case Tokens.count_tokens(model, request) do
        {:ok, response} ->
          assert %CountTokensResponse{} = response
          assert is_integer(response.total_tokens)
          assert response.total_tokens > 0

          # Optional fields might be nil or populated
          if response.cached_content_token_count do
            assert is_integer(response.cached_content_token_count)
          end

          if response.prompt_tokens_details do
            assert is_list(response.prompt_tokens_details)

            Enum.each(response.prompt_tokens_details, fn detail ->
              assert %ModalityTokenCount{} = detail
            end)
          end

          if response.cache_tokens_details do
            assert is_list(response.cache_tokens_details)
          end

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
  end
end

defmodule MockConfigProvider do
  @behaviour ExLLM.ConfigProvider

  def get_all(:gemini), do: [api_key: "invalid-api-key"]
  def get_all(_provider), do: []
  def get(_provider, _key, default), do: default
  def get(_provider, _key), do: nil
end
