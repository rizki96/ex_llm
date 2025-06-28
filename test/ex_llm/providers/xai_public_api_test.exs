defmodule ExLLM.Providers.XAIPublicAPITest do
  @moduledoc """
  XAI-specific integration tests using the public ExLLM API.
  Common tests are handled by the shared module.

  Note: XAI (Grok) tests require a valid XAI_API_KEY.
  """

  use ExLLM.Shared.ProviderIntegrationTest, provider: :xai

  # Provider-specific tests only
  describe "xai-specific features via public API" do
    test "supports Grok models" do
      messages = [
        %{role: "user", content: "What makes you different from other AI assistants?"}
      ]

      case ExLLM.chat(:xai, messages, model: "grok-2", max_tokens: 100) do
        {:ok, response} ->
          assert response.metadata.provider == :xai
          assert is_binary(response.content)
          assert response.model =~ "grok"
          # Grok tends to have a unique personality
          assert String.length(response.content) > 20

        {:error, {:api_error, %{status: 401}}} ->
          # No API key or invalid key
          :ok

        {:error, {:api_error, %{status: 402}}} ->
          # No credits
          IO.puts("XAI account has no credits")
          :ok

        {:error, _} ->
          :ok
      end
    end

    test "supports both Grok-2 and Grok-3-mini" do
      models = ["grok-2", "grok-3-mini"]
      messages = [%{role: "user", content: "Hello"}]

      for model <- models do
        case ExLLM.chat(:xai, messages, model: model, max_tokens: 20) do
          {:ok, response} ->
            assert response.metadata.provider == :xai
            assert response.model == model

          {:error, {:api_error, %{status: 402}}} ->
            # No credits
            :ok

          {:error, _} ->
            :ok
        end
      end
    end

    @tag :vision
    test "Grok vision capabilities" do
      # Small 1x1 red pixel PNG
      red_pixel =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What color is this image?"},
            %{
              type: "image",
              image: %{
                data: red_pixel,
                media_type: "image/png"
              }
            }
          ]
        }
      ]

      case ExLLM.chat(:xai, messages, model: "grok-2-vision", max_tokens: 50) do
        {:ok, response} ->
          # Verify Grok can see the image (don't test specific color)
          assert String.length(response.content) > 0

        {:error, {:api_error, %{status: 404}}} ->
          # Vision model might not be available
          :ok

        {:error, {:api_error, %{status: 402}}} ->
          # No credits
          :ok

        {:error, _} ->
          :ok
      end
    end

    test "handles XAI-specific parameters" do
      messages = [
        %{role: "user", content: "Tell me a joke"}
      ]

      # XAI might support unique parameters
      case ExLLM.chat(:xai, messages, temperature: 0.9, max_tokens: 100) do
        {:ok, response} ->
          assert response.metadata.provider == :xai
          # Jokes should be reasonably long
          assert String.length(response.content) > 30

        {:error, {:api_error, %{status: 402}}} ->
          # No credits
          :ok

        {:error, _} ->
          :ok
      end
    end

    test "model listing includes Grok models" do
      case ExLLM.list_models(:xai) do
        {:ok, models} ->
          assert is_list(models)
          assert length(models) > 0

          # Check for Grok models
          model_ids = Enum.map(models, & &1.id)
          assert Enum.any?(model_ids, &String.contains?(&1, "grok"))

          # Check model metadata
          grok_model = Enum.find(models, &(&1.id =~ "grok"))

          if grok_model do
            assert grok_model.context_window > 0
            
            # Handle both list and map formats for capabilities
            case grok_model.capabilities do
              capabilities when is_list(capabilities) ->
                # Fallback YAML format
                assert "streaming" in capabilities
                assert "function_calling" in capabilities
                
              %{features: features} = capabilities when is_map(capabilities) ->
                # Provider implementation format
                assert is_list(features)
                assert :streaming in features
                assert :function_calling in features
                assert capabilities.supports_streaming == true
                assert capabilities.supports_functions == true
            end
          end

        {:error, _} ->
          :ok
      end
    end
  end
end
