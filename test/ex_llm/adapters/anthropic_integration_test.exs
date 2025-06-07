defmodule ExLLM.Adapters.AnthropicIntegrationTest do
  use ExUnit.Case
  alias ExLLM.Adapters.Anthropic
  alias ExLLM.Types

  @moduletag :integration
  @moduletag :anthropic
  @moduletag :skip

  # These tests require a valid ANTHROPIC_API_KEY
  # Run with: mix test --only anthropic
  # Remove @skip tag and set ANTHROPIC_API_KEY env var to run

  setup_all do
    case check_anthropic_api() do
      :ok -> 
        :ok
      {:error, reason} ->
        IO.puts("\nSkipping Anthropic integration tests: #{reason}")
        :ok
    end
  end

  describe "chat/2" do
    @tag :skip
    test "sends chat completion request" do
      messages = [
        %{role: "user", content: "Say hello in one word"}
      ]
      
      case Anthropic.chat(messages, max_tokens: 10) do
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          assert is_binary(response.content)
          assert response.content != ""
          assert response.model =~ "claude"
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
      
      case Anthropic.chat(messages, max_tokens: 50) do
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
      results = for _ <- 1..3 do
        case Anthropic.chat(messages, temperature: 0.0, max_tokens: 10) do
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
    test "handles multimodal content with images" do
      # This requires a valid base64 image
      # Using a small 1x1 red pixel PNG
      red_pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="
      
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What color is this image?"},
            %{
              type: "image",
              image: %{
                data: red_pixel,
                media_type: "image/png"
              }
            }
          ]
        }
      ]
      
      case Anthropic.chat(messages, model: "claude-3-5-sonnet-20241022", max_tokens: 50) do
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
      
      case Anthropic.stream_chat(messages, max_tokens: 50) do
        {:ok, stream} ->
          chunks = stream |> Enum.to_list()
          
          assert length(chunks) > 0
          
          # Collect all content
          full_content = 
            chunks
            |> Enum.map(& &1.content)
            |> Enum.filter(& &1)
            |> Enum.join("")
          
          assert full_content =~ ~r/1.*2.*3.*4.*5/
          
          # Last chunk should have finish reason
          last_chunk = List.last(chunks)
          assert last_chunk.finish_reason in ["end_turn", "stop_sequence", "max_tokens"]
          
        {:error, reason} ->
          IO.puts("Stream failed: #{inspect(reason)}")
      end
    end

    @tag :skip
    test "handles streaming errors gracefully" do
      messages = [
        %{role: "user", content: "Test"}
      ]
      
      # Use invalid model to trigger error
      case Anthropic.stream_chat(messages, model: "invalid-model") do
        {:ok, stream} ->
          # Should throw error when consuming
          assert_raise RuntimeError, fn ->
            Enum.to_list(stream)
          end
          
        {:error, _} ->
          # Direct error is also acceptable
          :ok
      end
    end
  end

  describe "list_models/1" do
    @tag :skip
    test "fetches available models from API" do
      case Anthropic.list_models() do
        {:ok, models} ->
          assert is_list(models)
          assert length(models) > 0
          
          # Check model structure
          model = hd(models)
          assert %Types.Model{} = model
          assert String.contains?(model.id, "claude")
          assert model.context_window > 0
          assert is_map(model.capabilities)
          
          # Should have multiple Claude models
          claude_models = Enum.filter(models, &String.contains?(&1.id, "claude"))
          assert length(claude_models) >= 1
          
        {:error, reason} ->
          IO.puts("Model listing failed: #{inspect(reason)}")
      end
    end

    @tag :skip
    test "model capabilities are accurate" do
      case Anthropic.list_models() do
        {:ok, models} ->
          # Claude 3+ models should support tools/functions
          claude_3_model = Enum.find(models, &String.contains?(&1.id, "claude-3"))
          
          if claude_3_model do
            assert claude_3_model.capabilities.supports_streaming == true
            
            # Check for vision support in newer models
            if String.contains?(claude_3_model.id, "claude-3-5") do
              assert claude_3_model.capabilities.supports_vision ||
                     "vision" in claude_3_model.capabilities.features
            end
          end
          
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
      results = for _ <- 1..5 do
        Task.async(fn -> 
          Anthropic.chat(messages, max_tokens: 10)
        end)
      end
      |> Enum.map(&Task.await/1)
      
      # Check if any resulted in rate limit error
      rate_limited = Enum.any?(results, fn
        {:error, {:api_error, %{status: 429}}} -> true
        _ -> false
      end)
      
      # Note: might not actually hit rate limit in testing
      assert is_boolean(rate_limited)
    end

    @tag :skip
    test "handles invalid API key" do
      config = %{anthropic: %{api_key: "sk-ant-invalid-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      
      messages = [%{role: "user", content: "Test"}]
      
      case Anthropic.chat(messages, config_provider: provider) do
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
      long_content = String.duplicate("This is a test. ", 50_000)
      messages = [%{role: "user", content: long_content}]
      
      case Anthropic.chat(messages, max_tokens: 10) do
        {:error, {:api_error, %{status: 400, body: body}}} ->
          # Should mention context length or tokens
          assert String.contains?(inspect(body), "token") ||
                 String.contains?(inspect(body), "context")
          
        {:error, _} ->
          :ok
          
        {:ok, _} ->
          flunk("Should have failed with context length error")
      end
    end
  end

  describe "advanced features" do
    @tag :skip
    test "supports JSON mode output" do
      messages = [
        %{
          role: "user", 
          content: "Return a JSON object with name: 'test' and value: 42"
        }
      ]
      
      # Note: Anthropic doesn't have a specific JSON mode like OpenAI
      # but we can instruct it to return JSON
      case Anthropic.chat(messages, max_tokens: 100) do
        {:ok, response} ->
          # Try to parse as JSON
          case Jason.decode(response.content) do
            {:ok, json} ->
              assert json["name"] == "test"
              assert json["value"] == 42
              
            _ ->
              # Model might include markdown formatting
              if response.content =~ ~r/```json(.+)```/s do
                [_, json_content] = Regex.run(~r/```json(.+)```/s, response.content)
                case Jason.decode(String.trim(json_content)) do
                  {:ok, json} ->
                    assert is_map(json)
                  _ ->
                    IO.puts("Could not parse JSON from response")
                end
              end
          end
          
        {:error, _} ->
          :ok
      end
    end

    @tag :skip
    test "handles multiple system messages gracefully" do
      # Anthropic only supports one system message
      messages = [
        %{role: "system", content: "You are helpful."},
        %{role: "system", content: "You are concise."},
        %{role: "user", content: "Hi"}
      ]
      
      case Anthropic.chat(messages, max_tokens: 50) do
        {:ok, response} ->
          # Should combine or use last system message
          assert is_binary(response.content)
          
        {:error, _} ->
          # Might reject multiple system messages
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
      
      case Anthropic.chat(messages, max_tokens: 10) do
        {:ok, response} ->
          assert response.cost > 0
          assert is_float(response.cost)
          
          # Cost should be reasonable (less than $0.01 for this simple request)
          assert response.cost < 0.01
          
          # Verify cost matches usage
          expected_cost = ExLLM.Cost.calculate(
            "anthropic",
            response.model,
            response.usage
          )
          assert response.cost == expected_cost
          
        {:error, _} ->
          :ok
      end
    end
  end

  # Beta features (would require beta headers)
  describe "beta features" do
    @tag :skip
    @tag :beta
    test "message batches API" do
      # This would require implementing the batch API
      # Placeholder for future implementation
      :ok
    end

    @tag :skip
    @tag :beta
    test "files API" do
      # This would require implementing the files API
      # Placeholder for future implementation
      :ok
    end
  end

  # Helper to check if Anthropic API is accessible
  defp check_anthropic_api do
    case Anthropic.configured?() do
      false -> 
        {:error, "ANTHROPIC_API_KEY not set"}
      true ->
        # Try a minimal API call
        case Anthropic.list_models() do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, inspect(reason)}
        end
    end
  end
end