defmodule ExLLM.PipelineTest do
  use ExUnit.Case, async: true

  alias ExLLM.Pipeline
  alias ExLLM.Pipeline.Request
  alias ExLLM.Plugs.{ValidateProvider, FetchConfig, ManageContext}

  describe "Pipeline.run/2" do
    test "executes plugs in sequence" do
      request = Request.new(:openai, [%{role: "user", content: "Hello"}])

      pipeline = [
        ValidateProvider,
        FetchConfig,
        ManageContext
      ]

      result = Pipeline.run(request, pipeline)

      # Check that plugs were executed
      assert result.assigns[:provider_validated] == true
      assert result.assigns[:context_managed] == true
      assert is_map(result.config)
      assert result.state == :pending
      assert result.halted == false
    end

    test "halts pipeline when plug halts" do
      request = Request.new(:invalid_provider, [%{role: "user", content: "Hello"}])

      pipeline = [
        ValidateProvider,
        # Should not execute
        FetchConfig,
        # Should not execute
        ManageContext
      ]

      result = Pipeline.run(request, pipeline)

      # Check that pipeline halted
      assert result.halted == true
      assert result.state == :error
      assert length(result.errors) == 1
      assert hd(result.errors).error == :unsupported_provider

      # These should not be set since pipeline halted
      assert result.assigns[:context_managed] == nil
      assert result.config == %{}
    end

    test "handles plug errors gracefully" do
      defmodule ErrorPlug do
        use ExLLM.Plug

        def call(_request, _opts) do
          raise "Boom!"
        end
      end

      request = Request.new(:openai, [])
      pipeline = [ErrorPlug]

      result = Pipeline.run(request, pipeline)

      assert result.halted == true
      assert result.state == :error
      assert length(result.errors) == 1
      assert hd(result.errors).message == "Boom!"
    end

    test "supports plug options" do
      request = Request.new(:openai, [%{role: "user", content: "Hello"}])

      pipeline = [
        {ValidateProvider, providers: [:openai, :anthropic]},
        FetchConfig,
        {ManageContext, strategy: :none, max_tokens: 1000}
      ]

      result = Pipeline.run(request, pipeline)

      assert result.state == :pending
      assert result.halted == false
    end
  end

  describe "Pipeline.Builder" do
    defmodule TestPipeline do
      use Pipeline.Builder

      plug(ValidateProvider)
      plug(FetchConfig)
      plug(ManageContext, strategy: :truncate)
    end

    test "creates a runnable pipeline module" do
      request = Request.new(:openai, [%{role: "user", content: "Hello"}])

      result = TestPipeline.run(request)

      assert result.assigns[:provider_validated] == true
      assert result.assigns[:context_managed] == true
      assert is_map(result.config)
    end

    test "exposes pipeline plugs" do
      plugs = TestPipeline.__plugs__()

      assert length(plugs) == 3
      assert {ValidateProvider, []} in plugs
      assert {FetchConfig, []} in plugs
      assert {ManageContext, [strategy: :truncate]} in plugs
    end
  end

  describe "Request helpers" do
    test "assign/3 stores values" do
      request =
        Request.new(:openai, [])
        |> Request.assign(:foo, "bar")
        |> Request.assign(:baz, 42)

      assert request.assigns.foo == "bar"
      assert request.assigns.baz == 42
    end

    test "halt/1 halts the request" do
      request =
        Request.new(:openai, [])
        |> Request.halt()

      assert request.halted == true
    end

    test "add_error/2 accumulates errors" do
      request =
        Request.new(:openai, [])
        |> Request.add_error(%{error: :first})
        |> Request.add_error(%{error: :second})

      assert length(request.errors) == 2
      assert Enum.map(request.errors, & &1.error) == [:second, :first]
    end

    test "halt_with_error/2 halts and adds error" do
      request =
        Request.new(:openai, [])
        |> Request.halt_with_error(%{error: :failed})

      assert request.halted == true
      assert request.state == :error
      assert length(request.errors) == 1
    end
  end
end
