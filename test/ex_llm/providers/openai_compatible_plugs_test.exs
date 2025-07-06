defmodule ExLLM.Providers.OpenAICompatiblePlugsTest do
  use ExUnit.Case, async: false

  alias ExLLM.Pipeline.Request

  setup do
    # Save original API keys to restore them later
    original_xai_key = System.get_env("XAI_API_KEY")
    original_mistral_key = System.get_env("MISTRAL_API_KEY")
    original_openrouter_key = System.get_env("OPENROUTER_API_KEY")

    # Set dummy API keys for testing
    System.put_env("XAI_API_KEY", "test-key-12345")
    System.put_env("MISTRAL_API_KEY", "test-key-12345")
    System.put_env("OPENROUTER_API_KEY", "test-key-12345")

    on_exit(fn ->
      # Restore original environment variables to not interfere with other tests
      if original_xai_key do
        System.put_env("XAI_API_KEY", original_xai_key)
      else
        System.delete_env("XAI_API_KEY")
      end

      if original_mistral_key do
        System.put_env("MISTRAL_API_KEY", original_mistral_key)
      else
        System.delete_env("MISTRAL_API_KEY")
      end

      if original_openrouter_key do
        System.put_env("OPENROUTER_API_KEY", original_openrouter_key)
      else
        System.delete_env("OPENROUTER_API_KEY")
      end
    end)

    :ok
  end

  describe "OpenAI-compatible pipeline plugs" do
    test "XAI BuildRequest plug works correctly" do
      alias ExLLM.Providers.XAI.BuildRequest

      messages = [%{role: "user", content: "Hello"}]
      options = [model: "grok-beta", temperature: 0.8]

      request =
        Request.new(:xai, messages, options)
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key-12345")

      result = BuildRequest.call(request, [])

      assert result.assigns.model == "grok-beta"
      assert result.assigns.request_url == "https://api.x.ai/v1/chat/completions"

      body = result.assigns.request_body
      assert body.model == "grok-beta"
      assert body.temperature == 0.8
    end

    test "Mistral ParseResponse plug works correctly" do
      alias ExLLM.Providers.Mistral.ParseResponse

      raw_response = %{
        "choices" => [
          %{
            "message" => %{content: "Hello there!", role: "assistant"},
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 8,
          "completion_tokens" => 3,
          "total_tokens" => 11
        }
      }

      request =
        Request.new(:mistral, [], [])
        |> Request.assign(:http_response, raw_response)
        |> Request.assign(:model, "mistral-large-latest")

      result = ParseResponse.call(request, [])

      assert result.state == :completed

      llm_response = result.assigns.llm_response
      assert llm_response.content == "Hello there!"
      assert llm_response.model == "mistral-large-latest"
      assert llm_response.metadata.provider == :mistral
    end

    test "OpenRouter plugs handle different base URL" do
      alias ExLLM.Providers.OpenRouter.BuildRequest

      messages = [%{role: "user", content: "Hello"}]

      request =
        Request.new(:openrouter, messages, [])
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key")

      result = BuildRequest.call(request, [])

      assert result.assigns.request_url == "https://openrouter.ai/v1/chat/completions"
    end
  end
end
