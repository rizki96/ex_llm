defmodule ExLLM.PlugTest do
  alias ExLLM.Pipeline.Request

  @moduledoc """
  Testing utilities for ExLLM plugs and pipelines.

  This module provides helpers and utilities for testing ExLLM plugs in isolation
  and testing complete pipelines. It follows the patterns established by Phoenix's
  ConnTest but adapted for ExLLM's pipeline architecture.

  ## Usage

  Add this to your test files:

      use ExLLM.PlugTest
      
  ## Building Test Requests

      # Basic request
      request = build_request()
      
      # With specific provider
      request = build_request(provider: :openai)
      
      # With messages and options
      request = build_request(
        provider: :anthropic,
        messages: [%{role: "user", content: "Hello"}],
        options: %{model: "claude-3-5-sonnet", temperature: 0.7}
      )
      
  ## Assertions

      # Test if request was halted
      assert_halted(request)
      assert_not_halted(request)
      
      # Test request state
      assert_state(request, :completed)
      assert_state(request, :error)
      
      # Test for specific errors
      assert_error(request, :missing_api_key)
      assert_error_message(request, "Invalid model")
      
      # Test assigns and metadata
      assert_assign(request, :temperature, 0.7)
      assert_metadata(request, :http_status, 200)
      
  ## Mock Responses

      # Mock a successful HTTP response
      mock_response = mock_http_response(200, %{
        "choices" => [%{"message" => %{"content" => "Hello!"}}]
      })
      
      # Mock an error response  
      error_response = mock_http_response(401, %{
        "error" => %{"message" => "Invalid API key"}
      })
  """

  defmacro __using__(_opts) do
    quote do
      import ExLLM.PlugTest
      import ExUnit.Assertions

      alias ExLLM.Pipeline.Request

      @doc """
      Builds a test request with default or custom attributes.
      """
      def build_request(attrs \\ %{}) do
        defaults = %{
          provider: :mock,
          messages: [%{role: "user", content: "Test message"}],
          options: %{}
        }

        attrs = Map.merge(defaults, Map.new(attrs))
        Request.new(attrs.provider, attrs.messages, attrs.options)
      end
    end
  end

  @doc """
  Asserts that a request has been halted.
  """
  def assert_halted(%Request{halted: true}), do: :ok

  def assert_halted(%Request{halted: false}) do
    raise ExUnit.AssertionError, message: "Expected request to be halted, but it was not"
  end

  @doc """
  Asserts that a request has not been halted.
  """
  def assert_not_halted(%Request{halted: false}), do: :ok

  def assert_not_halted(%Request{halted: true}) do
    raise ExUnit.AssertionError, message: "Expected request to not be halted, but it was"
  end

  @doc """
  Asserts that a request is in a specific state.
  """
  def assert_state(%Request{state: state}, expected_state) when state == expected_state, do: :ok

  def assert_state(%Request{state: actual_state}, expected_state) do
    raise ExUnit.AssertionError,
      message:
        "Expected request state to be #{inspect(expected_state)}, got #{inspect(actual_state)}"
  end

  @doc """
  Asserts that a request has a specific error type.
  """
  def assert_error(%Request{errors: errors}, error_type) do
    if Enum.any?(errors, &(&1.error == error_type)) do
      :ok
    else
      error_types = Enum.map(errors, & &1.error)

      raise ExUnit.AssertionError,
        message: "Expected error #{inspect(error_type)}, got errors: #{inspect(error_types)}"
    end
  end

  @doc """
  Asserts that a request has an error with a specific message.
  """
  def assert_error_message(%Request{errors: errors}, message) do
    if Enum.any?(errors, &(&1.message == message)) do
      :ok
    else
      messages = Enum.map(errors, & &1.message)

      raise ExUnit.AssertionError,
        message: "Expected error message '#{message}', got messages: #{inspect(messages)}"
    end
  end

  @doc """
  Asserts that a request has no errors.
  """
  def assert_no_errors(%Request{errors: []}), do: :ok

  def assert_no_errors(%Request{errors: errors}) do
    raise ExUnit.AssertionError,
      message: "Expected no errors, got #{length(errors)} error(s): #{inspect(errors)}"
  end

  @doc """
  Asserts that a request has a specific assign value.
  """
  def assert_assign(%Request{assigns: assigns}, key, expected_value) do
    case Map.get(assigns, key) do
      ^expected_value ->
        :ok

      actual_value ->
        raise ExUnit.AssertionError,
          message:
            "Expected assign #{inspect(key)} to be #{inspect(expected_value)}, got #{inspect(actual_value)}"
    end
  end

  @doc """
  Asserts that a request has a specific metadata value.
  """
  def assert_metadata(%Request{metadata: metadata}, key, expected_value) do
    case Map.get(metadata, key) do
      ^expected_value ->
        :ok

      actual_value ->
        raise ExUnit.AssertionError,
          message:
            "Expected metadata #{inspect(key)} to be #{inspect(expected_value)}, got #{inspect(actual_value)}"
    end
  end

  @doc """
  Creates a mock Tesla HTTP response.

  ## Examples

      # Success response
      response = mock_http_response(200, %{"result" => "success"})
      
      # Error response
      response = mock_http_response(401, %{"error" => "Unauthorized"})
      
      # With custom headers
      response = mock_http_response(200, %{"data" => []}, [
        {"content-type", "application/json"},
        {"x-rate-limit", "1000"}
      ])
  """
  def mock_http_response(status, body, headers \\ []) do
    default_headers = [{"content-type", "application/json"}]

    %Tesla.Env{
      status: status,
      body: body,
      headers: headers ++ default_headers,
      method: :post,
      url: "https://api.example.com/test"
    }
  end

  @doc """
  Creates a mock streaming response for testing streaming plugs.
  """
  def mock_stream_response(chunks) when is_list(chunks) do
    %{
      chunks: chunks,
      stream_pid: spawn(fn -> :ok end),
      stream_ref: make_ref()
    }
  end

  @doc """
  Runs a single plug against a request.

  ## Examples

      request = build_request()
      result = run_plug(request, ExLLM.Plugs.ValidateProvider)
      
      # With options
      result = run_plug(request, ExLLM.Plugs.Cache, ttl: 3600)
  """
  def run_plug(%Request{} = request, plug, opts \\ []) do
    try do
      plug.call(request, plug.init(opts))
    rescue
      error ->
        error_entry = %{
          plug: plug,
          error: error,
          stacktrace: __STACKTRACE__,
          message: Exception.message(error)
        }

        request
        |> Map.update!(:errors, &[error_entry | &1])
        |> Map.put(:state, :error)
        |> Request.halt()
    end
  end

  @doc """
  Runs a pipeline against a request (convenience wrapper around Pipeline.run).
  """
  def run_pipeline(%Request{} = request, pipeline) when is_list(pipeline) do
    ExLLM.Pipeline.run(request, pipeline)
  end

  @doc """
  Creates a test pipeline with mock plugs for testing.

  ## Examples

      pipeline = test_pipeline([
        ExLLM.Plugs.ValidateProvider,
        {ExLLM.TestPlugs.MockSuccess, result: "test result"},
        ExLLM.TestPlugs.MockError
      ])
  """
  def test_pipeline(plugs) when is_list(plugs) do
    plugs
  end

  @doc """
  Captures log output during test execution.

  ## Examples

      {result, logs} = capture_log(fn ->
        run_plug(request, ExLLM.Plugs.FetchConfig)
      end)
      
      assert logs =~ "Missing API key"
  """
  def capture_log(fun) when is_function(fun, 0) do
    ExUnit.CaptureLog.capture_log(fun)
  end
end
