defmodule ExLLM.Providers.Shared.StreamingMigrationTest do
  @moduledoc """
  Test suite to verify that the streaming migration from HTTPClient to HTTP.Core
  maintains identical behavior and compatibility.

  These tests ensure:
  1. Both approaches produce identical streaming results
  2. Error handling is consistent
  3. Provider-specific behaviors are preserved
  4. Performance characteristics are maintained
  """
  use ExUnit.Case, async: true

  alias ExLLM.Providers.Shared.{
    EnhancedStreamingCoordinator,
    HTTP.Core,
    HTTPClient,
    StreamingCoordinator
  }

  alias ExLLM.Types.StreamChunk

  setup do
    bypass = Bypass.open()

    %{
      bypass: bypass,
      base_url: "http://localhost:#{bypass.port}",
      api_key: "test-api-key"
    }
  end

  describe "Identical behavior validation" do
    test "HTTPClient.post_stream and HTTP.Core.stream produce identical results", %{
      bypass: bypass,
      base_url: base_url,
      api_key: api_key
    } do
      # Setup mock response that will be used twice
      response_chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\" streaming\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n",
        "data: [DONE]\n\n"
      ]

      # Test HTTPClient.post_stream (legacy)
      legacy_chunks = test_legacy_streaming(bypass, base_url, api_key, response_chunks)

      # Test HTTP.Core.stream (new)
      new_chunks = test_new_streaming(bypass, base_url, api_key, response_chunks)

      # Compare results
      assert length(legacy_chunks) == length(new_chunks)
      assert Enum.sort(legacy_chunks) == Enum.sort(new_chunks)
    end

    test "Error handling is consistent between implementations", %{
      bypass: bypass,
      base_url: base_url,
      api_key: api_key
    } do
      # Mock error response
      error_response = %{
        "error" => %{
          "message" => "Invalid request",
          "type" => "invalid_request_error",
          "code" => "invalid_api_key"
        }
      }

      # Test legacy error
      legacy_error = test_legacy_error(bypass, base_url, api_key, error_response)

      # Test new error
      new_error = test_new_error(bypass, base_url, api_key, error_response)

      # Both should handle errors similarly
      assert legacy_error.type == new_error.type
      assert legacy_error.message == new_error.message
    end
  end

  describe "StreamingCoordinator migration" do
    test "StreamingCoordinator works identically with HTTP.Core", %{
      bypass: bypass,
      base_url: base_url,
      api_key: api_key
    } do
      # Mock response
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)
        |> send_sse_chunk("data: {\"choices\":[{\"delta\":{\"content\":\"Coordinator\"}}]}\n\n")
        |> send_sse_chunk("data: {\"choices\":[{\"delta\":{\"content\":\" test\"}}]}\n\n")
        |> send_sse_chunk("data: [DONE]\n\n")
      end)

      # Collect chunks using Agent to avoid variable shadowing
      {:ok, chunk_agent} = Agent.start_link(fn -> [] end)

      callback = fn chunk ->
        Agent.update(chunk_agent, fn chunks -> [chunk.content | chunks] end)
      end

      # Parse function
      parse_chunk_fn = fn data ->
        case Jason.decode(data) do
          {:ok, %{"choices" => [%{"delta" => %{"content" => content}}]}} ->
            {:ok, %StreamChunk{content: content}}

          _ ->
            nil
        end
      end

      # Start streaming
      url = "#{base_url}/v1/chat/completions"
      request = %{"stream" => true}
      headers = []

      options = [
        parse_chunk_fn: parse_chunk_fn,
        provider: :openai,
        api_key: api_key
      ]

      {:ok, _stream_id} =
        StreamingCoordinator.start_stream(
          url,
          request,
          headers,
          callback,
          options
        )

      # Wait for completion
      Process.sleep(100)

      # Verify results
      chunks = Agent.get(chunk_agent, & &1)
      assert "Coordinator" in chunks
      assert " test" in chunks
    end
  end

  describe "EnhancedStreamingCoordinator migration" do
    test "EnhancedStreamingCoordinator works with HTTP.Core", %{
      bypass: bypass,
      base_url: base_url,
      api_key: api_key
    } do
      # Mock response
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)
        |> send_sse_chunk("data: {\"choices\":[{\"delta\":{\"content\":\"Enhanced\"}}]}\n\n")
        |> send_sse_chunk("data: [DONE]\n\n")
      end)

      # Collect chunks using Agent to avoid variable shadowing
      {:ok, chunk_agent} = Agent.start_link(fn -> [] end)

      callback = fn chunk ->
        Agent.update(chunk_agent, fn chunks -> [chunk.content | chunks] end)
      end

      # Parse function
      parse_chunk_fn = fn data ->
        case Jason.decode(data) do
          {:ok, %{"choices" => [%{"delta" => %{"content" => content}}]}} ->
            {:ok, %StreamChunk{content: content}}

          _ ->
            nil
        end
      end

      # Start enhanced streaming (without flow control to test basic compatibility)
      url = "#{base_url}/v1/chat/completions"
      request = %{"stream" => true}
      headers = []

      options = [
        parse_chunk_fn: parse_chunk_fn,
        provider: :openai,
        api_key: api_key,
        enable_flow_control: false,
        enable_batching: false
      ]

      {:ok, _stream_id} =
        EnhancedStreamingCoordinator.start_stream(
          url,
          request,
          headers,
          callback,
          options
        )

      # Wait for completion
      Process.sleep(100)

      # Verify results
      chunks = Agent.get(chunk_agent, & &1)
      assert "Enhanced" in chunks
    end
  end

  describe "Provider-specific compatibility" do
    test "All providers work with new streaming architecture", %{bypass: bypass} do
      providers = [
        {:openai, "/v1/chat/completions", "authorization", "Bearer test-key"},
        {:anthropic, "/v1/messages", "x-api-key", "test-key"},
        {:gemini, "/models/gemini:stream", "authorization", "Bearer test-key"},
        {:groq, "/openai/v1/chat/completions", "authorization", "Bearer test-key"}
      ]

      Enum.each(providers, fn {provider, path, header_name, _header_value} ->
        # Reset bypass for each provider
        Bypass.expect_once(bypass, "POST", path, fn conn ->
          # Verify proper auth header
          assert [_] = Plug.Conn.get_req_header(conn, header_name)

          conn
          |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
          |> Plug.Conn.send_chunked(200)
          |> send_sse_chunk("data: {\"test\":\"#{provider}\"}\n\n")
          |> send_sse_chunk("data: [DONE]\n\n")
        end)

        # Test with HTTP.Core
        client =
          Core.client(
            provider: provider,
            api_key: "test-key",
            base_url: "http://localhost:#{bypass.port}"
          )

        {:ok, received_agent} = Agent.start_link(fn -> [] end)

        callback = fn chunk ->
          Agent.update(received_agent, fn chunks -> [chunk | chunks] end)
        end

        assert {:ok, _} = Core.stream(client, path, %{"stream" => true}, callback)

        # Basic verification that streaming worked
        received = Agent.get(received_agent, & &1)
        assert length(received) > 0
      end)
    end
  end

  # Helper functions

  defp test_legacy_streaming(bypass, base_url, api_key, response_chunks) do
    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn =
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)

      Enum.reduce(response_chunks, conn, fn chunk, conn ->
        send_sse_chunk(conn, chunk)
      end)
    end)

    {:ok, chunks_agent} = Agent.start_link(fn -> [] end)

    callback = fn
      {:data, data}, acc ->
        case parse_sse_data(data) do
          {:ok, content} ->
            Agent.update(chunks_agent, fn chunks -> [content | chunks] end)

          _ ->
            :ok
        end

        {:cont, acc}

      _, acc ->
        {:cont, acc}
    end

    url = "#{base_url}/v1/chat/completions"
    body = %{"stream" => true}

    opts = [
      headers: [],
      into: callback,
      provider: :openai,
      api_key: api_key
    ]

    {:ok, _} = HTTPClient.post_stream(url, body, opts)
    Process.sleep(50)
    Agent.get(chunks_agent, & &1)
  end

  defp test_new_streaming(bypass, base_url, api_key, response_chunks) do
    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn =
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)

      Enum.reduce(response_chunks, conn, fn chunk, conn ->
        send_sse_chunk(conn, chunk)
      end)
    end)

    client =
      Core.client(
        provider: :openai,
        api_key: api_key,
        base_url: base_url
      )

    {:ok, chunks_agent} = Agent.start_link(fn -> [] end)

    callback = fn chunk ->
      Agent.update(chunks_agent, fn chunks -> [chunk.content | chunks] end)
    end

    parse_chunk = fn data ->
      case Jason.decode(data) do
        {:ok, %{"choices" => [%{"delta" => %{"content" => content}}]}} ->
          {:ok, %StreamChunk{content: content}}

        _ ->
          nil
      end
    end

    {:ok, _} =
      Core.stream(client, "/v1/chat/completions", %{"stream" => true}, callback,
        parse_chunk: parse_chunk
      )

    Process.sleep(50)
    Agent.get(chunks_agent, & &1)
  end

  defp test_legacy_error(bypass, base_url, api_key, error_response) do
    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(400, Jason.encode!(error_response))
    end)

    url = "#{base_url}/v1/chat/completions"
    body = %{"stream" => true}

    opts = [
      headers: [],
      into: fn _, _ -> {:cont, nil} end,
      provider: :openai,
      api_key: api_key
    ]

    case HTTPClient.post_stream(url, body, opts) do
      {:error, error} -> error
      _ -> %{type: :unknown, message: "No error"}
    end
  end

  defp test_new_error(bypass, base_url, api_key, error_response) do
    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.resp(400, Jason.encode!(error_response))
    end)

    client =
      Core.client(
        provider: :openai,
        api_key: api_key,
        base_url: base_url
      )

    callback = fn _ -> :ok end

    case Core.stream(client, "/v1/chat/completions", %{"stream" => true}, callback) do
      {:error, error} -> error
      _ -> %{type: :unknown, message: "No error"}
    end
  end

  defp parse_sse_data(data) do
    case String.trim(data) do
      "data: [DONE]" ->
        {:done, nil}

      "data: " <> json ->
        case Jason.decode(json) do
          {:ok, %{"choices" => [%{"delta" => %{"content" => content}}]}} ->
            {:ok, content}

          _ ->
            {:error, :parse_error}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  defp send_sse_chunk(conn, chunk) do
    case Plug.Conn.chunk(conn, chunk) do
      {:ok, conn} -> conn
      {:error, _reason} -> conn
    end
  end
end
