defmodule ExLLM.Providers.GeminiPipelineTest do
  use ExUnit.Case, async: false

  alias ExLLM.Pipeline.Request

  setup do
    # Set API key for Gemini provider
    System.put_env("GOOGLE_API_KEY", "test-key-12345")

    on_exit(fn ->
      System.delete_env("GOOGLE_API_KEY")
    end)

    :ok
  end

  describe "Gemini pipeline plugs" do
    test "BuildRequest plug works correctly" do
      alias ExLLM.Providers.Gemini.BuildRequest

      messages = [%{role: "user", content: "Hello"}]
      options = [model: "gemini-2.5-flash", temperature: 0.7]

      request =
        Request.new(:gemini, messages, options)
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key-12345")

      result = BuildRequest.call(request, [])

      assert result.assigns.model == "gemini-2.5-flash"
      assert String.contains?(result.assigns.request_url, "gemini-2.5-flash:generateContent")
      assert String.contains?(result.assigns.request_url, "key=test-key-12345")

      body = result.assigns.request_body
      assert %ExLLM.Providers.Gemini.Content.GenerateContentRequest{} = body
      assert length(body.contents) == 1

      [content] = body.contents
      assert content.role == "user"
      assert [part] = content.parts
      assert part.text == "Hello"
    end

    test "ParseResponse plug works correctly" do
      alias ExLLM.Providers.Gemini.ParseResponse

      raw_response = %{
        "candidates" => [
          %{
            "content" => %{
              "parts" => [%{"text" => "Hello there!"}],
              "role" => "model"
            },
            "finishReason" => "STOP",
            "safetyRatings" => []
          }
        ],
        "usageMetadata" => %{
          "promptTokenCount" => 8,
          "candidatesTokenCount" => 3,
          "totalTokenCount" => 11
        }
      }

      request =
        Request.new(:gemini, [], [])
        |> Request.assign(:http_response, raw_response)
        |> Request.assign(:model, "gemini-2.5-flash")

      result = ParseResponse.call(request, [])

      assert result.state == :completed

      llm_response = result.assigns.llm_response
      assert llm_response.content == "Hello there!"
      assert llm_response.model == "gemini-2.5-flash"
      assert llm_response.metadata.provider == :gemini
      assert llm_response.usage.input_tokens == 8
      assert llm_response.usage.output_tokens == 3
      assert llm_response.usage.total_tokens == 11
    end

    test "BuildRequest handles system prompts" do
      alias ExLLM.Providers.Gemini.BuildRequest

      messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"}
      ]

      options = []

      request =
        Request.new(:gemini, messages, options)
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key")

      result = BuildRequest.call(request, [])

      body = result.assigns.request_body

      # System and user messages both convert to "user" role and get merged
      assert length(body.contents) == 1
      [merged_content] = body.contents
      assert merged_content.role == "user"
      # Should have 2 parts (system + user content merged)
      assert length(merged_content.parts) == 2
      [system_part, user_part] = merged_content.parts
      assert system_part.text == "You are a helpful assistant"
      assert user_part.text == "Hello"
    end

    test "ParseResponse handles tool calls" do
      alias ExLLM.Providers.Gemini.ParseResponse

      raw_response = %{
        "candidates" => [
          %{
            "content" => %{
              "parts" => [
                %{"text" => "I'll help you with that."},
                %{
                  "functionCall" => %{
                    "args" => %{"location" => "San Francisco"},
                    "name" => "get_weather"
                  }
                }
              ],
              "role" => "model"
            },
            "finishReason" => "STOP"
          }
        ]
      }

      request =
        Request.new(:gemini, [], [])
        |> Request.assign(:http_response, raw_response)
        |> Request.assign(:model, "gemini-2.5-flash")

      result = ParseResponse.call(request, [])

      llm_response = result.assigns.llm_response
      assert llm_response.content == "I'll help you with that."

      [tool_call] = llm_response.tool_calls
      assert tool_call.id == "get_weather"
      assert tool_call.type == "function"
      assert tool_call.function.name == "get_weather"
      assert tool_call.function.arguments == %{"location" => "San Francisco"}
    end

    test "ParseResponse handles blocked responses" do
      alias ExLLM.Providers.Gemini.ParseResponse

      raw_response = %{
        "candidates" => [],
        "promptFeedback" => %{
          "blockReason" => "SAFETY"
        }
      }

      request =
        Request.new(:gemini, [], [])
        |> Request.assign(:http_response, raw_response)
        |> Request.assign(:model, "gemini-2.5-flash")

      result = ParseResponse.call(request, [])

      llm_response = result.assigns.llm_response
      assert llm_response.content == ""
      assert llm_response.finish_reason == "SAFETY"
      assert String.contains?(llm_response.metadata.error, "Response blocked: SAFETY")
    end
  end

  describe "Generation config options" do
    test "BuildRequest handles generation config parameters" do
      alias ExLLM.Providers.Gemini.BuildRequest

      messages = [%{role: "user", content: "Hello"}]

      options = [
        temperature: 0.8,
        top_p: 0.9,
        top_k: 40,
        max_tokens: 100,
        stop_sequences: ["END"]
      ]

      request =
        Request.new(:gemini, messages, options)
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key")

      result = BuildRequest.call(request, [])
      body = result.assigns.request_body

      generation_config = body.generation_config
      assert generation_config.temperature == 0.8
      assert generation_config.top_p == 0.9
      assert generation_config.top_k == 40
      assert generation_config.max_output_tokens == 100
      assert generation_config.stop_sequences == ["END"]
    end

    test "BuildRequest handles safety settings" do
      alias ExLLM.Providers.Gemini.BuildRequest

      messages = [%{role: "user", content: "Hello"}]

      options = [
        safety_settings: [
          %{category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_ONLY_HIGH"},
          %{category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_MEDIUM_AND_ABOVE"}
        ]
      ]

      request =
        Request.new(:gemini, messages, options)
        |> Request.assign(:config, %{})
        |> Request.assign(:api_key, "test-key")

      result = BuildRequest.call(request, [])
      body = result.assigns.request_body

      [setting1, setting2] = body.safety_settings
      assert setting1.category == "HARM_CATEGORY_HARASSMENT"
      assert setting1.threshold == "BLOCK_ONLY_HIGH"
      assert setting2.category == "HARM_CATEGORY_HATE_SPEECH"
      assert setting2.threshold == "BLOCK_MEDIUM_AND_ABOVE"
    end
  end
end
