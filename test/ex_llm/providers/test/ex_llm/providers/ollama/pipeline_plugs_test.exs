defmodule ExLLM.Providers.Ollama.PipelinePlugsTest do
  use ExUnit.Case, async: false

  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.Ollama.{BuildRequest, ParseResponse}

  setup do
    # Set API key for FetchConfiguration plug. Ollama doesn't require one,
    # but we test that it's passed if provided.
    System.put_env("OLLAMA_API_KEY", "test-key-not-required")
    on_exit(fn -> System.delete_env("OLLAMA_API_KEY") end)
    :ok
  end

  describe "Ollama pipeline plugs integration" do
    test "BuildRequest plug correctly transforms request" do
      messages = [%{role: "user", content: "Hello"}]
      options = [model: "llama3:latest", temperature: 0.5, max_tokens: 100]

      request = Request.new(:ollama, messages, options)

      # Simulate FetchConfiguration assigns
      request =
        request
        |> Request.assign(:config, %{model: "llama2:latest"})
        |> Request.assign(:api_key, "test-key-not-required")

      result = BuildRequest.call(request, [])

      # options override config
      assert result.assigns.model == "llama3:latest"
      assert result.assigns.request_url == "http://localhost:11434/api/chat"
      assert result.assigns.timeout == 60_000

      body = result.assigns.request_body
      assert body.model == "llama3:latest"
      assert body.temperature == 0.5
      assert body.options.num_predict == 100
      assert body.messages == [%{role: "user", content: "Hello"}]

      headers = result.assigns.request_headers
      # Ollama doesn't require authorization headers
      assert {"content-type", "application/json"} in headers
      refute Enum.any?(headers, fn {key, _} -> key == "authorization" end)
    end

    test "ParseResponse plug correctly transforms Ollama response" do
      raw_response = %{
        "message" => %{content: "Hello there!", role: "assistant"},
        "done" => true,
        "done_reason" => "stop",
        "prompt_eval_count" => 10,
        "eval_count" => 5,
        "model" => "llama3:latest"
      }

      request =
        Request.new(:ollama, [], [])
        |> Map.put(:response, %{status: 200, body: raw_response})
        |> Request.assign(:model, "llama3:latest")

      result = ParseResponse.call(request, [])

      assert result.state == :completed

      llm_response = result.result
      assert llm_response.content == "Hello there!"
      assert llm_response.model == "llama3:latest"
      assert llm_response.finish_reason == "stop"
      assert llm_response.usage.prompt_tokens == 10
      assert llm_response.usage.completion_tokens == 5
      assert llm_response.usage.total_tokens == 15
      assert llm_response.metadata.provider == :ollama
    end

    test "BuildRequest handles system prompts" do
      messages = [%{role: "user", content: "Hello"}]
      options = [system: "You are helpful"]

      request =
        Request.new(:ollama, messages, options)
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key")

      result = BuildRequest.call(request, [])

      body = result.assigns.request_body

      expected_messages = [
        %{role: "system", content: "You are helpful"},
        %{role: "user", content: "Hello"}
      ]

      assert body.messages == expected_messages
    end
  end
end
