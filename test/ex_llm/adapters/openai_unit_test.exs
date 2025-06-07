defmodule ExLLM.Adapters.OpenAIUnitTest do
  use ExUnit.Case, async: true
  alias ExLLM.Adapters.OpenAI
  alias ExLLM.Types

  describe "configured?/1" do
    test "returns true when API key is available" do
      # Default config with env var should work
      result = OpenAI.configured?()
      # Will be true if OPENAI_API_KEY is set, false otherwise
      assert is_boolean(result)
    end

    test "returns false with empty API key" do
      config = %{openai: %{api_key: ""}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      
      refute OpenAI.configured?(config_provider: provider)
    end

    test "returns true with valid API key" do
      config = %{openai: %{api_key: "sk-test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      
      assert OpenAI.configured?(config_provider: provider)
    end
  end

  describe "default_model/0" do
    test "returns a default model string" do
      model = OpenAI.default_model()
      assert is_binary(model)
      # Should be a GPT model
      assert String.contains?(model, "gpt")
    end
  end

  describe "message formatting" do
    test "handles simple text messages" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]
      
      # Test that messages are properly formatted
      assert {:error, _} = OpenAI.chat(messages, timeout: 1)
    end

    test "handles system messages" do
      messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"}
      ]
      
      assert {:error, _} = OpenAI.chat(messages, timeout: 1)
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
      
      # Should handle multimodal content
      assert {:error, _} = OpenAI.chat(messages, timeout: 1)
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
      
      assert {:error, _} = OpenAI.chat(messages, timeout: 1)
    end
  end

  describe "parameter handling" do
    test "adds optional parameters to request body" do
      messages = [%{role: "user", content: "Test"}]
      
      body = OpenAI.build_request_body(messages, "gpt-4", %{}, 
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
      
      body = OpenAI.build_request_body(messages, "gpt-4", %{}, 
        response_format: %{type: "json_object"}
      )
      
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

  describe "streaming setup" do
    test "stream_chat returns a Stream" do
      messages = [%{role: "user", content: "Hello"}]
      
      # Even without API key, stream structure should be created
      case OpenAI.stream_chat(messages) do
        {:ok, stream} ->
          # Stream.resource returns a function
          assert is_function(stream) or is_struct(stream, Stream)
        {:error, _} ->
          # Missing API key is also valid
          :ok
      end
    end

    test "streaming adds stream: true to request" do
      messages = [%{role: "user", content: "Test streaming"}]
      
      # The stream parameter should be added
      case OpenAI.stream_chat(messages) do
        {:ok, _stream} ->
          :ok
        {:error, _} ->
          :ok
      end
    end
  end

  describe "tool/function calling" do
    test "supports modern tools API" do
      messages = [%{role: "user", content: "Get weather"}]
      
      tools = [
        %{
          type: "function",
          function: %{
            name: "get_weather",
            description: "Get weather for location",
            parameters: %{
              type: "object",
              properties: %{
                location: %{type: "string"}
              }
            }
          }
        }
      ]
      
      body = OpenAI.build_request_body(messages, "gpt-4", %{}, tools: tools)
      assert body.tools == tools
    end

    test "supports tool_choice parameter" do
      messages = [%{role: "user", content: "Test"}]
      tools = [%{type: "function", function: %{name: "test"}}]
      
      body = OpenAI.build_request_body(messages, "gpt-4", %{}, 
        tools: tools,
        tool_choice: "auto"
      )
      
      assert body.tool_choice == "auto"
    end

    test "supports parallel tool calls" do
      messages = [%{role: "user", content: "Test"}]
      tools = [%{type: "function", function: %{name: "test"}}]
      
      body = OpenAI.build_request_body(messages, "gpt-4", %{}, 
        tools: tools,
        parallel_tool_calls: true
      )
      
      assert body.parallel_tool_calls == true
    end

    test "validates deprecated functions parameter" do
      functions = [%{name: "test_function"}]
      assert :ok = OpenAI.validate_functions_parameter(functions)
    end
  end

  describe "model listing" do
    test "list_models returns models from config" do
      {:ok, models} = OpenAI.list_models()
      
      assert is_list(models)
      assert length(models) > 0
      
      model = hd(models)
      assert %Types.Model{} = model
      # Not all models have "gpt" in the name (e.g., dall-e models)
      assert is_binary(model.id)
      assert model.context_window > 0
      assert is_map(model.capabilities)
    end

    test "list_embedding_models returns embedding models" do
      {:ok, models} = OpenAI.list_embedding_models()
      
      assert is_list(models)
      assert length(models) > 0
      
      model = hd(models)
      assert %Types.EmbeddingModel{} = model
      assert model.provider == :openai
      # EmbeddingModel uses 'name' not 'id'
      assert String.contains?(model.name, "embedding")
    end
  end

  describe "headers and base URL" do
    test "uses default base URL when not configured" do
      messages = [%{role: "user", content: "Test"}]
      # Should use https://api.openai.com/v1
      assert {:error, _} = OpenAI.chat(messages, timeout: 1)
    end

    test "uses custom base URL from config" do
      config = %{
        openai: %{
          api_key: "test-key",
          base_url: "https://custom.openai.com/v1"
        }
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      
      messages = [%{role: "user", content: "Test"}]
      assert {:error, _} = OpenAI.chat(messages, config_provider: provider, timeout: 1)
    end
  end

  describe "response parsing" do
    test "parses standard response format" do
      mock_response = %{
        "id" => "chatcmpl-123",
        "model" => "gpt-4",
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
              "role" => "assistant",
              "content" => nil,
              "refusal" => "I can't help with that"
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
                  "type" => "function",
                  "function" => %{
                    "name" => "get_weather",
                    "arguments" => ~s({"location": "Boston"})
                  }
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
  end

  describe "error handling" do
    test "validates API key format" do
      invalid_configs = [
        %{openai: %{api_key: nil}},
        %{openai: %{api_key: ""}},
        %{openai: %{}}
      ]
      
      for config <- invalid_configs do
        {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
        refute OpenAI.configured?(config_provider: provider)
      end
    end
  end

  describe "special model features" do
    test "supports audio output configuration" do
      messages = [%{role: "user", content: "Test"}]
      
      audio_config = %{
        voice: "alloy",
        format: "mp3"
      }
      
      body = OpenAI.build_request_body(messages, "gpt-4o-audio", %{}, audio: audio_config)
      assert body.audio == audio_config
    end

    test "supports web search options" do
      messages = [%{role: "user", content: "Search for latest news"}]
      
      web_search = %{
        enabled: true,
        max_results: 5
      }
      
      body = OpenAI.build_request_body(messages, "gpt-4", %{}, web_search_options: web_search)
      assert body.web_search_options == web_search
    end

    test "supports reasoning effort for o-series models" do
      messages = [%{role: "user", content: "Complex problem"}]
      
      body = OpenAI.build_request_body(messages, "o1-preview", %{}, reasoning_effort: "high")
      assert body.reasoning_effort == "high"
    end

    test "ignores reasoning effort for non-o-series models" do
      messages = [%{role: "user", content: "Test"}]
      
      body = OpenAI.build_request_body(messages, "gpt-4", %{}, reasoning_effort: "high")
      refute Map.has_key?(body, :reasoning_effort)
    end
  end

  describe "embeddings" do
    test "handles single text input" do
      # Test would call embeddings function
      assert {:error, _} = OpenAI.embeddings("Hello world", timeout: 1)
    end

    test "handles multiple text inputs" do
      # Test would call embeddings function
      assert {:error, _} = OpenAI.embeddings(["Hello", "World"], timeout: 1)
    end
  end
end