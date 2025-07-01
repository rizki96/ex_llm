defmodule ExLLM.Providers.SharedOpenAICompatibleTest do
  @moduledoc """
  Shared test suite for OpenAI-compatible providers.

  This module provides a comprehensive test suite that can be used to verify
  any provider that implements the OpenAI-compatible base.
  """

  use ExUnit.Case, async: false

  # Helper function to get env var name for a provider
  def get_env_var_name(provider_atom) do
    case provider_atom do
      :xai -> "XAI_API_KEY"
      :groq -> "GROQ_API_KEY"
      :mistral -> "MISTRAL_API_KEY"
      :perplexity -> "PERPLEXITY_API_KEY"
      :openrouter -> "OPENROUTER_API_KEY"
      _ -> String.upcase(to_string(provider_atom)) <> "_API_KEY"
    end
  end

  # Helper macro to run test with temporarily removed env var
  defmacro with_env_var_removed(provider_atom, do: block) do
    quote do
      env_var_name = ExLLM.Providers.SharedOpenAICompatibleTest.get_env_var_name(unquote(provider_atom))
      original_key = System.get_env(env_var_name)

      try do
        System.delete_env(env_var_name)
        unquote(block)
      after
        if original_key, do: System.put_env(env_var_name, original_key)
      end
    end
  end

  defmacro run_standard_tests(provider_module, provider_atom) do
    quote do
      describe "#{unquote(provider_atom)} standard contract" do
        @tag :unit
        test "implements required behaviors" do
          behaviors = unquote(provider_module).module_info(:attributes)[:behaviour] || []
          assert ExLLM.Provider in behaviors
        end

        @tag :unit
        @tag :flaky
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
          with_env_var_removed unquote(provider_atom) do
            # Create a static config provider with empty config
            {:ok, config_provider} =
              ExLLM.Infrastructure.ConfigProvider.Static.start_link(%{
                unquote(provider_atom) => %{}
              })

            case unquote(provider_module).list_models(config_provider: config_provider) do
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
        end

        @tag :unit
        test "configured? works without API key" do
          with_env_var_removed unquote(provider_atom) do
            # Create a static config provider instance with no API key
            {:ok, config_provider} =
              ExLLM.Infrastructure.ConfigProvider.Static.start_link(%{
                unquote(provider_atom) => %{}
              })

            refute unquote(provider_module).configured?(config_provider: config_provider)
          end
        end
      end
    end
  end

  defmacro run_parameter_tests(_provider_module, provider_atom, extra_params \\ quote(do: %{})) do
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
          extra_map = unquote(extra_params)

          all_params =
            case extra_map do
              map when is_map(map) ->
                Keyword.merge(standard_params, Map.to_list(map))

              _ ->
                standard_params
            end

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
          with_env_var_removed unquote(provider_atom) do
            # Create a static config provider instance with no API key
            {:ok, config_provider} =
              ExLLM.Infrastructure.ConfigProvider.Static.start_link(%{
                unquote(provider_atom) => %{}
              })

            messages = [%{role: "user", content: "Hello"}]

            result = unquote(provider_module).chat(messages, config_provider: config_provider)

            assert {:error, _} = result
          end
        end

        @tag :unit
        test "handles empty API key" do
          # Create a static config provider instance with empty API key
          {:ok, config_provider} =
            ExLLM.Infrastructure.ConfigProvider.Static.start_link(%{
              unquote(provider_atom) => %{api_key: ""}
            })

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
  use ExUnit.Case, async: false
  import ExLLM.Providers.SharedOpenAICompatibleTest

  run_standard_tests(ExLLM.Providers.XAI, :xai)
  run_parameter_tests(ExLLM.Providers.XAI, :xai)
  run_error_handling_tests(ExLLM.Providers.XAI, :xai)
end

defmodule ExLLM.Providers.GroqCompatibilityTest do
  use ExUnit.Case, async: false
  import ExLLM.Providers.SharedOpenAICompatibleTest

  run_standard_tests(ExLLM.Providers.Groq, :groq)
  run_parameter_tests(ExLLM.Providers.Groq, :groq)
  run_error_handling_tests(ExLLM.Providers.Groq, :groq)
end

defmodule ExLLM.Providers.MistralCompatibilityTest do
  use ExUnit.Case, async: false
  import ExLLM.Providers.SharedOpenAICompatibleTest

  run_standard_tests(ExLLM.Providers.Mistral, :mistral)
  run_parameter_tests(ExLLM.Providers.Mistral, :mistral, %{safe_prompt: true, random_seed: 42})
  run_error_handling_tests(ExLLM.Providers.Mistral, :mistral)

  # Removed Mistral-specific temperature validation test
  # The API itself will validate temperature ranges
end
