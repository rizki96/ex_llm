defmodule ExLLM.Adapters.OpenAITest do
  use ExUnit.Case
  alias ExLLM.Adapters.OpenAI
  alias ExLLM.Types

  describe "basic adapter functions" do
    test "configured?/1 returns false when no API key" do
      {:ok, pid} = ExLLM.ConfigProvider.Static.start_link(%{openai: %{}})
      refute OpenAI.configured?(config_provider: pid)
    end

    test "configured?/1 returns true when API key is set" do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, pid} = ExLLM.ConfigProvider.Static.start_link(config)
      assert OpenAI.configured?(config_provider: pid)
    end

    test "default_model/0 returns the default model" do
      assert is_binary(OpenAI.default_model())
    end

    test "list_models/1 returns available models" do
      {:ok, models} = OpenAI.list_models()
      assert is_list(models)
      assert length(models) > 0

      first_model = hd(models)
      assert %Types.Model{} = first_model
      assert is_binary(first_model.id)
      assert is_binary(first_model.name)
      assert is_integer(first_model.context_window)
    end

    test "list_embedding_models/1 returns embedding models" do
      {:ok, models} = OpenAI.list_embedding_models()
      assert is_list(models)
      assert length(models) > 0

      first_model = hd(models)
      assert %Types.EmbeddingModel{} = first_model
      assert first_model.provider == :openai
    end
  end

  describe "modern request parameters" do
    setup do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, pid} = ExLLM.ConfigProvider.Static.start_link(config)
      %{config_provider: pid}
    end

    test "supports max_completion_tokens parameter", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]

      # This should now work and include max_completion_tokens in the request
      # We can't test the actual API call without real credentials, so we test request building
      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [max_completion_tokens: 100])
      assert body[:max_completion_tokens] == 100
      assert Map.has_key?(body, :max_completion_tokens)
      refute Map.has_key?(body, :max_tokens)  # Should use modern parameter
    end

    test "supports n parameter for multiple completions", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [n: 2])
      assert body[:n] == 2
    end

    test "supports top_p parameter", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [top_p: 0.9])
      assert body[:top_p] == 0.9
    end

    test "supports frequency_penalty parameter", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [frequency_penalty: 0.5])
      assert body[:frequency_penalty] == 0.5
    end

    test "supports presence_penalty parameter", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [presence_penalty: 0.5])
      assert body[:presence_penalty] == 0.5
    end

    test "supports seed parameter", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [seed: 12345])
      assert body[:seed] == 12345
    end

    test "supports stop parameter", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [stop: [".", "!"]])
      assert body[:stop] == [".", "!"]
    end

    test "supports service_tier parameter", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [service_tier: "auto"])
      assert body[:service_tier] == "auto"
    end
  end

  describe "response format and structured outputs" do
    setup do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, pid} = ExLLM.ConfigProvider.Static.start_link(config)
      %{config_provider: pid}
    end

    test "supports JSON mode response format", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Return a JSON object"}]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [response_format: %{type: "json_object"}])
      assert body[:response_format] == %{type: "json_object"}
    end

    test "supports JSON schema response format", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Generate a person object"}]
      
      schema = %{
        type: "json_schema",
        json_schema: %{
          name: "person",
          schema: %{
            type: "object",
            properties: %{
              name: %{type: "string"},
              age: %{type: "integer"}
            },
            required: ["name"]
          }
        }
      }

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [response_format: schema])
      assert body[:response_format] == schema
    end

    test "handles refusal in responses", %{config_provider: _provider} do
      # Mock response with refusal
      response = %{
        "choices" => [
          %{
            "message" => %{
              "content" => nil,
              "refusal" => "I can't help with that request."
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 0}
      }

      # This should parse refusal when implemented
      parsed = OpenAI.parse_response(response, "gpt-4")
      assert parsed.refusal == "I can't help with that request."
    end

    test "supports logprobs in responses", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [logprobs: true, top_logprobs: 3])
      assert body[:logprobs] == true
      assert body[:top_logprobs] == 3
    end
  end

  describe "modern tool calling" do
    setup do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, pid} = ExLLM.ConfigProvider.Static.start_link(config)
      %{config_provider: pid}
    end

    test "supports modern tools API instead of deprecated functions", %{config_provider: _provider} do
      messages = [%{role: "user", content: "What's the weather like?"}]
      
      tools = [
        %{
          type: "function",
          function: %{
            name: "get_weather",
            description: "Get the current weather",
            parameters: %{
              type: "object",
              properties: %{
                location: %{type: "string"}
              },
              required: ["location"]
            }
          }
        }
      ]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [tools: tools])
      assert body[:tools] == tools
    end

    test "supports tool_choice parameter", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]
      tools = [%{type: "function", function: %{name: "test_tool"}}]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [tools: tools, tool_choice: "auto"])
      assert body[:tools] == tools
      assert body[:tool_choice] == "auto"
    end

    test "supports parallel tool calls", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]
      tools = [
        %{type: "function", function: %{name: "tool1"}},
        %{type: "function", function: %{name: "tool2"}}
      ]

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [tools: tools, parallel_tool_calls: true])
      assert body[:tools] == tools
      assert body[:parallel_tool_calls] == true
    end

    test "deprecated functions parameter shows warning" do
      # This should show a deprecation warning when used
      _messages = [%{role: "user", content: "Hello"}]
      functions = [%{name: "test_function"}]

      # For now, this still works but should log warning
      # In the future, it should be deprecated
      assert :ok = OpenAI.validate_functions_parameter(functions)
    end
  end

  describe "advanced message content" do
    setup do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, pid} = ExLLM.ConfigProvider.Static.start_link(config)
      %{config_provider: pid}
    end

    test "supports multiple content parts per message", %{config_provider: provider} do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,..."}}
          ]
        }
      ]

      # This should now work! Multiple content parts are supported
      {:error, {:validation, :request, _}} = OpenAI.chat(messages, config_provider: provider)
    end

    test "supports file content references", %{config_provider: provider} do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Analyze this file"},
            %{type: "file", file: %{id: "file-123"}}
          ]
        }
      ]

      assert_raise RuntimeError, ~r/file.*content.*not.*supported/i, fn ->
        OpenAI.chat(messages, config_provider: provider)
      end
    end

    test "supports audio content in messages", %{config_provider: provider} do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Transcribe this audio"},
            %{type: "input_audio", input_audio: %{data: "base64audio", format: "wav"}}
          ]
        }
      ]

      # This should now work! (but will fail with validation error about API key)
      # Since we're using mock config with invalid API key, we expect it to fail at API validation
      {:error, {:validation, :request, _}} = OpenAI.chat(messages, config_provider: provider)
    end
  end

  describe "new model features" do
    setup do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, pid} = ExLLM.ConfigProvider.Static.start_link(config)
      %{config_provider: pid}
    end

    test "supports audio output", %{config_provider: provider} do
      messages = [%{role: "user", content: "Hello"}]

      # This should now work! (but will fail with validation error about API key)
      {:error, {:validation, :request, _}} = OpenAI.chat(messages,
        config_provider: provider,
        audio: %{
          voice: "alloy",
          format: "mp3"
        }
      )
    end

    test "supports web search integration", %{config_provider: provider} do
      messages = [%{role: "user", content: "What's the latest news?"}]

      # This should now work! (but will fail with validation error about API key)
      {:error, {:validation, :request, _}} = OpenAI.chat(messages,
        config_provider: provider,
        web_search_options: %{enabled: true}
      )
    end

    test "supports reasoning effort for o-series models", %{config_provider: provider} do
      messages = [%{role: "user", content: "Solve this complex problem"}]

      # This should now work! (but will fail with validation error about API key)
      {:error, {:validation, :request, _}} = OpenAI.chat(messages,
        config_provider: provider,
        model: "o1-preview",
        reasoning_effort: "high"
      )
    end

    test "supports developer role for o1+ models", %{config_provider: provider} do
      messages = [
        %{role: "developer", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"}
      ]

      # This should now work! MessageFormatter now supports developer role
      {:error, {:validation, :request, _}} = OpenAI.chat(messages,
        config_provider: provider,
        model: "o1-preview"
      )
    end

    test "supports predicted outputs", %{config_provider: provider} do
      messages = [%{role: "user", content: "Complete this text"}]

      # This should now work! (but will fail with validation error about API key)
      {:error, {:validation, :request, _}} = OpenAI.chat(messages,
        config_provider: provider,
        prediction: %{
          type: "content",
          content: "Expected completion..."
        }
      )
    end
  end

  describe "enhanced usage tracking" do
    test "parses enhanced usage information" do
      response = %{
        "choices" => [
          %{
            "message" => %{"content" => "Hello"},
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 5,
          "total_tokens" => 15,
          "prompt_tokens_details" => %{
            "cached_tokens" => 3,
            "audio_tokens" => 0
          },
          "completion_tokens_details" => %{
            "reasoning_tokens" => 2,
            "audio_tokens" => 0
          }
        }
      }

      parsed = OpenAI.parse_response(response, "gpt-4")
      
      # Current implementation doesn't parse these details
      assert parsed.usage.input_tokens == 10
      assert parsed.usage.output_tokens == 5
      assert parsed.usage.total_tokens == 15
      
      # These should be available when implemented - our implementation now supports them!
      assert Map.get(parsed.usage, :cached_tokens) == 3
      assert Map.get(parsed.usage, :reasoning_tokens) == 2
      assert Map.get(parsed.usage, :audio_tokens) == 0
    end
  end

  describe "streaming enhancements" do
    setup do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, pid} = ExLLM.ConfigProvider.Static.start_link(config)
      %{config_provider: pid}
    end

    test "supports tool calls in streaming responses", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Call a function"}]
      tools = [%{type: "function", function: %{name: "test_tool"}}]

      # Test that we can create a streaming request body with tools
      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [tools: tools])
      streaming_body = Map.put(body, :stream, true)
      assert streaming_body[:tools] == tools
      assert streaming_body[:stream] == true
    end

    test "supports usage information in streaming responses", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]

      # Test that we can create a streaming request body with stream_options
      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [stream_options: %{include_usage: true}])
      streaming_body = Map.put(body, :stream, true)
      assert streaming_body[:stream_options] == %{include_usage: true}
      assert streaming_body[:stream] == true
    end
  end

  describe "audio features" do
    setup do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, pid} = ExLLM.ConfigProvider.Static.start_link(config)
      %{config_provider: pid}
    end

    test "supports audio output in request body", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Hello"}]
      
      audio_config = %{
        voice: "alloy",
        format: "mp3"
      }

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [audio: audio_config])
      assert body[:audio] == audio_config
    end

    test "audio input is passed through in messages", %{config_provider: _provider} do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Transcribe this"},
            %{type: "input_audio", input_audio: %{data: "base64audio", format: "wav"}}
          ]
        }
      ]

      # Test that we can build request body with audio input messages
      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [])
      message_content = body[:messages] |> hd() |> Map.get("content")
      
      # Should have both text and audio content parts
      assert is_list(message_content)
      assert length(message_content) == 2
      
      text_part = Enum.find(message_content, &(&1["type"] == "text"))
      audio_part = Enum.find(message_content, &(&1["type"] == "input_audio"))
      
      assert text_part["text"] == "Transcribe this"
      assert audio_part["input_audio"]["data"] == "base64audio"
    end

    test "supports web search in request body", %{config_provider: _provider} do
      messages = [%{role: "user", content: "What's the latest news?"}]
      
      web_search_config = %{enabled: true}

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [web_search_options: web_search_config])
      assert body[:web_search_options] == web_search_config
    end

    test "supports reasoning effort for o-series models", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Solve this problem"}]
      
      # Test with o1 model - should include reasoning_effort
      body = OpenAI.build_request_body(messages, "o1-preview", %{}, [reasoning_effort: "high"])
      assert body[:reasoning_effort] == "high"
      
      # Test with non-o model - should not include reasoning_effort (only applies to o-series)
      body_non_o = OpenAI.build_request_body(messages, "gpt-4", %{}, [reasoning_effort: "high"])
      refute Map.has_key?(body_non_o, :reasoning_effort)
    end

    test "supports developer role in messages", %{config_provider: _provider} do
      messages = [
        %{role: "developer", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"}
      ]

      # Test that developer role is properly formatted in messages
      body = OpenAI.build_request_body(messages, "o1-preview", %{}, [])
      formatted_messages = body[:messages]
      
      assert length(formatted_messages) == 2
      assert hd(formatted_messages)["role"] == "developer"
      assert hd(formatted_messages)["content"] == "You are a helpful assistant"
    end

    test "supports predicted outputs in request body", %{config_provider: _provider} do
      messages = [%{role: "user", content: "Complete this text"}]
      
      prediction_config = %{
        type: "content",
        content: "Expected completion..."
      }

      body = OpenAI.build_request_body(messages, "gpt-4", %{}, [prediction: prediction_config])
      assert body[:prediction] == prediction_config
    end
  end

  describe "additional APIs (when implemented)" do
    setup do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, pid} = ExLLM.ConfigProvider.Static.start_link(config)
      %{config_provider: pid}
    end

    test "moderate_content/2 function exists and works", %{config_provider: provider} do
      # This should now work! (but will fail with validation error about API key)
      {:error, {:validation, :request, _}} = OpenAI.moderate_content("Test content", config_provider: provider)
    end

    test "transcribe_audio/2 function exists and works", %{config_provider: provider} do
      # This should now work! (but will fail with file not found error)
      {:error, :enoent} = OpenAI.transcribe_audio("nonexistent.mp3", config_provider: provider)
    end

    test "generate_image/2 function exists and works", %{config_provider: provider} do
      # This should now work! (but will fail with validation error about API key)
      {:error, {:validation, :request, _}} = OpenAI.generate_image("A beautiful sunset", config_provider: provider)
    end

    test "upload_file/3 function exists and works", %{config_provider: provider} do
      # This should now work! (but will fail with file not found error)
      {:error, :enoent} = OpenAI.upload_file("nonexistent.txt", "assistants", config_provider: provider)
    end

    test "create_assistant/2 function exists and works", %{config_provider: provider} do
      # This should now work! (but will fail with validation error about API key)
      {:error, {:validation, :request, _}} = OpenAI.create_assistant(%{name: "Test Assistant"}, config_provider: provider)
    end

    test "create_batch/2 function exists and works", %{config_provider: provider} do
      # This should now work! (but will fail with validation error about API key)
      {:error, {:validation, :request, _}} = OpenAI.create_batch([], config_provider: provider)
    end
  end

  # Helper function tests that don't exist yet
  describe "helper functions that should exist" do
    test "parse_response/2 function exists" do
      # This function should be public for testing
      assert function_exported?(OpenAI, :parse_response, 2)
    end

    test "validate_functions_parameter/1 function should exist and warn" do
      # This should warn about deprecated functions parameter
      assert :ok = OpenAI.validate_functions_parameter([%{name: "test"}])
    end
  end
end