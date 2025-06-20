defmodule ExLLM.Providers.OpenRouterPublicAPITest do
  @moduledoc """
  OpenRouter-specific integration tests using the public ExLLM API.
  Common tests are handled by the shared module.
  """

  use ExLLM.Shared.ProviderIntegrationTest, provider: :openrouter

  # Provider-specific tests only
  describe "openrouter-specific features via public API" do
    test "accesses models from multiple providers" do
      # Test different provider models through OpenRouter
      models_to_test = [
        "anthropic/claude-3-haiku",
        "openai/gpt-3.5-turbo",
        "google/gemini-flash-1.5"
      ]

      messages = [%{role: "user", content: "Say hi"}]

      for model <- models_to_test do
        case ExLLM.chat(:openrouter, messages, model: model, max_tokens: 10) do
          {:ok, response} ->
            assert response.provider == :openrouter
            assert is_binary(response.content)
            # OpenRouter returns the actual model used
            assert is_binary(response.model)

          {:error, {:api_error, %{status: 404}}} ->
            # Model might not be available
            :ok

          {:error, _} ->
            :ok
        end
      end
    end

    test "lists hundreds of available models" do
      case ExLLM.list_models(:openrouter) do
        {:ok, models} ->
          assert is_list(models)
          # OpenRouter has 300+ models
          assert length(models) > 100

          # Check for models from different providers
          model_ids = Enum.map(models, & &1.id)
          assert Enum.any?(model_ids, &String.contains?(&1, "anthropic/"))
          assert Enum.any?(model_ids, &String.contains?(&1, "openai/"))
          assert Enum.any?(model_ids, &String.contains?(&1, "google/"))

          # Check pricing info
          model_with_pricing = Enum.find(models, &(&1.pricing != nil))

          if model_with_pricing do
            assert model_with_pricing.pricing.input_cost_per_token > 0
            assert model_with_pricing.pricing.output_cost_per_token > 0
          end

        {:error, _} ->
          :ok
      end
    end

    @tag :streaming
    test "streaming across different provider models" do
      messages = [
        %{role: "user", content: "Count to 3"}
      ]

      # Collect chunks using the callback API
      collector = fn chunk ->
        send(self(), {:chunk, chunk})
      end

      # Try streaming with different underlying providers
      case ExLLM.stream(:openrouter, messages, collector,
             model: "meta-llama/llama-3.2-3b-instruct",
             max_tokens: 30,
             timeout: 10_000
           ) do
        :ok ->
          chunks = collect_stream_chunks([], 1000)

          assert length(chunks) > 0

          full_content =
            chunks
            |> Enum.map(& &1.content)
            |> Enum.filter(& &1)
            |> Enum.join("")

          assert full_content != ""

        {:error, _} ->
          :ok
      end
    end

    test "includes provider metadata" do
      messages = [%{role: "user", content: "Hi"}]

      # OpenRouter can include app metadata
      options = [
        max_tokens: 10,
        provider_options: %{
          "HTTP-Referer" => "https://example.com",
          "X-Title" => "ExLLM Test Suite"
        }
      ]

      case ExLLM.chat(:openrouter, messages, options) do
        {:ok, response} ->
          assert response.provider == :openrouter
          assert is_binary(response.content)

        {:error, _} ->
          :ok
      end
    end

    test "cost tracking across providers" do
      messages = [%{role: "user", content: "Hello"}]

      # Test with a specific model to ensure consistent pricing
      case ExLLM.chat(:openrouter, messages, model: "openai/gpt-3.5-turbo", max_tokens: 10) do
        {:ok, response} ->
          assert response.cost > 0
          # Should be very cheap for this request
          assert response.cost < 0.001

          # OpenRouter provides detailed usage
          assert response.usage.input_tokens > 0
          assert response.usage.output_tokens > 0

        {:error, _} ->
          :ok
      end
    end
  end
end
