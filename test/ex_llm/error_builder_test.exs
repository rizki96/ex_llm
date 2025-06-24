defmodule ExLLM.ErrorBuilderTest do
  use ExUnit.Case, async: true

  alias ExLLM.ErrorBuilder

  describe "http_error/3" do
    test "builds an unauthorized error for status 401" do
      error = ErrorBuilder.http_error(401, %{"detail" => "invalid key"}, :openai)

      assert error == %{
               error: :unauthorized,
               message: "Authentication failed for openai. Check your API key.",
               status: 401,
               body: %{"detail" => "invalid key"},
               provider: :openai
             }
    end

    test "builds a forbidden error for status 403" do
      error = ErrorBuilder.http_error(403, %{"detail" => "no access"}, :anthropic)

      assert error == %{
               error: :forbidden,
               message: "Access forbidden for anthropic. Check your permissions.",
               status: 403,
               body: %{"detail" => "no access"},
               provider: :anthropic
             }
    end

    test "builds a not_found error for status 404" do
      error = ErrorBuilder.http_error(404, "Not Found", :openai)

      assert error == %{
               error: :not_found,
               message: "Endpoint not found for openai. The API may have changed.",
               status: 404,
               provider: :openai
             }
    end

    test "builds a rate_limited error for status 429" do
      error = ErrorBuilder.http_error(429, %{"message" => "rate limited"}, :groq)
      assert error.error == :rate_limited
      assert error.status == 429
    end

    test "builds a server_error for status 500" do
      error = ErrorBuilder.http_error(500, "Internal Server Error", :mistral)
      assert error.error == :server_error
      assert error.status == 500
    end

    test "builds a connection_error for nil status" do
      error = ErrorBuilder.http_error(nil, "could not connect", :ollama)
      assert error.error == :connection_error
      assert error.status == nil
    end

    test "builds a generic http_error for other statuses" do
      error = ErrorBuilder.http_error(418, "I'm a teapot", :openai)

      assert error == %{
               error: :http_error,
               message: "HTTP error 418 from openai.",
               status: 418,
               body: "I'm a teapot",
               provider: :openai
             }
    end
  end

  describe "network_error/2" do
    test "builds a timeout error" do
      error = ErrorBuilder.network_error(:timeout, :openai)

      assert error == %{
               error: :timeout,
               message: "Request timeout for openai.",
               provider: :openai
             }
    end

    test "builds a connection_refused error" do
      error = ErrorBuilder.network_error(:econnrefused, :ollama)

      assert error == %{
               error: :connection_refused,
               message: "Connection refused for ollama. Is the service running?",
               provider: :ollama
             }
    end

    test "builds a circuit_open error" do
      circuit_error = %{reason: :circuit_open, message: "Circuit is open", retry_after: 1000}
      error = ErrorBuilder.network_error(circuit_error, :openai)

      assert error == %{
               error: :circuit_open,
               message: "Circuit is open",
               provider: :openai,
               retry_after: 1000
             }
    end

    test "builds a generic network_error for other reasons" do
      error = ErrorBuilder.network_error({:nxdomain, "api.openai.com"}, :openai)

      assert error == %{
               error: :network_error,
               message: "Network error for openai: #{inspect({:nxdomain, "api.openai.com"})}",
               reason: {:nxdomain, "api.openai.com"},
               provider: :openai
             }
    end
  end

  describe "authentication_error/1" do
    test "builds a 401 unauthorized error" do
      error = ErrorBuilder.authentication_error(:openai)

      assert error == %{
               error: :unauthorized,
               message: "Authentication failed for openai. Check your API key.",
               status: 401,
               body: nil,
               provider: :openai
             }
    end
  end

  describe "rate_limit_error/2" do
    test "builds a 429 rate_limited error" do
      error = ErrorBuilder.rate_limit_error(%{}, :openai)

      assert error.error == :rate_limited
      assert error.status == 429
      assert error.provider == :openai
    end

    test "extracts retry_after from body" do
      assert ErrorBuilder.rate_limit_error(%{"retry_after" => 60}, :openai).retry_after == 60
      assert ErrorBuilder.rate_limit_error(%{"retryAfter" => 30}, :openai).retry_after == 30
      assert ErrorBuilder.rate_limit_error(%{"retry-after" => 10}, :openai).retry_after == 10
      assert ErrorBuilder.rate_limit_error(%{"other_key" => 10}, :openai).retry_after == nil
      assert ErrorBuilder.rate_limit_error("not a map", :openai).retry_after == nil
    end
  end

  describe "server_error/2" do
    test "builds a 500 server error" do
      error = ErrorBuilder.server_error("server exploded", :openai)

      assert error == %{
               error: :server_error,
               message: "Internal server error from openai.",
               status: 500,
               body: "server exploded",
               provider: :openai
             }
    end
  end

  describe "connection_error/2" do
    test "builds a connection error with nil status" do
      error = ErrorBuilder.connection_error("no response", :openai)

      assert error == %{
               error: :connection_error,
               message: "Connection error to openai. No HTTP status received.",
               status: nil,
               body: "no response",
               provider: :openai
             }
    end
  end
end
