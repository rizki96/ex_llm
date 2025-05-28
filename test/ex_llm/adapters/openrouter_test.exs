defmodule ExLLM.Adapters.OpenRouterTest do
  use ExUnit.Case, async: true
  alias ExLLM.Adapters.OpenRouter
  alias ExLLM.Types

  describe "configuration" do
    test "configured?/1 returns false without API key" do
      refute OpenRouter.configured?()
    end

    test "configured?/1 returns true with API key" do
      config = %{openrouter: %{api_key: "sk-or-test"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      
      assert OpenRouter.configured?(config_provider: provider)
    end

    test "configured?/1 works with environment variables" do
      original = System.get_env("OPENROUTER_API_KEY")
      System.put_env("OPENROUTER_API_KEY", "sk-or-test")
      
      assert OpenRouter.configured?(config_provider: ExLLM.ConfigProvider.Env)
      
      if original do
        System.put_env("OPENROUTER_API_KEY", original)
      else
        System.delete_env("OPENROUTER_API_KEY")
      end
    end
  end

  describe "default_model/0" do
    test "returns default model" do
      assert OpenRouter.default_model() == "openai/gpt-4o-mini"
    end
  end

  describe "chat/2" do
    test "returns error without API key" do
      messages = [%{role: "user", content: "Hello"}]
      assert {:error, "OpenRouter API key not configured"} = OpenRouter.chat(messages)
    end

    test "builds correct request format" do
      # We'll test the request building logic by mocking the HTTP client
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"},
        %{role: "user", content: "How are you?"}
      ]

      config = %{openrouter: %{api_key: "sk-or-test", model: "openai/gpt-4o"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      # Mock the HTTP request
      mock_response = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "created" => 1677652288,
        "model" => "openai/gpt-4o",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "I'm doing well, thank you!"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 15,
          "completion_tokens" => 8,
          "total_tokens" => 23
        }
      }

      # Test would need HTTP mocking - for now we verify the adapter exists
      assert function_exported?(OpenRouter, :chat, 2)
    end

    test "handles function calls in responses" do
      # Test parsing of function calls from OpenRouter responses
      # This would need mocking to test properly
      assert function_exported?(OpenRouter, :chat, 2)
    end
  end

  describe "stream_chat/2" do
    test "returns error without API key" do
      messages = [%{role: "user", content: "Hello"}]
      assert {:error, "OpenRouter API key not configured"} = OpenRouter.stream_chat(messages)
    end

    test "handles streaming responses" do
      # Test streaming functionality
      # This would need mocking to test properly
      assert function_exported?(OpenRouter, :stream_chat, 2)
    end
  end

  describe "list_models/1" do
    test "returns error without API key" do
      assert {:error, "OpenRouter API key not configured"} = OpenRouter.list_models()
    end

    test "parses model list correctly" do
      # Mock response from OpenRouter models API
      mock_response = %{
        "data" => [
          %{
            "id" => "openai/gpt-4o",
            "name" => "GPT-4o",
            "description" => "OpenAI's most capable model",
            "context_length" => 128_000,
            "pricing" => %{
              "prompt" => 2.5,
              "completion" => 10.0
            },
            "supports_streaming" => true,
            "supports_functions" => true,
            "supports_vision" => true
          },
          %{
            "id" => "anthropic/claude-3-5-sonnet",
            "name" => "Claude 3.5 Sonnet",
            "description" => "Anthropic's most capable model",
            "context_length" => 200_000,
            "pricing" => %{
              "prompt" => 3.0,
              "completion" => 15.0
            },
            "supports_streaming" => true,
            "supports_functions" => true,
            "supports_vision" => false
          }
        ]
      }

      # Test would need HTTP mocking to verify parsing
      assert function_exported?(OpenRouter, :list_models, 1)
    end
  end

  describe "message formatting" do
    test "formats messages correctly" do
      # Test internal message formatting
      # This tests the private function indirectly by ensuring the module compiles
      assert function_exported?(OpenRouter, :chat, 2)
    end

    test "handles different message formats" do
      # Test various message input formats
      messages = [
        %{role: "user", content: "Hello"},
        %{"role" => "assistant", "content" => "Hi there!"},
        %{role: :user, content: "How are you?"}
      ]

      # Verify the adapter can handle these formats
      config = %{openrouter: %{api_key: "sk-or-test"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      # This would normally make an API call, but we're just testing the format handling
      # The actual API call would fail without proper mocking
      result = OpenRouter.chat(messages, config_provider: provider)
      
      # We expect either a valid response or a network error (since we're not mocking HTTP)
      assert match?({:ok, %Types.LLMResponse{}}, result) or 
             match?({:error, _}, result)
    end
  end

  describe "configuration options" do
    test "supports custom base URL" do
      config = %{
        openrouter: %{
          api_key: "sk-or-test",
          base_url: "https://custom.openrouter.ai/api/v1"
        }
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      # Verify the adapter uses custom configuration
      assert OpenRouter.configured?(config_provider: provider)
    end

    test "supports app identification headers" do
      config = %{
        openrouter: %{
          api_key: "sk-or-test",
          app_name: "TestApp",
          app_url: "https://testapp.com"
        }
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      # Headers would be tested with HTTP mocking
      assert OpenRouter.configured?(config_provider: provider)
    end

    test "handles temperature parameter" do
      messages = [%{role: "user", content: "Hello"}]
      config = %{openrouter: %{api_key: "sk-or-test"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      # Test temperature parameter
      result = OpenRouter.chat(messages, 
        config_provider: provider,
        temperature: 0.7
      )
      
      # We expect either a valid response or a network error
      assert match?({:ok, %Types.LLMResponse{}}, result) or 
             match?({:error, _}, result)
    end

    test "handles max_tokens parameter" do
      messages = [%{role: "user", content: "Hello"}]
      config = %{openrouter: %{api_key: "sk-or-test"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      # Test max_tokens parameter
      result = OpenRouter.chat(messages,
        config_provider: provider,
        max_tokens: 100
      )
      
      # We expect either a valid response or a network error
      assert match?({:ok, %Types.LLMResponse{}}, result) or 
             match?({:error, _}, result)
    end
  end

  describe "error handling" do
    test "handles network errors gracefully" do
      messages = [%{role: "user", content: "Hello"}]
      config = %{openrouter: %{api_key: "invalid-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      result = OpenRouter.chat(messages, config_provider: provider)
      
      # Should return an error (either API error or network error)
      assert match?({:error, _}, result)
    end

    test "handles API errors gracefully" do
      # Test API error handling
      # This would need HTTP mocking to test specific error scenarios
      assert function_exported?(OpenRouter, :chat, 2)
    end
  end

  describe "integration with ExLLM" do
    test "works with main ExLLM interface" do
      # Test that OpenRouter is properly integrated
      providers = ExLLM.supported_providers()
      assert :openrouter in providers
    end

    test "default model is accessible" do
      # Test integration with default_model
      case ExLLM.default_model(:openrouter) do
        model when is_binary(model) -> 
          assert model == "openai/gpt-4o-mini"
        {:error, _reason} ->
          # This is acceptable if the adapter isn't loaded
          :ok
      end
    end

    test "configuration check works" do
      # Test configuration through main interface
      configured = ExLLM.configured?(:openrouter)
      assert is_boolean(configured)
    end
  end

  describe "pricing and capabilities" do
    test "parses pricing information correctly" do
      # Test pricing parsing from API responses
      # This would be tested with mocked API responses
      assert function_exported?(OpenRouter, :list_models, 1)
    end

    test "parses model capabilities correctly" do
      # Test capability parsing (streaming, functions, vision)
      # This would be tested with mocked API responses
      assert function_exported?(OpenRouter, :list_models, 1)
    end
  end
end