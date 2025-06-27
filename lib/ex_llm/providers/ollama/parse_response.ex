defmodule ExLLM.Providers.Ollama.ParseResponse do
  @moduledoc """
  Pipeline plug for parsing Ollama API responses.

  Ollama uses its native response format.
  """

  use ExLLM.Plug

  alias ExLLM.Pipeline.Request
  alias ExLLM.Types

  @impl true
  def call(%Request{options: %{stream: true}} = request, _opts) do
    # Skip parsing for streaming requests - they're handled by the stream parser
    request
  end

  def call(%Request{response: %{status: 200, body: body}} = request, _opts)
      when is_binary(body) do
    with {:ok, json} <- Jason.decode(body),
         {:ok, parsed} <- parse_ollama_response(json, request) do
      request
      |> Map.put(:result, parsed)
      |> Request.put_state(:completed)
    else
      {:error, reason} ->
        Request.halt_with_error(request, %{
          plug: __MODULE__,
          error: :parse_error,
          message: "Failed to parse Ollama response: #{inspect(reason)}"
        })
    end
  end

  # Handle already-parsed JSON (Tesla might decode automatically)
  def call(%Request{response: %{status: 200, body: body}} = request, _opts) when is_map(body) do
    {:ok, parsed} = parse_ollama_response(body, request)

    request
    |> Map.put(:result, parsed)
    |> Request.put_state(:completed)
  end

  def call(%Request{response: %{status: status}} = request, _opts) when status != 200 do
    # Let error handling plugs deal with non-200 responses
    request
  end

  def call(request, _opts) do
    Request.halt_with_error(request, %{
      plug: __MODULE__,
      error: :no_response,
      message: "No response to parse"
    })
  end

  defp parse_ollama_response(json, request) do
    message = Map.get(json, "message", %{})
    content = Map.get(message, "content", "")
    model = Map.get(json, "model", request.assigns[:model])

    # Extract token usage
    prompt_tokens = Map.get(json, "prompt_eval_count", 0)
    completion_tokens = Map.get(json, "eval_count", 0)
    total_tokens = prompt_tokens + completion_tokens

    # Ollama is free/local, so no cost
    cost = 0.0

    response = %Types.LLMResponse{
      content: content,
      model: model,
      usage: %{
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        total_tokens: total_tokens
      },
      cost: cost,
      finish_reason: Map.get(json, "done_reason"),
      metadata: %{
        provider: :ollama,
        created_at: Map.get(json, "created_at"),
        done_reason: Map.get(json, "done_reason"),
        total_duration: Map.get(json, "total_duration"),
        load_duration: Map.get(json, "load_duration"),
        prompt_eval_duration: Map.get(json, "prompt_eval_duration"),
        eval_duration: Map.get(json, "eval_duration")
      }
    }

    {:ok, response}
  end
end
