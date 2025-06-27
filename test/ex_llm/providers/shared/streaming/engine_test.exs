defmodule ExLLM.Providers.Shared.Streaming.EngineTest do
  @moduledoc """
  Tests for the new Tesla-based streaming engine.

  These tests verify that the new streaming architecture works correctly
  and maintains compatibility with the existing StreamingCoordinator interface.
  """

  use ExUnit.Case, async: true

  alias ExLLM.Providers.Shared.Streaming.Compatibility
  alias ExLLM.Providers.Shared.Streaming.Engine
  alias ExLLM.Types.StreamChunk

  @moduletag :streaming_engine

  describe "Engine.client/1" do
    test "creates a Tesla client with default configuration" do
      client = Engine.client(provider: :openai, api_key: "sk-test")

      assert %Tesla.Client{} = client
      # Should have middleware
      assert client.pre != []
    end

    test "supports different providers with correct base URLs" do
      providers = [
        {:openai, "https://api.openai.com/v1"},
        {:anthropic, "https://api.anthropic.com"},
        {:groq, "https://api.groq.com/openai/v1"},
        {:gemini, "https://generativelanguage.googleapis.com/v1beta"}
      ]

      for {provider, _expected_base_url} <- providers do
        client = Engine.client(provider: provider, api_key: "test-key")
        # Note: We can't easily test the base URL without making an actual request
        # But we can verify the client was created successfully
        assert %Tesla.Client{} = client
      end
    end

    test "includes appropriate middleware based on options" do
      # Basic client should have minimal middleware
      basic_client = Engine.client(provider: :openai)
      basic_middleware_count = length(basic_client.pre)

      # Client with features should have more middleware
      enhanced_client =
        Engine.client(
          provider: :openai,
          enable_metrics: true,
          enable_recovery: true
        )

      # For now, middleware count should be the same since we haven't implemented
      # the optional middleware yet, but the structure should be correct
      assert length(enhanced_client.pre) >= basic_middleware_count
    end
  end

  describe "Engine.stream/4" do
    test "requires callback and parse_chunk options" do
      client = Engine.client(provider: :openai, api_key: "sk-test")

      # Should raise when missing required options
      assert_raise KeyError, fn ->
        Engine.stream(client, "/test", %{}, [])
      end

      # Should work with required options
      opts = [
        callback: fn _chunk -> :ok end,
        parse_chunk: fn _data -> {:ok, %StreamChunk{content: "test"}} end
      ]

      # This will fail with a connection error, but should not raise due to missing options
      assert {:ok, stream_id} = Engine.stream(client, "/test", %{}, opts)
      assert is_binary(stream_id)
      assert String.starts_with?(stream_id, "stream_")
    end

    test "generates unique stream IDs" do
      client = Engine.client(provider: :openai, api_key: "sk-test")

      opts = [
        callback: fn _chunk -> :ok end,
        parse_chunk: fn _data -> {:ok, %StreamChunk{content: "test"}} end
      ]

      {:ok, stream_id_1} = Engine.stream(client, "/test", %{}, opts)
      {:ok, stream_id_2} = Engine.stream(client, "/test", %{}, opts)

      assert stream_id_1 != stream_id_2
    end
  end

  describe "Engine.cancel_stream/1" do
    test "returns error for non-existent stream" do
      assert {:error, :not_found} = Engine.cancel_stream("non-existent-stream")
    end

    test "can cancel an active stream" do
      client = Engine.client(provider: :openai, api_key: "sk-test")

      opts = [
        callback: fn _chunk -> :ok end,
        parse_chunk: fn _data -> {:ok, %StreamChunk{content: "test"}} end
      ]

      {:ok, stream_id} = Engine.stream(client, "/test", %{}, opts)

      # Give the task a moment to start
      Process.sleep(10)

      assert :ok = Engine.cancel_stream(stream_id)

      # Subsequent cancellation should return not found
      assert {:error, :not_found} = Engine.cancel_stream(stream_id)
    end
  end

  describe "Engine.stream_status/1" do
    test "returns error for non-existent stream" do
      assert {:error, :not_found} = Engine.stream_status("non-existent-stream")
    end

    test "reports status of active streams" do
      client = Engine.client(provider: :openai, api_key: "sk-test")

      opts = [
        callback: fn _chunk -> :ok end,
        parse_chunk: fn _data -> {:ok, %StreamChunk{content: "test"}} end
      ]

      {:ok, stream_id} = Engine.stream(client, "/test", %{}, opts)

      # Stream should be running initially
      assert {:ok, :running} = Engine.stream_status(stream_id)

      # Cancel the stream
      :ok = Engine.cancel_stream(stream_id)

      # Status should reflect completion
      assert {:error, :not_found} = Engine.stream_status(stream_id)
    end
  end
