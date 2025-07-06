defmodule ExLLM.Providers.Anthropic.PipelinePlugsTest do
  use ExUnit.Case, async: false

  @moduletag provider: :anthropic
  @moduletag :unit
  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.Anthropic.{BuildRequest, ParseResponse}

  setup do
    # Set API key for FetchConfiguration plug
    System.put_env("ANTHROPIC_API_KEY", "test-key-12345")
    on_exit(fn -> System.delete_env("ANTHROPIC_API_KEY") end)
    :ok
  end

  describe "Anthropic pipeline plugs integration" do
    test "BuildRequest plug correctly transforms request" do
      messages = [
        %{role: "system", content: "You are helpful"},
        %{role: "user", content: "Hello"}
      ]

      options = [model: "claude-3-haiku-20240307", temperature: 0.5, max_tokens: 100]

      request = Request.new(:anthropic, messages, options)

      # Simulate FetchConfiguration assigns
      request =
        request
        |> Request.assign(:config, %{model: "claude-3-sonnet-20240229"})
        |> Request.assign(:api_key, "test-key-12345")

      result = BuildRequest.call(request, [])

      # options override config
      assert result.assigns.model == "claude-3-haiku-20240307"
      assert result.assigns.request_url == "https://api.anthropic.com/v1/messages"
      assert result.assigns.timeout == 60_000

      body = result.assigns.request_body
      assert body.model == "claude-3-haiku-20240307"
      assert body.temperature == 0.5
      assert body.max_tokens == 100
      assert body.system == "You are helpful"

      # Should have only user message after system extraction
      assert body.messages == [%{role: "user", content: "Hello"}]

      headers = result.assigns.request_headers
      assert {"authorization", "Bearer test-key-12345"} in headers
      assert {"anthropic-version", "2023-06-01"} in headers
    end

    test "ParseResponse plug correctly transforms Anthropic response" do
      raw_response = %{
        "model" => "claude-3-haiku-20240307",
        "stop_reason" => "end_turn",
        "usage" => %{
          "input_tokens" => 10,
          "output_tokens" => 5
        },
        content: [
          %{
            text: "Hello there!",
            type: "text"
          }
        ]
      }

      request =
        Request.new(:anthropic, [], [])
        |> Request.assign(:http_response, raw_response)

      result = ParseResponse.call(request, [])

      assert result.state == :completed

      llm_response = result.assigns.llm_response
      assert llm_response.content == "Hello there!"
      assert llm_response.model == "claude-3-haiku-20240307"
      assert llm_response.finish_reason == "end_turn"
      assert llm_response.usage.input_tokens == 10
      assert llm_response.usage.output_tokens == 5
      assert llm_response.metadata.provider == :anthropic
    end

    test "BuildRequest handles multimodal content" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{
              type: "image_url",
              image_url: %{url: "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQ"}
            }
          ]
        }
      ]

      request =
        Request.new(:anthropic, messages, [])
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key")

      result = BuildRequest.call(request, [])

      body = result.assigns.request_body
      content = hd(body.messages).content

      assert length(content) == 2
      assert %{type: "text", text: "What's in this image?"} = Enum.at(content, 0)

      image_content = Enum.at(content, 1)
      assert image_content.type == "image"
      assert image_content.source.type == "base64"
      assert image_content.source.data == "/9j/4AAQSkZJRgABAQAAAQ"
    end
  end
end
