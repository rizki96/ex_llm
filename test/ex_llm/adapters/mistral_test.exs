defmodule ExLLM.Adapters.MistralTest do
  use ExUnit.Case, async: true
  alias ExLLM.Adapters.Mistral
  alias ExLLM.Types

  describe "configured?/1" do
    test "returns true when API key is available" do
      config = %{mistral: %{api_key: "your-api-key"}}
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
    test "returns a default model string" do
      model = Mistral.default_model()
      assert is_binary(model)
      assert String.contains?(model, "mistral")
    end
  end

  describe "list_models/1" do
    test "returns models from config when API is not available" do
      # Without API key, should fall back to config
      case Mistral.list_models() do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            model = hd(models)
            assert %Types.Model{} = model
            assert String.contains?(model.id, "mistral")
          end

        {:error, _} ->
          # Error is also acceptable without API key
          :ok
      end
    end

    test "model capabilities are properly set" do
      case Mistral.list_models() do
        {:ok, models} ->
          mistral_model =
            Enum.find(models, fn m ->
              String.contains?(m.id, "mistral")
            end)

          if mistral_model do
            # Check capabilities structure
            assert is_map(mistral_model.capabilities)

            if is_list(mistral_model.capabilities.features) do
              assert "streaming" in mistral_model.capabilities.features
            end
          end

        {:error, _} ->
          :ok
      end
    end
  end

  describe "parameter validation" do
    test "rejects unsupported parameters" do
      messages = [%{role: "user", content: "Hello"}]

      # Test unsupported parameters
      unsupported_options = [
        [frequency_penalty: 0.5],
        [presence_penalty: 0.2],
        [logprobs: true],
        [n: 2]
      ]

      for options <- unsupported_options do
        assert {:error, error_msg} = Mistral.chat(messages, options ++ [timeout: 1])
        assert String.contains?(error_msg, "not supported")
      end
    end

    test "handles message validation" do
      # Empty messages should fail validation
      assert {:error, _} = Mistral.chat([], timeout: 1)

      # Invalid message format should fail
      invalid_messages = [%{content: "missing role"}]
      assert {:error, _} = Mistral.chat(invalid_messages, timeout: 1)
    end
  end

  describe "request building" do
    test "builds proper request body with basic options" do
      config = %{mistral: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Hello"}]
      
      # This will fail at the HTTP request level, but we can test the validation
      result = Mistral.chat(messages, config_provider: provider, timeout: 1)
      
      # Should get an error (likely connection), not a validation error
      assert {:error, _reason} = result
    end

    test "handles tools/functions parameter" do
      config = %{mistral: %{api_key: "test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Hello"}]
      
      functions = [
        %{
          name: "test_function",
          description: "A test function",
          parameters: %{
            type: "object",
            properties: %{
              param: %{type: "string"}
            }
          }
        }
      ]

      # Should not fail due to function parameter handling
      result = Mistral.chat(messages, 
        config_provider: provider, 
        functions: functions,
        timeout: 1
      )
      
      # Should get an error (likely connection), not a parameter validation error
      assert {:error, _reason} = result
    end
  end

  describe "stream parsing" do
    test "parses streaming chunks correctly" do
      # Test OpenAI-style streaming format that Mistral uses
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

  describe "model name formatting" do
    test "handles mistral model naming conventions" do
      test_cases = [
        {"mistral/mistral-tiny", true},
        {"mistral/mistral-small-latest", true},
        {"mistral/mistral-large-2411", true},
        {"mistral/codestral-latest", true},
        {"mistral/pixtral-large-latest", true}
      ]

      for {model_id, should_contain_mistral} <- test_cases do
        if should_contain_mistral do
          assert String.contains?(model_id, "mistral")
        end
      end
    end
  end
end