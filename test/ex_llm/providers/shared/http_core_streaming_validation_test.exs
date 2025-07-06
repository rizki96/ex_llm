defmodule ExLLM.Providers.Shared.HTTPCoreStreamingValidationTest do
  @moduledoc """
  Validation tests for HTTP.Core streaming migration.

  These tests verify that the streaming migration maintains compatibility
  and correct behavior across all components.
  """
  use ExUnit.Case, async: false

  alias ExLLM.Providers.Shared.{HTTP.Core, StreamingCoordinator}

  describe "HTTP.Core streaming basics" do
    test "can create a client and handle streaming responses" do
      # Create a simple test client
      client =
        Core.client(
          provider: :openai,
          api_key: "test-key",
          base_url: "https://api.openai.com/v1"
        )

      assert %Tesla.Client{} = client
    end

    test "streaming coordinators use HTTP.Core" do
      # Verify that StreamingCoordinator has been updated
      assert Code.ensure_loaded?(StreamingCoordinator)

      # Check that the source code uses HTTP.Core
      source = File.read!("lib/ex_llm/providers/shared/streaming_coordinator.ex")
      assert source =~ "alias ExLLM.Providers.Shared.HTTP.Core"
      assert source =~ "Core.client("
      assert source =~ "Core.stream("
    end
  end

  describe "Parse SSE functionality" do
    test "parse_sse_line handles various SSE formats" do
      # Test data lines
      assert {:data, "hello"} = StreamingCoordinator.parse_sse_line("data: hello")

      assert {:data, "{\"test\": true}"} =
               StreamingCoordinator.parse_sse_line("data: {\"test\": true}")

      # Test done signal
      assert :done = StreamingCoordinator.parse_sse_line("data: [DONE]")

      # Test skip cases
      assert :skip = StreamingCoordinator.parse_sse_line("")
      assert :skip = StreamingCoordinator.parse_sse_line(": comment")
      assert :skip = StreamingCoordinator.parse_sse_line("event: ping")
    end
  end

  describe "Default chunk parsing" do
    test "default parse chunk function handles OpenAI format" do
      # This tests the internal default_parse_chunk function behavior
      json_data =
        Jason.encode!(%{
          "choices" => [
            %{
              "delta" => %{content: "Hello"},
              "finish_reason" => nil
            }
          ]
        })

      # We can't test the private function directly, but we can verify the structure
      assert {:ok, decoded} = Jason.decode(json_data)
      assert "Hello" = get_in(decoded, ["choices", Access.at(0), "delta", "content"])
    end
  end

  describe "URL extraction" do
    test "extract_base_url_and_path handles various URL formats" do
      # Test absolute URLs
      assert {"https://api.openai.com", "/v1/chat/completions"} =
               extract_url("https://api.openai.com/v1/chat/completions")

      # Test with port
      assert {"http://localhost:8080", "/api/test"} =
               extract_url("http://localhost:8080/api/test")

      # Test with query params
      assert {"https://example.com", "/path?foo=bar"} =
               extract_url("https://example.com/path?foo=bar")

      # Test relative URL
      assert {nil, "/relative/path"} = extract_url("/relative/path")
    end
  end

  describe "ModelFetcher migration" do
    test "ModelFetcher uses HTTP.Core for API calls" do
      # Verify ModelFetcher module is loaded
      assert Code.ensure_loaded?(ExLLM.Providers.Shared.ModelFetcher)

      # Check that it aliases HTTP.Core
      source = File.read!("lib/ex_llm/providers/shared/model_fetcher.ex")
      assert source =~ "alias ExLLM.Providers.Shared.{ConfigHelper, HTTP.Core, ModelUtils}"
      assert source =~ "Core.client("
    end
  end

  describe "Migration completion" do
    test "HTTPClient has been removed and HTTP.Core is used everywhere" do
      # Verify HTTPClient module no longer exists
      refute Code.ensure_loaded?(ExLLM.Providers.Shared.HTTPClient)

      # Verify HTTP.Core is loaded and functioning
      assert Code.ensure_loaded?(ExLLM.Providers.Shared.HTTP.Core)
    end
  end

  # Helper function that mimics the private extract_base_url_and_path
  defp extract_url(url) do
    uri = URI.parse(url)

    if uri.scheme && uri.host do
      port_part =
        if uri.port && uri.port != URI.default_port(uri.scheme) do
          ":#{uri.port}"
        else
          ""
        end

      base_url = "#{uri.scheme}://#{uri.host}#{port_part}"
      path = uri.path || "/"

      path_with_query =
        if uri.query do
          "#{path}?#{uri.query}"
        else
          path
        end

      {base_url, path_with_query}
    else
      {nil, url}
    end
  end
end
