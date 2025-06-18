defmodule ExLLM.ChatBuilder do
  @moduledoc """
  Enhanced builder-style API for ExLLM chat operations.

  Provides a fluent interface for constructing and customizing chat requests
  with fine-grained control over the pipeline while maintaining simplicity
  for common use cases.

  ## Basic Usage

      {:ok, response} = 
        ExLLM.chat(:openai, messages)
        |> ExLLM.ChatBuilder.with_model("gpt-4-turbo")
        |> ExLLM.ChatBuilder.with_temperature(0.7)
        |> ExLLM.ChatBuilder.execute()
        
  ## Advanced Pipeline Customization

      {:ok, response} = 
        ExLLM.chat(:openai, messages)
        |> ExLLM.ChatBuilder.with_cache(ttl: 3600)
        |> ExLLM.ChatBuilder.with_custom_plug(MyApp.Plugs.Logger)
        |> ExLLM.ChatBuilder.without_cost_tracking()
        |> ExLLM.ChatBuilder.execute()
        
  ## Streaming

      ExLLM.chat(:openai, messages)
      |> ExLLM.ChatBuilder.with_model("gpt-4")
      |> ExLLM.ChatBuilder.stream(fn chunk ->
        IO.write(chunk.content)
      end)
  """

  alias ExLLM.Pipeline.Request
  alias ExLLM.Pipeline
  alias ExLLM.Providers

  @type pipeline_modification ::
          {:replace, module(), keyword()}
          | {:remove, module()}
          | {:append, module(), keyword()}
          | {:prepend, module(), keyword()}
          | {:insert_before, module(), module(), keyword()}
          | {:insert_after, module(), module(), keyword()}

  @type t :: %__MODULE__{
          request: Request.t(),
          pipeline_mods: [pipeline_modification()],
          streaming: boolean(),
          stream_callback: function() | nil
        }

  @enforce_keys [:request]
  defstruct [
    :request,
    pipeline_mods: [],
    streaming: false,
    stream_callback: nil
  ]

  @doc """
  Creates a new ChatBuilder from a provider and messages.

  This is typically called by ExLLM.chat/2, but can be used directly:

      builder = ExLLM.ChatBuilder.new(:openai, messages)
  """
  @spec new(atom(), list(map()), map()) :: t()
  def new(provider, messages, options \\ %{}) do
    request = Request.new(provider, messages, options)
    %__MODULE__{request: request}
  end

  # Configuration Methods

  @doc """
  Sets the model for the request.

  ## Examples

      builder |> with_model("gpt-4-turbo")
      builder |> with_model("claude-3-5-sonnet-20241022")
  """
  @spec with_model(t(), String.t()) :: t()
  def with_model(%__MODULE__{} = builder, model) when is_binary(model) do
    update_option(builder, :model, model)
  end

  @doc """
  Sets the temperature for the request (0.0 to 2.0).

  ## Examples

      builder |> with_temperature(0.7)
      builder |> with_temperature(0.0)  # Deterministic
  """
  @spec with_temperature(t(), float()) :: t()
  def with_temperature(%__MODULE__{} = builder, temperature)
      when is_number(temperature) and temperature >= 0 and temperature <= 2 do
    update_option(builder, :temperature, temperature)
  end

  @doc """
  Sets the maximum tokens for the response.

  ## Examples

      builder |> with_max_tokens(1000)
      builder |> with_max_tokens(4096)
  """
  @spec with_max_tokens(t(), pos_integer()) :: t()
  def with_max_tokens(%__MODULE__{} = builder, max_tokens)
      when is_integer(max_tokens) and max_tokens > 0 do
    update_option(builder, :max_tokens, max_tokens)
  end

  @doc """
  Sets multiple options at once.

  ## Examples

      builder |> with_options(%{
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000
      })
  """
  @spec with_options(t(), map()) :: t()
  def with_options(%__MODULE__{} = builder, options) when is_map(options) do
    updated_options = Map.merge(builder.request.options, options)
    put_in(builder.request.options, updated_options)
  end

  # Pipeline Customization Methods

  @doc """
  Enables caching with configurable options.

  ## Examples

      builder |> with_cache()  # Default TTL
      builder |> with_cache(ttl: 3600)  # 1 hour
      builder |> with_cache(ttl: :infinity)  # Never expire
  """
  @spec with_cache(t(), keyword()) :: t()
  def with_cache(%__MODULE__{} = builder, opts \\ []) do
    add_pipeline_mod(builder, {:replace, ExLLM.Plugs.Cache, opts})
  end

  @doc """
  Disables caching for this request.

  ## Examples

      builder |> without_cache()
  """
  @spec without_cache(t()) :: t()
  def without_cache(%__MODULE__{} = builder) do
    add_pipeline_mod(builder, {:remove, ExLLM.Plugs.Cache})
  end

  @doc """
  Disables cost tracking for this request.

  ## Examples

      builder |> without_cost_tracking()
  """
  @spec without_cost_tracking(t()) :: t()
  def without_cost_tracking(%__MODULE__{} = builder) do
    add_pipeline_mod(builder, {:remove, ExLLM.Plugs.TrackCost})
  end

  @doc """
  Adds a custom plug to the pipeline.

  ## Examples

      builder |> with_custom_plug(MyApp.Plugs.Logger)
      builder |> with_custom_plug(MyApp.Plugs.Auth, api_key: "secret")
  """
  @spec with_custom_plug(t(), module(), keyword()) :: t()
  def with_custom_plug(%__MODULE__{} = builder, plug, opts \\ []) do
    add_pipeline_mod(builder, {:append, plug, opts})
  end

  @doc """
  Inserts a plug before another plug in the pipeline.

  ## Examples

      builder |> insert_before(ExLLM.Plugs.ExecuteRequest, MyApp.Plugs.RequestModifier)
  """
  @spec insert_before(t(), module(), module(), keyword()) :: t()
  def insert_before(%__MODULE__{} = builder, before_plug, new_plug, opts \\ []) do
    add_pipeline_mod(builder, {:insert_before, before_plug, new_plug, opts})
  end

  @doc """
  Inserts a plug after another plug in the pipeline.

  ## Examples

      builder |> insert_after(ExLLM.Plugs.FetchConfig, MyApp.Plugs.ConfigValidator)
  """
  @spec insert_after(t(), module(), module(), keyword()) :: t()
  def insert_after(%__MODULE__{} = builder, after_plug, new_plug, opts \\ []) do
    add_pipeline_mod(builder, {:insert_after, after_plug, new_plug, opts})
  end

  @doc """
  Replaces a plug in the pipeline with a custom implementation.

  ## Examples

      builder |> replace_plug(ExLLM.Plugs.Cache, MyApp.Plugs.CustomCache, ttl: 7200)
  """
  @spec replace_plug(t(), module(), module(), keyword()) :: t()
  def replace_plug(%__MODULE__{} = builder, old_plug, new_plug, opts \\ []) do
    builder
    |> add_pipeline_mod({:remove, old_plug})
    |> add_pipeline_mod({:append, new_plug, opts})
  end

  @doc """
  Sets a custom pipeline, replacing the default entirely.

  ## Examples

      custom_pipeline = [
        ExLLM.Plugs.ValidateProvider,
        MyApp.Plugs.CustomAuth,
        ExLLM.Plugs.ExecuteRequest
      ]
      
      builder |> with_pipeline(custom_pipeline)
  """
  @spec with_pipeline(t(), Pipeline.pipeline()) :: t()
  def with_pipeline(%__MODULE__{} = builder, pipeline) when is_list(pipeline) do
    %{builder | pipeline_mods: [{:custom_pipeline, pipeline}]}
  end

  # Context Management

  @doc """
  Configures context management for long conversations.

  ## Examples

      builder |> with_context_strategy(:truncate, max_tokens: 8000)
      builder |> with_context_strategy(:summarize, preserve_system: true)
  """
  @spec with_context_strategy(t(), atom(), keyword()) :: t()
  def with_context_strategy(%__MODULE__{} = builder, strategy, opts \\ []) do
    context_opts = [strategy: strategy] ++ opts
    add_pipeline_mod(builder, {:replace, ExLLM.Plugs.ManageContext, context_opts})
  end

  # Execution Methods

  @doc """
  Executes the chat request and returns the response.

  ## Examples

      {:ok, response} = builder |> execute()
      {:error, reason} = builder |> execute()
  """
  @spec execute(t()) :: {:ok, map()} | {:error, term()}
  def execute(%__MODULE__{streaming: true}) do
    {:error, :use_stream_method_for_streaming}
  end

  def execute(%__MODULE__{request: request, pipeline_mods: mods}) do
    # Build the final pipeline
    pipeline = build_pipeline(request.provider, :chat, mods)

    # Execute the pipeline
    case Pipeline.run(request, pipeline) do
      %Request{state: :completed, result: result} ->
        {:ok, result}

      %Request{state: :error, errors: errors} ->
        {:error, format_errors(errors)}

      %Request{} = failed ->
        {:error, {:pipeline_failed, failed}}
    end
  end

  @doc """
  Executes the request as a streaming chat.

  ## Examples

      builder |> stream(fn chunk ->
        case chunk do
          %{done: true} -> IO.puts("\\nDone!")
          %{content: content} -> IO.write(content)
        end
      end)
  """
  @spec stream(t(), function()) :: :ok | {:error, term()}
  def stream(%__MODULE__{request: request, pipeline_mods: mods}, callback)
      when is_function(callback, 1) do
    # Add streaming configuration
    streaming_request =
      request
      |> Map.put(
        :options,
        Map.merge(request.options, %{
          stream: true,
          stream_callback: callback
        })
      )

    # Build streaming pipeline
    pipeline = build_pipeline(request.provider, :stream, mods)

    # Execute the pipeline
    case Pipeline.run(streaming_request, pipeline) do
      %Request{state: :completed} ->
        :ok

      %Request{state: :streaming} ->
        :ok

      %Request{state: :error, errors: errors} ->
        {:error, format_errors(errors)}

      %Request{} = failed ->
        {:error, {:pipeline_failed, failed}}
    end
  end

  # Debugging and Introspection

  @doc """
  Returns the pipeline that would be executed without running it.

  Useful for debugging and understanding what plugs will run.

  ## Examples

      pipeline = builder |> inspect_pipeline()
      IO.inspect(pipeline, label: "Pipeline")
  """
  @spec inspect_pipeline(t()) :: Pipeline.pipeline()
  def inspect_pipeline(%__MODULE__{request: request, pipeline_mods: mods}) do
    build_pipeline(request.provider, :chat, mods)
  end

  @doc """
  Returns detailed information about the builder state.

  ## Examples

      info = builder |> debug_info()
      IO.inspect(info, label: "Builder State")
  """
  @spec debug_info(t()) :: map()
  def debug_info(%__MODULE__{} = builder) do
    %{
      provider: builder.request.provider,
      message_count: length(builder.request.messages),
      options: builder.request.options,
      pipeline_modifications: length(builder.pipeline_mods),
      streaming: builder.streaming,
      has_custom_pipeline: Enum.any?(builder.pipeline_mods, &match?({:custom_pipeline, _}, &1))
    }
  end

  # Private Helper Functions

  defp update_option(%__MODULE__{} = builder, key, value) do
    updated_options = Map.put(builder.request.options, key, value)
    put_in(builder.request.options, updated_options)
  end

  defp add_pipeline_mod(%__MODULE__{} = builder, mod) do
    %{builder | pipeline_mods: builder.pipeline_mods ++ [mod]}
  end

  defp build_pipeline(provider, pipeline_type, mods) do
    # Check if there's a custom pipeline
    case Enum.find(mods, &match?({:custom_pipeline, _}, &1)) do
      {:custom_pipeline, custom_pipeline} ->
        custom_pipeline

      nil ->
        # Start with default pipeline and apply modifications
        base_pipeline = Providers.get_pipeline(provider, pipeline_type)
        apply_modifications(base_pipeline, mods)
    end
  end

  defp apply_modifications(pipeline, []), do: pipeline

  defp apply_modifications(pipeline, [mod | rest]) do
    modified_pipeline = apply_modification(pipeline, mod)
    apply_modifications(modified_pipeline, rest)
  end

  defp apply_modification(pipeline, {:replace, old_plug, opts}) do
    replace_plug_in_pipeline(pipeline, old_plug, {old_plug, opts})
  end

  defp apply_modification(pipeline, {:remove, plug}) do
    remove_plug_from_pipeline(pipeline, plug)
  end

  defp apply_modification(pipeline, {:append, plug, opts}) do
    plug_spec = if opts == [], do: plug, else: {plug, opts}
    pipeline ++ [plug_spec]
  end

  defp apply_modification(pipeline, {:prepend, plug, opts}) do
    plug_spec = if opts == [], do: plug, else: {plug, opts}
    [plug_spec | pipeline]
  end

  defp apply_modification(pipeline, {:insert_before, before_plug, new_plug, opts}) do
    plug_spec = if opts == [], do: new_plug, else: {new_plug, opts}
    insert_plug_before(pipeline, before_plug, plug_spec)
  end

  defp apply_modification(pipeline, {:insert_after, after_plug, new_plug, opts}) do
    plug_spec = if opts == [], do: new_plug, else: {new_plug, opts}
    insert_plug_after(pipeline, after_plug, plug_spec)
  end

  defp replace_plug_in_pipeline(pipeline, target_plug, replacement) do
    Enum.map(pipeline, fn
      ^target_plug -> replacement
      {^target_plug, _} -> replacement
      other -> other
    end)
  end

  defp remove_plug_from_pipeline(pipeline, target_plug) do
    Enum.reject(pipeline, fn
      ^target_plug -> true
      {^target_plug, _} -> true
      _ -> false
    end)
  end

  defp insert_plug_before(pipeline, before_plug, new_plug) do
    {before, after_list} = split_at_plug(pipeline, before_plug)
    before ++ [new_plug] ++ after_list
  end

  defp insert_plug_after(pipeline, after_plug, new_plug) do
    {before_and_target, after_list} = split_after_plug(pipeline, after_plug)
    before_and_target ++ [new_plug] ++ after_list
  end

  defp split_at_plug(pipeline, target_plug) do
    index = find_plug_index(pipeline, target_plug)
    if index, do: Enum.split(pipeline, index), else: {pipeline, []}
  end

  defp split_after_plug(pipeline, target_plug) do
    index = find_plug_index(pipeline, target_plug)
    if index, do: Enum.split(pipeline, index + 1), else: {pipeline, []}
  end

  defp find_plug_index(pipeline, target_plug) do
    Enum.find_index(pipeline, fn
      ^target_plug -> true
      {^target_plug, _} -> true
      _ -> false
    end)
  end

  defp format_errors([]), do: :unknown_error
  defp format_errors([error]), do: format_error(error)

  defp format_errors(errors) do
    %{
      errors: Enum.map(errors, &format_error/1),
      count: length(errors)
    }
  end

  defp format_error(%{message: message}), do: message
  defp format_error(%{error: error}), do: error
  defp format_error(error), do: error
end
