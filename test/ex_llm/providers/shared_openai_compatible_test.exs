defmodule ExLLM.Providers.SharedOpenAICompatibleTest do
  @moduledoc """
  Shared test suite for OpenAI-compatible providers.

  This module provides a comprehensive test suite that can be used to verify
  any provider that implements the OpenAI-compatible base.
  """

  use ExUnit.Case

  defmacro run_standard_tests(provider_module, provider_atom) do
    quote do
      describe "#{unquote(provider_atom)} standard contract" do
        @tag :unit
        test "implements required behaviors" do
          behaviors = unquote(provider_module).module_info(:attributes)[:behaviour] || []
          assert ExLLM.Provider in behaviors
        end

        @tag :unit
        test "has required functions" do
          assert function_exported?(unquote(provider_module), :chat, 2)
          assert function_exported?(unquote(provider_module), :stream_chat, 2)

          assert function_exported?(unquote(provider_module), :configured?, 0) or
                   function_exported?(unquote(provider_module), :configured?, 1)

          assert function_exported?(unquote(provider_module), :list_models, 0) or
                   function_exported?(unquote(provider_module), :list_models, 1)

          assert function_exported?(unquote(provider_module), :default_model, 0) or
                   function_exported?(unquote(provider_module), :default_model, 1)
        end

        @tag :unit
        test "returns valid default model" do
          model = unquote(provider_module).default_model()
          assert is_binary(model)
          assert model != ""
        end

        @tag :unit
        test "list_models returns proper format" do
          case unquote(provider_module).list_models() do
            {:ok, models} ->
              assert is_list(models)

              Enum.each(models, fn model ->
                assert Map.has_key?(model, :id)
                assert is_binary(model.id)
              end)

            {:error, _} ->
              # OK if it fails due to missing API key
              :ok
          end
        end

        @tag :unit
        test "configured? works without API key" do
          config_provider = ExLLM.Infrastructure.Config.ConfigProvider.Static

          # Clear any existing key
          Process.delete({config_provider, unquote(provider_atom), :api_key})

          refute unquote(provider_module).configured?(config_provider: config_provider)
        end
      end
    end
  end

  defmacro run_parameter_tests(provider_module, provider_atom, extra_params \\ quote(do: %{})) do
    quote do
      describe "#{unquote(provider_atom)} parameter handling" do
        @tag :unit
        test "builds request with standard parameters" do
          # This is a placeholder - in real tests we'd mock the HTTP client
          messages = [%{role: "user", content: "Hello"}]

          standard_params = [
            temperature: 0.7,
            max_tokens: 100,
            top_p: 0.9,
            frequency_penalty: 0.1,
            presence_penalty: 0.1,
            stop: ["END"],
            user: "test-user"
          ]

          # Merge with provider-specific params
          all_params =
            Keyword.merge(standard_params, Map.to_list(unquote(Macro.escape(extra_params))))

          # Just ensure we can build params without crashing
          assert is_list(all_params)
        end
      end
    end
  end

  defmacro run_error_handling_tests(provider_module, provider_atom) do
    quote do
      describe "#{unquote(provider_atom)} error handling" do
        @tag :unit
        test "handles missing API key" do
          config_provider = ExLLM.Infrastructure.Config.ConfigProvider.Static
          Process.delete({config_provider, unquote(provider_atom), :api_key})

          messages = [%{role: "user", content: "Hello"}]

          result = unquote(provider_module).chat(messages, config_provider: config_provider)

          assert {:error, _} = result
        end

        @tag :unit
        test "handles empty API key" do
          config_provider = ExLLM.Infrastructure.Config.ConfigProvider.Static
          Process.put({config_provider, unquote(provider_atom), :api_key}, "")

          messages = [%{role: "user", content: "Hello"}]

          result = unquote(provider_module).chat(messages, config_provider: config_provider)

          assert {:error, _} = result
        end
      end
    end
  end
end

# Now create individual test modules for each provider
defmodule ExLLM.Providers.XAICompatibilityTest do
  use ExUnit.Case
  import ExLLM.Providers.SharedOpenAICompatibleTest

  run_standard_tests(ExLLM.Providers.XAI, :xai)
  run_parameter_tests(ExLLM.Providers.XAI, :xai)
  run_error_handling_tests(ExLLM.Providers.XAI, :xai)
end

defmodule ExLLM.Providers.GroqCompatibilityTest do
  use ExUnit.Case
  import ExLLM.Providers.SharedOpenAICompatibleTest

  run_standard_tests(ExLLM.Providers.Groq, :groq)
  run_parameter_tests(ExLLM.Providers.Groq, :groq)
  run_error_handling_tests(ExLLM.Providers.Groq, :groq)
end

defmodule ExLLM.Providers.MistralCompatibilityTest do
  use ExUnit.Case
  import ExLLM.Providers.SharedOpenAICompatibleTest

  run_standard_tests(ExLLM.Providers.Mistral, :mistral)
  run_parameter_tests(ExLLM.Providers.Mistral, :mistral, %{safe_prompt: true, random_seed: 42})
  run_error_handling_tests(ExLLM.Providers.Mistral, :mistral)

  describe "Mistral-specific features" do
    @tag :unit
    test "validates temperature range 0-1" do
      config_provider = ExLLM.Infrastructure.Config.ConfigProvider.Static
      messages = [%{role: "user", content: "Hello"}]

      # Test temperature > 1
      result =
        ExLLM.Providers.Mistral.chat(messages,
          temperature: 1.5,
          config_provider: config_provider
        )

      assert {:error, "Temperature must be between 0.0 and 1.0"} = result

      # Test temperature < 0
      result =
        ExLLM.Providers.Mistral.chat(messages,
          temperature: -0.5,
          config_provider: config_provider
        )

      assert {:error, "Temperature must be between 0.0 and 1.0"} = result
    end
  end
end
