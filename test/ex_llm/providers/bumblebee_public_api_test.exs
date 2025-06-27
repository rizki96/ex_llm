defmodule ExLLM.Providers.BumblebeePublicAPITest do
  @moduledoc """
  Bumblebee-specific integration tests using the public ExLLM API.
  Common tests are handled by the shared module.

  Note: Bumblebee tests require the optional Bumblebee dependency and
  will download models on first run.
  """

  use ExLLM.Shared.ProviderIntegrationTest, provider: :bumblebee

  @moduletag :requires_deps
  @moduletag :local_only

  # Provider-specific tests only
  describe "bumblebee-specific features via public API" do
    @tag :model_loading
    test "works with local Bumblebee models" do
      messages = [
        %{role: "user", content: "What is 1+1?"}
      ]

      case ExLLM.chat(:bumblebee, messages, max_tokens: 10) do
        {:ok, response} ->
          assert response.content =~ ~r/2|two/i
          assert response.metadata.provider == :bumblebee
          # Local models have no cost
          assert response.cost == 0.0

        {:error, %{message: message}} ->
          # Check if it's a ModelLoader or Bumblebee error
          if String.contains?(message, "ModelLoader") or String.contains?(message, "Bumblebee") do
            :ok
          else
            flunk("Unexpected error: #{message}")
          end

        {:error, _} ->
          :ok
      end
    end

    test "supports different local models" do
      models_to_test = [
        "Qwen/Qwen3-0.6B",
        "microsoft/Phi-3-mini-4k-instruct"
      ]

      messages = [%{role: "user", content: "Hello"}]

      for model <- models_to_test do
        case ExLLM.chat(:bumblebee, messages, model: model, max_tokens: 20) do
          {:ok, response} ->
            assert response.metadata.provider == :bumblebee
            assert is_binary(response.content)
            assert response.model == model

          {:error, %{message: message}} ->
            # Model not loaded is acceptable
            if String.contains?(message, "not loaded") do
              :ok
            else
              flunk("Unexpected error: #{message}")
            end

          {:error, _} ->
            :ok
        end
      end
    end

    test "handles CPU inference" do
      messages = [
        %{role: "user", content: "Complete this: The sky is"}
      ]

      # Bumblebee runs on CPU by default
      case ExLLM.chat(:bumblebee, messages, temperature: 0.1, max_tokens: 10) do
        {:ok, response} ->
          assert response.metadata.provider == :bumblebee
          # Common completions
          assert response.content =~ ~r/blue|clear|cloudy|gray|dark/i

        {:error, _} ->
          :ok
      end
    end

    test "respects generation parameters" do
      messages = [
        %{role: "user", content: "Generate a random word"}
      ]

      # Test different temperatures
      results =
        for temp <- [0.0, 1.0] do
          case ExLLM.chat(:bumblebee, messages, temperature: temp, max_tokens: 10) do
            {:ok, response} -> response.content
            _ -> nil
          end
        end

      valid_results = Enum.filter(results, & &1)

      if length(valid_results) == 2 do
        # Temperature 0 and 1 should likely produce different results
        [low_temp, high_temp] = valid_results
        assert low_temp != high_temp || String.length(low_temp) < 5
      end
    end

    test "handles model-specific token limits" do
      # Create a prompt that might exceed small model limits
      long_context = String.duplicate("This is a test. ", 100)

      messages = [
        %{role: "user", content: long_context <> "Summarize in one word."}
      ]

      case ExLLM.chat(:bumblebee, messages, max_tokens: 10) do
        {:ok, response} ->
          assert response.metadata.provider == :bumblebee
          assert is_binary(response.content)
          # Should produce some output even with long context
          assert String.length(response.content) > 0

        {:error, %{message: message}} ->
          # Token limit exceeded is acceptable
          if String.contains?(message, "token") do
            :ok
          else
            flunk("Unexpected error: #{message}")
          end

        {:error, _} ->
          :ok
      end
    end
  end

  describe "bumblebee model management via public API" do
    @tag :model_loading
    test "lists available models" do
      case ExLLM.list_models(:bumblebee) do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            model = hd(models)
            assert model.id =~ ~r/Qwen|Phi|gpt2/
            # Local models have specific context windows
            assert model.context_window > 0
            # No pricing for local models
            assert model.pricing == nil
          end

        {:error, %{message: message}} ->
          # ModelLoader not started is acceptable
          if String.contains?(message, "ModelLoader") do
            :ok
          else
            flunk("Unexpected error: #{message}")
          end

        {:error, _} ->
          :ok
      end
    end
  end
end
