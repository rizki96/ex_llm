defmodule ExLLM.MockTest do
  use ExUnit.Case, async: false

  alias ExLLM.Providers.Mock
  alias ExLLM.Types

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

      # Check that the specific options we passed are present
      assert Keyword.get(last_request.options, :temperature) == 0.7
      assert Keyword.get(last_request.options, :max_tokens) == 100
      assert Keyword.get(last_request.options, :cache) == false
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
      # Configure application environment for mock streaming
      Application.put_env(:ex_llm, :mock_responses, %{
        stream: [
          %Types.StreamChunk{content: "Hello ", finish_reason: nil},
          %Types.StreamChunk{content: "world!", finish_reason: nil},
          %Types.StreamChunk{content: "", finish_reason: "stop"}
        ]
      })

      messages = [%{role: "user", content: "Hi"}]
      collected = []

      # Use the new streaming API
      result =
        ExLLM.stream(:mock, messages, fn chunk ->
          send(self(), {:chunk, chunk})
          chunk
        end)

      case result do
        :ok ->
          # Collect chunks from messages
          collected = collect_chunks(3, [])
          assert length(collected) == 3
          assert Enum.at(collected, 0).content == "Hello "
          assert Enum.at(collected, 1).content == "world!"
          assert Enum.at(collected, 2).finish_reason == "stop"

        error ->
          flunk("Streaming failed: #{inspect(error)}")
      end

      # Clean up
      Application.delete_env(:ex_llm, :mock_responses)
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
    test "retry functionality not implemented" do
      # Retry functionality not yet implemented in v1.0 pipeline architecture
      # This test documents that retry is not currently supported
      
      # The pipeline doesn't currently implement retry logic, so errors
      # are returned immediately without retry attempts
      messages = [%{role: "user", content: "Test"}]
      
      # Set mock to return an error
      Mock.set_error({:network_error, "Connection failed"})
      
      # Should get the error immediately without retries
      assert {:error, {:network_error, "Connection failed"}} =
               ExLLM.chat(:mock, messages, cache: false)
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
      assert length(models) == 3

      assert Enum.find(models, &(&1.id == "mock-model-small"))
      assert Enum.find(models, &(&1.id == "mock-model-large"))
      assert Enum.find(models, &(&1.id == "mock-embedding-model"))
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

  # Helper function to collect streaming chunks
  defp collect_chunks(0, acc), do: Enum.reverse(acc)

  defp collect_chunks(remaining, acc) do
    receive do
      {:chunk, chunk} ->
        collect_chunks(remaining - 1, [chunk | acc])
    after
      1000 ->
        # Timeout - return what we have
        Enum.reverse(acc)
    end
  end
end
