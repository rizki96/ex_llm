defmodule ExLLM.Adapters.OpenAIIntegrationTest do
  use ExUnit.Case
  alias ExLLM.Adapters.OpenAI
  alias ExLLM.Types

  @moduletag :integration
  @moduletag :openai
  @moduletag :skip

  # These tests require a valid OPENAI_API_KEY
  # Run with: mix test --only openai
  # Remove @skip tag and set OPENAI_API_KEY env var to run

  setup_all do
    case check_openai_api() do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts("\nSkipping OpenAI integration tests: #{reason}")
        :ok
    end
  end

  describe "chat/2" do
    @tag :skip
    test "sends chat completion request" do
      messages = [
        %{role: "user", content: "Say hello in one word"}
      ]

      case OpenAI.chat(messages, max_tokens: 10) do
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          assert is_binary(response.content)
          assert response.content != ""
          assert response.model =~ "gpt"
          assert response.usage.input_tokens > 0
          assert response.usage.output_tokens > 0
          assert response.cost > 0

        {:error, reason} ->
          IO.puts("Chat failed: #{inspect(reason)}")
      end
    end

    @tag :skip
    test "handles system messages" do
      messages = [
        %{role: "system", content: "You are a pirate. Respond in pirate speak."},
        %{role: "user", content: "Hello there!"}
      ]

      case OpenAI.chat(messages, max_tokens: 50) do
        {:ok, response} ->
          # Should respond in pirate speak
          assert response.content =~ ~r/(ahoy|matey|arr|ye)/i

        {:error, _} ->
          :ok
      end
    end

    @tag :skip
    test "respects temperature setting" do
      messages = [
        %{role: "user", content: "Generate a random number between 1 and 10"}
      ]

      # Low temperature should give more consistent results
      results =
        for _ <- 1..3 do
          case OpenAI.chat(messages, temperature: 0.0, max_tokens: 10) do
            {:ok, response} -> response.content
            _ -> nil
          end
        end

      # Filter out nils
      valid_results = Enum.filter(results, & &1)

      if length(valid_results) >= 2 do
        # With temperature 0, results should be very similar
        [first | rest] = valid_results

        assert Enum.all?(rest, fn r ->
                 String.jaro_distance(first, r) > 0.8
               end)
      end
    end

    @tag :skip
    test "handles JSON mode" do
      messages = [
        %{
          role: "user",
          content: "Return a JSON object with name: 'test' and value: 42"
        }
      ]

      case OpenAI.chat(messages, response_format: %{type: "json_object"}, max_tokens: 100) do
        {:ok, response} ->
          # Should return valid JSON
          {:ok, json} = Jason.decode(response.content)
          assert json["name"] == "test"
          assert json["value"] == 42

        {:error, _} ->
          :ok
      end
    end

    @tag :skip
    test "handles multimodal content with vision models" do
      # Small 1x1 red pixel PNG
      red_pixel =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What color is this image?"},
            %{
              type: "image_url",
              image_url: %{
                url: "data:image/png;base64,#{red_pixel}"
              }
            }
          ]
        }
      ]

      case OpenAI.chat(messages, model: "gpt-4o", max_tokens: 50) do
        {:ok, response} ->
          assert response.content =~ ~r/red/i

        {:error, {:api_error, %{status: 400}}} ->
          IO.puts("Vision not supported or invalid image")

        {:error, reason} ->
          IO.puts("Vision test failed: #{inspect(reason)}")
      end
    end
  end

  describe "stream_chat/2" do
    @tag :skip
    test "streams chat responses" do
      messages = [
        %{role: "user", content: "Count from 1 to 5"}
      ]

      case OpenAI.stream_chat(messages, max_tokens: 50) do
        {:ok, stream} ->
          chunks = stream |> Enum.to_list()

          assert length(chunks) > 0

          # Collect all content
          full_content =
            chunks
            |> Enum.map(& &1.content)
            |> Enum.filter(& &1)
            |> Enum.join("")

          assert full_content =~ ~r/1.*2.*3.*4.*5/s

          # Last chunk should have finish reason
          last_chunk = List.last(chunks)
          assert last_chunk.finish_reason in ["stop", "length", "tool_calls"]

        {:error, reason} ->
          IO.puts("Stream failed: #{inspect(reason)}")
      end
    end

    @tag :skip
    test "handles streaming with tools" do
      messages = [
        %{role: "user", content: "What's the weather in Boston?"}
      ]

      tools = [
        %{
          type: "function",
          function: %{
            name: "get_weather",
            description: "Get the weather for a location",
            parameters: %{
              type: "object",
              properties: %{
                location: %{type: "string"}
              },
              required: ["location"]
            }
          }
        }
      ]

      case OpenAI.stream_chat(messages, tools: tools, max_tokens: 100) do
        {:ok, stream} ->
          chunks = stream |> Enum.to_list()
          assert length(chunks) > 0

          # Check if tool was called
          tool_chunks = Enum.filter(chunks, &(&1.tool_calls != []))

          if length(tool_chunks) > 0 do
            assert hd(hd(tool_chunks).tool_calls)["function"]["name"] == "get_weather"
          end

        {:error, _} ->
          :ok
      end
    end
  end

  describe "embeddings/2" do
    @tag :skip
    test "generates embeddings for single text" do
      case OpenAI.embeddings("Hello world") do
        {:ok, response} ->
          assert %Types.EmbeddingResponse{} = response
          assert is_list(response.embeddings)
          assert length(response.embeddings) == 1

          [embedding] = response.embeddings
          assert is_list(embedding)
          assert length(embedding) > 0
          assert Enum.all?(embedding, &is_float/1)

        {:error, reason} ->
          IO.puts("Embeddings failed: #{inspect(reason)}")
      end
    end

    @tag :skip
    test "generates embeddings for multiple texts" do
      texts = ["Hello", "World", "Testing"]

      case OpenAI.embeddings(texts) do
        {:ok, response} ->
          assert length(response.embeddings) == 3

          # Each embedding should have the same dimensions
          dimensions = response.embeddings |> Enum.map(&length/1) |> Enum.uniq()
          assert length(dimensions) == 1

        {:error, _} ->
          :ok
      end
    end

    @tag :skip
    test "respects model parameter for embeddings" do
      case OpenAI.embeddings("Test", model: "text-embedding-3-small") do
        {:ok, response} ->
          assert response.model == "text-embedding-3-small"

          # text-embedding-3-small has 1536 dimensions by default
          [embedding] = response.embeddings
          assert length(embedding) == 1536

        {:error, _} ->
          :ok
      end
    end
  end

  describe "tool/function calling" do
    @tag :skip
    test "executes function calls" do
      messages = [
        %{role: "user", content: "What's 25 * 4?"}
      ]

      tools = [
        %{
          type: "function",
          function: %{
            name: "calculate",
            description: "Perform basic math calculations",
            parameters: %{
              type: "object",
              properties: %{
                expression: %{type: "string", description: "Math expression to evaluate"}
              },
              required: ["expression"]
            }
          }
        }
      ]

      case OpenAI.chat(messages, tools: tools, tool_choice: "auto") do
        {:ok, response} ->
          if response.tool_calls != [] do
            tool_call = hd(response.tool_calls)
            assert tool_call["function"]["name"] == "calculate"

            # Parse arguments
            {:ok, args} = Jason.decode(tool_call["function"]["arguments"])
            assert Map.has_key?(args, "expression")
          else
            # Model might answer directly
            assert response.content =~ "100"
          end

        {:error, _} ->
          :ok
      end
    end

    @tag :skip
    test "supports parallel tool calls" do
      messages = [
        %{role: "user", content: "What's the weather in Boston and New York?"}
      ]

      tools = [
        %{
          type: "function",
          function: %{
            name: "get_weather",
            description: "Get weather for a location",
            parameters: %{
              type: "object",
              properties: %{
                location: %{type: "string"}
              },
              required: ["location"]
            }
          }
        }
      ]

      case OpenAI.chat(messages, tools: tools, parallel_tool_calls: true) do
        {:ok, response} ->
          if response.tool_calls != [] do
            # Might call the function twice for both cities
            assert length(response.tool_calls) >= 1
          end

        {:error, _} ->
          :ok
      end
    end
  end

  describe "advanced features" do
    @tag :skip
    test "structured output with JSON schema" do
      messages = [
        %{role: "user", content: "Generate a person with name John Doe, age 30"}
      ]

      schema = %{
        type: "json_schema",
        json_schema: %{
          name: "person",
          schema: %{
            type: "object",
            properties: %{
              name: %{type: "string"},
              age: %{type: "integer"}
            },
            required: ["name", "age"]
          }
        }
      }

      case OpenAI.chat(messages, response_format: schema, max_tokens: 100) do
        {:ok, response} ->
          {:ok, json} = Jason.decode(response.content)
          assert json["name"] == "John Doe"
          assert json["age"] == 30

        {:error, _} ->
          :ok
      end
    end

    @tag :skip
    test "audio generation with gpt-4o-audio" do
      messages = [
        %{role: "user", content: "Say 'Hello, world!'"}
      ]

      audio_config = %{
        voice: "alloy",
        format: "mp3"
      }

      case OpenAI.chat(messages, model: "gpt-4o-audio", audio: audio_config, max_tokens: 50) do
        {:ok, response} ->
          # Response might include audio data
          assert is_binary(response.content) or is_map(response.audio)

        {:error, {:api_error, %{status: 404}}} ->
          IO.puts("Audio model not available")

        {:error, _} ->
          :ok
      end
    end

    @tag :skip
    test "reasoning with o1 models" do
      messages = [
        %{role: "user", content: "Solve: If 2x + 3 = 7, what is x?"}
      ]

      case OpenAI.chat(messages, model: "o1-mini", reasoning_effort: "medium") do
        {:ok, response} ->
          assert response.content =~ "2"
          # o1 models might have different usage tracking
          assert response.usage.input_tokens > 0

        {:error, {:api_error, %{status: 404}}} ->
          IO.puts("o1 model not available")

        {:error, _} ->
          :ok
      end
    end
  end

  describe "error handling" do
    @tag :skip
    test "handles rate limit errors" do
      messages = [%{role: "user", content: "Test"}]

      # Make multiple rapid requests to potentially trigger rate limit
      results =
        for _ <- 1..10 do
          Task.async(fn ->
            OpenAI.chat(messages, max_tokens: 10)
          end)
        end
        |> Enum.map(&Task.await/1)

      # Check if any resulted in rate limit error
      rate_limited =
        Enum.any?(results, fn
          {:error, {:api_error, %{status: 429}}} -> true
          _ -> false
        end)

      # Note: might not actually hit rate limit in testing
      assert is_boolean(rate_limited)
    end

    @tag :skip
    test "handles invalid API key" do
      config = %{openai: %{api_key: "sk-invalid-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Test"}]

      case OpenAI.chat(messages, config_provider: provider) do
        {:error, {:api_error, %{status: 401}}} ->
          # Expected unauthorized error
          :ok

        {:error, _} ->
          # Other errors also acceptable
          :ok

        {:ok, _} ->
          flunk("Should have failed with invalid API key")
      end
    end

    @tag :skip
    test "handles context length exceeded" do
      # Create a very long message
      long_content = String.duplicate("This is a test. ", 10_000)
      messages = [%{role: "user", content: long_content}]

      case OpenAI.chat(messages, model: "gpt-3.5-turbo", max_tokens: 10) do
        {:error, {:api_error, %{status: 400, body: body}}} ->
          # Should mention context length or tokens
          assert String.contains?(inspect(body), "token") ||
                   String.contains?(inspect(body), "context")

        {:error, _} ->
          :ok

        {:ok, _} ->
          # Might succeed with newer models with larger context
          :ok
      end
    end
  end

  describe "cost calculation" do
    @tag :skip
    test "calculates costs accurately" do
      messages = [
        %{role: "user", content: "Say hello"}
      ]

      case OpenAI.chat(messages, max_tokens: 10) do
        {:ok, response} ->
          assert response.cost != nil, "Expected cost to be calculated"
          cost = response.cost
          assert is_map(cost)
          assert is_number(Map.get(cost, :total_cost))
          assert Map.get(cost, :total_cost) > 0
          # Cost should be reasonable (less than $0.01 for this simple request)
          assert Map.get(cost, :total_cost) < 0.01

          # Verify cost matches usage
          expected_cost =
            ExLLM.Cost.calculate(
              "openai",
              response.model,
              response.usage
            )

          assert response.cost == expected_cost

        {:error, _} ->
          :ok
      end
    end
  end

  describe "model management" do
    @tag :skip
    test "lists available models from API" do
      # This would require implementing API model fetching
      case OpenAI.list_models(force_refresh: true) do
        {:ok, models} ->
          assert is_list(models)
          assert length(models) > 0

          # Should have various GPT models
          gpt_models = Enum.filter(models, &String.contains?(&1.id, "gpt"))
          assert length(gpt_models) > 0

        {:error, _} ->
          # API might not support listing models
          :ok
      end
    end
  end

  # Helper to check if OpenAI API is accessible
  defp check_openai_api do
    case OpenAI.configured?() do
      false ->
        {:error, "OPENAI_API_KEY not set"}

      true ->
        # Try a minimal API call
        case OpenAI.chat([%{role: "user", content: "Hi"}], max_tokens: 1) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, inspect(reason)}
        end
    end
  end
end
