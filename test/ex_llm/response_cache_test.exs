defmodule ExLLM.ResponseCacheTest do
  use ExUnit.Case, async: false
  alias ExLLM.Providers.Mock
  alias ExLLM.CachingInterceptor
  alias ExLLM.ResponseCache

  @moduletag :cache_test

  setup do
    # Ensure clean state
    Mock.reset()

    # Set test cache directory
    test_cache_dir = Path.join(System.tmp_dir(), "ex_llm_test_cache_#{:rand.uniform(1000)}")
    System.put_env("EX_LLM_CACHE_DIR", test_cache_dir)
    System.put_env("EX_LLM_CACHE_RESPONSES", "true")

    on_exit(fn ->
      # Clean up test cache
      if File.exists?(test_cache_dir) do
        File.rm_rf!(test_cache_dir)
      end

      System.delete_env("EX_LLM_CACHE_DIR")
      System.delete_env("EX_LLM_CACHE_RESPONSES")
    end)

    {:ok, cache_dir: test_cache_dir}
  end

  describe "response caching" do
    test "stores and retrieves responses" do
      # Store a mock response
      request_data = %{
        messages: [%{role: "user", content: "Hello"}],
        model: "gpt-3.5-turbo"
      }

      response_data = %{
        "choices" => [
          %{
            "message" => %{
              "content" => "Hello! How can I help you?",
              "role" => "assistant"
            },
            "finish_reason" => "stop"
          }
        ],
        "model" => "gpt-3.5-turbo",
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 8,
          "total_tokens" => 18
        }
      }

      # Store the response
      assert :ok = ResponseCache.store_response("openai", "chat", request_data, response_data)

      # Retrieve the response
      cached_entry = ResponseCache.get_response("openai", "chat", request_data)
      assert cached_entry != nil
      assert cached_entry.provider == "openai"
      assert cached_entry.endpoint == "chat"

      # Response data should be similar but keys may have been converted
      assert get_in(cached_entry.response_data, [:choices, Access.at(0), :message, :content]) ==
               "Hello! How can I help you?"

      assert cached_entry.response_data[:model] == "gpt-3.5-turbo"
    end

    test "handles provider responses loading" do
      # Store multiple responses for a provider
      for i <- 1..3 do
        request = %{messages: [%{role: "user", content: "Test #{i}"}]}
        response = %{"choices" => [%{"message" => %{"content" => "Response #{i}"}}]}

        ResponseCache.store_response("test_provider", "chat", request, response)
      end

      # Load all responses for the provider
      responses = ResponseCache.load_provider_responses("test_provider")
      assert length(responses) == 3

      # Check they're properly structured
      assert Enum.all?(responses, &match?(%ResponseCache.CacheEntry{}, &1))
    end

    test "lists cached providers" do
      # Store responses for multiple providers
      ResponseCache.store_response("openai", "chat", %{test: "data1"}, %{response: "1"})
      ResponseCache.store_response("anthropic", "messages", %{test: "data2"}, %{response: "2"})

      providers = ResponseCache.list_cached_providers()
      provider_names = Enum.map(providers, fn {name, _count} -> name end)

      assert "openai" in provider_names
      assert "anthropic" in provider_names
    end

    test "configures mock adapter with cached responses" do
      # Store a response
      request_data = %{
        messages: [%{role: "user", content: "What is 2+2?"}],
        model: "gpt-3.5-turbo"
      }

      response_data = %{
        "choices" => [
          %{
            "message" => %{
              "content" => "2+2 equals 4",
              "role" => "assistant"
            },
            "finish_reason" => "stop"
          }
        ],
        "model" => "gpt-3.5-turbo",
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 6
        }
      }

      ResponseCache.store_response("openai", "chat", request_data, response_data)

      # Configure mock to use cached responses
      assert :ok = ResponseCache.configure_mock_provider("openai")

      # Test that mock now returns cached response with same request structure
      messages = [%{role: "user", content: "What is 2+2?"}]
      {:ok, response} = Mock.chat(messages, model: "gpt-3.5-turbo")

      assert response.content == "2+2 equals 4"
      assert response.model == "gpt-3.5-turbo"
    end

    test "caching interceptor wraps function calls" do
      # Create a simple function that returns a mock response
      test_function = fn ->
        {:ok,
         %ExLLM.Types.LLMResponse{
           content: "Intercepted response",
           model: "test-model",
           usage: %{input_tokens: 10, output_tokens: 15}
         }}
      end

      # Wrap with caching
      {:ok, response} = CachingInterceptor.with_caching(:test_provider, test_function)

      assert response.content == "Intercepted response"
      assert response.model == "test-model"

      # Verify it was cached
      # Empty since we can't capture the actual request in this simple test
      request_data = %{}
      cached = ResponseCache.get_response("test_provider", "chat_completions", request_data)
      assert cached != nil
    end

    test "handles streaming cache correctly" do
      # Create mock stream chunks
      chunks = [
        %ExLLM.Types.StreamChunk{content: "Hello", finish_reason: nil, model: "test-model"},
        %ExLLM.Types.StreamChunk{content: " there", finish_reason: nil, model: "test-model"},
        %ExLLM.Types.StreamChunk{
          content: "!",
          finish_reason: "stop",
          model: "test-model",
          id: "test-123"
        }
      ]

      test_stream_function = fn ->
        {:ok,
         Stream.resource(
           fn -> chunks end,
           fn
             [] -> {:halt, []}
             [chunk | rest] -> {[chunk], rest}
           end,
           fn _ -> :ok end
         )}
      end

      messages = [%{role: "user", content: "Hello"}]
      options = [model: "test-model"]

      # Wrap streaming with cache
      {:ok, stream} =
        CachingInterceptor.with_streaming_cache(
          :test_provider,
          messages,
          options,
          test_stream_function
        )

      # Consume the stream
      result_chunks = Enum.to_list(stream)
      assert length(result_chunks) == 3
      assert Enum.map(result_chunks, & &1.content) == ["Hello", " there", "!"]

      # Verify streaming response was cached (try exact match first, then fuzzy)
      cached =
        ResponseCache.get_response("test_provider", "streaming", %{
          messages: messages,
          model: "test-model"
        })

      assert cached != nil

      assert cached.response_data[:streaming_chunks] != nil or
               cached.response_data["streaming_chunks"] != nil

      assert cached.response_data[:choices] != nil or cached.response_data["choices"] != nil
    end

    test "mock adapter can use different cached providers" do
      # Store different responses for different providers
      openai_response = %{
        "choices" => [%{"message" => %{"content" => "OpenAI response"}}],
        "model" => "gpt-3.5-turbo"
      }

      anthropic_response = %{
        "content" => [%{"text" => "Anthropic response"}],
        "model" => "claude-3-sonnet",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
      }

      request = %{messages: [%{role: "user", content: "Hello"}]}

      ResponseCache.store_response("openai", "chat", request, openai_response)
      ResponseCache.store_response("anthropic", "chat", request, anthropic_response)

      # Test OpenAI cached responses
      assert :ok = ResponseCache.configure_mock_provider("openai")
      {:ok, response1} = Mock.chat([%{role: "user", content: "Hello"}])
      assert response1.content == "OpenAI response"

      # Switch to Anthropic cached responses
      assert :ok = ResponseCache.configure_mock_provider("anthropic")
      {:ok, response2} = Mock.chat([%{role: "user", content: "Hello"}])
      assert response2.content == "Anthropic response"
    end

    test "handles cache miss gracefully" do
      # Configure mock with empty cache
      assert :no_cache = ResponseCache.configure_mock_provider("nonexistent_provider")

      # Mock should still work with default responses
      {:ok, response} = Mock.chat([%{role: "user", content: "Hello"}])
      assert is_binary(response.content)
    end

    test "caching can be disabled" do
      # Disable caching
      System.put_env("EX_LLM_CACHE_RESPONSES", "false")

      # Try to store a response
      result = ResponseCache.store_response("test", "endpoint", %{}, %{})
      assert result == :disabled

      # Re-enable for other tests
      System.put_env("EX_LLM_CACHE_RESPONSES", "true")
    end
  end

  describe "test scenario collection" do
    test "collect_test_responses works with mock provider" do
      # Set up mock to return predictable responses
      Mock.set_response_handler(fn messages, _options ->
        user_message = List.last(messages)
        %{content: "Mock response to: #{user_message.content}"}
      end)

      test_cases = [
        {[%{role: "user", content: "Hello"}], []},
        {[%{role: "user", content: "What is 2+2?"}], [max_tokens: 10]}
      ]

      results = CachingInterceptor.collect_test_responses(:mock, test_cases)

      assert length(results) == 2
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    test "create_test_collection organizes responses by category" do
      # Set up mock for consistent responses
      Mock.set_response_handler(fn messages, _options ->
        user_message = List.last(messages)

        content =
          if is_binary(user_message.content), do: user_message.content, else: "complex content"

        %{content: "Response to: #{content}"}
      end)

      # Note: This will call the actual collection functions
      # but they'll use the mock adapter, so no real API calls
      results = CachingInterceptor.create_test_collection(:mock)

      assert is_map(results)
      assert Map.has_key?(results, :basic_chat)
      assert Map.has_key?(results, :streaming)
      assert Map.has_key?(results, :function_calling)
      assert Map.has_key?(results, :multimodal)
      assert Map.has_key?(results, :error_scenarios)
    end
  end

  describe "response format conversion" do
    test "converts different provider response formats" do
      # This tests the private conversion functions indirectly
      openai_response = %{
        "choices" => [
          %{
            "message" => %{"content" => "Hello from OpenAI"},
            "finish_reason" => "stop"
          }
        ],
        "model" => "gpt-3.5-turbo",
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 8}
      }

      request_data = %{messages: [%{role: "user", content: "test"}]}
      ResponseCache.store_response("openai", "chat", request_data, openai_response)
      ResponseCache.configure_mock_provider("openai")

      {:ok, response} = Mock.chat([%{role: "user", content: "test"}])
      assert response.content == "Hello from OpenAI"
      assert response.model == "gpt-3.5-turbo"
    end
  end
end
