defmodule ExLLM.Plugs.Providers.BumblebeeHandler do
  @moduledoc """
  Handler for Bumblebee local inference provider.

  This plug calls the Bumblebee provider directly, bypassing HTTP infrastructure
  since Bumblebee runs models locally.
  """

  use ExLLM.Plug

  alias ExLLM.{Pipeline.Request, Types}

  @impl true
  def call(%Request{messages: messages, config: config} = request, _opts) do
    # Check if this is a streaming request
    is_streaming = config[:stream] || Map.get(request, :stream, false)

    if is_streaming do
      handle_streaming_request(request, messages, config)
    else
      handle_chat_request(request, messages, config)
    end
  end

  defp handle_chat_request(request, messages, config) do
    # Extract options from config
    opts = extract_bumblebee_options(config)

    # Call the Bumblebee provider directly
    case ExLLM.Providers.Bumblebee.chat(messages, opts) do
      {:ok, %Types.LLMResponse{} = response} ->
        # Convert LLMResponse to pipeline format
        pipeline_response = %{
          content: response.content,
          role: "assistant",
          model: response.model,
          usage: %{
            prompt_tokens: response.usage.input_tokens,
            completion_tokens: response.usage.output_tokens,
            total_tokens: response.usage.total_tokens
          },
          provider: :bumblebee,
          finish_reason: response.finish_reason,
          cost: response.cost
        }

        request
        |> Map.put(:result, pipeline_response)
        |> Request.put_state(:completed)
        |> Request.assign(:bumblebee_handler_called, true)

      {:error, reason} ->
        Request.halt_with_error(request, %{
          error: reason,
          plug: __MODULE__,
          bumblebee_handler_called: true
        })
    end
  end

  defp handle_streaming_request(request, messages, config) do
    # Extract options from config
    opts = extract_bumblebee_options(config)

    # Call the Bumblebee provider's stream_chat function
    case ExLLM.Providers.Bumblebee.stream_chat(messages, opts) do
      {:ok, stream} ->
        # Handle the streaming callback if provided
        if callback = config[:stream_callback] do
          # Process the stream and call callback for each chunk
          Enum.each(stream, fn chunk ->
            callback.(chunk)
            # Small delay to simulate real streaming behavior
            Process.sleep(10)
          end)
        end

        request
        |> Map.put(:result, stream)
        |> Request.put_state(:completed)
        |> Request.assign(:bumblebee_handler_called, true)

      {:error, reason} ->
        Request.halt_with_error(request, %{
          error: reason,
          plug: __MODULE__,
          bumblebee_handler_called: true
        })
    end
  end

  defp extract_bumblebee_options(config) do
    # Convert config to options that Bumblebee provider expects
    config
    |> Enum.filter(fn {key, _value} ->
      key in [:model, :max_tokens, :temperature, :stream, :top_p, :top_k]
    end)
    |> Enum.into([])
  end
end
