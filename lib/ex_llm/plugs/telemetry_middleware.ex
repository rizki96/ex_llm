defmodule ExLLM.Plugs.TelemetryMiddleware do
  @moduledoc """
  A plug that wraps a pipeline execution within a telemetry span.

  This plug is designed to be a middleware that encapsulates a series of other
  plugs, providing instrumentation for the entire sequence. It automatically
  generates telemetry events for the start, stop, and exceptions of the
  pipeline execution, including metadata extracted from the request.

  ## Options

  - `:pipeline` (required) - A list of plugs to be executed within the telemetry span.
  - `:event_name` (optional) - A list of atoms for the telemetry event prefix.
    Defaults to `[:ex_llm, :pipeline, :execution]`.

  ## Example Usage

  This plug is used to wrap other plugs in a pipeline definition.

      pipeline = [
        {ExLLM.Plugs.TelemetryMiddleware, %{
          event_name: [:ex_llm, :chat],
          pipeline: [
            {ExLLM.Plugs.ValidateProvider, []},
            {ExLLM.Plugs.PrepareRequest, []},
            {ExLLM.Plugs.ExecuteRequest, []}
          ]
        }}
      ]

      ExLLM.Pipeline.run(initial_request, pipeline)

  This setup will emit telemetry events like `[:ex_llm, :chat, :start]`,
  `[:ex_llm, :chat, :stop]`, and `[:ex_llm, :chat, :exception]`.
  """

  use ExLLM.Plug
  alias ExLLM.Infrastructure.Telemetry
  alias ExLLM.Pipeline.Request

  @impl true
  def init(opts) when is_list(opts) do
    pipeline =
      case Keyword.fetch(opts, :pipeline) do
        {:ok, p} when is_list(p) ->
          p

        :error ->
          raise ArgumentError, "the :pipeline option is required and must be a list"

        _ ->
          raise ArgumentError, "the :pipeline option must be a list"
      end

    event_name = Keyword.get(opts, :event_name, [:ex_llm, :pipeline, :execution])

    unless is_list(event_name) and Enum.all?(event_name, &is_atom/1) do
      raise ArgumentError, "the :event_name option must be a list of atoms"
    end

    %{
      pipeline: pipeline,
      event_name: event_name
    }
  end

  def init(opts) when is_map(opts) do
    pipeline =
      case Map.fetch(opts, :pipeline) do
        {:ok, p} when is_list(p) ->
          p

        :error ->
          raise ArgumentError, "the :pipeline option is required and must be a list"

        _ ->
          raise ArgumentError, "the :pipeline option must be a list"
      end

    event_name = Map.get(opts, :event_name, [:ex_llm, :pipeline, :execution])

    unless is_list(event_name) and Enum.all?(event_name, &is_atom/1) do
      raise ArgumentError, "the :event_name option must be a list of atoms"
    end

    %{
      pipeline: pipeline,
      event_name: event_name
    }
  end

  @impl true
  def call(%Request{} = request, %{pipeline: pipeline, event_name: event_name}) do
    metadata = build_metadata(request)

    Telemetry.span(event_name, metadata, fn ->
      run_pipeline(request, pipeline)
    end)
  end

  @doc false
  def build_metadata(%Request{provider: provider, options: options}) do
    # Handle both keyword list and map options
    getter = if is_map(options), do: &Map.get/3, else: &Keyword.get/3
    has_key? = if is_map(options), do: &Map.has_key?/2, else: &Keyword.has_key?/2

    %{
      provider: provider,
      model: getter.(options, :model, nil),
      stream: getter.(options, :stream, false),
      structured_output: has_key?.(options, :response_model),
      retry_enabled: getter.(options, :retry, true),
      cache_enabled: getter.(options, :cache, false)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # This is a basic pipeline runner. In a real application, this logic might
  # be centralized in a dedicated `ExLLM.Pipeline` module. It is included
  # here to make the plug self-contained.
  defp run_pipeline(request, pipeline) do
    Enum.reduce(pipeline, request, fn {plug, plug_opts}, acc_request ->
      if acc_request.halted do
        acc_request
      else
        # Initialize plug options. This enforces that all plugs must
        # implement init/1, which is a more robust contract.
        initialized_opts = plug.init(plug_opts)

        # Call the plug
        plug.call(acc_request, initialized_opts)
      end
    end)
  end
end
