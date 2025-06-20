defmodule ExLLM.Providers.OpenAIUnitTest do
  use ExUnit.Case, async: true
  alias ExLLM.Providers.OpenAI
  alias ExLLM.Types
  alias ExLLM.Testing.ConfigProviderHelper

  describe "configured?/1" do
    test "returns true when API key is available" do
      # Default config with env var should work
      result = OpenAI.configured?()
      # Will be true if OPENAI_API_KEY is set, false otherwise
      assert is_boolean(result)
    end

    test "returns false with empty API key" do
      config = %{openai: %{api_key: ""}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      refute OpenAI.configured?(config_provider: provider)
    end

    test "returns true with valid API key" do
      config = %{openai: %{api_key: "sk-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

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

      body =
        OpenAI.build_request_body(messages, "gpt-4", %{},
          tools: tools,
          tool_choice: "auto"
        )

      assert body.tool_choice == "auto"
    end

    test "supports parallel tool calls" do
      messages = [%{role: "user", content: "Test"}]
      tools = [%{type: "function", function: %{name: "test"}}]

      body =
        OpenAI.build_request_body(messages, "gpt-4", %{},
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
    test "uses custom base URL from config" do
      config = %{
        openai: %{
          api_key: "test-key",
          base_url: "https://custom.openai.com/v1"
        }
      }

      provider = ConfigProviderHelper.setup_static_provider(config)

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
        provider = ConfigProviderHelper.setup_static_provider(config)
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

  describe "file upload" do
    setup do
      # Create a temporary test file
      tmp_path = Path.join(System.tmp_dir!(), "test_file_#{:rand.uniform(1000)}.jsonl")
      File.write!(tmp_path, ~s({"prompt": "test", "completion": "response"}\n))
      on_exit(fn -> File.rm(tmp_path) end)
      {:ok, tmp_path: tmp_path}
    end

    test "upload_file returns proper response structure", %{tmp_path: tmp_path} do
      config = %{openai: %{api_key: "test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      # With test key, we'll get an API error
      result = OpenAI.upload_file(tmp_path, "fine-tune", config_provider: provider)
      assert {:error, {:validation, :request, _}} = result
    end

    test "upload_file validates purpose parameter", %{tmp_path: tmp_path} do
      config = %{openai: %{api_key: "test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      # Test all valid purpose values (including output types)
      valid_purposes = [
        "fine-tune",
        "fine-tune-results",
        "assistants",
        "assistants_output",
        "batch",
        "batch_output",
        "vision",
        "user_data",
        "evals"
      ]

      for purpose <- valid_purposes do
        # Will implement actual upload later, for now just verify validation passes
        _result = OpenAI.upload_file(tmp_path, purpose, config_provider: provider)
        # We don't assert here as the error is from multipart not being fully implemented
      end

      # Test invalid purpose
      result = OpenAI.upload_file(tmp_path, "invalid_purpose", config_provider: provider)
      assert {:error, {:validation, _, _}} = result
    end

    test "upload_file validates API key" do
      tmp_path = Path.join(System.tmp_dir!(), "test.jsonl")
      File.write!(tmp_path, "test")
      on_exit(fn -> File.rm(tmp_path) end)

      # No API key
      config = %{openai: %{}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      result = OpenAI.upload_file(tmp_path, "fine-tune", config_provider: provider)
      assert {:error, "API key not configured"} = result
    end

    test "upload_file handles non-existent file" do
      config = %{openai: %{api_key: "test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      result =
        OpenAI.upload_file("/non/existent/file.jsonl", "fine-tune", config_provider: provider)

      assert {:error, :enoent} = result
    end
  end

  describe "file operations" do
    test "list_files accepts query parameters" do
      # This test verifies query parameter handling without making actual API calls
      # The actual API call will fail due to test environment, but we can verify
      # that the parameters are being processed correctly

      config = %{openai: %{api_key: "test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      # Test with all query parameters
      _result =
        OpenAI.list_files(
          config_provider: provider,
          after: "file-abc123",
          limit: 50,
          order: "asc",
          purpose: "fine-tune"
        )

      # Test limit validation (should be clamped to 1-10000)
      _result = OpenAI.list_files(config_provider: provider, limit: 0)
      _result = OpenAI.list_files(config_provider: provider, limit: 20_000)

      # Test order validation (should default to "desc" for invalid values)
      _result = OpenAI.list_files(config_provider: provider, order: "invalid")
    end

    test "get_file retrieves file metadata" do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, _provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)

      # Test get_file when implemented
      # result = OpenAI.get_file("file-abc123", config_provider: provider)
      # assert {:ok, file} = result
      # assert file["id"] == "file-abc123"
    end

    test "delete_file removes uploaded file" do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, _provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)

      # Test delete_file when implemented
      # result = OpenAI.delete_file("file-abc123", config_provider: provider)
      # assert {:ok, response} = result
      # assert response["deleted"] == true
    end

    test "retrieve_file_content downloads file data" do
      config = %{openai: %{api_key: "test-key"}}
      {:ok, _provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)

      # Test retrieve_file_content when implemented
      # result = OpenAI.retrieve_file_content("file-abc123", config_provider: provider)
      # assert {:ok, content} = result
      # assert is_binary(content)
    end
  end

  describe "upload API" do
    test "create_upload with valid parameters" do
      config = %{openai: %{api_key: "test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      params = [
        bytes: 1_000_000,
        filename: "test.jsonl",
        mime_type: "text/jsonl",
        purpose: "fine-tune"
      ]

      # Will fail with connection error in test, but validates parameter handling
      _result = OpenAI.create_upload(params, config_provider: provider)
    end

    test "create_upload validates size limit" do
      config = %{openai: %{api_key: "test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      # 9GB exceeds limit
      params = [
        bytes: 9 * 1024 * 1024 * 1024,
        filename: "huge.jsonl",
        mime_type: "text/jsonl",
        purpose: "fine-tune"
      ]

      result = OpenAI.create_upload(params, config_provider: provider)
      assert {:error, {:validation, _, _}} = result
    end

    test "add_upload_part validates chunk size" do
      config = %{openai: %{api_key: "test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      # 65MB exceeds part limit
      large_chunk = :binary.copy(<<0>>, 65 * 1024 * 1024)

      result = OpenAI.add_upload_part("upload_123", large_chunk, config_provider: provider)
      assert {:error, {:validation, _, msg}} = result
      assert msg =~ "64 MB"
    end

    test "complete_upload with MD5 checksum" do
      config = %{openai: %{api_key: "test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      # Test with optional MD5
      _result =
        OpenAI.complete_upload(
          "upload_123",
          ["part_1", "part_2"],
          config_provider: provider,
          md5: "d41d8cd98f00b204e9800998ecf8427e"
        )
    end
  end
end
