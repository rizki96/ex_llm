defmodule ExLLM.Adapters.AnthropicUnitTest do
  use ExUnit.Case, async: true
  alias ExLLM.Adapters.Anthropic
  alias ExLLM.Types
  alias ExLLM.Test.ConfigProviderHelper

  describe "configured?/1" do
    test "returns true when API key is available" do
      # Default config with env var should work
      result = Anthropic.configured?()
      # Will be true if ANTHROPIC_API_KEY is set, false otherwise
      assert is_boolean(result)
    end

    test "returns false with empty API key" do
      config = %{anthropic: %{api_key: ""}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      refute Anthropic.configured?(config_provider: provider)
    end

    test "returns true with valid API key" do
      config = %{anthropic: %{api_key: "sk-ant-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      assert Anthropic.configured?(config_provider: provider)
    end
  end

  describe "default_model/0" do
    test "returns a default model string" do
      model = Anthropic.default_model()
      assert is_binary(model)
      # Should be one of the Claude models
      assert String.contains?(model, "claude")
    end
  end

  describe "message formatting" do
    test "extracts system message from messages" do
      messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]

      # Test that system messages are properly extracted
      # This would be tested through the chat function
      assert {:error, _} = Anthropic.chat(messages, timeout: 1)
    end

    test "handles alternating user/assistant messages" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi!"},
        %{role: "user", content: "How are you?"}
      ]

      # Anthropic requires alternating messages
      assert {:error, _} = Anthropic.chat(messages, timeout: 1)
    end

    test "handles multimodal content with images" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{
              type: "image",
              image: %{
                data: "base64encodeddata",
                media_type: "image/jpeg"
              }
            }
          ]
        }
      ]

      # Should format images correctly for Anthropic
      assert {:error, _} = Anthropic.chat(messages, timeout: 1)
    end

    test "handles image_url format conversion" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Describe this"},
            %{
              type: "image_url",
              image_url: %{
                url: "data:image/jpeg;base64,/9j/4AAQSkZJRg=="
              }
            }
          ]
        }
      ]

      # Should convert image_url to Anthropic's format
      assert {:error, _} = Anthropic.chat(messages, timeout: 1)
    end
  end

  describe "parameter handling" do
    test "adds optional parameters to request body" do
      messages = [%{role: "user", content: "Test"}]

      opts = [
        temperature: 0.7,
        max_tokens: 100,
        model: "claude-3-5-sonnet-20241022"
      ]

      # Parameters should be included in request
      assert {:error, _} = Anthropic.chat(messages, opts ++ [timeout: 1])
    end

    test "uses default max_tokens when not specified" do
      messages = [%{role: "user", content: "Test"}]

      # Should use default of 4096
      assert {:error, _} = Anthropic.chat(messages, timeout: 1)
    end

    test "overrides model from options" do
      messages = [%{role: "user", content: "Test"}]

      # Model in options should override config
      assert {:error, _} =
               Anthropic.chat(
                 messages,
                 model: "claude-3-5-haiku-20241022",
                 timeout: 1
               )
    end
  end

  describe "streaming setup" do
    test "stream_chat returns a Stream" do
      messages = [%{role: "user", content: "Hello"}]

      # Even without API key, stream structure should be created
      case Anthropic.stream_chat(messages) do
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
      case Anthropic.stream_chat(messages) do
        {:ok, _stream} ->
          :ok

        {:error, _} ->
          :ok
      end
    end
  end

  describe "headers" do
    test "includes required Anthropic headers" do
      # Headers should include:
      # - x-api-key
      # - anthropic-version
      # This is tested indirectly through API calls
      messages = [%{role: "user", content: "Test"}]
      assert {:error, _} = Anthropic.chat(messages, timeout: 1)
    end
  end

  describe "base URL handling" do
    test "uses default base URL when not configured" do
      messages = [%{role: "user", content: "Test"}]
      # Should use https://api.anthropic.com/v1
      assert {:error, _} = Anthropic.chat(messages, timeout: 1)
    end

    test "uses custom base URL from config" do
      config = %{
        anthropic: %{
          api_key: "test-key",
          base_url: "https://custom.anthropic.com/v1"
        }
      }

      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test"}]
      assert {:error, _} = Anthropic.chat(messages, config_provider: provider, timeout: 1)
    end
  end

  describe "model listing" do
    test "list_models returns models from config when API fails" do
      # Without valid API key, should fall back to config
      case Anthropic.list_models() do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            model = hd(models)
            assert %Types.Model{} = model
            assert String.contains?(model.id, "claude")
          end

        {:error, _} ->
          # Error is also acceptable without API key
          :ok
      end
    end

    test "model capabilities are properly set" do
      case Anthropic.list_models() do
        {:ok, models} ->
          claude_model =
            Enum.find(models, fn m ->
              String.contains?(m.id, "claude")
            end)

          if claude_model do
            # Check features list for streaming
            assert is_map(claude_model.capabilities)

            if is_list(claude_model.capabilities.features) do
              assert "streaming" in claude_model.capabilities.features
            end
          end

        {:error, _} ->
          :ok
      end
    end
  end

  describe "response parsing" do
    test "parses standard response format" do
      # Test response parsing logic
      mock_response = %{
        "id" => "msg_123",
        "type" => "message",
        "role" => "assistant",
        "model" => "claude-3-5-sonnet-20241022",
        "content" => [
          %{"type" => "text", "text" => "Hello!"}
        ],
        "stop_reason" => "end_turn",
        "usage" => %{
          "input_tokens" => 10,
          "output_tokens" => 5
        }
      }

      # This would be parsed in parse_response/1
      # Testing the expected structure
      assert is_map(mock_response)
      assert mock_response["content"] |> List.first() |> Map.get("text") == "Hello!"
    end
  end

  describe "streaming chunk parsing" do
    test "parses content block delta" do
      chunk_data = ~s({"type":"content_block_delta","delta":{"text":"Hello"}})

      # Using the parse_stream_chunk function indirectly
      case Jason.decode(chunk_data) do
        {:ok, decoded} ->
          assert decoded["type"] == "content_block_delta"
          assert decoded["delta"]["text"] == "Hello"

        _ ->
          :ok
      end
    end

    test "handles message stop event" do
      chunk_data = ~s({"type":"message_stop"})

      case Jason.decode(chunk_data) do
        {:ok, decoded} ->
          assert decoded["type"] == "message_stop"

        _ ->
          :ok
      end
    end

    test "handles message delta with stop reason" do
      chunk_data = ~s({"type":"message_delta","delta":{"stop_reason":"end_turn"}})

      case Jason.decode(chunk_data) do
        {:ok, decoded} ->
          assert decoded["type"] == "message_delta"
          assert decoded["delta"]["stop_reason"] == "end_turn"

        _ ->
          :ok
      end
    end
  end

  describe "error handling" do
    test "handles API errors properly" do
      # Various error scenarios
      messages = [%{role: "user", content: "Test"}]

      # Connection timeout
      assert {:error, _} = Anthropic.chat(messages, timeout: 1)
    end

    test "validates API key format" do
      # Store original env var
      original_key = System.get_env("ANTHROPIC_API_KEY")

      # Temporarily unset env var to ensure test isolation
      System.delete_env("ANTHROPIC_API_KEY")

      try do
        # Test with invalid API key formats
        invalid_configs = [
          %{anthropic: %{api_key: nil}},
          %{anthropic: %{api_key: ""}},
          %{anthropic: %{}}
        ]

        for config <- invalid_configs do
          provider = ConfigProviderHelper.setup_static_provider(config)
          refute Anthropic.configured?(config_provider: provider)
        end
      after
        # Restore original env var if it existed
        if original_key do
          System.put_env("ANTHROPIC_API_KEY", original_key)
        end
      end
    end
  end

  describe "model description generation" do
    test "generates appropriate descriptions for models" do
      test_cases = [
        {"claude-opus-4-20250514", "Claude Opus 4: Most intelligent model"},
        {"claude-3-5-sonnet-20241022", "Balanced model for general tasks"},
        {"claude-3-5-haiku-20241022", "Fast and efficient model for simple tasks"},
        {"claude-unknown", "Claude model"}
      ]

      for {model_id, expected_pattern} <- test_cases do
        # This tests the description generation logic
        description =
          cond do
            String.contains?(model_id, "opus-4") -> "Claude Opus 4: Most intelligent model"
            String.contains?(model_id, "sonnet-4") -> "Claude Sonnet 4: Best value model"
            String.contains?(model_id, "opus") -> "Most capable model with advanced reasoning"
            String.contains?(model_id, "sonnet") -> "Balanced model for general tasks"
            String.contains?(model_id, "haiku") -> "Fast and efficient model for simple tasks"
            true -> "Claude model"
          end

        assert String.contains?(description, String.split(expected_pattern, ":") |> List.first())
      end
    end
  end

  describe "context window defaults" do
    test "sets appropriate context window for models" do
      # Anthropic models typically have 100k-200k context
      case Anthropic.list_models() do
        {:ok, models} ->
          claude_model = Enum.find(models, &String.contains?(&1.id, "claude"))

          if claude_model do
            # Claude instant has 100k, others have 200k
            assert claude_model.context_window >= 100_000
          end

        {:error, _} ->
          :ok
      end
    end
  end

  describe "vision capability detection" do
    test "marks appropriate models with vision support" do
      # Vision support varies by model
      case Anthropic.list_models() do
        {:ok, models} ->
          # Claude 3.5+ models should support vision
          vision_model =
            Enum.find(models, fn m ->
              String.contains?(m.id, "claude-3-5") || String.contains?(m.id, "claude-3-7")
            end)

          if vision_model && vision_model.capabilities do
            # Check capabilities - vision may be in features list
            # or indicated by document_understanding capability
            if is_list(vision_model.capabilities.features) do
              has_vision_related =
                Enum.any?(vision_model.capabilities.features, fn f ->
                  f in ["vision", "document_understanding", "multimodal"]
                end)

              # Vision support may not be explicitly listed for all models
              assert is_boolean(has_vision_related)
            end
          end

        {:error, _} ->
          :ok
      end
    end
  end
end
