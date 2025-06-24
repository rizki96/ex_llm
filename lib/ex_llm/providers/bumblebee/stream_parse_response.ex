defmodule ExLLM.Providers.Bumblebee.StreamParseResponse do
  @moduledoc """
  Handles streaming responses from local Bumblebee model execution.

  This plug converts the local token stream into ExLLM's standard
  streaming format, handling token-by-token generation from local models.
  """

  use ExLLM.Plug

  alias ExLLM.Pipeline.Request
  alias ExLLM.Types

  @impl true
  def call(%Request{state: :streaming} = request, _opts) do
    token_stream = request.assigns[:token_stream]
    model = request.assigns[:model]

    if token_stream do
      handle_streaming_response(request, token_stream, model)
    else
      # Not a streaming request, pass through
      request
    end
  end

  def call(request, _opts), do: request

  defp handle_streaming_response(request, token_stream, model) do
    # Convert the token stream to chunk stream
    chunk_stream = convert_to_chunk_stream(token_stream, model)

    request
    |> Request.assign(:response_stream, chunk_stream)
    |> Request.assign(:stream_type, :local_tokens)
  end

  defp convert_to_chunk_stream(token_stream, model) do
    # Track accumulated text for the response
    accumulated_ref = :ets.new(:accumulated_text, [:set, :public])
    :ets.insert(accumulated_ref, {:text, ""})

    token_stream
    |> Stream.map(fn token ->
      # Accumulate text
      current_text =
        case :ets.lookup(accumulated_ref, :text) do
          [{:text, text}] -> text
          _ -> ""
        end

      new_text = current_text <> token
      :ets.insert(accumulated_ref, {:text, new_text})

      # Create chunk
      %Types.StreamChunk{
        content: token,
        finish_reason: nil,
        model: model,
        metadata: %{
          token_count: estimate_token_count(new_text),
          is_local: true,
          provider: :bumblebee
        }
      }
    end)
    |> Stream.concat([create_final_chunk(accumulated_ref, model)])
    |> Stream.map(fn chunk ->
      # Clean up ETS table after final chunk
      if chunk.finish_reason == "stop" do
        :ets.delete(accumulated_ref)
      end

      chunk
    end)
  end

  defp create_final_chunk(accumulated_ref, model) do
    final_text =
      case :ets.lookup(accumulated_ref, :text) do
        [{:text, text}] -> text
        _ -> ""
      end

    %Types.StreamChunk{
      # No new content in final chunk
      content: "",
      finish_reason: "stop",
      model: model,
      metadata: %{
        is_local: true,
        final_text: final_text,
        provider: :bumblebee,
        usage: %{
          # Already counted in initial request
          input_tokens: 0,
          output_tokens: estimate_token_count(final_text),
          total_tokens: estimate_token_count(final_text)
        }
      }
    }
  end

  defp estimate_token_count(text) when is_binary(text) do
    # Rough estimation: ~4 characters per token
    div(String.length(text), 4)
  end

  defp estimate_token_count(_), do: 0
end
