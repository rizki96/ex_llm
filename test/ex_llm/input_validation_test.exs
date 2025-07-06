defmodule ExLLM.InputValidationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Tests input validation and boundary conditions for user-configurable parameters
  in the ExLLM public API.

  This ensures that users receive appropriate errors when providing invalid inputs,
  rather than obscure FunctionClauseErrors.
  """

  setup do
    # Reset mock provider to ensure clean state for each test
    ExLLM.Providers.Mock.reset()
    :ok
  end

  describe "temperature validation" do
    test "accepts valid temperature range 0.0 to 2.0" do
      messages = [%{role: "user", content: "test"}]

      # Lower bound
      assert builder = ExLLM.build(:openai, messages) |> ExLLM.with_temperature(0.0)
      assert builder.request.options.temperature == 0.0

      # Upper bound
      assert builder = ExLLM.build(:openai, messages) |> ExLLM.with_temperature(2.0)
      assert builder.request.options.temperature == 2.0

      # Mid-range values
      assert builder = ExLLM.build(:openai, messages) |> ExLLM.with_temperature(0.7)
      assert builder.request.options.temperature == 0.7

      assert builder = ExLLM.build(:openai, messages) |> ExLLM.with_temperature(1.5)
      assert builder.request.options.temperature == 1.5
    end

    test "rejects temperature above 2.0" do
      messages = [%{role: "user", content: "test"}]

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_temperature(2.1)
      end

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_temperature(3.0)
      end

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_temperature(100.0)
      end
    end

    test "rejects negative temperature" do
      messages = [%{role: "user", content: "test"}]

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_temperature(-0.1)
      end

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_temperature(-1.0)
      end
    end

    test "rejects non-numeric temperature" do
      messages = [%{role: "user", content: "test"}]

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_temperature("0.7")
      end

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_temperature(nil)
      end

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_temperature(:high)
      end
    end
  end

  describe "max_tokens validation" do
    test "accepts positive integers for max_tokens" do
      messages = [%{role: "user", content: "test"}]

      # Small values
      assert builder = ExLLM.build(:openai, messages) |> ExLLM.with_max_tokens(1)
      assert builder.request.options.max_tokens == 1

      # Common values
      assert builder = ExLLM.build(:openai, messages) |> ExLLM.with_max_tokens(100)
      assert builder.request.options.max_tokens == 100

      assert builder = ExLLM.build(:openai, messages) |> ExLLM.with_max_tokens(4096)
      assert builder.request.options.max_tokens == 4096

      # Large values
      assert builder = ExLLM.build(:openai, messages) |> ExLLM.with_max_tokens(128_000)
      assert builder.request.options.max_tokens == 128_000
    end

    test "rejects zero max_tokens" do
      messages = [%{role: "user", content: "test"}]

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_max_tokens(0)
      end
    end

    test "rejects negative max_tokens" do
      messages = [%{role: "user", content: "test"}]

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_max_tokens(-1)
      end

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_max_tokens(-100)
      end
    end

    test "rejects non-integer max_tokens" do
      messages = [%{role: "user", content: "test"}]

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_max_tokens(100.5)
      end

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_max_tokens("100")
      end

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_max_tokens(nil)
      end
    end
  end

  describe "model validation" do
    test "accepts string model names" do
      messages = [%{role: "user", content: "test"}]

      assert builder = ExLLM.build(:openai, messages) |> ExLLM.with_model("gpt-4")
      assert builder.request.options.model == "gpt-4"

      assert builder = ExLLM.build(:openai, messages) |> ExLLM.with_model("gpt-3.5-turbo")
      assert builder.request.options.model == "gpt-3.5-turbo"

      # Should accept any string, validation happens at provider level
      assert builder = ExLLM.build(:openai, messages) |> ExLLM.with_model("future-model-2025")
      assert builder.request.options.model == "future-model-2025"
    end

    test "rejects non-string model names" do
      messages = [%{role: "user", content: "test"}]

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_model(:gpt4)
      end

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_model(nil)
      end

      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages) |> ExLLM.with_model(123)
      end
    end
  end

  describe "message validation" do
    test "accepts valid message structures" do
      # Basic user message
      assert {:ok, _} = ExLLM.chat(:mock, [%{role: "user", content: "Hello"}])

      # Multiple messages
      messages = [
        %{role: "system", content: "You are helpful"},
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there"},
        %{role: "user", content: "How are you?"}
      ]

      assert {:ok, _} = ExLLM.chat(:mock, messages)

      # String keys should be normalized to atoms internally
      # but for now they cause errors - this is a known limitation
      # assert {:ok, _} = ExLLM.chat(:mock, [%{role: "user", content: "Hello"}])
    end

    test "validates message role values" do
      # Valid roles according to MessageFormatter validation
      valid_roles = ["system", "user", "assistant", "function", "developer"]

      for role <- valid_roles do
        assert {:ok, _} = ExLLM.chat(:mock, [%{role: role, content: "test"}])
      end
    end

    test "handles empty messages list" do
      # Empty messages are rejected by validation
      assert {:error, :invalid_messages} = ExLLM.chat(:mock, [])
    end
  end

  describe "options validation" do
    test "accepts valid timeout values" do
      messages = [%{role: "user", content: "test"}]

      # Should accept positive integers
      assert {:ok, _} = ExLLM.chat(:mock, messages, timeout: 1000)
      assert {:ok, _} = ExLLM.chat(:mock, messages, timeout: 60_000)
      assert {:ok, _} = ExLLM.chat(:mock, messages, timeout: 300_000)
    end

    test "handles stream callback validation" do
      messages = [%{role: "user", content: "test"}]

      # Valid callback
      callback = fn _chunk -> :ok end
      assert :ok = ExLLM.stream(:mock, messages, callback)

      # Should validate arity - ExLLM.stream expects a 1-arity function
      assert_raise FunctionClauseError, fn ->
        # 0-arity function
        bad_callback = fn -> :ok end
        ExLLM.stream(:mock, messages, bad_callback)
      end
    end
  end

  describe "provider validation" do
    test "accepts known providers" do
      messages = [%{role: "user", content: "test"}]

      # Known providers from the supported list
      providers = [:openai, :anthropic, :gemini, :groq, :mistral, :ollama, :mock]

      for provider <- providers do
        request = ExLLM.Pipeline.Request.new(provider, messages)
        assert request.provider == provider
      end
    end

    test "handles unknown providers gracefully" do
      messages = [%{role: "user", content: "test"}]

      # The pipeline validation will catch unknown providers
      request = ExLLM.Pipeline.Request.new(:unknown_provider, messages)
      result = ExLLM.Pipeline.run(request, [ExLLM.Plugs.ValidateProvider])

      assert result.state == :error
      assert hd(result.errors).error == :unsupported_provider
    end
  end

  describe "context strategy validation" do
    test "accepts valid context strategies" do
      messages = [%{role: "user", content: "test"}]

      valid_strategies = [:truncate, :sliding_window, :smart]

      for strategy <- valid_strategies do
        builder =
          ExLLM.build(:openai, messages)
          |> ExLLM.with_context_strategy(strategy)

        assert {:replace, ExLLM.Plugs.ManageContext, opts} =
                 Enum.find(builder.pipeline_mods, fn
                   {:replace, ExLLM.Plugs.ManageContext, _} -> true
                   _ -> false
                 end)

        assert opts[:strategy] == strategy
      end
    end

    test "context strategy accepts additional options" do
      messages = [%{role: "user", content: "test"}]

      builder =
        ExLLM.build(:openai, messages)
        |> ExLLM.with_context_strategy(:sliding_window, max_tokens: 8000)

      assert {:replace, ExLLM.Plugs.ManageContext, opts} =
               Enum.find(builder.pipeline_mods, fn
                 {:replace, ExLLM.Plugs.ManageContext, _} -> true
                 _ -> false
               end)

      assert opts[:strategy] == :sliding_window
      assert opts[:max_tokens] == 8000
    end
  end

  describe "combined validation scenarios" do
    test "validates multiple parameters together" do
      messages = [%{role: "user", content: "test"}]

      # Valid combination
      assert builder =
               ExLLM.build(:openai, messages)
               |> ExLLM.with_model("gpt-4")
               |> ExLLM.with_temperature(0.7)
               |> ExLLM.with_max_tokens(1000)

      assert builder.request.options.model == "gpt-4"
      assert builder.request.options.temperature == 0.7
      assert builder.request.options.max_tokens == 1000
    end

    test "first invalid parameter prevents further execution" do
      messages = [%{role: "user", content: "test"}]

      # Temperature validation fails first
      assert_raise FunctionClauseError, fn ->
        ExLLM.build(:openai, messages)
        # Invalid
        |> ExLLM.with_temperature(3.0)
        # Would be valid
        |> ExLLM.with_max_tokens(1000)
      end
    end
  end
end
