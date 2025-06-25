defmodule ExLLM.Pipeline do
  @moduledoc """
  The pipeline runner that executes a series of plugs on a request.

  The pipeline provides a way to process LLM requests through a series of
  transformations, similar to how Plug processes HTTP requests. Each plug
  in the pipeline can modify the request, add data, or halt execution.

  ## Basic Usage

      request = ExLLM.Pipeline.Request.new(:openai, messages)
      
      pipeline = [
        ExLLM.Plugs.ValidateProvider,
        ExLLM.Plugs.FetchConfig,
        {ExLLM.Plugs.ManageContext, max_tokens: 4000},
        ExLLM.Plugs.ExecuteRequest
      ]
      
      result = ExLLM.Pipeline.run(request, pipeline)
      
  ## Pipeline Definition

  A pipeline is a list of plugs, where each plug can be either:

    * A module atom - `ExLLM.Plugs.ValidateProvider`
    * A tuple of module and options - `{ExLLM.Plugs.Cache, ttl: 300}`
    
  ## Halting

  If any plug halts the request (by setting `request.halted = true`), the
  pipeline stops executing and returns the current request state.

  ## Error Handling

  If a plug raises an exception, the pipeline catches it, adds the error to
  the request, halts execution, and returns the request with state `:error`.

  ## Telemetry Events

  The pipeline emits telemetry events for monitoring:

    * `[:ex_llm, :pipeline, :start]` - Pipeline execution started
    * `[:ex_llm, :pipeline, :stop]` - Pipeline execution completed
    * `[:ex_llm, :pipeline, :plug, :start]` - Individual plug started
    * `[:ex_llm, :pipeline, :plug, :stop]` - Individual plug completed
    * `[:ex_llm, :pipeline, :plug, :error]` - Plug raised an error
  """

  alias ExLLM.Infrastructure.Logger
  alias ExLLM.Pipeline.Request

  @type plug :: module() | {module(), ExLLM.Plug.opts()}
  @type pipeline :: [plug()]

  @doc """
  Runs a pipeline of plugs on a request.

  Each plug is executed in sequence, with the output of one plug becoming the
  input to the next. If any plug halts the request or raises an error, the
  pipeline stops executing.

  ## Options

    * `:telemetry_metadata` - Additional metadata to include in telemetry events
    
  ## Examples

      pipeline = [
        ExLLM.Plugs.ValidateProvider,
        ExLLM.Plugs.FetchConfig,
        ExLLM.Plugs.ExecuteRequest
      ]
      
      request = ExLLM.Pipeline.Request.new(:openai, messages)
      result = ExLLM.Pipeline.run(request, pipeline)
      
      case result.state do
        :completed -> {:ok, result.result}
        :error -> {:error, result.errors}
        _ -> {:error, :unknown_state}
      end
  """
  @spec run(Request.t(), pipeline(), keyword()) :: Request.t()
  def run(%Request{} = request, pipeline, opts \\ []) when is_list(pipeline) do
    start_time = System.monotonic_time()
    telemetry_metadata = opts[:telemetry_metadata] || %{}

    # Set start time in metadata
    request = Request.put_metadata(request, :start_time, start_time)

    # Emit pipeline start event
    :telemetry.execute(
      [:ex_llm, :pipeline, :start],
      %{time: start_time},
      Map.merge(telemetry_metadata, %{
        request_id: request.id,
        provider: request.provider,
        pipeline_length: length(pipeline)
      })
    )

    # Run the pipeline
    result = do_run(request, pipeline, telemetry_metadata)

    # Calculate duration and update metadata
    end_time = System.monotonic_time()
    duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

    result =
      result
      |> Request.put_metadata(:end_time, end_time)
      |> Request.put_metadata(:duration_ms, duration_ms)

    # Emit pipeline stop event
    :telemetry.execute(
      [:ex_llm, :pipeline, :stop],
      %{duration: duration_ms},
      Map.merge(telemetry_metadata, %{
        request_id: result.id,
        provider: result.provider,
        state: result.state,
        halted: result.halted,
        error_count: length(result.errors)
      })
    )

    result
  end

  @doc """
  Runs a pipeline on a request and returns a stream.

  This is used for providers that support streaming responses. The pipeline
  executes plugs sequentially until one of them initiates a stream by
  updating the request state to `:streaming` and adding a `:response_stream`
  to the `assigns` map.

  If the pipeline completes without starting a stream, or if an error occurs
  before streaming begins, it returns an error tuple.

  ## Returns

    * `{:ok, stream}` - On success, where `stream` is a stream of response chunks.
    * `{:error, request}` - If an error occurs or no stream is started.

  ## Examples

      pipeline = [
        ExLLM.Plugs.ValidateProvider,
        ExLLM.Plugs.FetchConfig,
        ExLLM.Plugs.ExecuteRequest # This plug must support streaming
      ]
      
      request = ExLLM.Pipeline.Request.new(:openai, messages, stream: true)
      
      case ExLLM.Pipeline.stream(request, pipeline) do
        {:ok, stream} ->
          Enum.each(stream, fn chunk -> IO.inspect(chunk) end)
          
        {:error, request} ->
          IO.inspect(request.errors)
      end
  """
  @spec stream(Request.t(), pipeline(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Request.t()}
  def stream(%Request{} = request, pipeline, opts \\ []) when is_list(pipeline) do
    start_time = System.monotonic_time()
    telemetry_metadata = opts[:telemetry_metadata] || %{}

    request = Request.put_metadata(request, :start_time, start_time)

    :telemetry.execute(
      [:ex_llm, :pipeline, :start],
      %{time: start_time},
      Map.merge(telemetry_metadata, %{
        request_id: request.id,
        provider: request.provider,
        pipeline_length: length(pipeline),
        stream: true
      })
    )

    final_request = do_stream_run(request, pipeline, telemetry_metadata)

    case final_request do
      %{state: :streaming, assigns: %{response_stream: response_stream}} = req ->
        duration_ms =
          System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

        :telemetry.execute(
          [:ex_llm, :pipeline, :stop],
          %{duration: duration_ms},
          Map.merge(telemetry_metadata, %{
            request_id: req.id,
            provider: req.provider,
            state: req.state,
            halted: req.halted,
            error_count: length(req.errors)
          })
        )

        wrapped_stream = wrap_stream_for_telemetry(response_stream, req, telemetry_metadata)
        {:ok, wrapped_stream}

      error_request ->
        error_request =
          if error_request.state != :error do
            error_request
            |> Request.add_error(%{
              plug: __MODULE__,
              reason: :no_stream_started,
              message: "The pipeline completed without initiating a stream."
            })
            |> Request.put_state(:error)
            |> Request.halt()
          else
            error_request
          end

        duration_ms =
          System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)

        final_error_request =
          error_request
          |> Request.put_metadata(:end_time, System.monotonic_time())
          |> Request.put_metadata(:duration_ms, duration_ms)

        :telemetry.execute(
          [:ex_llm, :pipeline, :stop],
          %{duration: duration_ms},
          Map.merge(telemetry_metadata, %{
            request_id: final_error_request.id,
            provider: final_error_request.provider,
            state: final_error_request.state,
            halted: final_error_request.halted,
            error_count: length(final_error_request.errors)
          })
        )

        {:error, final_error_request}
    end
  end

  defp do_run(request, pipeline, telemetry_metadata) do
    Enum.reduce_while(pipeline, request, fn plug, acc ->
      if acc.halted do
        {:halt, acc}
      else
        {:cont, execute_plug(acc, plug, telemetry_metadata)}
      end
    end)
  end

  defp do_stream_run(request, pipeline, telemetry_metadata) do
    Enum.reduce_while(pipeline, request, fn plug, acc ->
      if acc.halted do
        {:halt, acc}
      else
        result = execute_plug(acc, plug, telemetry_metadata)

        if result.state == :streaming or result.halted do
          {:halt, result}
        else
          {:cont, result}
        end
      end
    end)
  end

  defp wrap_stream_for_telemetry(stream, request, telemetry_metadata) do
    stream_start_time = System.monotonic_time()
    chunk_counter = :counters.new(1, [])

    Stream.transform(stream, nil, fn chunk, _acc ->
      :counters.add(chunk_counter, 1, 1)

      :telemetry.execute(
        [:ex_llm, :pipeline, :stream, :chunk],
        %{time: System.monotonic_time()},
        Map.merge(telemetry_metadata, %{
          request_id: request.id,
          provider: request.provider
        })
      )

      # Assumes chunk is a struct with a :finish_reason field
      if Map.get(chunk, :finish_reason) != nil do
        duration = System.monotonic_time() - stream_start_time
        total_chunks = :counters.get(chunk_counter, 1)

        :telemetry.execute(
          [:ex_llm, :pipeline, :stream, :complete],
          %{duration: duration},
          Map.merge(telemetry_metadata, %{
            request_id: request.id,
            provider: request.provider,
            chunk_count: total_chunks,
            finish_reason: Map.get(chunk, :finish_reason)
          })
        )
      end

      {[chunk], nil}
    end)
  end

  defp execute_plug(request, plug, telemetry_metadata) when is_atom(plug) do
    execute_plug(request, {plug, []}, telemetry_metadata)
  end

  defp execute_plug(request, {plug, opts}, telemetry_metadata) do
    plug_start = System.monotonic_time()

    # Emit plug start event
    :telemetry.execute(
      [:ex_llm, :pipeline, :plug, :start],
      %{time: plug_start},
      Map.merge(telemetry_metadata, %{
        request_id: request.id,
        plug: plug
      })
    )

    try do
      # Initialize and call the plug
      initialized_opts = plug.init(opts)
      result = plug.call(request, initialized_opts)

      # Emit plug stop event
      duration = System.monotonic_time() - plug_start

      :telemetry.execute(
        [:ex_llm, :pipeline, :plug, :stop],
        %{duration: duration},
        Map.merge(telemetry_metadata, %{
          request_id: request.id,
          plug: plug,
          halted: result.halted
        })
      )

      result
    rescue
      error ->
        # Create error entry
        error_entry = %{
          plug: plug,
          error: error,
          stacktrace: __STACKTRACE__,
          message: Exception.message(error),
          timestamp: DateTime.utc_now()
        }

        # Log the error
        Logger.error("""
        Plug error in #{inspect(plug)}:
        #{Exception.message(error)}
        #{Exception.format_stacktrace(__STACKTRACE__)}
        """)

        # Emit plug error event
        :telemetry.execute(
          [:ex_llm, :pipeline, :plug, :error],
          %{duration: System.monotonic_time() - plug_start},
          Map.merge(telemetry_metadata, %{
            request_id: request.id,
            plug: plug,
            error: error
          })
        )

        # Return request with error
        request
        |> Request.add_error(error_entry)
        |> Request.put_state(:error)
        |> Request.halt()
    end
  end

  defmodule Builder do
    @moduledoc """
    DSL for building reusable pipeline modules.

    ## Example

        defmodule MyApp.CustomPipeline do
          use ExLLM.Pipeline.Builder
          
          plug ExLLM.Plugs.ValidateProvider
          plug ExLLM.Plugs.FetchConfig
          plug MyApp.Plugs.CustomAuth
          plug ExLLM.Plugs.ExecuteRequest
        end
    """

    defmacro __using__(_opts) do
      quote do
        import ExLLM.Pipeline.Builder

        @before_compile ExLLM.Pipeline.Builder
        Module.register_attribute(__MODULE__, :plugs, accumulate: true)
      end
    end

    @doc """
    Adds a plug to the pipeline.

    ## Examples

        plug ExLLM.Plugs.ValidateProvider
        plug ExLLM.Plugs.Cache, ttl: 300
        plug MyApp.CustomPlug, option: "value"
    """
    defmacro plug(plug, opts \\ []) do
      quote do
        @plugs {unquote(plug), unquote(opts)}
      end
    end

    defmacro __before_compile__(_env) do
      quote do
        @doc """
        Returns the list of plugs in this pipeline.
        """
        def __plugs__, do: @plugs |> Enum.reverse()

        @doc """
        Runs this pipeline on the given request.

        ## Examples

            request = ExLLM.Pipeline.Request.new(:openai, messages)
            result = #{inspect(__MODULE__)}.run(request)
        """
        def run(request, opts \\ []) do
          ExLLM.Pipeline.run(request, __plugs__(), opts)
        end
      end
    end
  end

  @doc """
  Inspects a pipeline to show what plugs will be executed.

  Useful for debugging and understanding pipeline composition.

  ## Examples

      iex> pipeline = [
      ...>   ExLLM.Plugs.ValidateProvider,
      ...>   {ExLLM.Plugs.Cache, ttl: 300},
      ...>   ExLLM.Plugs.ExecuteRequest
      ...> ]
      iex> ExLLM.Pipeline.inspect_pipeline(pipeline)
      1. ExLLM.Plugs.ValidateProvider
      2. ExLLM.Plugs.Cache [ttl: 300]
      3. ExLLM.Plugs.ExecuteRequest
      :ok
  """
  @spec inspect_pipeline(pipeline()) :: :ok
  def inspect_pipeline(pipeline) when is_list(pipeline) do
    pipeline
    |> Enum.with_index(1)
    |> Enum.each(fn
      {{plug, opts}, index} ->
        IO.puts("#{index}. #{plug} #{Kernel.inspect(opts)}")

      {plug, index} ->
        IO.puts("#{index}. #{plug}")
    end)

    :ok
  end
end
