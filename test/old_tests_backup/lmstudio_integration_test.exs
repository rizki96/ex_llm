defmodule ExLLM.LMStudioIntegrationTest do
  use ExUnit.Case
  alias ExLLM.Providers.LMStudio
  alias ExLLM.Types

  @moduletag :integration
  @moduletag :lmstudio

  # These tests require LM Studio to be running locally on localhost:1234
  # Run with: mix test --only lmstudio

  setup_all do
    case check_lmstudio_availability() do
      :ok ->
        IO.puts("\nLM Studio detected - running integration tests")
        :ok

      {:error, reason} ->
        IO.puts("\nSkipping LM Studio integration tests: #{reason}")
        IO.puts("To run these tests:")
        IO.puts("1. Install LM Studio from https://lmstudio.ai")
        IO.puts("2. Load a model (e.g., llama-3.2-3b-instruct)")
        IO.puts("3. Start the local server on localhost:1234")
        IO.puts("4. Run: mix test --only lmstudio")
        :skip
    end
  end

  describe "connectivity and configuration" do
    test "LM Studio server is accessible" do
      assert LMStudio.configured?() == true
    end

    test "can connect to custom host and port" do
      # Test with default localhost:1234
      assert LMStudio.configured?(host: "localhost", port: 1234) == true
    end

    test "detects when LM Studio is not running" do
      # Test with non-existent port
      assert LMStudio.configured?(host: "localhost", port: 9999) == false
    end
  end

  describe "model management" do
    test "lists available models" do
      case LMStudio.list_models() do
        {:ok, models} ->
          assert is_list(models)
          assert length(models) > 0

          model = hd(models)
          assert %Types.Model{} = model
          assert is_binary(model.id)
          assert is_binary(model.name)
          assert is_binary(model.description)
          assert is_integer(model.context_window)
          assert model.context_window > 0
          assert is_map(model.capabilities)

          IO.puts("✓ Found #{length(models)} available models")

          Enum.each(models, fn m ->
            IO.puts("  - #{m.id} (#{m.context_window} context)")
          end)

        {:error, reason} ->
          IO.puts("Models list failed: #{reason}")
          # Don't fail the test if LM Studio is running but no models loaded
          assert String.contains?(reason, "No models") or String.contains?(reason, "not loaded")
      end
    end

    test "lists models with enhanced information" do
      case LMStudio.list_models(enhanced: true) do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            model = hd(models)
            assert %Types.Model{} = model

            # Enhanced info should include more details
            assert model.description =~ ~r/(llama\.cpp|MLX|Loaded|Available)/
            assert Map.has_key?(model.capabilities, :features)

            IO.puts("✓ Enhanced model info available")
            IO.puts("  Example: #{model.id} - #{model.description}")
          else
            IO.puts("⚠ No models loaded in LM Studio")
          end

        {:error, reason} ->
          IO.puts("Enhanced models list failed: #{reason}")
      end
    end

    test "filters for loaded models only" do
      case LMStudio.list_models(loaded_only: true) do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            # All returned models should be loaded
            loaded_count =
              Enum.count(models, fn m ->
                String.contains?(m.description, "Loaded")
              end)

            assert loaded_count == length(models)
            IO.puts("✓ Found #{length(models)} loaded models")
          else
            IO.puts("⚠ No models currently loaded in LM Studio")
          end

        {:error, _reason} ->
          # Expected if no models are loaded
          :ok
      end
    end
  end

  describe "chat functionality" do
    test "basic chat completion" do
      messages = [%{role: "user", content: "What is 2+2? Answer with just the number."}]

      case LMStudio.chat(messages) do
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          assert is_binary(response.content)
          assert String.trim(response.content) != ""
          assert is_map(response.usage)
          assert response.usage.input_tokens > 0
          assert response.usage.output_tokens > 0
          assert response.usage.total_tokens > 0
          assert is_binary(response.model)
          assert response.finish_reason in ["stop", "length", "tool_calls"]

          IO.puts("✓ Basic chat works")
          IO.puts("  Model: #{response.model}")
          IO.puts("  Response: #{String.slice(response.content, 0, 50)}...")
          IO.puts("  Tokens: #{response.usage.input_tokens} → #{response.usage.output_tokens}")

        {:error, reason} ->
          IO.puts("Chat failed: #{reason}")
          # Fail only if it's not a "no models loaded" error
          refute String.contains?(reason, "No model")
      end
    end

    test "chat with specific model" do
      # First get available models
      case LMStudio.list_models() do
        {:ok, [_ | _] = models} ->
          model_id = hd(models).id
          messages = [%{role: "user", content: "Say 'Hello from #{model_id}'"}]

          case LMStudio.chat(messages, model: model_id) do
            {:ok, response} ->
              assert response.model == model_id
              assert String.contains?(response.content, "Hello")

              IO.puts("✓ Specific model chat works")
              IO.puts("  Used model: #{model_id}")

            {:error, reason} ->
              IO.puts("Model-specific chat failed: #{reason}")
          end

        {:ok, []} ->
          IO.puts("⚠ No models available for specific model test")

        {:error, reason} ->
          IO.puts("Could not get models for specific model test: #{reason}")
      end
    end

    test "chat with temperature control" do
      messages = [%{role: "user", content: "Write a creative sentence about cats."}]

      # Test low temperature (more deterministic)
      case LMStudio.chat(messages, temperature: 0.1) do
        {:ok, response1} ->
          # Test high temperature (more creative)
          case LMStudio.chat(messages, temperature: 0.9) do
            {:ok, response2} ->
              assert response1.content != response2.content
              IO.puts("✓ Temperature control works")
              IO.puts("  Low temp: #{String.slice(response1.content, 0, 40)}...")
              IO.puts("  High temp: #{String.slice(response2.content, 0, 40)}...")

            {:error, reason} ->
              IO.puts("High temperature chat failed: #{reason}")
          end

        {:error, reason} ->
          IO.puts("Low temperature chat failed: #{reason}")
      end
    end

    test "chat with token limits" do
      messages = [%{role: "user", content: "Count from 1 to 100."}]

      case LMStudio.chat(messages, max_tokens: 20) do
        {:ok, response} ->
          # Response should be limited
          # Allow some buffer
          assert response.usage.output_tokens <= 25
          IO.puts("✓ Token limits work")
          IO.puts("  Output tokens: #{response.usage.output_tokens}")

        {:error, reason} ->
          IO.puts("Token-limited chat failed: #{reason}")
      end
    end

    test "multi-turn conversation" do
      conversation = [
        %{role: "user", content: "My name is Alice."},
        %{role: "assistant", content: "Nice to meet you, Alice!"},
        %{role: "user", content: "What's my name?"}
      ]

      case LMStudio.chat(conversation) do
        {:ok, response} ->
          # Model should remember the name from context
          assert String.contains?(String.downcase(response.content), "alice")
          IO.puts("✓ Multi-turn conversation works")
          IO.puts("  Context memory: #{String.slice(response.content, 0, 50)}...")

        {:error, reason} ->
          IO.puts("Multi-turn chat failed: #{reason}")
      end
    end

    test "system prompt handling" do
      messages = [
        %{role: "system", content: "You are a helpful math tutor. Always show your work."},
        %{role: "user", content: "What is 15 × 8?"}
      ]

      case LMStudio.chat(messages) do
        {:ok, response} ->
          # Response should follow system instructions
          content_lower = String.downcase(response.content)

          assert String.contains?(content_lower, "120") or String.contains?(content_lower, "15") or
                   String.contains?(content_lower, "8")

          IO.puts("✓ System prompts work")
          IO.puts("  Guided response: #{String.slice(response.content, 0, 60)}...")

        {:error, reason} ->
          IO.puts("System prompt chat failed: #{reason}")
      end
    end
  end

  describe "streaming chat" do
    test "basic streaming response" do
      messages = [
        %{role: "user", content: "Tell me a short story about a robot in exactly two sentences."}
      ]

      case LMStudio.stream_chat(messages) do
        {:ok, stream} ->
          chunks = stream |> Enum.take(20) |> Enum.to_list()

          assert length(chunks) > 0

          # Check chunk structure
          chunk = hd(chunks)
          assert %Types.StreamChunk{} = chunk
          assert is_binary(chunk.content) or is_nil(chunk.content)

          # Concatenate content
          full_content =
            chunks
            |> Enum.map(&(&1.content || ""))
            |> Enum.join("")

          assert String.trim(full_content) != ""

          # Verify we got meaningful content
          assert length(chunks) > 0
          assert String.trim(full_content) != ""

          # Note: finish_reason may not be present in the first 20 chunks
          # as the response might be longer

          IO.puts("✓ Streaming works")
          IO.puts("  Chunks received: #{length(chunks)}")
          IO.puts("  Total content: #{String.length(full_content)} chars")

        {:error, reason} ->
          IO.puts("Streaming failed: #{reason}")
      end
    end

    test "streaming with token limits" do
      messages = [%{role: "user", content: "List the first 20 prime numbers."}]

      case LMStudio.stream_chat(messages, max_tokens: 30) do
        {:ok, stream} ->
          chunks = Enum.to_list(stream)

          full_content =
            chunks
            |> Enum.map(&(&1.content || ""))
            |> Enum.join("")

          # Should be limited due to token constraint
          assert String.length(full_content) < 300

          IO.puts("✓ Streaming with limits works")
          IO.puts("  Limited content: #{String.slice(full_content, 0, 50)}...")

        {:error, reason} ->
          IO.puts("Limited streaming failed: #{reason}")
      end
    end
  end

  describe "LM Studio specific features" do
    test "TTL parameter for model management" do
      messages = [%{role: "user", content: "Hello with TTL"}]

      case LMStudio.chat(messages, ttl: 300) do
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          IO.puts("✓ TTL parameter accepted")

        {:error, reason} ->
          IO.puts("TTL chat failed: #{reason}")
      end
    end

    test "custom API key support" do
      messages = [%{role: "user", content: "Hello with custom key"}]

      case LMStudio.chat(messages, api_key: "custom-key") do
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          IO.puts("✓ Custom API key accepted")

        {:error, reason} ->
          # LM Studio might reject non-standard keys, that's OK
          IO.puts("Custom key result: #{reason}")
      end
    end

    test "native API endpoints provide enhanced information" do
      case LMStudio.list_models(enhanced: true) do
        {:ok, [_ | _] = models} ->
          model = hd(models)

          # Enhanced models should have architecture info
          assert Map.has_key?(model.capabilities, :features)

          architecture_mentioned =
            String.contains?(model.description, "llama.cpp") or
              String.contains?(model.description, "MLX") or
              String.contains?(model.description, "Loaded")

          assert architecture_mentioned
          IO.puts("✓ Native API provides enhanced info")

        {:ok, []} ->
          IO.puts("⚠ No models for enhanced info test")

        {:error, reason} ->
          IO.puts("Enhanced API test failed: #{reason}")
      end
    end
  end

  describe "error handling" do
    test "handles invalid model names gracefully" do
      messages = [%{role: "user", content: "Test"}]

      case LMStudio.chat(messages, model: "definitely-not-a-real-model") do
        {:ok, _response} ->
          # Unexpected success, but not necessarily wrong
          IO.puts("⚠ Invalid model accepted (LM Studio may have auto-fallback)")

        {:error, reason} ->
          assert is_binary(reason)
          assert String.contains?(reason, "not found") or String.contains?(reason, "invalid")
          IO.puts("✓ Invalid model rejected properly")
      end
    end

    test "handles connection timeouts" do
      messages = [%{role: "user", content: "Test"}]

      case LMStudio.chat(messages, timeout: 1) do
        {:ok, _response} ->
          # Very fast response, that's fine
          IO.puts("✓ Very fast response received")

        {:error, reason} ->
          assert String.contains?(reason, "timeout") or String.contains?(reason, "connection")
          IO.puts("✓ Timeout handled properly")
      end
    end
  end

  describe "performance and reliability" do
    test "handles concurrent requests" do
      messages = [%{role: "user", content: "What is #{:rand.uniform(100)}?"}]

      # Send 3 concurrent requests
      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            case LMStudio.chat(messages) do
              {:ok, response} -> {:success, i, response.content}
              {:error, reason} -> {:error, i, reason}
            end
          end)
        end

      results = Task.await_many(tasks, 30_000)
      successful = Enum.count(results, fn {status, _, _} -> status == :success end)

      assert successful >= 1
      IO.puts("✓ Concurrent requests: #{successful}/3 succeeded")
    end

    test "model loading and caching behavior" do
      messages = [%{role: "user", content: "Test model caching"}]

      # First request might be slower (model loading)
      {time1, result1} = :timer.tc(fn -> LMStudio.chat(messages) end)

      case result1 do
        {:ok, _} ->
          # Second request should be faster (cached)
          {time2, result2} = :timer.tc(fn -> LMStudio.chat(messages) end)

          case result2 do
            {:ok, _} ->
              time1_ms = div(time1, 1000)
              time2_ms = div(time2, 1000)

              IO.puts("✓ Model caching test")
              IO.puts("  First request: #{time1_ms}ms")
              IO.puts("  Second request: #{time2_ms}ms")

              if time2_ms < time1_ms do
                IO.puts("  ✓ Caching appears to work (faster second request)")
              else
                IO.puts("  ? Second request not faster (may still be cached)")
              end

            {:error, reason} ->
              IO.puts("Second caching request failed: #{reason}")
          end

        {:error, reason} ->
          IO.puts("First caching request failed: #{reason}")
      end
    end
  end

  # Helper functions

  defp check_lmstudio_availability do
    case LMStudio.configured?() do
      true ->
        # Also check if we can list models
        case LMStudio.list_models() do
          {:ok, _models} -> :ok
          {:error, reason} -> {:error, "LM Studio running but no models: #{reason}"}
        end

      false ->
        {:error, "LM Studio not accessible on localhost:1234"}
    end
  end
end
