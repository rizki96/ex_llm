defmodule ExLLM.Providers.LMStudio.PipelinePlugsTest do
  use ExUnit.Case, async: false

  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.LMStudio.{BuildRequest, ParseResponse}

  setup do
    # Set API key for FetchConfiguration plug. LMStudio doesn't require one,
    # but we test that it's passed if provided.
    System.put_env("LMSTUDIO_API_KEY", "test-key-not-required")
    on_exit(fn -> System.delete_env("LMSTUDIO_API_KEY") end)
    :ok
  end

  describe "LMStudio pipeline plugs integration" do
    test "BuildRequest plug correctly transforms request" do
      messages = [%{role: "user", content: "Hello"}]
      options = [model: "local-model/gguf-v2-q8_0", temperature: 0.5, max_tokens: 100]

      request = Request.new(:lmstudio, messages, options)

      # Simulate FetchConfiguration assigns
      request =
        request
        |> Request.assign(:config, %{model: "local-model/gguf-v2-q4_0"})
        |> Request.assign(:api_key, "test-key-not-required")

      result = BuildRequest.call(request, [])

      # options override config
      assert result.assigns.model == "local-model/gguf-v2-q8_0"
      assert result.assigns.request_url == "http://localhost:1234/v1/chat/completions"
      assert result.assigns.timeout == 60_000

      body = result.assigns.request_body
      assert body.model == "local-model/gguf-v2-q8_0"
      assert body.temperature == 0.5
      assert body.max_tokens == 100
      assert body.messages == [%{"role" => "user", "content" => "Hello"}]

      headers = result.assigns.request_headers
      assert {"authorization", "Bearer test-key-not-required"} in headers
    end

    test "ParseResponse plug correctly transforms LMStudio response" do
      raw_response = %{
        "choices" => [
          %{
            "message" => %{
              "content" => "Hello there!",
              "role" => "assistant"
            },
            "finish_reason" => "stop",
            "logprobs" => nil
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 5,
          "total_tokens" => 15
        }
      }

      request =
        Request.new(:lmstudio, [], [])
        |> Request.assign(:http_response, raw_response)
        |> Request.assign(:model, "local-model/gguf-v2-q8_0")

      result = ParseResponse.call(request, [])

      assert result.state == :completed

      llm_response = result.assigns.llm_response
      assert llm_response.content == "Hello there!"
      assert llm_response.model == "local-model/gguf-v2-q8_0"
      assert llm_response.finish_reason == "stop"
      assert llm_response.usage.input_tokens == 10
      assert llm_response.usage.output_tokens == 5
      assert llm_response.usage.total_tokens == 15
      assert llm_response.metadata.provider == :lmstudio
    end

    test "BuildRequest handles system prompts" do
      messages = [%{role: "user", content: "Hello"}]
      options = [system: "You are helpful"]

      request =
        Request.new(:lmstudio, messages, options)
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key")

      result = BuildRequest.call(request, [])

      body = result.assigns.request_body

      expected_messages = [
        %{"role" => "system", "content" => "You are helpful"},
        %{"role" => "user", "content" => "Hello"}
      ]

      assert body.messages == expected_messages
    end
  end
end
