defmodule ExLLM.TestPlugs do
  @moduledoc """
  Collection of mock plugs for testing ExLLM pipelines.

  These plugs provide controlled behavior for testing various scenarios
  without making real API calls or depending on external services.
  """

  alias ExLLM.Pipeline.Request

  defmodule MockSuccess do
    @moduledoc """
    A plug that always succeeds with a configurable result.

    ## Options

      * `:result` - The result to set on the request (default: "mock success")
      * `:assign` - Key-value pairs to add to assigns
      * `:metadata` - Key-value pairs to add to metadata
      
    ## Examples

        # Simple success
        plug ExLLM.TestPlugs.MockSuccess
        
        # With custom result
        plug ExLLM.TestPlugs.MockSuccess, result: %{content: "Hello!"}
        
        # With assigns and metadata
        plug ExLLM.TestPlugs.MockSuccess,
          result: "test",
          assign: [temperature: 0.7],
          metadata: [model_used: "test-model"]
    """

    use ExLLM.Plug

    @impl true
    def init(opts) do
      Keyword.validate!(opts, [
        :result,
        :assign,
        :metadata
      ])
    end

    @impl true
    def call(%Request{} = request, opts) do
      result = Keyword.get(opts, :result, "mock success")
      assigns = Keyword.get(opts, :assign, [])
      metadata = Keyword.get(opts, :metadata, [])

      request
      |> Map.put(:result, result)
      |> Request.put_state(:completed)
      |> add_assigns(assigns)
      |> add_metadata(metadata)
    end

    defp add_assigns(request, []), do: request

    defp add_assigns(request, assigns) do
      Enum.reduce(assigns, request, fn {key, value}, acc ->
        Request.assign(acc, key, value)
      end)
    end

    defp add_metadata(request, []), do: request

    defp add_metadata(request, metadata) do
      Enum.reduce(metadata, request, fn {key, value}, acc ->
        Request.put_metadata(acc, key, value)
      end)
    end
  end

  defmodule MockError do
    @moduledoc """
    A plug that always fails with a configurable error.

    ## Options

      * `:error` - The error type (default: :mock_error)
      * `:message` - The error message (default: "Mock error")
      * `:halt` - Whether to halt the pipeline (default: true)
      
    ## Examples

        # Simple error
        plug ExLLM.TestPlugs.MockError
        
        # Custom error
        plug ExLLM.TestPlugs.MockError,
          error: :invalid_api_key,
          message: "API key is invalid"
    """

    use ExLLM.Plug

    @impl true
    def init(opts) do
      Keyword.validate!(opts, [
        :error,
        :message,
        :halt
      ])
    end

    @impl true
    def call(%Request{} = request, opts) do
      error_type = Keyword.get(opts, :error, :mock_error)
      message = Keyword.get(opts, :message, "Mock error")
      should_halt = Keyword.get(opts, :halt, true)

      error_data = %{
        plug: __MODULE__,
        error: error_type,
        message: message
      }

      request = Request.add_error(request, error_data)

      if should_halt do
        Request.halt_with_error(request, error_data)
      else
        request
      end
    end
  end

  defmodule MockDelay do
    @moduledoc """
    A plug that introduces a configurable delay for testing timeouts.

    ## Options

      * `:delay_ms` - Delay in milliseconds (default: 100)
      * `:pass_through` - Whether to continue normally after delay (default: true)
      
    ## Examples

        # Short delay
        plug ExLLM.TestPlugs.MockDelay, delay_ms: 50
        
        # Long delay that might trigger timeouts
        plug ExLLM.TestPlugs.MockDelay, delay_ms: 5000
    """

    use ExLLM.Plug

    @impl true
    def init(opts) do
      Keyword.validate!(opts, [:delay_ms, :pass_through])
    end

    @impl true
    def call(%Request{} = request, opts) do
      delay_ms = Keyword.get(opts, :delay_ms, 100)
      pass_through = Keyword.get(opts, :pass_through, true)

      :timer.sleep(delay_ms)

      if pass_through do
        request
      else
        Request.halt_with_error(request, %{
          plug: __MODULE__,
          error: :timeout,
          message: "Mock timeout after #{delay_ms}ms"
        })
      end
    end
  end

  defmodule MockHttpResponse do
    @moduledoc """
    A plug that sets a mock HTTP response on the request.

    ## Options

      * `:status` - HTTP status code (default: 200)
      * `:body` - Response body (default: %{})
      * `:headers` - Response headers (default: [])
      
    ## Examples

        # Success response
        plug ExLLM.TestPlugs.MockHttpResponse,
          status: 200,
          body: %{"choices" => [%{"message" => %{"content" => "Hello"}}]}
        
        # Error response
        plug ExLLM.TestPlugs.MockHttpResponse,
          status: 401,
          body: %{"error" => %{"message" => "Unauthorized"}}
    """

    use ExLLM.Plug

    @impl true
    def init(opts) do
      Keyword.validate!(opts, [:status, :body, :headers])
    end

    @impl true
    def call(%Request{} = request, opts) do
      status = Keyword.get(opts, :status, 200)
      body = Keyword.get(opts, :body, %{})
      headers = Keyword.get(opts, :headers, [{"content-type", "application/json"}])

      mock_response = %Tesla.Env{
        status: status,
        body: body,
        headers: headers,
        method: :post,
        url: "https://api.mock.com/test"
      }

      request
      |> Map.put(:response, mock_response)
      |> Request.put_metadata(:http_status, status)
    end
  end

  defmodule MockCounter do
    @moduledoc """
    A plug that counts how many times it has been called.

    Useful for testing pipeline ordering and ensuring plugs are called
    the expected number of times.

    ## Usage

        # Start the counter
        MockCounter.start()
        
        # Use in pipeline
        plug ExLLM.TestPlugs.MockCounter, name: :test_counter
        
        # Check count
        assert MockCounter.count(:test_counter) == 1
        
        # Reset
        MockCounter.reset(:test_counter)
    """

    use ExLLM.Plug
    use Agent

    def start do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def count(name \\ :default) do
      Agent.get(__MODULE__, &Map.get(&1, name, 0))
    end

    def reset(name \\ :default) do
      Agent.update(__MODULE__, &Map.put(&1, name, 0))
    end

    def stop do
      Agent.stop(__MODULE__)
    end

    @impl true
    def init(opts) do
      Keyword.validate!(opts, [:name])
    end

    @impl true
    def call(%Request{} = request, opts) do
      name = Keyword.get(opts, :name, :default)

      Agent.update(__MODULE__, fn state ->
        Map.update(state, name, 1, &(&1 + 1))
      end)

      request
    end
  end

  defmodule ShouldNotReach do
    @moduledoc """
    A plug that should never be reached - always raises an error.

    Useful for testing that pipeline halting works correctly.
    """

    use ExLLM.Plug

    @impl true
    def call(%Request{}, _opts) do
      raise "This plug should not have been reached - pipeline halting failed"
    end
  end

  defmodule MockTeslaClient do
    @moduledoc """
    A plug that sets a mock Tesla client for testing HTTP requests.
    """

    use ExLLM.Plug

    @impl true
    def init(opts) do
      Keyword.validate!(opts, [:responses])
    end

    @impl true
    def call(%Request{} = request, opts) do
      responses = Keyword.get(opts, :responses, [])

      # Create a mock Tesla client that returns predefined responses
      mock_client = create_mock_client(responses)

      Map.put(request, :tesla_client, mock_client)
    end

    defp create_mock_client(responses) do
      # This would be a more sophisticated mock in a real implementation
      # For now, just store the responses in the client
      %{mock_responses: responses, type: :mock}
    end
  end
end
