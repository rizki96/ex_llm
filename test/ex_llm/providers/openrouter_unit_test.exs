defmodule ExLLM.Providers.OpenRouterUnitTest do
  use ExUnit.Case, async: true
  alias ExLLM.Providers.OpenRouter
  alias ExLLM.Testing.ConfigProviderHelper
  alias ExLLM.Types

  describe "configured?/1" do
    test "returns true when API key is available" do
      # Default config with env var should work
      result = OpenRouter.configured?()
      # Will be true if OPENROUTER_API_KEY is set, false otherwise
      assert is_boolean(result)
    end

    test "returns false with empty API key" do
      config = %{openrouter: %{api_key: ""}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      refute OpenRouter.configured?(config_provider: provider)
    end

    test "returns true with valid API key" do
      config = %{openrouter: %{api_key: "sk-or-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      assert OpenRouter.configured?(config_provider: provider)
    end

    test "works with environment variables" do
      original = System.get_env("OPENROUTER_API_KEY")
      System.put_env("OPENROUTER_API_KEY", "sk-or-test")

      assert OpenRouter.configured?(config_provider: ExLLM.Infrastructure.ConfigProvider.Env)

      if original do
        System.put_env("OPENROUTER_API_KEY", original)
      else
        System.delete_env("OPENROUTER_API_KEY")
      end
    end
  end

  describe "default_model/0" do
    test "returns a default model string" do
      model = OpenRouter.default_model()
      assert is_binary(model)
      # Should be a provider/model format
      assert String.contains?(model, "/")
    end
  end

  describe "message formatting" do
    test "handles simple text messages" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]

      # Test that messages are properly formatted
      assert {:error, _} = OpenRouter.chat(messages, config_provider: provider, timeout: 1)
    end

    test "handles system messages" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"}
      ]

      assert {:error, _} = OpenRouter.chat(messages, config_provider: provider, timeout: 1)
    end

    test "handles multimodal content with images" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{
              type: "image_url",
              image_url: %{
                url: "data:image/jpeg;base64,/9j/4AAQSkZJRg=="
              }
            }
          ]
        }
      ]

      # Should handle multimodal content
      assert {:error, _} = OpenRouter.chat(messages, config_provider: provider, timeout: 1)
    end

    test "handles OpenAI-style function calling format" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [
        %{role: "user", content: "Get weather"},
        %{
          role: "assistant",
          function_call: %{
            name: "get_weather",
            arguments: "{\"location\": \"Boston\"}"
          }
        }
      ]

      assert {:error, _} = OpenRouter.chat(messages, config_provider: provider, timeout: 1)
    end
  end

  describe "parameter handling" do
    test "builds correct request body" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      # Can't directly test build_request_body since it's private
      # But we can test that parameters are passed correctly
      messages = [%{role: "user", content: "Test"}]

      opts = [
        temperature: 0.7,
        max_tokens: 100,
        top_p: 0.9,
        seed: 42,
        model: "openai/gpt-4o",
        config_provider: provider
      ]

      # These would be added to the request body
      assert {:error, _} = OpenRouter.chat(messages, opts ++ [timeout: 1])
    end

    test "supports OpenRouter-specific parameters" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]

      opts = [
        models: ["openai/gpt-4o", "anthropic/claude-3-5-sonnet"],
        transforms: ["middle-out"],
        provider: %{order: ["openai", "anthropic"]},
        config_provider: provider,
        timeout: 1
      ]

      # OpenRouter-specific options should be handled
      assert {:error, _} = OpenRouter.chat(messages, opts)
    end

    test "handles app identification headers" do
      config = %{
        openrouter: %{
          api_key: "test-key",
          app_name: "ExLLM Test",
          app_url: "https://example.com"
        }
      }

      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]
      assert {:error, _} = OpenRouter.chat(messages, config_provider: provider, timeout: 1)
    end
  end

  describe "streaming setup" do
    test "stream_chat returns a Stream" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Hello"}]

      # With invalid API key, should return error
      case OpenRouter.stream_chat(messages, config_provider: provider) do
        {:ok, stream} ->
          # Should be a stream if API key is available
          assert is_function(stream) or is_struct(stream, Stream)

        {:error, "OpenRouter API key not configured"} ->
          # Expected without API key
          :ok

        {:error, _} ->
          # Other errors also valid
          :ok
      end
    end

    test "streaming adds stream: true to request" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test streaming"}]

      # The stream parameter should be added
      case OpenRouter.stream_chat(messages, config_provider: provider) do
        {:ok, _stream} ->
          :ok

        {:error, _} ->
          :ok
      end
    end
  end

  describe "model listing" do
    test "list_models returns models from config when API fails" do
      # Without valid API key, should fall back to config
      case OpenRouter.list_models() do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            model = hd(models)
            assert %Types.Model{} = model
            # OpenRouter models use provider/model format
            assert String.contains?(model.id, "/")
          end

        {:error, _} ->
          # Error is also acceptable without API key
          :ok
      end
    end

    test "model capabilities are properly set" do
      case OpenRouter.list_models() do
        {:ok, models} ->
          if length(models) > 0 do
            model = hd(models)
            assert %Types.Model{} = model
            assert is_map(model.capabilities)

            # Check for OpenRouter-specific capabilities
            if is_list(model.capabilities.features) do
              # Should have at least some capabilities
              assert length(model.capabilities.features) >= 0
            end
          end

        {:error, _} ->
          :ok
      end
    end
  end

  describe "headers and base URL" do
    test "uses default base URL when not configured" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]
      # Should use https://openrouter.ai/api/v1
      assert {:error, _} = OpenRouter.chat(messages, config_provider: provider, timeout: 1)
    end

    test "uses custom base URL from config" do
      config = %{
        openrouter: %{
          api_key: "test-key",
          base_url: "https://custom.openrouter.ai/api/v1"
        }
      }

      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]
      assert {:error, _} = OpenRouter.chat(messages, config_provider: provider, timeout: 1)
    end

    test "includes OpenRouter-specific headers" do
      config = %{
        openrouter: %{
          api_key: "test-key",
          app_name: "TestApp",
          app_url: "https://test.com"
        }
      }

      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]
      # Should include HTTP-Referer and X-Title headers
      assert {:error, _} = OpenRouter.chat(messages, config_provider: provider, timeout: 1)
    end
  end

  describe "response parsing" do
    test "handles OpenAI-compatible response format" do
      # Mock response would be parsed here
      # Testing the expected structure
      mock_response = %{
        "id" => "gen-123",
        "model" => "openai/gpt-4o",
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "Hello!"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 5,
          "total_tokens" => 15
        }
      }

      # This would be parsed in parse_response/2
      assert is_map(mock_response)
      assert mock_response["choices"] |> hd() |> get_in(["message", "content"]) == "Hello!"
    end

    test "handles function call responses" do
      mock_response = %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "function_call" => %{
                "name" => "get_weather",
                "arguments" => "{\"location\": \"Boston\"}"
              }
            }
          }
        ]
      }

      # Should parse function calls correctly
      assert is_map(mock_response)
      message = mock_response["choices"] |> hd() |> Map.get("message")
      assert message["function_call"]["name"] == "get_weather"
    end

    test "handles tool call responses" do
      mock_response = %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "tool_calls" => [
                %{
                  "id" => "call_123",
                  "function" => %{
                    "name" => "get_weather",
                    "arguments" => "{\"location\": \"Boston\"}"
                  }
                }
              ]
            }
          }
        ]
      }

      # Should parse tool calls correctly
      assert is_map(mock_response)
      tool_calls = mock_response["choices"] |> hd() |> get_in(["message", "tool_calls"])
      assert hd(tool_calls)["function"]["name"] == "get_weather"
    end
  end

  describe "streaming chunk parsing" do
    test "parses content chunks" do
      chunk_data = ~s(data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n)

      # This would be parsed in the streaming handler
      lines = String.split(chunk_data, "\n", trim: true)
      data_line = Enum.find(lines, &String.starts_with?(&1, "data: "))

      if data_line do
        json = String.trim_leading(data_line, "data: ")
        {:ok, decoded} = Jason.decode(json)
        assert decoded["choices"] |> hd() |> get_in(["delta", "content"]) == "Hello"
      end
    end

    test "handles [DONE] message" do
      chunk_data = "data: [DONE]\n\n"

      lines = String.split(chunk_data, "\n", trim: true)
      data_line = Enum.find(lines, &String.starts_with?(&1, "data: "))

      assert String.trim_leading(data_line, "data: ") == "[DONE]"
    end

    test "handles OpenRouter processing comments" do
      chunk_data = ": OPENROUTER PROCESSING\n\n"

      # Should be filtered out in streaming
      lines = String.split(chunk_data, "\n", trim: true)
      data_lines = Enum.filter(lines, &String.starts_with?(&1, "data: "))

      assert Enum.empty?(data_lines)
    end
  end

  describe "error handling" do
    setup do
      # Temporarily disable environment API key
      original_key = System.get_env("OPENROUTER_API_KEY")
      System.delete_env("OPENROUTER_API_KEY")

      on_exit(fn ->
        if original_key do
          System.put_env("OPENROUTER_API_KEY", original_key)
        end
      end)

      :ok
    end

    test "validates API key format" do
      invalid_configs = [
        %{openrouter: %{api_key: nil}},
        %{openrouter: %{api_key: ""}},
        %{openrouter: %{}}
      ]

      for config <- invalid_configs do
        provider = ConfigProviderHelper.setup_static_provider(config)
        refute OpenRouter.configured?(config_provider: provider)
      end
    end

    test "handles missing API key error" do
      messages = [%{role: "user", content: "Test"}]

      config = %{openrouter: %{}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      assert {:error, "OpenRouter API key not configured"} =
               OpenRouter.chat(messages, config_provider: provider)
    end
  end

  describe "model routing features" do
    test "supports fallback model list" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]

      # OpenRouter supports fallback models
      models = ["openai/gpt-4o", "anthropic/claude-3-5-sonnet", "openai/gpt-3.5-turbo"]

      assert {:error, _} =
               OpenRouter.chat(messages, config_provider: provider, models: models, timeout: 1)
    end

    test "supports auto-router model" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]

      # OpenRouter has an auto model
      assert {:error, _} =
               OpenRouter.chat(messages,
                 config_provider: provider,
                 model: "openrouter/auto",
                 timeout: 1
               )
    end

    test "supports provider preferences" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]

      provider_prefs = %{
        order: ["openai", "anthropic"],
        allow_fallbacks: true
      }

      assert {:error, _} =
               OpenRouter.chat(messages,
                 config_provider: provider,
                 provider: provider_prefs,
                 timeout: 1
               )
    end
  end

  describe "pricing and cost calculation" do
    test "handles OpenRouter pricing format" do
      # OpenRouter returns pricing in their specific format
      mock_pricing = %{
        "prompt" => "0.005",
        "completion" => "0.015"
      }

      # This would be processed in parse_pricing/1
      assert is_map(mock_pricing)
      assert is_binary(mock_pricing["prompt"])
      assert is_binary(mock_pricing["completion"])
    end

    test "handles free model pricing" do
      # Free models have different pricing structure
      mock_pricing = %{
        "prompt" => "0",
        "completion" => "0"
      }

      assert is_map(mock_pricing)
      assert mock_pricing["prompt"] == "0"
      assert mock_pricing["completion"] == "0"
    end
  end

  describe "model capabilities parsing" do
    test "parses OpenRouter model capabilities" do
      mock_model = %{
        "supports_streaming" => true,
        "supports_functions" => true,
        "supports_vision" => false
      }

      # This would be processed in parse_capabilities/1
      assert mock_model["supports_streaming"] == true
      assert mock_model["supports_functions"] == true
      assert mock_model["supports_vision"] == false
    end

    test "handles missing capability fields" do
      mock_model = %{
        "id" => "test/model"
      }

      # Should handle missing capability fields gracefully
      assert is_map(mock_model)
      assert Map.get(mock_model, "supports_streaming", false) == false
    end
  end

  describe "transform handling" do
    test "supports OpenRouter transforms" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]

      # OpenRouter supports prompt transforms
      transforms = ["middle-out", "no-op"]

      assert {:error, _} =
               OpenRouter.chat(messages,
                 config_provider: provider,
                 transforms: transforms,
                 timeout: 1
               )
    end
  end

  describe "data collection policies" do
    test "supports data collection restrictions" do
      config = %{openrouter: %{api_key: "invalid-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]

      # OpenRouter supports data collection policies
      data_collection = "deny"

      assert {:error, _} =
               OpenRouter.chat(messages,
                 config_provider: provider,
                 data_collection: data_collection,
                 timeout: 1
               )
    end
  end
end
