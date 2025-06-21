defmodule ExLLM.IntegrationTest do
  use ExUnit.Case, async: true

  alias ExLLM.Pipeline.Request
  alias ExLLM.Plugs

  describe "integration with mock provider" do
    test "full pipeline execution with mock provider" do
      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Hello, how are you?"}
      ]

      {:ok, response} = ExLLM.chat(:mock, messages, temperature: 0.7)

      assert response.content =~ "Mock response"
      assert response.role == "assistant"
      assert response.provider == :mock
      assert response.usage.total_tokens == 30
    end

    test "custom pipeline with mock provider" do
      # Reset mock provider to ensure clean state
      ExLLM.Providers.Mock.reset()
      
      # Also clear Application environment to ensure clean state
      Application.delete_env(:ex_llm, :mock_responses)
      
      messages = [%{role: "user", content: "Test message"}]

      # Build a custom pipeline
      builder =
        ExLLM.build(:mock, messages)
        |> ExLLM.with_model("custom-model")
        |> ExLLM.with_temperature(0.5)

      # Execute with custom pipeline
      pipeline = [
        Plugs.ValidateProvider,
        Plugs.FetchConfig,
        {Plugs.Providers.MockHandler,
         response: %{
           content: "Custom response",
           role: "assistant",
           model: "custom-model",
           usage: %{prompt_tokens: 5, completion_tokens: 10, total_tokens: 15},
           provider: :mock
         }}
      ]

      result = ExLLM.run(builder.request, pipeline)

      assert result.state == :completed
      assert result.result.content == "Custom response"
      assert result.result.model == "custom-model"
    end

    test "error handling in pipeline" do
      messages = [%{role: "user", content: "Test"}]

      # Create a pipeline that will error
      pipeline = [
        Plugs.ValidateProvider,
        {Plugs.Providers.MockHandler, error: :simulated_error}
      ]

      request = Request.new(:mock, messages)
      result = ExLLM.run(request, pipeline)

      assert result.state == :error
      assert result.halted == true
      assert length(result.errors) == 1
      assert hd(result.errors).error == :simulated_error
    end
  end

  describe "provider-specific pipelines" do
    test "OpenAI pipeline structure" do
      pipeline = ExLLM.Providers.get_pipeline(:openai, :chat)

      # Verify key plugs are present
      plug_modules =
        Enum.map(pipeline, fn
          {module, _opts} -> module
          module -> module
        end)

      assert Plugs.ValidateProvider in plug_modules
      assert Plugs.FetchConfig in plug_modules
      assert Plugs.ManageContext in plug_modules
      assert Plugs.BuildTeslaClient in plug_modules
      assert Plugs.Cache in plug_modules
      assert Plugs.Providers.OpenAIPrepareRequest in plug_modules
      assert Plugs.ExecuteRequest in plug_modules
      assert Plugs.Providers.OpenAIParseResponse in plug_modules
      assert Plugs.TrackCost in plug_modules
    end

    test "Anthropic pipeline structure" do
      pipeline = ExLLM.Providers.get_pipeline(:anthropic, :chat)

      plug_modules =
        Enum.map(pipeline, fn
          {module, _opts} -> module
          module -> module
        end)

      assert Plugs.Providers.AnthropicPrepareRequest in plug_modules
      assert Plugs.Providers.AnthropicParseResponse in plug_modules
    end

    test "Gemini pipeline structure" do
      pipeline = ExLLM.Providers.get_pipeline(:gemini, :chat)

      plug_modules =
        Enum.map(pipeline, fn
          {module, _opts} -> module
          module -> module
        end)

      assert Plugs.Providers.GeminiPrepareRequest in plug_modules
      assert Plugs.Providers.GeminiParseResponse in plug_modules
    end
  end

  describe "fluent API" do
    test "builder pattern works correctly" do
      builder =
        ExLLM.build(:mock, [%{role: "user", content: "Hello"}])
        |> ExLLM.with_model("test-model")
        |> ExLLM.with_temperature(0.8)
        |> ExLLM.with_max_tokens(500)

      assert builder.request.provider == :mock
      assert builder.request.options.model == "test-model"
      assert builder.request.options.temperature == 0.8
      assert builder.request.options.max_tokens == 500
    end

    test "execute with fluent API" do
      {:ok, response} =
        ExLLM.build(:mock, [%{role: "user", content: "Hello"}])
        |> ExLLM.with_model("fluent-model")
        |> ExLLM.execute()

      assert response.content =~ "Mock response"
      assert response.mock_config.model == "fluent-model"
    end
  end
end
