defmodule ExLLM.Providers.Shared.HTTPCoreStreamingTest do
  @moduledoc """
  Comprehensive test suite for HTTP.Core streaming migration.

  Tests that the new HTTP.Core.stream implementation maintains
  compatibility and behavior with the legacy HTTPClient.post_stream.
  """
  use ExUnit.Case, async: false

  alias ExLLM.Providers.Shared.{HTTP.Core, HTTPClient, StreamingCoordinator}
  alias ExLLM.Types.StreamChunk

  import ExUnit.CaptureLog

  setup do
    bypass = Bypass.open()

    # Base configuration
    %{
      bypass: bypass,
      base_url: "http://localhost:#{bypass.port}",
      api_key: "test-key-123"
    }
  end

  describe "HTTP.Core.stream/5" do
    test "successfully streams SSE responses", %{
      bypass: bypass,
      base_url: base_url,
      api_key: api_key
    } do
      # Mock SSE response
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)
        |> send_sse_chunk("data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n")
        |> send_sse_chunk("data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n")
        |> send_sse_chunk("data: [DONE]\n\n")
      end)

      # Build client
      client =
        Core.client(
          provider: :openai,
          api_key: api_key,
          base_url: base_url
        )

      # Collect chunks
      {:ok, agent} = Agent.start_link(fn -> [] end)

      callback = fn chunk ->
        Agent.update(agent, fn chunks -> [chunk | chunks] end)
      end

      # Stream request
      body = %{
        "model" => "gpt-4",
        "messages" => [%{"role" => "user", "content" => "Hi"}],
        "stream" => true
      }

      assert {:ok, _response} = Core.stream(client, "/v1/chat/completions", body, callback)

      # Wait for streaming to complete
      Process.sleep(100)

      # Verify chunks were received
      chunks = Agent.get(agent, & &1)
      assert length(chunks) >= 2
      assert Enum.any?(chunks, fn c -> c.content == "Hello" end)
      assert Enum.any?(chunks, fn c -> c.content == " world" end)
    end

    test "handles authentication headers correctly", %{
      bypass: bypass,
      base_url: base_url,
      api_key: api_key
    } do
      # Verify auth header is sent
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        assert ["Bearer " <> ^api_key] = Plug.Conn.get_req_header(conn, "authorization")

        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)
        |> send_sse_chunk("data: [DONE]\n\n")
      end)

      client =
        Core.client(
          provider: :openai,
          api_key: api_key,
          base_url: base_url
        )

      callback = fn _chunk -> :ok end
      body = %{"stream" => true}

      assert {:ok, _} = Core.stream(client, "/v1/chat/completions", body, callback)
    end

    test "handles errors gracefully", %{bypass: bypass, base_url: base_url, api_key: api_key} do
      # Mock error response
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(
          429,
          Jason.encode!(%{
            "error" => %{
              "message" => "Rate limit exceeded",
              "type" => "rate_limit_error"
            }
          })
        )
      end)

      client =
        Core.client(
          provider: :openai,
          api_key: api_key,
          base_url: base_url
        )

      callback = fn _chunk -> :ok end
      body = %{"stream" => true}

      assert {:error, error} = Core.stream(client, "/v1/chat/completions", body, callback)
      assert error.type == :rate_limit_error
    end
  end

  describe "StreamingCoordinator with HTTP.Core" do
    test "StreamingCoordinator now uses HTTP.Core directly", %{
      bypass: bypass,
      base_url: base_url,
      api_key: api_key
    } do
      # Mock SSE response
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)
        |> send_sse_chunk("data: {\"choices\":[{\"delta\":{\"content\":\"Test\"}}]}\n\n")
        |> send_sse_chunk("data: [DONE]\n\n")
      end)

      # Collect chunks
      {:ok, agent} = Agent.start_link(fn -> [] end)

      callback = fn chunk ->
        Agent.update(agent, fn chunks -> [chunk | chunks] end)
      end

      # Use StreamingCoordinator
      url = "#{base_url}/v1/chat/completions"

      request = %{
        "model" => "gpt-4",
        "messages" => [%{"role" => "user", "content" => "Hi"}],
        "stream" => true
      }

      headers = []

      parse_chunk_fn = fn data ->
        case Jason.decode(data) do
          {:ok, %{"choices" => [%{"delta" => %{"content" => content}}]}} ->
            {:ok, %StreamChunk{content: content}}

          _ ->
            nil
        end
      end

      options = [
        parse_chunk_fn: parse_chunk_fn,
        provider: :openai,
        api_key: api_key
      ]

      {:ok, _stream_id} =
        StreamingCoordinator.start_stream(url, request, headers, callback, options)

      # Wait for streaming to complete
      Process.sleep(100)

      # Get chunks from agent and verify
      chunks = Agent.get(agent, & &1)
      assert length(chunks) >= 1
      assert Enum.any?(chunks, fn c -> c.content == "Test" end)
    end
  end

  describe "HTTPClient.post_stream compatibility" do
    test "HTTPClient.post_stream still works as compatibility layer", %{
      bypass: bypass,
      base_url: base_url,
      api_key: api_key
    } do
      # Mock SSE response
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)
        |> send_sse_chunk("data: {\"choices\":[{\"delta\":{\"content\":\"Legacy\"}}]}\n\n")
        |> send_sse_chunk("data: [DONE]\n\n")
      end)

      # Collect chunks using Agent to avoid variable shadowing
      {:ok, chunk_agent} = Agent.start_link(fn -> [] end)

      callback = fn {:data, data}, acc ->
        case data do
          "data: " <> json ->
            case Jason.decode(json) do
              {:ok, %{"choices" => [%{"delta" => %{"content" => content}}]}} ->
                Agent.update(chunk_agent, fn chunks -> [content | chunks] end)

              _ ->
                :ok
            end

          _ ->
            :ok
        end

        {:cont, acc}
      end

      url = "#{base_url}/v1/chat/completions"

      body = %{
        "model" => "gpt-4",
        "messages" => [%{"role" => "user", "content" => "Hi"}],
        "stream" => true
      }

      opts = [
        headers: [],
        into: callback,
        provider: :openai,
        api_key: api_key
      ]

      # Should log deprecation warning
      _log =
        capture_log(fn ->
          assert {:ok, _} = HTTPClient.post_stream(url, body, opts)
        end)

      # Note: @deprecated doesn't produce runtime logs, only compile-time warnings
      # So we won't see deprecation in logs here

      # Wait for streaming
      Process.sleep(100)

      # Verify chunks were received
      chunks = Agent.get(chunk_agent, & &1)
      assert "Legacy" in chunks
    end
  end

  describe "Provider-specific streaming" do
    test "Anthropic streaming with HTTP.Core", %{bypass: bypass, base_url: base_url} do
      api_key = "anthropic-key"

      # Mock Anthropic SSE response
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        assert ["anthropic-key"] = Plug.Conn.get_req_header(conn, "x-api-key")

        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)
        |> send_sse_chunk(
          "data: {\"type\":\"content_block_delta\",\"delta\":{\"text\":\"Claude\"}}\n\n"
        )
        |> send_sse_chunk("data: {\"type\":\"message_stop\"}\n\n")
      end)

      client =
        Core.client(
          provider: :anthropic,
          api_key: api_key,
          base_url: base_url
        )

      {:ok, chunk_agent} = Agent.start_link(fn -> [] end)

      callback = fn chunk ->
        Agent.update(chunk_agent, fn chunks -> [chunk | chunks] end)
      end

      body = %{
        "model" => "claude-3",
        "messages" => [%{"role" => "user", "content" => "Hi"}],
        "stream" => true
      }

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
            {:ok, %StreamChunk{content: text}}

          _ ->
            nil
        end
      end

      assert {:ok, _} =
               Core.stream(client, "/v1/messages", body, callback, parse_chunk: parse_chunk)

      # Wait for streaming to complete
      Process.sleep(100)

      # Verify Anthropic chunk
      chunks = Agent.get(chunk_agent, & &1)
      assert length(chunks) >= 1
      assert Enum.any?(chunks, fn c -> c.content == "Claude" end)
    end

    test "Gemini streaming with HTTP.Core", %{bypass: bypass, base_url: base_url} do
      api_key = "gemini-key"

      # Mock Gemini SSE response
      Bypass.expect_once(bypass, "POST", "/models/gemini-pro:streamGenerateContent", fn conn ->
        assert ["Bearer gemini-key"] = Plug.Conn.get_req_header(conn, "authorization")

        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)
        |> send_sse_chunk(
          "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Gemini\"}]}}]}\n\n"
        )
      end)

      client =
        Core.client(
          provider: :gemini,
          api_key: api_key,
          base_url: base_url
        )

      {:ok, chunk_agent} = Agent.start_link(fn -> [] end)

      callback = fn chunk ->
        Agent.update(chunk_agent, fn chunks -> [chunk | chunks] end)
      end

      body = %{
        "contents" => [%{"parts" => [%{"text" => "Hi"}]}]
      }

      parse_chunk = fn data ->
        case Jason.decode(data) do
          {:ok, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text}]}}]}} ->
            {:ok, %StreamChunk{content: text}}

          _ ->
            nil
        end
      end

      assert {:ok, _} =
               Core.stream(client, "/models/gemini-pro:streamGenerateContent", body, callback,
                 parse_chunk: parse_chunk
               )

      # Wait for streaming to complete
      Process.sleep(100)

      # Verify Gemini chunk
      chunks = Agent.get(chunk_agent, & &1)
      assert length(chunks) >= 1
      assert Enum.any?(chunks, fn c -> c.content == "Gemini" end)
    end
  end

  # Helper functions

  defp send_sse_chunk(conn, chunk) do
    case Plug.Conn.chunk(conn, chunk) do
      {:ok, conn} -> conn
      {:error, _reason} -> conn
    end
  end
end
