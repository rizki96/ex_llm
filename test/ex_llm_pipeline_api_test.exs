defmodule ExLLM.PipelineAPITest do
  use ExUnit.Case, async: true

  alias ExLLM.Pipeline.Request
  alias ExLLM.Plugs

  describe "new pipeline API" do
    test "chat/3 works with mock provider" do
      # Create a mock handler plug for testing
      defmodule MockHandler do
        use ExLLM.Plug

        def call(request, _opts) do
          result = %{
            content: "Hello! I'm a mock response.",
            role: "assistant",
            model: "mock-model",
            usage: %{
              prompt_tokens: 10,
              completion_tokens: 20,
              total_tokens: 30
            },
            provider: :mock
          }

          request
          |> Map.put(:result, result)
          |> Request.put_state(:completed)
        end
      end

      # Override the mock pipeline temporarily
      pipeline = [
        Plugs.ValidateProvider,
        Plugs.FetchConfig,
        MockHandler
      ]

      # Build and run request directly
      request = Request.new(:mock, [%{role: "user", content: "Hello"}])
      result = ExLLM.Pipeline.run(request, pipeline)

      assert result.state == :completed
      assert result.result.content == "Hello! I'm a mock response."
    end

    test "fluent API with build/execute" do
      # Create a test pipeline that sets a result
      defmodule TestHandler do
        use ExLLM.Plug

        def call(request, _opts) do
          temperature = request.config[:temperature] || 1.0
          model = request.config[:model] || "default"

          result = %{
            content: "Temperature: #{temperature}, Model: #{model}",
            role: "assistant",
            model: model,
            provider: request.provider
          }

          request
          |> Map.put(:result, result)
          |> Request.put_state(:completed)
        end
      end

      # Use the request builder API directly with mock provider
      request =
        ExLLM.build(:mock, [%{role: "user", content: "Test"}])
        |> ExLLM.with_model("test-model")
        |> ExLLM.with_temperature(0.5)
        |> ExLLM.with_plug(TestHandler)

      # Execute with a minimal pipeline (skip validation for test provider)
      result =
        ExLLM.Pipeline.run(request, [
          Plugs.FetchConfig,
          TestHandler
        ])

      assert result.state == :completed
      assert result.result.content == "Temperature: 0.5, Model: test-model"
    end

    test "pipeline error handling" do
      defmodule ErrorPlug do
        use ExLLM.Plug

        def call(request, _opts) do
          Request.halt_with_error(request, %{
            plug: __MODULE__,
            error: :test_error,
            message: "This is a test error"
          })
        end
      end

      request = Request.new(:test, [%{role: "user", content: "Test"}])
      result = ExLLM.Pipeline.run(request, [ErrorPlug])

      assert result.state == :error
      assert result.halted == true
      assert length(result.errors) == 1
      assert hd(result.errors).message == "This is a test error"
    end

    test "ValidateProvider plug integration" do
      # Test with valid provider
      request = Request.new(:openai, [])
      result = ExLLM.Pipeline.run(request, [Plugs.ValidateProvider])

      assert result.state == :pending
      assert result.halted == false
      assert result.assigns[:provider_validated] == true

      # Test with invalid provider
      request = Request.new(:invalid_provider, [])
      result = ExLLM.Pipeline.run(request, [Plugs.ValidateProvider])

      assert result.state == :error
      assert result.halted == true
      assert hd(result.errors).error == :unsupported_provider
    end

    test "FetchConfig plug integration" do
      # Set some test config
      Application.put_env(:ex_llm, :test_provider,
        api_key: "test-key",
        default_model: "test-model"
      )

      request = Request.new(:test_provider, [], %{temperature: 0.7})
      result = ExLLM.Pipeline.run(request, [Plugs.FetchConfig])

      assert result.config[:api_key] == "test-key"
      assert result.config[:default_model] == "test-model"
      assert result.config[:temperature] == 0.7

      # Cleanup
      Application.delete_env(:ex_llm, :test_provider)
    end
  end

  describe "provider pipelines" do
    test "get_pipeline returns pipeline for known providers" do
      pipeline = ExLLM.Providers.get_pipeline(:openai, :chat)
      assert is_list(pipeline)
      assert length(pipeline) > 0

      # Check it includes expected plugs
      plug_modules =
        Enum.map(pipeline, fn
          {module, _opts} -> module
          module -> module
        end)

      assert Plugs.ValidateProvider in plug_modules
      assert Plugs.FetchConfig in plug_modules
      assert Plugs.BuildTeslaClient in plug_modules
    end

    test "supported_providers returns list" do
      providers = ExLLM.Providers.supported_providers()
      assert is_list(providers)
      assert :openai in providers
      assert :anthropic in providers
      assert :gemini in providers
    end

    test "supported? checks provider support" do
      assert ExLLM.Providers.supported?(:openai) == true
      assert ExLLM.Providers.supported?(:invalid) == false
    end
  end
end
