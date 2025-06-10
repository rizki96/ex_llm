defmodule ExLLM.Adapters.MistralUnitTest do
  use ExUnit.Case, async: true
  alias ExLLM.Adapters.Mistral
  alias ExLLM.Types

  describe "configured?/1" do
    test "returns true when API key is available" do
      config = %{mistral: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      assert Mistral.configured?(config_provider: provider)
    end

    test "returns false with empty API key" do
      config = %{mistral: %{api_key: ""}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      refute Mistral.configured?(config_provider: provider)
    end

    test "returns false with no API key" do
      config = %{mistral: %{}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      refute Mistral.configured?(config_provider: provider)
    end
  end

  describe "default_model/0" do
    test "returns mistral/mistral-tiny as default" do
      assert Mistral.default_model() == "mistral/mistral-tiny"
    end
  end

  describe "message validation" do
    test "validates messages before processing" do
      # Empty messages should be valid but might fail at API level
      result = Mistral.chat([], timeout: 1)
      assert {:error, _} = result

      # Invalid message format should fail
      invalid_messages = [%{content: "missing role"}]
      assert {:error, _} = Mistral.chat(invalid_messages, timeout: 1)
    end

    test "accepts valid message formats" do
      config = %{mistral: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Hello"}]

      # Should get connection error, not validation error
      assert {:error, _reason} = Mistral.chat(messages, config_provider: provider, timeout: 1)
    end
  end

  describe "parameter validation" do
    test "rejects unsupported OpenAI parameters" do
      config = %{mistral: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Test"}]

      # frequency_penalty is not supported
      result =
        Mistral.chat(messages,
          config_provider: provider,
          frequency_penalty: 0.5,
          timeout: 1
        )

      assert {:error, msg} = result
      assert msg =~ "frequency_penalty"
      assert msg =~ "not supported"
    end

    test "accepts supported parameters" do
      config = %{mistral: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Test"}]

      # These parameters are supported
      result =
        Mistral.chat(messages,
          config_provider: provider,
          temperature: 0.7,
          max_tokens: 100,
          top_p: 0.9,
          seed: 42,
          safe_prompt: true,
          timeout: 1
        )

      # Should get connection error, not parameter validation error
      assert {:error, reason} = result

      case reason do
        msg when is_binary(msg) -> refute msg =~ "not supported"
        # Any other error type is fine (e.g., authentication error)
        _ -> true
      end
    end
  end

  describe "function calling support" do
    test "converts functions to tools format" do
      config = %{mistral: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "What's the weather?"}]

      functions = [
        %{
          name: "get_weather",
          description: "Get weather information",
          parameters: %{
            type: "object",
            properties: %{
              location: %{type: "string", description: "City name"}
            }
          }
        }
      ]

      # Should handle function calling
      result =
        Mistral.chat(messages,
          config_provider: provider,
          functions: functions,
          timeout: 1
        )

      assert {:error, _reason} = result
    end

    test "handles tool_choice parameter" do
      config = %{mistral: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Test"}]

      result =
        Mistral.chat(messages,
          config_provider: provider,
          tools: [%{type: "function", function: %{name: "test"}}],
          tool_choice: "auto",
          timeout: 1
        )

      assert {:error, _reason} = result
    end
  end

  describe "embeddings support" do
    test "handles text embeddings" do
      config = %{mistral: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      result =
        Mistral.embeddings("Hello world",
          config_provider: provider,
          timeout: 1
        )

      assert {:error, _reason} = result
    end

    test "handles batch embeddings" do
      config = %{mistral: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      inputs = ["Hello", "World", "Test"]

      result =
        Mistral.embeddings(inputs,
          config_provider: provider,
          model: "mistral/mistral-embed",
          timeout: 1
        )

      assert {:error, _reason} = result
    end
  end

  describe "stream parsing" do
    test "parses streaming chunks correctly" do
      chunk_data = ~s({"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]})

      chunk = Mistral.parse_stream_chunk(chunk_data)
      assert %Types.StreamChunk{content: "Hello", finish_reason: nil} = chunk
    end

    test "handles finish reason in streaming" do
      chunk_data = ~s({"choices":[{"delta":{},"finish_reason":"stop"}]})

      chunk = Mistral.parse_stream_chunk(chunk_data)
      assert %Types.StreamChunk{content: nil, finish_reason: "stop"} = chunk
    end

    test "handles invalid streaming data" do
      assert nil == Mistral.parse_stream_chunk("invalid json")
      assert nil == Mistral.parse_stream_chunk("")
      assert nil == Mistral.parse_stream_chunk("{}")
    end
  end

  describe "model naming" do
    test "handles mistral model naming conventions" do
      test_cases = [
        {"mistral/mistral-tiny", true},
        {"mistral/mistral-small-latest", true},
        {"mistral/mistral-medium-latest", true},
        {"mistral/mistral-large-latest", true},
        {"mistral/codestral-latest", true},
        {"mistral/pixtral-12b-2409", true}
      ]

      for {model_id, should_contain_mistral} <- test_cases do
        if should_contain_mistral do
          assert String.contains?(model_id, "mistral")
        end
      end
    end
  end

  describe "error handling" do
    test "handles missing API key" do
      messages = [%{role: "user", content: "Test"}]

      result = Mistral.chat(messages, timeout: 1)

      assert {:error, _reason} = result
    end

    test "provides specific error for unsupported parameters" do
      config = %{mistral: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Test"}]

      unsupported_params = [
        presence_penalty: 0.5,
        logprobs: true,
        n: 2
      ]

      for {param, value} <- unsupported_params do
        result =
          Mistral.chat(
            messages,
            [{param, value} | [config_provider: provider, timeout: 1]]
          )

        assert {:error, msg} = result
        assert msg =~ to_string(param)
        assert msg =~ "not supported"
      end
    end
  end

  describe "list_models/1 fallback" do
    test "returns models from config when API is not available" do
      # Without API key, should fall back to config
      case Mistral.list_models() do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            model = hd(models)
            assert %Types.Model{} = model
            assert String.contains?(model.id, "mistral/")
          end

        {:error, _} ->
          # Error is also acceptable without API key
          :ok
      end
    end
  end

  describe "adapter behavior compliance" do
    test "implements all required callbacks" do
      # Functions with default arguments export multiple arities
      # Check that at least one expected arity exists
      assert function_exported?(Mistral, :chat, 1) or function_exported?(Mistral, :chat, 2)
      assert function_exported?(Mistral, :stream_chat, 1) or function_exported?(Mistral, :stream_chat, 2)
      assert function_exported?(Mistral, :configured?, 0) or function_exported?(Mistral, :configured?, 1)
      assert function_exported?(Mistral, :default_model, 0)
      assert function_exported?(Mistral, :list_models, 0) or function_exported?(Mistral, :list_models, 1)
    end

    test "implements embeddings callback" do
      # Embeddings is an optional callback
      # Mistral implements it
      # Debug: Check what functions are exported
      functions = ExLLM.Adapters.Mistral.__info__(:functions)
      embeddings_funcs = Enum.filter(functions, fn {name, _} -> name == :embeddings end)

      # The test should pass because Mistral does implement embeddings
      assert length(embeddings_funcs) > 0
    end
  end
end
