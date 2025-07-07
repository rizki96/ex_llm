defmodule ExLLM.Providers.OpenAI.ChatTest do
  @moduledoc """
  Tests for OpenAI chat functionality.

  This module tests message formatting, parameter handling, and response parsing
  for OpenAI chat completions.
  """

  use ExUnit.Case, async: true

  alias ExLLM.Providers.OpenAI
  alias ExLLM.Testing.ConfigProviderHelper
  alias ExLLM.Types

  @moduletag :openai_chat
  @moduletag :integration
  @moduletag :provider_openai

  describe "message formatting" do
    test "handles simple text messages" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]

      # Test with invalid API key to ensure error response
      config = %{openai: %{api_key: "invalid-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      assert {:error, _} = OpenAI.chat(messages, config_provider: provider, timeout: 100)
    end

    test "handles system messages" do
      messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"}
      ]

      # Test with invalid API key to ensure error response
      config = %{openai: %{api_key: "invalid-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      assert {:error, _} = OpenAI.chat(messages, config_provider: provider, timeout: 100)
    end

    test "handles multimodal content with images" do
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

      # Test with invalid API key to ensure error response
      config = %{openai: %{api_key: "invalid-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      assert {:error, _} = OpenAI.chat(messages, config_provider: provider, timeout: 100)
    end

    test "handles audio content" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Transcribe this audio"},
            %{
              type: "input_audio",
              input_audio: %{
                data: "base64audio",
                format: "wav"
              }
            }
          ]
        }
      ]

      # Test with invalid API key to ensure error response
      config = %{openai: %{api_key: "invalid-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      assert {:error, _} = OpenAI.chat(messages, config_provider: provider, timeout: 100)
    end
  end

  describe "parameter handling" do
    test "adds optional parameters to request body" do
      messages = [%{role: "user", content: "Test"}]

      body =
        OpenAI.build_request_body(messages, "gpt-4", %{},
          temperature: 0.7,
          max_completion_tokens: 100,
          top_p: 0.9,
          seed: 42,
          n: 2
        )

      assert body.temperature == 0.7
      assert body.max_completion_tokens == 100
      assert body.top_p == 0.9
      assert body.seed == 42
      assert body.n == 2
    end

    test "uses max_completion_tokens for newer models" do
      messages = [%{role: "user", content: "Test"}]

      # For newer models like gpt-4o when max_completion_tokens is specified
      body = OpenAI.build_request_body(messages, "gpt-4o", %{}, max_completion_tokens: 100)
      assert body.max_completion_tokens == 100
    end

    test "uses max_tokens for legacy models" do
      messages = [%{role: "user", content: "Test"}]

      # For legacy models
      body = OpenAI.build_request_body(messages, "gpt-3.5-turbo-instruct", %{}, max_tokens: 100)
      assert body.max_tokens == 100
      refute Map.has_key?(body, :max_completion_tokens)
    end

    test "handles response format" do
      messages = [%{role: "user", content: "Test"}]

      body =
        OpenAI.build_request_body(messages, "gpt-4", %{}, response_format: %{type: "json_object"})

      assert body.response_format == %{type: "json_object"}
    end

    test "handles structured output schema" do
      messages = [%{role: "user", content: "Test"}]

      schema = %{
        type: "json_schema",
        json_schema: %{
          name: "test",
          schema: %{
            type: "object",
            properties: %{
              name: %{type: "string"}
            }
          }
        }
      }

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, response_format: schema)
      assert body.response_format == schema
    end
  end

  describe "response parsing" do
    test "parses standard response format" do
      mock_response = %{
        "id" => "chatcmpl-123",
        "model" => "gpt-4",
        "choices" => [
          %{
            "message" => %{"role" => "assistant", "content" => "Hello!"},
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 5,
          "total_tokens" => 15
        }
      }

      parsed = OpenAI.parse_response(mock_response, "gpt-4")
      assert %Types.LLMResponse{} = parsed
      assert parsed.content == "Hello!"
      assert parsed.usage.input_tokens == 10
      assert parsed.usage.output_tokens == 5
    end

    test "parses response with refusal" do
      mock_response = %{
        "id" => "chatcmpl-123",
        "model" => "gpt-4",
        "choices" => [
          %{
            "message" => %{
              "refusal" => "I can't help with that",
              role: "assistant",
              content: nil
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 0
        }
      }

      parsed = OpenAI.parse_response(mock_response, "gpt-4")
      assert parsed.refusal == "I can't help with that"
    end

    test "parses response with tool calls" do
      mock_response = %{
        "id" => "chatcmpl-123",
        "model" => "gpt-4",
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call_123",
                  "function" => %{
                    "arguments" => ~s({"location": "Boston"}),
                    "name" => "get_weather"
                  },
                  "type" => "function"
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 20
        }
      }

      parsed = OpenAI.parse_response(mock_response, "gpt-4")
      assert length(parsed.tool_calls) == 1
      assert hd(parsed.tool_calls)["function"]["name"] == "get_weather"
    end
  end
end
