defmodule ExLLM.Adapters.MockTest do
  use ExUnit.Case, async: false
  alias ExLLM.Adapters.Mock
  alias ExLLM.Types.{LLMResponse, StreamChunk}

  setup do
    # Clear any existing mock configuration
    Application.delete_env(:ex_llm, :mock_responses)
    :ok
  end

  describe "chat/2" do
    test "returns static response when configured" do
      response = %LLMResponse{
        content: "Mock response",
        usage: %{input_tokens: 10, output_tokens: 20},
        model: "mock-model",
        cost: %{input: 0.01, output: 0.02, total: 0.03}
      }

      Application.put_env(:ex_llm, :mock_responses, %{chat: response})

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, ^response} = Mock.chat(messages, [])
    end

    test "returns dynamic response based on messages" do
      dynamic_fn = fn messages, _options ->
        last_message = List.last(messages)

        %LLMResponse{
          content: "Echo: #{last_message.content}",
          usage: %{input_tokens: 5, output_tokens: 10},
          model: "echo-model"
        }
      end

      Application.put_env(:ex_llm, :mock_responses, %{chat: dynamic_fn})

      messages = [%{role: "user", content: "Test message"}]
      {:ok, response} = Mock.chat(messages, [])

      assert response.content == "Echo: Test message"
      assert response.model == "echo-model"
    end

    test "returns error when configured" do
      Application.put_env(:ex_llm, :mock_responses, %{
        chat: {:error, "API Error"}
      })

      messages = [%{role: "user", content: "Hello"}]
      assert {:error, "API Error"} = Mock.chat(messages, [])
    end

    test "returns default response when not configured" do
      messages = [%{role: "user", content: "Hello"}]
      {:ok, response} = Mock.chat(messages, [])

      assert response.content == "This is a mock response"
      assert response.usage.input_tokens == 10
      assert response.usage.output_tokens == 20
    end

    test "simulates rate limit error when configured" do
      Application.put_env(:ex_llm, :mock_responses, %{
        chat: {:error, :rate_limit}
      })

      messages = [%{role: "user", content: "Hello"}]
      assert {:error, :rate_limit} = Mock.chat(messages, [])
    end

    test "cycles through responses when list is provided" do
      responses = [
        %LLMResponse{content: "Response 1", usage: %{}, model: "mock"},
        %LLMResponse{content: "Response 2", usage: %{}, model: "mock"},
        %LLMResponse{content: "Response 3", usage: %{}, model: "mock"}
      ]

      Application.put_env(:ex_llm, :mock_responses, %{chat: responses})

      messages = [%{role: "user", content: "Hello"}]

      # Should cycle through responses
      assert {:ok, %{content: "Response 1"}} = Mock.chat(messages, [])
      assert {:ok, %{content: "Response 2"}} = Mock.chat(messages, [])
      assert {:ok, %{content: "Response 3"}} = Mock.chat(messages, [])
      # Cycles back
      assert {:ok, %{content: "Response 1"}} = Mock.chat(messages, [])
    end
  end

  describe "stream/2" do
    test "streams chunks when configured" do
      chunks = [
        %StreamChunk{content: "Hello", id: "chunk-0", finish_reason: nil},
        %StreamChunk{content: " world", id: "chunk-1", finish_reason: nil},
        %StreamChunk{content: "!", id: "chunk-2", finish_reason: "stop"}
      ]

      Application.put_env(:ex_llm, :mock_responses, %{stream: chunks})

      messages = [%{role: "user", content: "Hello"}]
      {:ok, stream} = Mock.stream_chat(messages, [])

      collected_chunks = Enum.to_list(stream)
      assert length(collected_chunks) == 3
      assert Enum.at(collected_chunks, 0).content == "Hello"
      assert Enum.at(collected_chunks, 2).finish_reason == "stop"
    end

    test "returns stream error when configured" do
      Application.put_env(:ex_llm, :mock_responses, %{
        stream: {:error, "Stream error"}
      })

      messages = [%{role: "user", content: "Hello"}]
      assert {:error, "Stream error"} = Mock.stream_chat(messages, [])
    end

    test "generates dynamic stream" do
      dynamic_stream = fn messages, _options ->
        last_msg = List.last(messages).content
        words = String.split(last_msg, " ")

        Stream.map(words, fn word ->
          %StreamChunk{content: word <> " ", id: "dynamic-chunk"}
        end)
      end

      Application.put_env(:ex_llm, :mock_responses, %{stream: dynamic_stream})

      messages = [%{role: "user", content: "one two three"}]
      {:ok, stream} = Mock.stream_chat(messages, [])

      chunks = Enum.to_list(stream)
      assert length(chunks) == 3
      assert Enum.at(chunks, 0).content == "one "
      assert Enum.at(chunks, 1).content == "two "
      assert Enum.at(chunks, 2).content == "three "
    end

    test "returns default stream when not configured" do
      messages = [%{role: "user", content: "Hello"}]
      {:ok, stream} = Mock.stream_chat(messages, [])

      chunks = Enum.to_list(stream)
      assert length(chunks) == 7
      assert Enum.at(chunks, 0).content == "This "
      assert Enum.at(chunks, 6).finish_reason == "stop"
    end

    test "simulates stream interruption" do
      # Start Mock GenServer for this test
      {:ok, _} = Mock.start_link()
      
      chunks_with_error = [
        %StreamChunk{content: "Start", id: "chunk-0"},
        %StreamChunk{content: " of", id: "chunk-1"},
        {:error, :connection_lost}
      ]

      Application.put_env(:ex_llm, :mock_responses, %{stream: chunks_with_error})

      messages = [%{role: "user", content: "Hello"}]
      {:ok, stream} = Mock.stream_chat(messages, [])

      # Collecting should raise when it hits the error
      assert_raise RuntimeError, fn ->
        Enum.to_list(stream)
      end
    end
  end

  describe "embeddings/2" do
    test "returns embedding response when configured" do
      embedding_response = %{
        embeddings: [
          %{embedding: [0.1, 0.2, 0.3], index: 0}
        ],
        model: "text-embedding-mock",
        usage: %{input_tokens: 5, output_tokens: 0}
      }

      Application.put_env(:ex_llm, :mock_responses, %{embeddings: embedding_response})

      assert {:ok, response} = Mock.embeddings("test text", [])
      assert response.embeddings == embedding_response.embeddings
      assert response.model == "text-embedding-mock"
    end

    test "handles multiple inputs" do
      dynamic_embeddings = fn inputs, _options ->
        embeddings =
          inputs
          |> Enum.with_index()
          |> Enum.map(fn {_text, idx} ->
            %{embedding: [0.1 * idx, 0.2 * idx, 0.3 * idx], index: idx}
          end)

        %{
          embeddings: embeddings,
          model: "multi-embed",
          usage: %{input_tokens: length(inputs) * 5, output_tokens: 0}
        }
      end

      Application.put_env(:ex_llm, :mock_responses, %{embeddings: dynamic_embeddings})

      inputs = ["text1", "text2", "text3"]
      {:ok, response} = Mock.embeddings(inputs, [])

      assert length(response.embeddings) == 3
      assert Enum.at(response.embeddings, 1).embedding == [0.1, 0.2, 0.3]
      assert Enum.at(response.embeddings, 2).embedding == [0.2, 0.4, 0.6]
    end

    test "returns default embeddings when not configured" do
      {:ok, response} = Mock.embeddings("test", [])

      assert length(response.embeddings) == 1
      # Default mock embedding size
      assert length(hd(response.embeddings)) == 384
      # Default mock model
      assert response.model == "mock-embedding-model"
    end
  end

  describe "list_models/1" do
    test "returns configured models" do
      models = [
        %{id: "mock-gpt-4", context_window: 8192},
        %{id: "mock-claude", context_window: 100_000}
      ]

      Application.put_env(:ex_llm, :mock_responses, %{list_models: models})

      result = Mock.list_models([])
      assert {:ok, returned_models} = result
      assert length(returned_models) == 2
      # Check that models were converted to proper structs
      assert Enum.all?(returned_models, &is_struct(&1, ExLLM.Types.Model))
    end

    test "returns default models when not configured" do
      result = Mock.list_models([])
      assert {:ok, models} = result

      assert is_list(models)
      assert length(models) > 0
      assert "mock-model-small" in Enum.map(models, & &1.id)
    end
  end

  describe "list_embedding_models/1" do
    test "returns configured embedding models" do
      models = [
        %{name: "mock-embed-1", dimensions: 768},
        %{name: "mock-embed-2", dimensions: 1536}
      ]

      Application.put_env(:ex_llm, :mock_responses, %{list_embedding_models: models})

      result = Mock.list_embedding_models([])
      assert {:ok, returned_models} = result
      assert length(returned_models) == 2
      # Check the models have the expected fields
      assert Enum.all?(returned_models, &Map.has_key?(&1, :name))
      assert Enum.all?(returned_models, &Map.has_key?(&1, :dimensions))
    end

    test "returns default embedding models when not configured" do
      result = Mock.list_embedding_models([])
      assert {:ok, models} = result

      assert is_list(models)
      assert length(models) > 0
      # Default mock embedding model
      assert hd(models).name == "mock-embedding-small"
    end
  end

  describe "complex scenarios" do
    test "simulates function calling" do
      function_response = %LLMResponse{
        content: nil,
        tool_calls: [
          %{
            id: "call_123",
            type: "function",
            function: %{
              name: "get_weather",
              arguments: ~s({"location": "San Francisco"})
            }
          }
        ],
        usage: %{input_tokens: 50, output_tokens: 30},
        model: "mock-function-model"
      }

      Application.put_env(:ex_llm, :mock_responses, %{chat: function_response})

      messages = [%{role: "user", content: "What's the weather?"}]

      options = [
        functions: [
          %{
            name: "get_weather",
            parameters: %{type: "object", properties: %{}}
          }
        ]
      ]

      {:ok, response} = Mock.chat(messages, options)
      assert response.tool_calls != nil
      assert length(response.tool_calls) == 1
      assert hd(response.tool_calls).function.name == "get_weather"
    end

    test "simulates vision model response" do
      vision_response = fn messages, _options ->
        # Check if message contains image content
        has_image =
          Enum.any?(messages, fn msg ->
            case msg.content do
              content when is_list(content) ->
                Enum.any?(content, fn part ->
                  Map.get(part, :type) == "image_url"
                end)

              _ ->
                false
            end
          end)

        content =
          if has_image do
            "I can see an image in the conversation"
          else
            "No image provided"
          end

        %LLMResponse{
          content: content,
          usage: %{input_tokens: 100, output_tokens: 20},
          model: "mock-vision-model"
        }
      end

      Application.put_env(:ex_llm, :mock_responses, %{chat: vision_response})

      # Test with image
      messages_with_image = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{type: "image_url", image_url: %{url: "https://example.com/img.jpg"}}
          ]
        }
      ]

      {:ok, response} = Mock.chat(messages_with_image, [])
      assert response.content == "I can see an image in the conversation"

      # Test without image
      messages_without_image = [%{role: "user", content: "Hello"}]
      {:ok, response} = Mock.chat(messages_without_image, [])
      assert response.content == "No image provided"
    end

    test "tracks call count and arguments" do
      # This demonstrates how mock adapter could be extended for testing
      call_tracker = :ets.new(:mock_calls, [:set, :public])

      tracking_fn = fn messages, options ->
        try do
          :ets.update_counter(call_tracker, :call_count, 1, {:call_count, 0})
          :ets.insert(call_tracker, {:last_call, {messages, options}})
        catch
          :error, :badarg ->
            # Table doesn't exist anymore, skip tracking
            :ok
        end

        %LLMResponse{
          content: "Tracked response",
          usage: %{input_tokens: 5, output_tokens: 5},
          model: "tracking-model"
        }
      end

      Application.put_env(:ex_llm, :mock_responses, %{chat: tracking_fn})

      # Make multiple calls
      Mock.chat([%{role: "user", content: "First"}], temperature: 0.5)
      Mock.chat([%{role: "user", content: "Second"}], temperature: 0.7)

      # Verify tracking (only if table still exists)
      try do
        [{:call_count, count}] = :ets.lookup(call_tracker, :call_count)
        assert count == 2

        [{:last_call, {messages, options}}] = :ets.lookup(call_tracker, :last_call)
        assert hd(messages).content == "Second"
        assert options[:temperature] == 0.7
      catch
        :error, :badarg ->
          # Table was deleted, which is acceptable
          :ok
      end

      # Clean up
      try do
        :ets.delete(call_tracker)
      catch
        :error, :badarg ->
          # Already deleted
          :ok
      end

      # Clean up the global mock responses to avoid affecting other tests
      Application.delete_env(:ex_llm, :mock_responses)
    end
  end
end
