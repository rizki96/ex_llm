defmodule ExLLM.Plugs.Providers.BumblebeeParseStreamResponse do
  @moduledoc """
  Parses streaming responses from Bumblebee (local model) execution.

  This plug handles streaming for local models that use the Bumblebee library.
  It replaces the legacy StreamParseResponse module with the modern HTTP.Core-based approach.
  """

  use ExLLM.Plug

  @impl true
  def call(%Request{provider: provider, options: %{stream: true}} = request, _opts) do
    # For local models, streaming is handled differently
    # This is mainly for compatibility with the pipeline structure
    parser_config = %{
      parse_chunk: fn data -> parse_bumblebee_chunk(data, provider) end,
      accumulator: %{
        content: "",
        done: false
      }
    }

    request
    |> Request.put_private(:stream_parser, parser_config)
    |> Request.assign(:stream_parser_configured, true)
  end

  def call(request, _opts), do: request

  @doc """
  Parses a Bumblebee streaming chunk.

  Local models may have different streaming formats depending on implementation.
  """
  def parse_bumblebee_chunk(data, _provider) when is_binary(data) do
    # For local models, the streaming format may vary
    # This is a basic implementation that can be extended
    case Jason.decode(data) do
      {:ok, %{"content" => content, "done" => done}} ->
        {:ok,
         %{
           content: content,
           finish_reason: if(done, do: "stop", else: nil)
         }}

      {:ok, %{"content" => content}} ->
        {:ok,
         %{
           content: content,
           finish_reason: nil
         }}

      {:ok, %{"done" => true}} ->
        {:ok,
         %{
           content: nil,
           finish_reason: "stop"
         }}

      _ ->
        nil
    end
  end
end
