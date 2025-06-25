defmodule ExLLM.Plugs.Providers.MockHandler do
  @moduledoc """
  Mock handler for testing the pipeline architecture.

  This plug simulates an LLM provider by returning predefined responses.
  Useful for testing pipelines without making actual API calls.
  """

  use ExLLM.Plug

  alias ExLLM.Pipeline.Request
  alias ExLLM.Types

  @impl true
  def call(%Request{state: :pending} = request, _opts) do
    # Build request phase - just pass through to executing
    request
    |> Request.assign(:url, "http://mock/api")
    |> Request.assign(:headers, %{"content-type" => "application/json"})
    |> Request.assign(:body, Jason.encode!(%{messages: request.messages}))
    |> Request.put_state(:executing)
  end

  def call(%Request{state: :executing} = request, opts) do
    messages = request.messages
    # Use provider configuration from merged config sources
    # Provider config contains API keys, model settings, and other configuration
    config = request.config || %{}

    # Check if this is a streaming request
    is_streaming = Map.get(request.options || %{}, :stream, false)

    if is_streaming do
      handle_streaming_request(request, messages, config, opts)
    else
      handle_chat_request(request, messages, config, opts)
    end
  end

  def call(request, _opts), do: request

  defp handle_chat_request(request, messages, config, opts) do
    # Check multiple sources for mock response in priority order:
    # 1. Options passed to handler (explicit override)
    # 2. Mock agent configuration
    # 3. Application environment (for cache tests)  
    # 4. Default echo response
    response =
      case opts[:response] do
        nil ->
          case get_mock_agent_response(messages, config) do
            {:ok, agent_response} ->
              agent_response

            _ ->
              case Application.get_env(:ex_llm, :mock_responses, %{})[:chat] do
                nil -> generate_mock_response(messages, config)
                app_response -> normalize_app_response(app_response, messages, config)
              end
          end

        explicit_response ->
          explicit_response
      end

    # Simulate some processing time if configured
    if delay = opts[:delay] do
      Process.sleep(delay)
    end

    # Check if we should simulate an error (from Mock agent or options)
    error_to_simulate = get_mock_agent_error() || request.options[:mock_error] || opts[:error]

    if error_to_simulate do
      # Use the Request error handling system properly
      request
      |> Request.add_error(%{
        error: error_to_simulate,
        plug: __MODULE__,
        mock_handler_called: true
      })
      |> Request.put_state(:error)
      |> Request.halt()
    else
      # Convert response to LLMResponse
      llm_response = %Types.LLMResponse{
        content: response.content,
        model: response.model,
        usage: response.usage,
        finish_reason: "stop",
        function_call: response.function_call,
        tool_calls: response.tool_calls,
        metadata: %{provider: response.provider, mock_config: response.mock_config}
      }

      request
      |> Request.assign(:llm_response, llm_response)
      |> Request.put_state(:completed)
      |> Request.assign(:mock_handler_called, true)
    end
  end

  defp handle_streaming_request(request, messages, config, opts) do
    stream_response = get_stream_response(messages, config, opts)
    error_to_simulate = get_mock_agent_error() || config[:mock_error] || opts[:error]

    if error_to_simulate do
      request
      |> Request.add_error(%{
        error: error_to_simulate,
        plug: __MODULE__,
        mock_handler_called: true
      })
      |> Request.put_state(:error)
      |> Request.halt()
    else
      # Don't consume the stream here - let Pipeline.stream handle it
      # The callback will be triggered when ExLLM.stream consumes the stream

      request
      |> Request.assign(:response_stream, stream_response)
      |> Request.put_state(:streaming)
      |> Request.assign(:mock_handler_called, true)
    end
  end

  defp get_stream_response(messages, config, opts) do
    # Check explicit options first (highest priority)
    case opts[:stream] do
      nil ->
        # Then check Mock agent
        case get_mock_agent_stream(messages, config) do
          {:ok, stream} ->
            stream

          _ ->
            # Finally check environment or generate default
            get_stream_from_env_or_opts(messages, config, opts)
        end

      explicit_stream ->
        convert_chunks_to_stream(explicit_stream)
    end
  end

  defp get_stream_from_env_or_opts(messages, config, _opts) do
    case Application.get_env(:ex_llm, :mock_responses, %{})[:stream] do
      nil ->
        generate_mock_stream(messages, config)

      chunks when is_list(chunks) ->
        convert_chunks_to_stream(chunks)

      stream_fn when is_function(stream_fn, 2) ->
        execute_stream_function(stream_fn, messages, config)

      _ ->
        generate_mock_stream(messages, config)
    end
  end

  defp convert_chunks_to_stream(chunks) do
    Stream.map(chunks, fn chunk ->
      Process.sleep(10)
      chunk
    end)
  end

  defp execute_stream_function(stream_fn, messages, config) do
    case stream_fn.(messages, config) do
      {:ok, stream} -> stream
      stream -> stream
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
              {:ok,
               %{
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
        nil ->
          nil

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
        convert_llm_response_to_pipeline_format(response, config)

      response when is_map(response) ->
        convert_map_response_to_pipeline_format(response, config)

      _ ->
        generate_mock_response([], config)
    end
  end

  defp convert_llm_response_to_pipeline_format(response, config) do
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
  end

  defp convert_map_response_to_pipeline_format(response, config) do
    %{
      content: extract_content(response),
      role: "assistant",
      model: extract_model(response, config),
      usage: extract_usage(response),
      provider: :mock,
      mock_config: config,
      function_call: extract_function_call(response),
      tool_calls: extract_tool_calls(response)
    }
  end

  defp extract_content(response) do
    response[:content] || response["content"] || "Mock response"
  end

  defp extract_model(response, config) do
    response[:model] || response["model"] || config[:model] || "mock-model"
  end

  defp extract_usage(response) do
    response[:usage] || response["usage"] ||
      %{
        prompt_tokens: 10,
        completion_tokens: 15,
        total_tokens: 25
      }
  end

  defp extract_function_call(response) do
    response[:function_call] || response["function_call"]
  end

  defp extract_tool_calls(response) do
    response[:tool_calls] || response["tool_calls"]
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
        completion_tokens: 20,
        total_tokens: 30
      },
      provider: :mock,
      mock_config: config,
      function_call: nil,
      tool_calls: nil
    }
  end
end
