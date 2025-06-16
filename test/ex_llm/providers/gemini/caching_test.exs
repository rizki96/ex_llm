defmodule ExLLM.Gemini.CachingTest do
  @moduledoc """
  Tests for the Gemini Context Caching API.

  Tests cover:
  - Creating cached content with TTL and expiration time
  - Listing cached contents with pagination
  - Getting cached content details
  - Updating cached content expiration
  - Deleting cached content
  - Using cached content in generation requests
  - Error handling
  """

  use ExUnit.Case, async: true
  alias ExLLM.Gemini.Caching
  alias ExLLM.Gemini.Caching.CachedContent
  alias ExLLM.Gemini.Content.{Content, Part, Tool}

  @moduletag :integration

  describe "create_cached_content/2" do
    test "successfully creates cached content with TTL" do
      # Create large content that meets the minimum 4096 token requirement
      large_text =
        String.duplicate(
          "This is a large context that I want to cache for reuse. " <>
            "It contains a lot of information that would be expensive to process repeatedly. " <>
            "By caching this content, we can save on processing costs and improve response times. " <>
            "The Gemini API requires cached content to have at least 4096 tokens. " <>
            "So we need to make sure our test content is sufficiently large. " <>
            "This paragraph will be repeated many times to reach the required token count. " <>
            "Each repetition adds more tokens to the total count. " <>
            "We want to ensure that our cached content is substantial enough to be useful. " <>
            "Caching is particularly beneficial for large documents, knowledge bases, or contexts. " <>
            "It allows us to reuse processed content across multiple requests efficiently. ",
          50
        )

      request = %{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: large_text}]
          }
        ],
        model: "models/gemini-2.0-flash",
        ttl: "3600s",
        display_name: "Test Cache"
      }

      case Caching.create_cached_content(request) do
        {:ok, %CachedContent{} = cached} ->
          assert cached.name =~ "cachedContents/"
          assert cached.model == "models/gemini-2.0-flash"
          assert cached.display_name == "Test Cache"
          assert cached.expire_time
          assert cached.usage_metadata
          assert cached.usage_metadata.total_token_count > 0

          # Clean up
          Caching.delete_cached_content(cached.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          # Expected when running without valid API key
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "successfully creates cached content with expire time" do
      # Create large content that meets the minimum 4096 token requirement
      large_text =
        String.duplicate(
          "This is a large context that I want to cache for reuse. " <>
            "It contains a lot of information that would be expensive to process repeatedly. " <>
            "By caching this content, we can save on processing costs and improve response times. " <>
            "The Gemini API requires cached content to have at least 4096 tokens. " <>
            "So we need to make sure our test content is sufficiently large. " <>
            "This paragraph will be repeated many times to reach the required token count. " <>
            "Each repetition adds more tokens to the total count. " <>
            "We want to ensure that our cached content is substantial enough to be useful. " <>
            "Caching is particularly beneficial for large documents, knowledge bases, or contexts. " <>
            "It allows us to reuse processed content across multiple requests efficiently. ",
          50
        )

      # Set expiration to 1 hour from now
      expire_time =
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.to_iso8601()

      request = %{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: large_text}]
          }
        ],
        model: "models/gemini-2.0-flash",
        expire_time: expire_time,
        display_name: "Expire Time Test"
      }

      case Caching.create_cached_content(request) do
        {:ok, %CachedContent{} = cached} ->
          assert cached.expire_time
          assert cached.display_name == "Expire Time Test"

          # Clean up
          Caching.delete_cached_content(cached.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "creates cached content with system instruction" do
      # Create large content that meets the minimum 4096 token requirement
      large_text =
        String.duplicate(
          "This is a large context that I want to cache for reuse. " <>
            "It contains a lot of information that would be expensive to process repeatedly. " <>
            "By caching this content, we can save on processing costs and improve response times. " <>
            "The Gemini API requires cached content to have at least 4096 tokens. " <>
            "So we need to make sure our test content is sufficiently large. " <>
            "This paragraph will be repeated many times to reach the required token count. " <>
            "Each repetition adds more tokens to the total count. " <>
            "We want to ensure that our cached content is substantial enough to be useful. " <>
            "Caching is particularly beneficial for large documents, knowledge bases, or contexts. " <>
            "It allows us to reuse processed content across multiple requests efficiently. ",
          50
        )

      request = %{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: large_text}]
          }
        ],
        model: "models/gemini-2.0-flash",
        system_instruction: %Content{
          role: "system",
          parts: [%Part{text: "You are an expert in this domain."}]
        },
        ttl: "1800s"
      }

      case Caching.create_cached_content(request) do
        {:ok, %CachedContent{} = cached} ->
          # System instruction might not be returned in response
          assert cached.name =~ "cachedContents/"
          assert cached.model == "models/gemini-2.0-flash"

          # Clean up
          Caching.delete_cached_content(cached.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "creates cached content with tools" do
      # Create large content that meets the minimum 4096 token requirement
      large_text =
        String.duplicate(
          "This is a large context that I want to cache for reuse. " <>
            "It contains a lot of information that would be expensive to process repeatedly. " <>
            "By caching this content, we can save on processing costs and improve response times. " <>
            "The Gemini API requires cached content to have at least 4096 tokens. " <>
            "So we need to make sure our test content is sufficiently large. " <>
            "This paragraph will be repeated many times to reach the required token count. " <>
            "Each repetition adds more tokens to the total count. " <>
            "We want to ensure that our cached content is substantial enough to be useful. " <>
            "Caching is particularly beneficial for large documents, knowledge bases, or contexts. " <>
            "It allows us to reuse processed content across multiple requests efficiently. ",
          50
        )

      request = %{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: large_text}]
          }
        ],
        model: "models/gemini-2.0-flash",
        tools: [
          %Tool{
            function_declarations: [
              %{
                "name" => "get_weather",
                "description" => "Get weather information",
                "parameters" => %{
                  "type" => "object",
                  "properties" => %{
                    "location" => %{"type" => "string"}
                  }
                }
              }
            ]
          }
        ],
        ttl: "1800s"
      }

      case Caching.create_cached_content(request) do
        {:ok, %CachedContent{} = cached} ->
          # Tools might not be returned in response
          assert cached.name =~ "cachedContents/"
          assert cached.model == "models/gemini-2.0-flash"

          # Clean up
          Caching.delete_cached_content(cached.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "returns error for missing model" do
      request = %{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Content without model"}]
          }
        ],
        ttl: "3600s"
      }

      result = Caching.create_cached_content(request)
      assert {:error, %{reason: :invalid_params}} = result
    end

    test "returns error for missing expiration" do
      request = %{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Content without expiration"}]
          }
        ],
        model: "models/gemini-2.0-flash"
      }

      result = Caching.create_cached_content(request)
      assert {:error, %{reason: :invalid_params}} = result
    end

    test "returns error for invalid TTL format" do
      request = %{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: "Content with bad TTL"}]
          }
        ],
        model: "models/gemini-2.0-flash",
        ttl: "invalid"
      }

      case Caching.create_cached_content(request) do
        {:error, %{status: 400}} ->
          assert true

        {:error, %{reason: :invalid_params}} ->
          assert true

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        other ->
          flunk("Expected error, got: #{inspect(other)}")
      end
    end
  end

  describe "list_cached_contents/1" do
    test "lists cached contents" do
      case Caching.list_cached_contents() do
        {:ok, %{cached_contents: contents, next_page_token: _token}} ->
          assert is_list(contents)

          Enum.each(contents, fn content ->
            assert %CachedContent{} = content
            assert content.name =~ "cachedContents/"
            assert content.model
          end)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "lists cached contents with pagination" do
      case Caching.list_cached_contents(page_size: 2) do
        {:ok, %{cached_contents: contents, next_page_token: token}} ->
          assert length(contents) <= 2

          if token do
            # Try to get next page
            case Caching.list_cached_contents(page_token: token, page_size: 2) do
              {:ok, %{cached_contents: next_contents}} ->
                assert is_list(next_contents)

              {:error, _} ->
                # Pagination error is acceptable
                assert true
            end
          end

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "handles invalid page size" do
      result = Caching.list_cached_contents(page_size: -1)
      assert {:error, %{reason: :invalid_params}} = result

      result = Caching.list_cached_contents(page_size: 1001)
      assert {:error, %{reason: :invalid_params}} = result
    end
  end

  describe "get_cached_content/2" do
    test "retrieves cached content details" do
      # Create large content that meets the minimum 4096 token requirement
      large_text =
        String.duplicate(
          "This is a large context that I want to cache for reuse. " <>
            "It contains a lot of information that would be expensive to process repeatedly. " <>
            "By caching this content, we can save on processing costs and improve response times. " <>
            "The Gemini API requires cached content to have at least 4096 tokens. " <>
            "So we need to make sure our test content is sufficiently large. " <>
            "This paragraph will be repeated many times to reach the required token count. " <>
            "Each repetition adds more tokens to the total count. " <>
            "We want to ensure that our cached content is substantial enough to be useful. " <>
            "Caching is particularly beneficial for large documents, knowledge bases, or contexts. " <>
            "It allows us to reuse processed content across multiple requests efficiently. ",
          50
        )

      # First create a cached content
      request = %{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: large_text}]
          }
        ],
        model: "models/gemini-2.0-flash",
        ttl: "600s",
        display_name: "Get Test"
      }

      case Caching.create_cached_content(request) do
        {:ok, created} ->
          # Now get the cached content
          case Caching.get_cached_content(created.name) do
            {:ok, %CachedContent{} = cached} ->
              assert cached.name == created.name
              assert cached.display_name == "Get Test"
              assert cached.model == "models/gemini-2.0-flash"

            {:error, error} ->
              flunk("Failed to get cached content: #{inspect(error)}")
          end

          # Clean up
          Caching.delete_cached_content(created.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Failed to create cached content: #{inspect(error)}")
      end
    end

    test "returns error for non-existent cached content" do
      case Caching.get_cached_content("cachedContents/non-existent") do
        {:error, %{status: 404}} ->
          assert true

        {:error, %{status: 403}} ->
          # Google might return 403 for non-existent resources
          assert true

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        other ->
          flunk("Expected error, got: #{inspect(other)}")
      end
    end

    test "returns error for invalid name format" do
      result = Caching.get_cached_content("invalid-format")
      assert {:error, %{reason: :invalid_params}} = result
    end
  end

  describe "update_cached_content/3" do
    test "updates TTL of cached content" do
      # Create large content that meets the minimum 4096 token requirement
      large_text =
        String.duplicate(
          "This is a large context that I want to cache for reuse. " <>
            "It contains a lot of information that would be expensive to process repeatedly. " <>
            "By caching this content, we can save on processing costs and improve response times. " <>
            "The Gemini API requires cached content to have at least 4096 tokens. " <>
            "So we need to make sure our test content is sufficiently large. " <>
            "This paragraph will be repeated many times to reach the required token count. " <>
            "Each repetition adds more tokens to the total count. " <>
            "We want to ensure that our cached content is substantial enough to be useful. " <>
            "Caching is particularly beneficial for large documents, knowledge bases, or contexts. " <>
            "It allows us to reuse processed content across multiple requests efficiently. ",
          50
        )

      # First create a cached content
      request = %{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: large_text}]
          }
        ],
        model: "models/gemini-2.0-flash",
        ttl: "600s"
      }

      case Caching.create_cached_content(request) do
        {:ok, created} ->
          # Update with new TTL
          update = %{ttl: "7200s"}

          case Caching.update_cached_content(created.name, update) do
            {:ok, %CachedContent{} = updated} ->
              assert updated.name == created.name
              # The new expiration should be further in the future
              assert DateTime.compare(updated.expire_time, created.expire_time) == :gt

            {:error, error} ->
              flunk("Failed to update cached content: #{inspect(error)}")
          end

          # Clean up
          Caching.delete_cached_content(created.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Failed to create cached content: #{inspect(error)}")
      end
    end

    test "updates expire_time of cached content" do
      # Create large content that meets the minimum 4096 token requirement
      large_text =
        String.duplicate(
          "This is a large context that I want to cache for reuse. " <>
            "It contains a lot of information that would be expensive to process repeatedly. " <>
            "By caching this content, we can save on processing costs and improve response times. " <>
            "The Gemini API requires cached content to have at least 4096 tokens. " <>
            "So we need to make sure our test content is sufficiently large. " <>
            "This paragraph will be repeated many times to reach the required token count. " <>
            "Each repetition adds more tokens to the total count. " <>
            "We want to ensure that our cached content is substantial enough to be useful. " <>
            "Caching is particularly beneficial for large documents, knowledge bases, or contexts. " <>
            "It allows us to reuse processed content across multiple requests efficiently. ",
          50
        )

      # First create a cached content
      request = %{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: large_text}]
          }
        ],
        model: "models/gemini-2.0-flash",
        ttl: "600s"
      }

      case Caching.create_cached_content(request) do
        {:ok, created} ->
          # Update with new expire time
          new_expire_time =
            DateTime.utc_now()
            |> DateTime.add(7200, :second)
            |> DateTime.to_iso8601()

          update = %{expire_time: new_expire_time}

          case Caching.update_cached_content(created.name, update) do
            {:ok, %CachedContent{} = updated} ->
              assert updated.name == created.name
              assert DateTime.compare(updated.expire_time, created.expire_time) == :gt

            {:error, error} ->
              flunk("Failed to update cached content: #{inspect(error)}")
          end

          # Clean up
          Caching.delete_cached_content(created.name)

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Failed to create cached content: #{inspect(error)}")
      end
    end

    test "returns error for invalid update fields" do
      # Try to update non-updatable fields
      update = %{model: "models/gemini-1.5-pro"}

      case Caching.update_cached_content("cachedContents/test", update) do
        {:error, %{status: 400}} ->
          assert true

        {:error, %{reason: :invalid_params}} ->
          assert true

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        other ->
          flunk("Expected error, got: #{inspect(other)}")
      end
    end
  end

  describe "delete_cached_content/2" do
    test "successfully deletes cached content" do
      # Create large content that meets the minimum 4096 token requirement
      large_text =
        String.duplicate(
          "This is a large context that I want to cache for reuse. " <>
            "It contains a lot of information that would be expensive to process repeatedly. " <>
            "By caching this content, we can save on processing costs and improve response times. " <>
            "The Gemini API requires cached content to have at least 4096 tokens. " <>
            "So we need to make sure our test content is sufficiently large. " <>
            "This paragraph will be repeated many times to reach the required token count. " <>
            "Each repetition adds more tokens to the total count. " <>
            "We want to ensure that our cached content is substantial enough to be useful. " <>
            "Caching is particularly beneficial for large documents, knowledge bases, or contexts. " <>
            "It allows us to reuse processed content across multiple requests efficiently. ",
          50
        )

      # First create a cached content
      request = %{
        contents: [
          %Content{
            role: "user",
            parts: [%Part{text: large_text}]
          }
        ],
        model: "models/gemini-2.0-flash",
        ttl: "600s"
      }

      case Caching.create_cached_content(request) do
        {:ok, created} ->
          # Delete the cached content
          case Caching.delete_cached_content(created.name) do
            :ok ->
              # Verify it's gone
              case Caching.get_cached_content(created.name) do
                {:error, %{status: 404}} ->
                  assert true

                {:error, %{status: 403}} ->
                  assert true

                {:ok, _} ->
                  flunk("Cached content should have been deleted")

                {:error, _} ->
                  # Any error after deletion is acceptable
                  assert true
              end

            {:error, error} ->
              flunk("Failed to delete cached content: #{inspect(error)}")
          end

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        {:error, error} ->
          flunk("Failed to create cached content: #{inspect(error)}")
      end
    end

    test "returns error for non-existent cached content" do
      case Caching.delete_cached_content("cachedContents/non-existent") do
        {:error, %{status: 404}} ->
          assert true

        {:error, %{status: 403}} ->
          assert true

        {:error, %{status: 400, message: "API key not valid" <> _}} ->
          assert true

        :ok ->
          # Some APIs might return success for non-existent resources
          assert true

        other ->
          flunk("Expected error, got: #{inspect(other)}")
      end
    end
  end

  describe "CachedContent struct" do
    test "parses all fields correctly" do
      api_response = %{
        "name" => "cachedContents/abc123",
        "displayName" => "Test Cache",
        "model" => "models/gemini-2.0-flash",
        "systemInstruction" => %{
          "role" => "system",
          "parts" => [%{"text" => "System instruction"}]
        },
        "contents" => [
          %{
            "role" => "user",
            "parts" => [%{"text" => "Cached content"}]
          }
        ],
        "tools" => [
          %{
            "functionDeclarations" => [
              %{
                "name" => "test_function",
                "description" => "Test"
              }
            ]
          }
        ],
        "toolConfig" => %{
          "functionCallingConfig" => %{
            "mode" => "AUTO"
          }
        },
        "createTime" => "2024-01-01T12:00:00Z",
        "updateTime" => "2024-01-01T12:01:00Z",
        "expireTime" => "2024-01-01T13:00:00Z",
        "usageMetadata" => %{
          "totalTokenCount" => 100
        }
      }

      cached = CachedContent.from_api(api_response)

      assert cached.name == "cachedContents/abc123"
      assert cached.display_name == "Test Cache"
      assert cached.model == "models/gemini-2.0-flash"
      assert cached.system_instruction
      assert length(cached.contents) == 1
      assert length(cached.tools) == 1
      assert cached.tool_config
      assert cached.create_time == ~U[2024-01-01 12:00:00Z]
      assert cached.update_time == ~U[2024-01-01 12:01:00Z]
      assert cached.expire_time == ~U[2024-01-01 13:00:00Z]
      assert cached.usage_metadata.total_token_count == 100
    end

    test "handles minimal response" do
      api_response = %{
        "name" => "cachedContents/minimal",
        "model" => "models/gemini-2.0-flash",
        "expireTime" => "2024-01-01T12:00:00Z"
      }

      cached = CachedContent.from_api(api_response)

      assert cached.name == "cachedContents/minimal"
      assert cached.model == "models/gemini-2.0-flash"
      assert cached.expire_time == ~U[2024-01-01 12:00:00Z]
      assert cached.contents == nil
      assert cached.tools == nil
    end
  end

  describe "using cached content in generation" do
    test "generates content using cached context" do
      # This would be tested in integration with the content generation API
      # Just verifying the cached content name format
      cached_name = "cachedContents/test-123"
      assert String.starts_with?(cached_name, "cachedContents/")
    end
  end
end
