defmodule ExLLM.Plugs.Providers.MockHandler do
  @moduledoc """
  Mock handler for testing the pipeline architecture.

  This plug simulates an LLM provider by returning predefined responses.
  Useful for testing pipelines without making actual API calls.
  """

  use ExLLM.Plug

  @impl true
  def call(%Request{messages: messages, config: config} = request, opts) do
    # Check if this is a streaming request
    is_streaming = config[:stream] || Map.get(request, :stream, false)

    if is_streaming do
      handle_streaming_request(request, messages, config, opts)
    else
      handle_chat_request(request, messages, config, opts)
    end
  end

  defp handle_chat_request(request, messages, config, opts) do
    # Check multiple sources for mock response in priority order:
    # 1. Mock agent configuration
    # 2. Application environment (for cache tests)  
    # 3. Options passed to handler
    # 4. Default echo response
    response = 
      case get_mock_agent_response(messages, config) do
        {:ok, agent_response} -> agent_response
        _ -> 
          case Application.get_env(:ex_llm, :mock_responses, %{})[:chat] do
            nil -> opts[:response] || generate_mock_response(messages, config)
            app_response -> normalize_app_response(app_response, messages, config)
          end
      end

    # Simulate some processing time if configured
    if delay = opts[:delay] do
      Process.sleep(delay)
    end

    # Check if we should simulate an error (from Mock agent or options)
    error_to_simulate = get_mock_agent_error() || config[:mock_error] || opts[:error]
    
    if error_to_simulate do
      # Use the Request error handling system properly
      Request.halt_with_error(request, %{
        error: error_to_simulate,
        plug: __MODULE__,
        mock_handler_called: true
      })
    else
      request
      |> Map.put(:result, response)
      |> Request.put_state(:completed)
      |> Request.assign(:mock_handler_called, true)
    end
  end

  defp handle_streaming_request(request, messages, config, opts) do
    # Check if Mock agent has streaming chunks configured
    stream_response = 
      case get_mock_agent_stream(messages, config) do
        {:ok, stream} -> stream
        _ -> opts[:stream] || generate_mock_stream(messages, config)
      end

    # Check if we should simulate an error
    error_to_simulate = get_mock_agent_error() || config[:mock_error] || opts[:error]
    
    if error_to_simulate do
      # Use the Request error handling system properly
      Request.halt_with_error(request, %{
        error: error_to_simulate,
        plug: __MODULE__,
        mock_handler_called: true
      })
    else
      request
      |> Map.put(:result, stream_response)
      |> Request.put_state(:completed)
      |> Request.assign(:mock_handler_called, true)
    end
  end

  # Try to get response from Mock agent if it's configured
  defp get_mock_agent_response(messages, config) do
    try do
      # Check if Mock agent is running and has a response configured
      case Process.whereis(ExLLM.Providers.Mock) do
        nil -> 
          {:error, :agent_not_running}
        _pid ->
          # Use the Mock agent's chat function to get the response
          case ExLLM.Providers.Mock.chat(messages, Enum.to_list(config)) do
            {:ok, response} -> 
              # Convert to the format expected by the pipeline
              {:ok, %{
                content: response.content,
                role: "assistant", 
                model: response.model,
                usage: response.usage,
                provider: :mock,
                mock_config: config,
                function_call: response.function_call,
                tool_calls: response.tool_calls
              }}
            {:error, _} = error -> 
              error
          end
      end
    rescue
      _ -> {:error, :agent_error}
    end
  end

  # Try to get stream from Mock agent if it's configured
  defp get_mock_agent_stream(messages, config) do
    try do
      case Process.whereis(ExLLM.Providers.Mock) do
        nil -> 
          {:error, :agent_not_running}
        _pid ->
          # Use the Mock agent's stream_chat function to get the stream
          case ExLLM.Providers.Mock.stream_chat(messages, Enum.to_list(config)) do
            {:ok, stream} -> {:ok, stream}
            {:error, _} = error -> error
          end
      end
    rescue
      _ -> {:error, :agent_error}
    end
  end

  # Check if Mock agent has an error configured
  defp get_mock_agent_error do
    try do
      case Process.whereis(ExLLM.Providers.Mock) do
        nil -> nil
        _pid ->
          # Check the agent's state to see if it's in error mode
          Agent.get(ExLLM.Providers.Mock, fn state ->
            case state.response_mode do
              :error -> state.error_response
              _ -> nil
            end
          end)
      end
    rescue
      _ -> nil
    end
  end

  defp generate_mock_stream(_messages, _config) do
    # Create a default mock stream
    chunks = [
      %{content: "Mock ", finish_reason: nil},
      %{content: "stream ", finish_reason: nil},
      %{content: "response", finish_reason: nil},
      %{content: "", finish_reason: "stop"}
    ]

    # Convert to a stream
    Stream.map(chunks, fn chunk ->
      # Add delay to simulate real streaming
      Process.sleep(10)
      chunk
    end)
  end

  defp normalize_app_response(app_response, _messages, config) do
    case app_response do
      %ExLLM.Types.LLMResponse{} = response ->
        # Convert LLMResponse to pipeline format
        %{
          content: response.content,
          role: "assistant",
          model: response.model,
          usage: response.usage,
          provider: :mock,
          mock_config: config,
          function_call: response.function_call,
          tool_calls: response.tool_calls
        }
      
      response when is_map(response) ->
        # Convert map to pipeline format
        %{
          content: response[:content] || response["content"] || "Mock response",
          role: "assistant",
          model: response[:model] || response["model"] || config[:model] || "mock-model",
          usage: response[:usage] || response["usage"] || %{
            prompt_tokens: 10,
            completion_tokens: 15,
            total_tokens: 25
          },
          provider: :mock,
          mock_config: config,
          function_call: response[:function_call] || response["function_call"],
          tool_calls: response[:tool_calls] || response["tool_calls"]
        }
      
      _ ->
        generate_mock_response([], config)
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
