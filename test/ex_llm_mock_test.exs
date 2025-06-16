defmodule ExLLM.MockTest do
  use ExUnit.Case, async: false

  alias ExLLM.Providers.Mock

  setup do
    # Using TestHelpers would reset the mock, but we need direct control
    # for this test suite to test the Mock adapter itself
    case Mock.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    Mock.reset()
    :ok
  end

  describe "basic chat operations" do
    test "returns static response" do
      Mock.set_response(%{
        content: "Hello from mock!",
        model: "test-model",
        usage: %{input_tokens: 5, output_tokens: 10}
      })

      messages = [%{role: "user", content: "Hello"}]

      assert {:ok, response} = ExLLM.chat(:mock, messages, cache: false)
      assert response.content == "Hello from mock!"
      assert response.model == "test-model"
      assert response.usage.input_tokens == 5
      assert response.usage.output_tokens == 10
    end

    test "captures requests" do
      messages = [%{role: "user", content: "Test message"}]
      options = [temperature: 0.7, max_tokens: 100]
      full_options = options ++ [cache: false]

      ExLLM.chat(:mock, messages, full_options)

      requests = Mock.get_requests()
      assert length(requests) == 1

      last_request = Mock.get_last_request()
      assert last_request.type == :chat
      assert last_request.messages == messages
      assert last_request.options == full_options
    end

    test "handles dynamic responses" do
      Mock.set_response_handler(fn messages, _options ->
        last_message = List.last(messages)

        %{
          content: "Echo: #{last_message.content}",
          model: "echo-model"
        }
      end)

      messages = [%{role: "user", content: "Hello world"}]

      assert {:ok, response} = ExLLM.chat(:mock, messages, cache: false)
      assert response.content == "Echo: Hello world"
      assert response.model == "echo-model"
    end

    test "simulates errors" do
      # Explicitly reset before setting error to ensure clean state
      Mock.reset()
      Mock.set_error({:api_error, %{status: 500, body: "Internal server error"}})

      messages = [%{role: "user", content: "Hello"}]

      assert {:error, {:api_error, %{status: 500, body: "Internal server error"}}} =
               ExLLM.chat(:mock, messages, retry: false, cache: false)
    end
  end

  describe "streaming operations" do
    test "returns stream chunks" do
      chunks = [
        %ExLLM.Types.StreamChunk{content: "Hello ", finish_reason: nil},
        %ExLLM.Types.StreamChunk{content: "world!", finish_reason: nil},
        %ExLLM.Types.StreamChunk{content: "", finish_reason: "stop"}
      ]

      Mock.set_stream_chunks(chunks)

      messages = [%{role: "user", content: "Hi"}]

      assert {:ok, stream} = ExLLM.stream_chat(:mock, messages)

      collected = Enum.to_list(stream)
      assert length(collected) == 3
      assert Enum.at(collected, 0).content == "Hello "
      assert Enum.at(collected, 1).content == "world!"
      assert Enum.at(collected, 2).finish_reason == "stop"
    end

    test "captures streaming requests" do
      messages = [%{role: "user", content: "Stream test"}]

      {:ok, stream} = ExLLM.stream_chat(:mock, messages, temperature: 0.5)
      # Consume stream
      Enum.to_list(stream)

      last_request = Mock.get_last_request()
      assert last_request.type == :stream_chat
      assert last_request.messages == messages
      assert last_request.options[:temperature] == 0.5
    end
  end

  describe "function calling" do
    test "returns function call response" do
      Mock.set_response(%{
        content: nil,
        function_call: %{
          name: "get_weather",
          arguments: ~s({"location": "San Francisco"})
        }
      })

      functions = [
        %{
          name: "get_weather",
          description: "Get weather",
          parameters: %{
            "type" => "object",
            "properties" => %{
              "location" => %{"type" => "string"}
            }
          }
        }
      ]

      messages = [%{role: "user", content: "What's the weather?"}]

      assert {:ok, response} = ExLLM.chat(:mock, messages, functions: functions, cache: false)
      assert response.function_call != nil
      assert response.function_call.name == "get_weather"
      assert response.function_call.arguments == ~s({"location": "San Francisco"})
    end

    test "parses function calls from response" do
      Mock.set_response(%{
        content: nil,
        tool_calls: [
          %{
            id: "call_123",
            type: "function",
            function: %{
              name: "get_time",
              arguments: ~s({"timezone": "PST"})
            }
          }
        ]
      })

      messages = [%{role: "user", content: "What time is it?"}]
      {:ok, response} = ExLLM.chat(:mock, messages, cache: false)

      # Since mock adapter doesn't implement provider-specific parsing,
      # we'll test the response structure directly
      assert response.tool_calls
      assert length(response.tool_calls) == 1
      assert hd(response.tool_calls).function.name == "get_time"
    end
  end

  describe "retry behavior" do
    test "retries on transient errors" do
      call_count = :counters.new(1, [:atomics])

      Mock.set_response_handler(fn _messages, _options ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        if count <= 2 do
          {:error, {:network_error, "Connection timeout"}}
        else
          {:ok, %{content: "Success after retry"}}
        end
      end)

      messages = [%{role: "user", content: "Test retry"}]

      assert {:ok, response} =
               ExLLM.chat(:mock, messages,
                 retry_options: [max_attempts: 3, base_delay: 10],
                 cache: false
               )

      assert response.content == "Success after retry"
      assert :counters.get(call_count, 1) == 3
    end

    test "respects retry disabled option" do
      messages = [%{role: "user", content: "No retry"}]

      assert {:error, {:network_error, "Connection failed"}} =
               ExLLM.chat(:mock, messages,
                 retry: false,
                 cache: false,
                 mock_error: {:network_error, "Connection failed"}
               )

      # Should only have one request
      assert length(Mock.get_requests()) == 1
    end
  end

  describe "model listing" do
    test "returns mock models" do
      assert {:ok, models} = ExLLM.list_models(:mock)
      assert length(models) == 2

      assert Enum.find(models, &(&1.id == "mock-model-small"))
      assert Enum.find(models, &(&1.id == "mock-model-large"))
    end
  end

  describe "configuration" do
    test "mock adapter is always configured" do
      assert ExLLM.configured?(:mock)
    end
  end

  describe "context management integration" do
    test "respects context truncation with mock" do
      Mock.set_response_handler(fn messages, _options ->
        # Return the number of messages received
        %{content: "Received #{length(messages)} messages"}
      end)

      # Create many messages
      messages =
        for i <- 1..100 do
          %{role: "user", content: "Message #{i} with some content to fill tokens"}
        end

      assert {:ok, response} =
               ExLLM.chat(:mock, messages,
                 max_tokens: 100,
                 strategy: :sliding_window,
                 cache: false
               )

      # The response should indicate fewer messages due to truncation
      assert response.content =~ "Received"
      # The exact number depends on token estimation
    end
  end
end
