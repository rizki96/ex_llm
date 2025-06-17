defmodule ExLLM.Core.StructuredOutputsTest do
  use ExUnit.Case, async: true
  alias ExLLM.Core.StructuredOutputs
  alias ExLLM.Types

  setup do
    # Set mock API keys for testing
    System.put_env("OPENAI_API_KEY", "test-openai-key")
    System.put_env("ANTHROPIC_API_KEY", "test-anthropic-key")
    System.put_env("GOOGLE_API_KEY", "test-google-key")
    System.put_env("GROQ_API_KEY", "test-groq-key")
    System.put_env("XAI_API_KEY", "test-xai-key")

    on_exit(fn ->
      System.delete_env("OPENAI_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")
      System.delete_env("GOOGLE_API_KEY")
      System.delete_env("GROQ_API_KEY")
      System.delete_env("XAI_API_KEY")
    end)
  end

  describe "available?/0" do
    test "returns true since instructor is now required" do
      assert StructuredOutputs.available?() == true
    end
  end

  describe "chat/3" do
    test "returns error for unsupported providers" do
      messages = [%{role: "user", content: "Test"}]
      unsupported_providers = [:bumblebee, :bedrock, :openrouter]

      for provider <- unsupported_providers do
        assert {:error, :unsupported_provider_for_instructor} =
                 StructuredOutputs.chat(provider, messages, response_model: %{name: :string})
      end
    end

    test "validates response_model is required" do
      messages = [%{role: "user", content: "Test"}]

      assert_raise KeyError, fn ->
        StructuredOutputs.chat(:anthropic, messages, [])
      end
    end
  end

  describe "parse_response/2 with simple types" do
    test "parses valid JSON response" do
      response = %Types.LLMResponse{
        content: ~s({"name": "John", "age": 30}),
        model: "test-model",
        usage: %{input_tokens: 10, output_tokens: 20},
        cost: %{input: 0.01, output: 0.02, total: 0.03}
      }

      type_spec = %{name: :string, age: :integer}

      assert {:ok, %{name: "John", age: 30}} =
               StructuredOutputs.parse_response(response, type_spec)
    end

    test "extracts JSON from markdown code blocks" do
      response = %Types.LLMResponse{
        content: """
        Here's the data:

        ```json
        {"name": "Jane", "age": 25}
        ```
        """,
        model: "test-model",
        usage: %{input_tokens: 10, output_tokens: 20},
        cost: %{input: 0.01, output: 0.02, total: 0.03}
      }

      type_spec = %{name: :string, age: :integer}

      assert {:ok, %{name: "Jane", age: 25}} =
               StructuredOutputs.parse_response(response, type_spec)
    end

    test "returns error for invalid JSON" do
      response = %Types.LLMResponse{
        content: "not valid json",
        model: "test-model",
        usage: %{input_tokens: 10, output_tokens: 20},
        cost: %{input: 0.01, output: 0.02, total: 0.03}
      }

      type_spec = %{name: :string}

      assert {:error, {:json_decode_error, _}} =
               StructuredOutputs.parse_response(response, type_spec)
    end

    test "validates types correctly" do
      response = %Types.LLMResponse{
        content: ~s({"name": 123, "age": "not a number"}),
        model: "test-model",
        usage: %{input_tokens: 10, output_tokens: 20},
        cost: %{input: 0.01, output: 0.02, total: 0.03}
      }

      type_spec = %{name: :string, age: :integer}

      assert {:error, {:name, {:invalid_type, :string}}} =
               StructuredOutputs.parse_response(response, type_spec)
    end

    test "handles array types" do
      response = %Types.LLMResponse{
        content: ~s({"tags": ["elixir", "programming", "functional"]}),
        model: "test-model",
        usage: %{input_tokens: 10, output_tokens: 20},
        cost: %{input: 0.01, output: 0.02, total: 0.03}
      }

      type_spec = %{tags: {:array, :string}}

      assert {:ok, %{tags: ["elixir", "programming", "functional"]}} =
               StructuredOutputs.parse_response(response, type_spec)
    end
  end

  describe "simple_schema/2" do
    test "returns error indicating to use type specs" do
      fields = %{name: :string, age: :integer}
      assert {:error, :use_type_spec_instead} = StructuredOutputs.simple_schema(fields)
    end
  end
end
