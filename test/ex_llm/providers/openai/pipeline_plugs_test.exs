defmodule ExLLM.Providers.OpenAI.PipelinePlugsTest do
  use ExUnit.Case, async: false

  alias ExLLM.Pipeline.Request
  alias ExLLM.Pipelines.StandardProvider
  alias ExLLM.Providers.OpenAI.{BuildRequest, ParseResponse}

  setup do
    # Set API key for FetchConfiguration plug
    System.put_env("OPENAI_API_KEY", "test-key-12345")
    on_exit(fn -> System.delete_env("OPENAI_API_KEY") end)
    :ok
  end

  describe "OpenAI pipeline plugs integration" do
    test "BuildRequest plug correctly transforms request" do
      messages = [%{role: "user", content: "Hello"}]
      options = [model: "gpt-4", temperature: 0.5, max_tokens: 100]

      request = Request.new(:openai, messages, options)

      # Simulate FetchConfiguration assigns
      request =
        request
        |> Request.assign(:config, %{model: "gpt-3.5-turbo"})
        |> Request.assign(:api_key, "test-key-12345")

      result = BuildRequest.call(request, [])

      # options override config
      assert result.assigns.model == "gpt-4"
      assert result.assigns.request_url == "https://api.openai.com/v1/chat/completions"
      assert result.assigns.timeout == 60_000

      body = result.assigns.request_body
      assert body.model == "gpt-4"
      assert body.temperature == 0.5
      assert body.max_tokens == 100
      assert body.messages == [%{"role" => "user", "content" => "Hello"}]

      headers = result.assigns.request_headers
      assert {"authorization", "Bearer test-key-12345"} in headers
    end

    test "ParseResponse plug correctly transforms OpenAI response" do
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
        Request.new(:openai, [], [])
        |> Request.assign(:http_response, raw_response)
        |> Request.assign(:model, "gpt-4")

      result = ParseResponse.call(request, [])

      assert result.state == :completed

      llm_response = result.assigns.llm_response
      assert llm_response.content == "Hello there!"
      assert llm_response.model == "gpt-4"
      assert llm_response.finish_reason == "stop"
      assert llm_response.usage.input_tokens == 10
      assert llm_response.usage.output_tokens == 5
      assert llm_response.usage.total_tokens == 15
      assert llm_response.metadata.provider == :openai
    end

    @tag :skip
    test "full pipeline with OpenAI plugs (mocked execution)" do
      provider_plugs = [
        build_request: {BuildRequest, []},
        parse_response: {ParseResponse, []}
      ]

      # Build pipeline but replace ExecuteRequest with mock
      [{telemetry_plug, telemetry_opts}] = StandardProvider.build(provider_plugs)
      inner_pipeline = telemetry_opts.pipeline

      # Create mock ExecuteRequest that simulates successful API response
      mock_execute = fn request, _opts ->
        mock_response = %{
          "choices" => [
            %{
              "message" => %{"content" => "Mock response", "role" => "assistant"},
              "finish_reason" => "stop"
            }
          ],
          "usage" => %{
            "prompt_tokens" => 5,
            "completion_tokens" => 3,
            "total_tokens" => 8
          }
        }

        request
        |> Request.assign(:http_response, mock_response)
      end

      # Replace ExecuteRequest (index 4) with mock
      modified_pipeline = List.replace_at(inner_pipeline, 4, {mock_execute, []})
      modified_telemetry_opts = %{telemetry_opts | pipeline: modified_pipeline}
      full_pipeline = [{telemetry_plug, modified_telemetry_opts}]

      messages = [%{role: "user", content: "Test"}]
      request = Request.new(:openai, messages, [])

      result = ExLLM.Pipeline.run(request, full_pipeline)

      refute result.halted
      assert result.state == :completed
      assert result.assigns.llm_response.content == "Mock response"
    end
  end
end
