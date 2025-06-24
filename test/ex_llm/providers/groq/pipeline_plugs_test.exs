defmodule ExLLM.Providers.Groq.PipelinePlugsTest do
  use ExUnit.Case, async: false

  alias ExLLM.Pipeline.Request
  alias ExLLM.Pipelines.StandardProvider
  alias ExLLM.Providers.Groq.{BuildRequest, ParseResponse}

  setup do
    # Set API key for FetchConfiguration plug
    System.put_env("GROQ_API_KEY", "test-key-12345")
    on_exit(fn -> System.delete_env("GROQ_API_KEY") end)
    :ok
  end

  describe "Groq pipeline plugs integration" do
    test "BuildRequest plug correctly transforms request" do
      messages = [%{role: "user", content: "Hello"}]
      options = [model: "llama3-70b-8192", temperature: 0.5, max_tokens: 100]

      request = Request.new(:groq, messages, options)

      # Simulate FetchConfiguration assigns
      request =
        request
        |> Request.assign(:config, %{model: "llama3-8b-8192"})
        |> Request.assign(:api_key, "test-key-12345")

      result = BuildRequest.call(request, [])

      # options override config
      assert result.assigns.model == "llama3-70b-8192"
      assert result.assigns.request_url == "https://api.groq.com/openai/v1/chat/completions"
      assert result.assigns.timeout == 60_000

      body = result.assigns.request_body
      assert body.model == "llama3-70b-8192"
      assert body.temperature == 0.5
      assert body.max_tokens == 100
      assert body.messages == [%{"role" => "user", "content" => "Hello"}]

      headers = result.assigns.request_headers
      assert {"authorization", "Bearer test-key-12345"} in headers
    end

    test "ParseResponse plug correctly transforms Groq response" do
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
        Request.new(:groq, [], [])
        |> Request.assign(:http_response, raw_response)
        |> Request.assign(:model, "llama3-70b-8192")

      result = ParseResponse.call(request, [])

      assert result.state == :completed

      llm_response = result.assigns.llm_response
      assert llm_response.content == "Hello there!"
      assert llm_response.model == "llama3-70b-8192"
      assert llm_response.finish_reason == "stop"
      assert llm_response.usage.input_tokens == 10
      assert llm_response.usage.output_tokens == 5
      assert llm_response.usage.total_tokens == 15
      assert llm_response.metadata.provider == :groq
    end

    test "BuildRequest handles system prompts" do
      messages = [%{role: "user", content: "Hello"}]
      options = [system: "You are helpful"]

      request =
        Request.new(:groq, messages, options)
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
