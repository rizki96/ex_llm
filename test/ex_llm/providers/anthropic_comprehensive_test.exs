defmodule ExLLM.Providers.AnthropicComprehensiveTest do
  use ExUnit.Case, async: false
  import ExLLM.Testing.TestCacheHelpers

  alias ExLLM.Providers.Anthropic

  @moduletag :live_api
  @moduletag :provider
  @moduletag provider: :anthropic

  # Skip these tests if no API key is configured
  setup context do
    if System.get_env("ANTHROPIC_API_KEY") do
      # Enable cache for tests
      setup_test_cache(context)

      on_exit(fn ->
        ExLLM.Testing.TestCacheDetector.clear_test_context()
      end)

      :ok
    else
      :skip
    end
  end

  describe "Messages API (chat)" do
    @tag :requires_api_key
    test "basic chat completion" do
      messages = [
        %{role: "user", content: "Say 'test' and nothing else."}
      ]

      assert {:ok, response} = Anthropic.chat(messages, max_tokens: 10)
      assert %ExLLM.Types.LLMResponse{} = response
      assert is_binary(response.content)
      assert response.model
      assert response.usage
      assert response.id
    end

    @tag :requires_api_key
    test "chat with system message" do
      messages = [
        %{role: "system", content: "You are a helpful assistant that only responds with 'OK'."},
        %{role: "user", content: "Hello!"}
      ]

      assert {:ok, response} = Anthropic.chat(messages, max_tokens: 10)
      assert response.content =~ ~r/OK/i
    end

    @tag :requires_api_key
    test "chat with temperature" do
      messages = [
        %{role: "user", content: "Say 'test'."}
      ]

      assert {:ok, response} = Anthropic.chat(messages, temperature: 0.0, max_tokens: 10)
      assert response.content
    end

    @tag :requires_api_key
    test "chat with specific model" do
      messages = [
        %{role: "user", content: "Say 'test'."}
      ]

      assert {:ok, response} =
               Anthropic.chat(messages,
                 model: "claude-3-haiku-20240307",
                 max_tokens: 10
               )

      assert response.model == "claude-3-haiku-20240307"
    end

    @tag :requires_api_key
    @tag :multimodal
    test "chat with image content" do
      # This would require a base64 encoded image
      # Skipping for now as it requires test fixtures
      :skip
    end
  end

  describe "Models API" do
    @tag :requires_api_key
    test "list available models" do
      assert {:ok, models} = Anthropic.list_models()
      assert is_list(models)
      assert length(models) > 0

      # Verify model structure
      [first_model | _] = models
      assert %ExLLM.Types.Model{} = first_model
      assert first_model.id
      assert first_model.name
      assert first_model.context_window
      assert first_model.capabilities
    end

    @tag :requires_api_key
    test "list models with caching" do
      # First call
      {:ok, models1} = Anthropic.list_models()

      # Second call should be cached
      {:ok, models2} = Anthropic.list_models()

      # Models should be identical if cached
      assert models1 == models2
    end
  end

  describe "Streaming API" do
    @tag :requires_api_key
    @tag :streaming
    test "stream chat completion" do
      messages = [
        %{role: "user", content: "Count from 1 to 3."}
      ]

      assert {:ok, stream} = Anthropic.stream_chat(messages, max_tokens: 50)

      chunks = Enum.to_list(stream)
      assert length(chunks) > 0

      # Verify chunk structure
      assert Enum.all?(chunks, fn chunk ->
               match?(%ExLLM.Types.StreamChunk{}, chunk)
             end)

      # Concatenate content
      full_content =
        chunks
        |> Enum.map(&(&1.content || ""))
        |> Enum.join("")

      assert full_content =~ ~r/1.*2.*3/s
    end

    @tag :requires_api_key
    @tag :streaming
    test "stream with early termination" do
      messages = [
        %{role: "user", content: "Count from 1 to 100."}
      ]

      assert {:ok, stream} = Anthropic.stream_chat(messages, max_tokens: 20)

      # Take only first 5 chunks
      chunks = stream |> Enum.take(5)
      assert length(chunks) <= 5
    end
  end

  describe "Error Handling" do
    test "chat without API key" do
      # Temporarily unset API key
      original_key = System.get_env("ANTHROPIC_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")

      messages = [%{role: "user", content: "test"}]
      result = Anthropic.chat(messages)

      # Restore key
      if original_key, do: System.put_env("ANTHROPIC_API_KEY", original_key)

      assert {:error, :api_key_required} = result
    end

    @tag :requires_api_key
    test "chat with invalid model" do
      messages = [%{role: "user", content: "test"}]

      assert {:error, _} =
               Anthropic.chat(messages,
                 model: "invalid-model-name",
                 max_tokens: 10
               )
    end

    @tag :requires_api_key
    test "chat with empty messages" do
      assert {:error, _} = Anthropic.chat([])
    end
  end

  describe "Configuration" do
    test "check if configured with API key" do
      if System.get_env("ANTHROPIC_API_KEY") do
        assert Anthropic.configured?()
      else
        refute Anthropic.configured?()
      end
    end

    test "default model" do
      model = Anthropic.default_model()
      assert is_binary(model)
      assert model =~ ~r/claude/
    end
  end

  describe "Token Counting API" do
    @tag :requires_api_key
    test "count tokens for a message" do
      messages = [
        %{role: "user", content: "Count the tokens in this message."}
      ]

      assert {:ok, response} = Anthropic.count_tokens(messages, "claude-3-haiku-20240307")
      assert is_map(response)
      assert Map.has_key?(response, "input_tokens")
      assert response["input_tokens"] > 0
    end

    @tag :requires_api_key
    test "count tokens with system message" do
      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Hello!"}
      ]

      assert {:ok, response} = Anthropic.count_tokens(messages, "claude-3-haiku-20240307")
      assert response["input_tokens"] > 0
    end
  end

  describe "Files API (Beta)" do
    @tag :requires_api_key
    @tag :beta_api
    test "list files (may be empty)" do
      case Anthropic.list_files() do
        {:ok, response} ->
          assert is_map(response)
          assert Map.has_key?(response, "data")
          assert is_list(response["data"])

        {:error, {:api_error, %{status: 403}}} ->
          # Files API may not be available for all accounts
          :skip

        {:error, _} = error ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    @tag :requires_api_key
    @tag :beta_api
    test "create and manage file lifecycle" do
      # Create a test file
      file_content = "This is a test file for Anthropic Files API."
      filename = "test_file.txt"

      case Anthropic.create_file(file_content, filename) do
        {:ok, file_response} ->
          assert is_map(file_response)
          assert Map.has_key?(file_response, "id")
          file_id = file_response["id"]

          # Get file metadata
          {:ok, metadata} = Anthropic.get_file(file_id)
          assert metadata["id"] == file_id
          assert metadata["filename"] == filename

          # Get file content
          {:ok, content} = Anthropic.get_file_content(file_id)
          assert content == file_content

          # Clean up - delete the file
          {:ok, _} = Anthropic.delete_file(file_id)

        {:error, {:api_error, %{status: 403}}} ->
          # Files API may not be available for all accounts
          :skip

        {:error, _} = error ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
  end

  describe "Message Batches API" do
    @tag :requires_api_key
    @tag :batch_api
    test "list message batches (may be empty)" do
      case Anthropic.list_message_batches() do
        {:ok, response} ->
          assert is_map(response)
          assert Map.has_key?(response, "data")
          assert is_list(response["data"])

        {:error, {:api_error, %{status: 403}}} ->
          # Batch API may not be available for all accounts
          :skip

        {:error, _} = error ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    @tag :requires_api_key
    @tag :batch_api
    test "create and manage batch lifecycle" do
      # Create a small batch request
      requests = [
        %{
          custom_id: "request_1",
          model: "claude-3-haiku-20240307",
          messages: [%{role: "user", content: "Say 'batch test 1'"}],
          max_tokens: 10
        },
        %{
          custom_id: "request_2",
          model: "claude-3-haiku-20240307",
          messages: [%{role: "user", content: "Say 'batch test 2'"}],
          max_tokens: 10
        }
      ]

      case Anthropic.create_message_batch(requests) do
        {:ok, batch_response} ->
          assert is_map(batch_response)
          assert Map.has_key?(batch_response, "id")
          batch_id = batch_response["id"]

          # Get batch details
          {:ok, batch_details} = Anthropic.get_message_batch(batch_id)
          assert batch_details["id"] == batch_id

          # Try to get results (may not be ready yet)
          case Anthropic.get_message_batch_results(batch_id) do
            {:ok, _results} -> :ok
            # Expected if not ready
            {:error, _} -> :ok
          end

          # Cancel the batch to clean up
          {:ok, _} = Anthropic.cancel_message_batch(batch_id)

        {:error, {:api_error, %{status: 403}}} ->
          # Batch API may not be available for all accounts
          :skip

        {:error, _} = error ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
  end

  describe "Embeddings API (Not Supported)" do
    test "embeddings returns not supported error" do
      assert {:error, {:embeddings_not_supported, :anthropic}} =
               Anthropic.embeddings(["test"])
    end
  end

  describe "Cache Verification" do
    @tag :requires_api_key
    @tag :cache_test
    test "verify messages API caching by timing" do
      messages = [
        %{role: "user", content: "Say exactly 'CACHE_TEST_MARKER'"}
      ]

      # Make first request and time it
      start1 = System.monotonic_time(:millisecond)
      {:ok, response1} = Anthropic.chat(messages, max_tokens: 20)
      duration1 = System.monotonic_time(:millisecond) - start1

      # Both should return expected content
      assert response1.content =~ "CACHE_TEST_MARKER"

      # Small delay to ensure cache is written
      :timer.sleep(100)

      # Make second identical request and time it
      start2 = System.monotonic_time(:millisecond)
      {:ok, response2} = Anthropic.chat(messages, max_tokens: 20)
      duration2 = System.monotonic_time(:millisecond) - start2

      assert response2.content =~ "CACHE_TEST_MARKER"

      # Second call should be significantly faster if cached
      # Cached responses should be at least 3x faster OR under 5ms (already very fast)
      cache_working = duration2 < duration1 / 3 || duration2 < 5

      assert cache_working,
             "Second call (#{duration2}ms) was not significantly faster than first call (#{duration1}ms)"
    end

    @tag :requires_api_key
    @tag :cache_test
    test "verify models API caching" do
      # Make first request and time it
      start1 = System.monotonic_time(:millisecond)
      {:ok, models1} = Anthropic.list_models()
      duration1 = System.monotonic_time(:millisecond) - start1

      # Small delay to ensure cache is written
      :timer.sleep(100)

      # Make second identical request and time it
      start2 = System.monotonic_time(:millisecond)
      {:ok, models2} = Anthropic.list_models()
      duration2 = System.monotonic_time(:millisecond) - start2

      # Should return identical results if cached
      assert models1 == models2

      # Second call should be significantly faster OR already very fast
      cache_working = duration2 < duration1 / 3 || duration2 < 5

      assert cache_working,
             "Second call (#{duration2}ms) was not significantly faster than first call (#{duration1}ms)"
    end

    @tag :requires_api_key
    @tag :cache_test
    test "verify token counting API caching" do
      messages = [%{role: "user", content: "Cache test for token counting"}]
      model = "claude-3-haiku-20240307"

      # First call
      start1 = System.monotonic_time(:millisecond)
      {:ok, result1} = Anthropic.count_tokens(messages, model)
      duration1 = System.monotonic_time(:millisecond) - start1

      :timer.sleep(100)

      # Second call should be cached
      start2 = System.monotonic_time(:millisecond)
      {:ok, result2} = Anthropic.count_tokens(messages, model)
      duration2 = System.monotonic_time(:millisecond) - start2

      # Results should be identical
      assert result1 == result2

      # Second call should be faster OR already very fast
      cache_working = duration2 < duration1 / 3 || duration2 < 5

      assert cache_working,
             "Second call (#{duration2}ms) was not significantly faster than first call (#{duration1}ms)"
    end

    @tag :requires_api_key
    @tag :cache_test
    @tag :beta_api
    test "verify files API caching" do
      # Test list_files caching
      start1 = System.monotonic_time(:millisecond)
      result1 = Anthropic.list_files()
      duration1 = System.monotonic_time(:millisecond) - start1

      # Skip if Files API not available
      case result1 do
        {:error, {:api_error, %{status: 403}}} ->
          :skip

        {:ok, _} ->
          :timer.sleep(100)

          start2 = System.monotonic_time(:millisecond)
          result2 = Anthropic.list_files()
          duration2 = System.monotonic_time(:millisecond) - start2

          assert result1 == result2
          cache_working = duration2 < duration1 / 3 || duration2 < 5

          assert cache_working,
                 "Second call (#{duration2}ms) was not significantly faster than first call (#{duration1}ms)"
      end
    end

    @tag :requires_api_key
    @tag :cache_test
    @tag :batch_api
    test "verify batch API caching" do
      # Test list_message_batches caching
      start1 = System.monotonic_time(:millisecond)
      result1 = Anthropic.list_message_batches()
      duration1 = System.monotonic_time(:millisecond) - start1

      # Skip if Batch API not available
      case result1 do
        {:error, {:api_error, %{status: 403}}} ->
          :skip

        {:ok, _} ->
          :timer.sleep(100)

          start2 = System.monotonic_time(:millisecond)
          result2 = Anthropic.list_message_batches()
          duration2 = System.monotonic_time(:millisecond) - start2

          assert result1 == result2
          cache_working = duration2 < duration1 / 3 || duration2 < 5

          assert cache_working,
                 "Second call (#{duration2}ms) was not significantly faster than first call (#{duration1}ms)"
      end
    end
  end
end
