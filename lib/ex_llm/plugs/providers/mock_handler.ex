defmodule ExLLM.Plugs.Providers.MockHandler do
  @moduledoc """
  Mock handler for testing the pipeline architecture.

  This plug simulates an LLM provider by returning predefined responses.
  Useful for testing pipelines without making actual API calls.
  """

  use ExLLM.Plug

  @impl true
  def call(%Request{messages: messages, config: config} = request, opts) do
    # Get mock response from options or generate default
    response = opts[:response] || generate_mock_response(messages, config)

    # Simulate some processing time if configured
    if delay = opts[:delay] do
      Process.sleep(delay)
    end

    # Check if we should simulate an error
    if opts[:error] do
      Request.halt_with_error(request, %{
        plug: __MODULE__,
        error: opts[:error],
        message: opts[:error_message] || "Mock error"
      })
    else
      request
      |> Map.put(:result, response)
      |> Request.put_state(:completed)
      |> Request.assign(:mock_handler_called, true)
    end
  end

  defp generate_mock_response(messages, config) do
    last_message = List.last(messages) || %{}
    user_content = last_message[:content] || "Hello"

    %{
      content: "Mock response to: #{user_content}",
      role: "assistant",
      model: config[:model] || "mock-model",
      usage: %{
        prompt_tokens: 10,
        completion_tokens: 15,
        total_tokens: 25
      },
      provider: :mock,
      mock_config: config
    }
  end
end