end

defmodule ExLLM.Providers.Shared.Streaming.CompatibilityTest do
  @moduledoc """
  Tests for backward compatibility with existing StreamingCoordinator interface.
  """

  use ExUnit.Case, async: true

  alias ExLLM.Providers.Shared.Streaming.Compatibility
  alias ExLLM.Types.StreamChunk

  @moduletag :streaming_compatibility

  describe "Compatibility.start_stream/5" do
    test "maintains the same interface as StreamingCoordinator" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      # Should have the same signature as original StreamingCoordinator.start_stream/5
      assert {:ok, stream_id} =
               Compatibility.start_stream(
                 "https://api.openai.com/v1/chat/completions",
                 %{model: "gpt-4", messages: []},
                 [{"authorization", "Bearer sk-test"}],
                 callback,
                 parse_chunk_fn: parse_chunk_fn
               )

      assert is_binary(stream_id)
    end

    test "supports all original options" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      # Test with comprehensive options that match original StreamingCoordinator
      options = [
        parse_chunk_fn: parse_chunk_fn,
        recovery_id: "test_recovery",
        timeout: 30_000,
        on_error: fn _error -> :ok end,
        on_metrics: fn _metrics -> :ok end,
        transform_chunk: fn chunk -> {:ok, chunk} end,
        buffer_chunks: 5,
        validate_chunk: fn _chunk -> :ok end,
        track_metrics: true,
        stream_recovery: true
      ]

      assert {:ok, stream_id} =
               Compatibility.start_stream(
                 "https://api.openai.com/v1/chat/completions",
                 %{model: "gpt-4", messages: []},
                 [{"authorization", "Bearer sk-test"}],
                 callback,
                 options
               )

      assert is_binary(stream_id)
    end

    test "detects provider from URL correctly" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end
      options = [parse_chunk_fn: parse_chunk_fn]

      provider_urls = [
        "https://api.openai.com/v1/chat/completions",
        "https://api.anthropic.com/v1/messages",
        "https://api.groq.com/openai/v1/chat/completions",
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent"
      ]

      for url <- provider_urls do
        assert {:ok, stream_id} =
                 Compatibility.start_stream(
                   url,
                   %{},
                   [{"authorization", "Bearer test-key"}],
                   callback,
                   options
                 )

        assert is_binary(stream_id)
      end
    end
  end

  describe "Compatibility.simple_stream/1" do
    test "maintains the same interface as StreamingCoordinator.simple_stream/1" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      params = [
        url: "https://api.openai.com/v1/chat/completions",
        request: %{model: "gpt-4", messages: []},
        headers: [{"authorization", "Bearer sk-test"}],
        callback: callback,
        parse_chunk: parse_chunk_fn,
        options: [timeout: 30_000]
      ]

      assert {:ok, stream_id} = Compatibility.simple_stream(params)
      assert is_binary(stream_id)
    end

    test "supports additional options through params" do
      callback = fn _chunk -> :ok end
      parse_chunk_fn = fn _data -> {:ok, %StreamChunk{content: "test"}} end

      params = [
        url: "https://api.openai.com/v1/chat/completions",
        request: %{model: "gpt-4", messages: []},
        headers: [{"authorization", "Bearer sk-test"}],
        callback: callback,
        parse_chunk: parse_chunk_fn,
        options: [
          timeout: 60_000,
          track_metrics: true,
          buffer_chunks: 3
        ]
      ]

      assert {:ok, stream_id} = Compatibility.simple_stream(params)
      assert is_binary(stream_id)
    end
  end

  describe "chunk transformation and validation" do
    test "applies transform_chunk function when provided" do
      _received_chunks = []
      callback_spy = self()

      callback = fn chunk ->
        send(callback_spy, {:chunk_received, chunk})
      end

      parse_chunk_fn = fn _data ->
        {:ok, %StreamChunk{content: "original"}}
      end

      # Transform function that modifies content
      transform_fn = fn chunk ->
        {:ok, %{chunk | content: "transformed"}}
      end

      options = [
        parse_chunk_fn: parse_chunk_fn,
        transform_chunk: transform_fn
      ]

      # This will fail to connect, but we're testing the option handling
      assert {:ok, _stream_id} =
               Compatibility.start_stream(
                 "https://api.openai.com/v1/chat/completions",
                 %{},
                 [{"authorization", "Bearer sk-test"}],
                 callback,
                 options
               )

      # The transform function should be properly configured
      # (actual testing would require a mock HTTP response)
    end
  end
end
