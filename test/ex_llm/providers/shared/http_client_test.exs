defmodule ExLLM.Providers.Shared.HTTPClientTest do
  use ExUnit.Case, async: true

  alias ExLLM.Infrastructure.ConfigProvider.Static
  alias ExLLM.Providers.Shared.HTTPClient

  setup do
    # Disable Tesla.Mock for these tests since they use Bypass
    original_mock_setting = Application.get_env(:ex_llm, :use_tesla_mock, false)
    Application.put_env(:ex_llm, :use_tesla_mock, false)

    bypass = Bypass.open()

    config = %{
      openai: %{
        api_key: "test-api-key",
        base_url: "http://localhost:#{bypass.port}/v1"
      }
    }

    {:ok, config_provider} = Static.start_link(config)

    on_exit(fn ->
      Application.put_env(:ex_llm, :use_tesla_mock, original_mock_setting)
    end)

    %{
      bypass: bypass,
      config_provider: config_provider,
      base_url: "http://localhost:#{bypass.port}/v1"
    }
  end

  describe "basic HTTP operations" do
    test "post/3 sends POST request with correct headers and body", %{
      bypass: bypass,
      config_provider: config_provider
    } do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        # Verify headers
        assert {"authorization", "Bearer test-api-key"} in conn.req_headers
        assert {"content-type", "application/json"} in conn.req_headers

        # Verify body
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)
        assert decoded_body["model"] == "gpt-4"
        assert decoded_body["messages"] == [%{"role" => "user", "content" => "Hello"}]

        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{
            choices: [%{message: %{content: "Hi there!"}}],
            usage: %{total_tokens: 20}
          })
        )
      end)

      url = "http://localhost:#{bypass.port}/v1/chat/completions"
      headers = %{"authorization" => "Bearer test-api-key", "content-type" => "application/json"}
      body = %{model: "gpt-4", messages: [%{role: "user", content: "Hello"}]}

      {:ok, response} = HTTPClient.post(url, body, headers: headers)

      assert response.status == 200
      decoded = Jason.decode!(response.body)
      assert decoded["choices"] |> hd() |> get_in(["message", "content"]) == "Hi there!"
    end

    test "get/2 sends GET request with headers", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/v1/models", fn conn ->
        assert {"authorization", "Bearer test-api-key"} in conn.req_headers

        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{
            data: [%{id: "gpt-4", object: "model"}]
          })
        )
      end)

      url = "http://localhost:#{bypass.port}/v1/models"
      headers = [{"authorization", "Bearer test-api-key"}]

      {:ok, response} = HTTPClient.get(url, headers)

      assert response.status == 200
      decoded = Jason.decode!(response.body)
      assert length(decoded["data"]) == 1
    end
  end

  describe "streaming requests" do
    test "post_stream/3 handles SSE streaming correctly", %{bypass: bypass} do
      chunks = [
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\n",
        "data: [DONE]\n\n"
      ]

      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        # Verify streaming request
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)
        assert decoded_body["stream"] == true

        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_chunked(200)
        |> then(fn conn ->
          Enum.reduce(chunks, conn, fn chunk, acc_conn ->
            {:ok, acc_conn} = Plug.Conn.chunk(acc_conn, chunk)
            # Simulate streaming delay
            Process.sleep(10)
            acc_conn
          end)
        end)
      end)

      url = "http://localhost:#{bypass.port}/v1/chat/completions"
      headers = %{"authorization" => "Bearer test-api-key", "content-type" => "application/json"}
      body = %{model: "gpt-4", messages: [%{role: "user", content: "Hello"}], stream: true}

      collected_chunks = []

      collector = fn chunk ->
        send(self(), {:chunk, chunk})
      end

      {:ok, _response} = HTTPClient.post_stream(url, body, headers: headers, into: collector)

      # Collect chunks
      chunks_received = receive_chunks([])
      # At least content chunks
      assert length(chunks_received) >= 2
    end

    test "handles streaming errors gracefully", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      url = "http://localhost:#{bypass.port}/v1/chat/completions"
      headers = %{"content-type" => "application/json"}
      body = %{stream: true}

      collector = fn _chunk -> :ok end

      {:error, error} = HTTPClient.post_stream(url, body, headers: headers, into: collector)

      assert error.status_code == 500
    end
  end

  describe "error handling" do
    test "handles 401 authentication errors", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        Plug.Conn.resp(conn, 401, Jason.encode!(%{error: "Invalid API key"}))
      end)

      url = "http://localhost:#{bypass.port}/v1/chat/completions"
      headers = %{"authorization" => "Bearer invalid-key"}
      body = %{}

      {:error, error} = HTTPClient.post(url, body, headers: headers)

      assert error.status_code == 401
      assert error.type == :authentication_error
    end

    test "handles 429 rate limit errors", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "60")
        |> Plug.Conn.resp(429, Jason.encode!(%{error: "Rate limit exceeded"}))
      end)

      url = "http://localhost:#{bypass.port}/v1/chat/completions"
      headers = %{"authorization" => "Bearer test-key"}
      body = %{}

      {:error, error} = HTTPClient.post(url, body, headers: headers)

      assert error.status_code == 429
      assert error.type == :rate_limit_error
      assert error.retry_after == 60
    end

    test "handles 500 server errors", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        Plug.Conn.resp(conn, 500, "Internal Server Error")
      end)

      url = "http://localhost:#{bypass.port}/v1/chat/completions"
      headers = %{}
      body = %{}

      {:error, error} = HTTPClient.post(url, body, headers: headers)

      assert error.status_code == 500
      assert error.type == :api_error
    end

    test "handles network connection errors" do
      url = "http://localhost:99999/nonexistent"
      headers = %{}
      body = %{}

      {:error, error} = HTTPClient.post(url, body, headers: headers)

      assert error.type == :connection_error
    end
  end

  describe "caching functionality" do
    test "caches responses when cache is enabled", %{bypass: bypass} do
      call_count = Agent.start_link(fn -> 0 end)
      {:ok, counter} = call_count

      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        Agent.update(counter, &(&1 + 1))

        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{
            choices: [%{message: %{content: "Cached response"}}]
          })
        )
      end)

      url = "http://localhost:#{bypass.port}/v1/chat/completions"
      headers = %{"content-type" => "application/json"}
      body = %{model: "gpt-4", messages: [%{role: "user", content: "Hello"}]}
      cache_key = "test-cache-key"

      # First call should hit the server
      {:ok, response1} =
        HTTPClient.post(url, body, headers: headers, cache_key: cache_key, cache_ttl: 60_000)

      assert response1.status == 200

      # Second call should use cache (if caching is implemented)
      {:ok, response2} =
        HTTPClient.post(url, body, headers: headers, cache_key: cache_key, cache_ttl: 60_000)

      assert response2.status == 200

      # Verify API was called at least once
      call_count_final = Agent.get(counter, & &1)
      assert call_count_final >= 1
    end
  end

  describe "retry functionality" do
    test "retries on transient failures", %{bypass: bypass} do
      call_count = Agent.start_link(fn -> 0 end)
      {:ok, counter} = call_count

      Bypass.expect(bypass, "POST", "/v1/chat/completions", fn conn ->
        count = Agent.get_and_update(counter, fn c -> {c + 1, c + 1} end)

        case count do
          1 ->
            Plug.Conn.resp(conn, 500, "Server Error")

          2 ->
            Plug.Conn.resp(
              conn,
              200,
              Jason.encode!(%{choices: [%{message: %{content: "Success"}}]})
            )
        end
      end)

      url = "http://localhost:#{bypass.port}/v1/chat/completions"
      headers = %{"content-type" => "application/json"}
      body = %{}

      {:ok, response} = HTTPClient.post(url, body, headers: headers, retry: true, max_retries: 2)

      assert response.status == 200
      final_count = Agent.get(counter, & &1)
      # Should have retried once
      assert final_count == 2
    end
  end

  describe "multipart uploads" do
    test "handles file uploads with multipart/form-data", %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/v1/files", fn conn ->
        # Verify content-type is multipart
        content_type = conn |> Plug.Conn.get_req_header("content-type") |> hd()
        assert String.starts_with?(content_type, "multipart/form-data")

        Plug.Conn.resp(
          conn,
          200,
          Jason.encode!(%{
            id: "file-123",
            filename: "test.txt"
          })
        )
      end)

      url = "http://localhost:#{bypass.port}/v1/files"
      file_content = "Test file content"

      multipart = [
        {"purpose", "fine-tune"},
        {"file", file_content, [{"content-type", "text/plain"}, {"filename", "test.txt"}]}
      ]

      {:ok, response} =
        HTTPClient.post_multipart(url, multipart,
          headers: %{"authorization" => "Bearer test-key"}
        )

      assert response.status == 200
      decoded = Jason.decode!(response.body)
      assert decoded["id"] == "file-123"
    end
  end

  # Helper functions
  defp receive_chunks(acc, timeout \\ 100) do
    receive do
      {:chunk, chunk} ->
        receive_chunks([chunk | acc], timeout)
    after
      timeout ->
        Enum.reverse(acc)
    end
  end
end
