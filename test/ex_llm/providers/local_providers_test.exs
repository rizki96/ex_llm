defmodule ExLLM.Providers.LocalProvidersTest do
  use ExUnit.Case, async: false

  alias ExLLM.Pipeline.Request

  setup do
    # Set API keys for local providers (often not needed but good for testing)
    System.put_env("LMSTUDIO_API_KEY", "test-key-12345")
    System.put_env("OLLAMA_API_KEY", "test-key-12345")

    on_exit(fn ->
      System.delete_env("LMSTUDIO_API_KEY")
      System.delete_env("OLLAMA_API_KEY")
    end)

    :ok
  end

  describe "LMStudio pipeline plugs" do
    test "BuildRequest plug works correctly" do
      alias ExLLM.Providers.LMStudio.BuildRequest

      messages = [%{role: "user", content: "Hello"}]
      options = [model: "llama-3.1-8b-instruct", temperature: 0.7]

      request =
        Request.new(:lmstudio, messages, options)
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key-12345")

      result = BuildRequest.call(request, [])

      assert result.assigns.model == "llama-3.1-8b-instruct"
      assert result.assigns.request_url == "http://localhost:1234/v1/chat/completions"

      body = result.assigns.request_body
      assert body.model == "llama-3.1-8b-instruct"
      assert body.temperature == 0.7
      assert body.messages == [%{role: "user", content: "Hello"}]
    end

    test "ParseResponse plug works correctly" do
      alias ExLLM.Providers.LMStudio.ParseResponse

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
        Request.new(:lmstudio, [], [])
        |> Request.assign(:http_response, raw_response)
        |> Request.assign(:model, "llama-3.1-8b-instruct")

      result = ParseResponse.call(request, [])

      assert result.state == :completed

      llm_response = result.assigns.llm_response
      assert llm_response.content == "Hello there!"
      assert llm_response.model == "llama-3.1-8b-instruct"
      assert llm_response.metadata.provider == :lmstudio
    end
  end

  describe "Ollama pipeline plugs" do
    test "BuildRequest plug works correctly" do
      alias ExLLM.Providers.Ollama.BuildRequest

      messages = [%{role: "user", content: "Hello"}]
      options = [model: "llama3.2", temperature: 0.5]

      request =
        Request.new(:ollama, messages, options)
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key-12345")

      result = BuildRequest.call(request, [])

      assert result.assigns.model == "llama3.2"
      assert result.assigns.request_url == "http://localhost:11434/api/chat"

      body = result.assigns.request_body
      assert body.model == "llama3.2"
      assert body.temperature == 0.5
      assert body.messages == [%{role: "user", content: "Hello"}]
    end

    test "ParseResponse plug works correctly" do
      alias ExLLM.Providers.Ollama.ParseResponse

      raw_response = %{
        "message" => %{content: "Hello there!", role: "assistant"},
        "done" => true,
        "done_reason" => "stop",
        "prompt_eval_count" => 8,
        "eval_count" => 3,
        "model" => "llama3.2"
      }

      request =
        Request.new(:ollama, [], [])
        |> Map.put(:response, %{status: 200, body: raw_response})
        |> Request.assign(:model, "llama3.2")

      result = ParseResponse.call(request, [])

      assert result.state == :completed

      llm_response = result.result
      assert llm_response.content == "Hello there!"
      assert llm_response.model == "llama3.2"
      assert llm_response.metadata.provider == :ollama
    end
  end

  describe "System prompt handling" do
    test "LMStudio handles system prompts" do
      alias ExLLM.Providers.LMStudio.BuildRequest

      messages = [%{role: "user", content: "Hello"}]
      options = [system: "You are a helpful assistant"]

      request =
        Request.new(:lmstudio, messages, options)
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key")

      result = BuildRequest.call(request, [])

      body = result.assigns.request_body

      expected_messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"}
      ]

      assert body.messages == expected_messages
    end

    test "Ollama handles system prompts" do
      alias ExLLM.Providers.Ollama.BuildRequest

      messages = [%{role: "user", content: "Hello"}]
      options = [system: "You are a helpful assistant"]

      request =
        Request.new(:ollama, messages, options)
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key")

      result = BuildRequest.call(request, [])

      body = result.assigns.request_body

      expected_messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"}
      ]

      assert body.messages == expected_messages
    end
  end
end
