defmodule ExLLM do
  @moduledoc """
  ExLLM - A unified Elixir client for Large Language Models.

  ExLLM provides a clean, pipeline-based architecture for interacting with various
  LLM providers. The library focuses on two main APIs:

  ## Simple API

  For basic chat completions:

      {:ok, response} = ExLLM.chat(:openai, [
        %{role: "user", content: "Hello!"}
      ])
      
      IO.puts(response.content)
      
  ## Advanced API

  For full control over the pipeline:

      import ExLLM.Pipeline.Request
      
      request = 
        new(:openai, messages)
        |> assign(:temperature, 0.7)
        |> assign(:max_tokens, 1000)
      
      result = ExLLM.run(request, custom_pipeline)
      
  ## Providers

  ExLLM supports 14+ providers including:
  - OpenAI (GPT-4, GPT-3.5)
  - Anthropic (Claude)
  - Google (Gemini)
  - Groq
  - Mistral
  - And many more...

  ## Configuration

  Configure providers in your `config.exs`:

      config :ex_llm, :openai,
        api_key: System.get_env("OPENAI_API_KEY"),
        default_model: "gpt-4"
  """

  alias ExLLM.Pipeline
  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers

  require Logger

  @doc """
  Sends a chat request to the specified provider.

  This is the simple API for basic use cases. For more control,
  use `run/2` with a custom pipeline.

  ## Parameters

    * `provider` - The LLM provider atom (e.g., `:openai`, `:anthropic`)
    * `messages` - List of message maps with `:role` and `:content`
    * `opts` - Optional keyword list of options
    
  ## Options

    * `:model` - Override the default model
    * `:temperature` - Control randomness (0.0 to 2.0)
    * `:max_tokens` - Maximum tokens in response
    * `:stream` - Enable streaming (requires callback function)
    * `:timeout` - Request timeout in milliseconds
    
  ## Examples

      # Simple chat
      {:ok, response} = ExLLM.chat(:openai, [
        %{role: "user", content: "Hello!"}
      ])
      
      # With options
      {:ok, response} = ExLLM.chat(:anthropic, messages,
        model: "claude-3-opus",
        temperature: 0.5,
        max_tokens: 1000
      )
      
  ## Return Values

  Returns `{:ok, response}` on success where response includes:
    * `:content` - The response text
    * `:role` - The role (usually "assistant")
    * `:model` - The model used
    * `:usage` - Token usage information
    * `:cost` - Calculated cost in USD
    
  Returns `{:error, error}` on failure.
  """
  @spec chat(atom(), list(map()), keyword()) :: {:ok, map()} | {:error, term()}
  def chat(provider, messages, opts \\ []) do
    # Build request
    request = Request.new(provider, messages, Enum.into(opts, %{}))

    # Get default pipeline for provider
    pipeline = Providers.get_pipeline(provider, :chat)

    # Run pipeline
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
  Sends a streaming chat request to the specified provider.

  Similar to `chat/3` but streams the response in chunks.

  ## Parameters

    * `provider` - The LLM provider atom
    * `messages` - List of message maps
    * `callback` - Function called for each chunk
    * `opts` - Optional keyword list of options
    
  ## Callback Function

  The callback receives chunks with the following structure:
    * `:content` - The text content of this chunk
    * `:done` - Boolean indicating if streaming is complete
    * `:usage` - Token usage (only in final chunk)
    
  ## Examples

      ExLLM.stream(:openai, messages, fn
        %{done: true, usage: usage} ->
          IO.puts("\\nTotal tokens: \#{usage.total_tokens}")
          
        %{content: content} ->
          IO.write(content)
      end)
  """
  @spec stream(atom(), list(map()), function(), keyword()) :: :ok | {:error, term()}
  def stream(provider, messages, callback, opts \\ []) when is_function(callback, 1) do
    # Add streaming options
    opts = Keyword.merge(opts, stream: true, stream_callback: callback)

    # Build request
    request = Request.new(provider, messages, Enum.into(opts, %{}))

    # Get streaming pipeline for provider
    pipeline = Providers.get_pipeline(provider, :stream)

    # Run pipeline
    case Pipeline.run(request, pipeline) do
      %Request{state: :completed} ->
        :ok

      %Request{state: :error, errors: errors} ->
        {:error, format_errors(errors)}

      %Request{} = failed ->
        {:error, {:pipeline_failed, failed}}
    end
  end

  @doc """
  Runs a custom pipeline on a request.

  This is the advanced API that gives you full control over the
  request processing pipeline.

  ## Parameters

    * `request` - An `ExLLM.Pipeline.Request` struct
    * `pipeline` - List of plug modules or `{module, opts}` tuples
    
  ## Examples

      # Build custom request
      request = ExLLM.Pipeline.Request.new(:openai, messages)
      
      # Define custom pipeline
      pipeline = [
        ExLLM.Plugs.ValidateProvider,
        ExLLM.Plugs.FetchConfig,
        {ExLLM.Plugs.Cache, ttl: 3600},
        MyApp.Plugs.CustomAuth,
        ExLLM.Plugs.ExecuteRequest,
        ExLLM.Plugs.TrackCost
      ]
      
      # Run it
      result = ExLLM.run(request, pipeline)
  """
  @spec run(Request.t(), Pipeline.pipeline()) :: Request.t()
  def run(%Request{} = request, pipeline) when is_list(pipeline) do
    Pipeline.run(request, pipeline)
  end

  @doc """
  Creates a new request builder for the fluent API.

  ## Examples

      ExLLM.build(:openai, messages)
      |> ExLLM.with_model("gpt-4")
      |> ExLLM.with_temperature(0.7)
      |> ExLLM.execute()
  """
  @spec build(atom(), list(map())) :: Request.t()
  def build(provider, messages) do
    Request.new(provider, messages)
  end

  @doc """
  Sets the model for a request.

  ## Examples

      request
      |> ExLLM.with_model("gpt-4-turbo")
  """
  @spec with_model(Request.t(), String.t()) :: Request.t()
  def with_model(%Request{} = request, model) when is_binary(model) do
    update_config(request, :model, model)
  end

  @doc """
  Sets the temperature for a request.

  ## Examples

      request
      |> ExLLM.with_temperature(0.5)
  """
  @spec with_temperature(Request.t(), float()) :: Request.t()
  def with_temperature(%Request{} = request, temperature)
      when is_number(temperature) and temperature >= 0 and temperature <= 2 do
    update_config(request, :temperature, temperature)
  end

  @doc """
  Sets the maximum tokens for a request.

  ## Examples

      request
      |> ExLLM.with_max_tokens(1000)
  """
  @spec with_max_tokens(Request.t(), pos_integer()) :: Request.t()
  def with_max_tokens(%Request{} = request, max_tokens)
      when is_integer(max_tokens) and max_tokens > 0 do
    update_config(request, :max_tokens, max_tokens)
  end

  @doc """
  Adds a custom plug to the pipeline.

  ## Examples

      request
      |> ExLLM.with_plug(MyApp.Plugs.Logger)
      |> ExLLM.with_plug({ExLLM.Plugs.Cache, ttl: 3600})
  """
  @spec with_plug(Request.t(), Pipeline.plug()) :: Request.t()
  def with_plug(%Request{} = request, plug) do
    current_pipeline = request.private[:custom_pipeline] || []
    Request.put_private(request, :custom_pipeline, current_pipeline ++ [plug])
  end

  @doc """
  Executes a request built with the fluent API.

  ## Examples

      {:ok, response} = 
        ExLLM.build(:openai, messages)
        |> ExLLM.with_model("gpt-4")
        |> ExLLM.execute()
  """
  @spec execute(Request.t()) :: {:ok, map()} | {:error, term()}
  def execute(%Request{provider: provider} = request) do
    # Get custom pipeline or default
    pipeline =
      case request.private[:custom_pipeline] do
        nil ->
          Providers.get_pipeline(provider, :chat)

        custom ->
          # Merge custom plugs with default pipeline
          base_pipeline = Providers.get_pipeline(provider, :chat)
          merge_pipelines(base_pipeline, custom)
      end

    # Run pipeline
    case Pipeline.run(request, pipeline) do
      %Request{state: :completed, result: result} ->
        {:ok, result}

      %Request{state: :error, errors: errors} ->
        {:error, format_errors(errors)}

      %Request{} = failed ->
        {:error, {:pipeline_failed, failed}}
    end
  end

  # Private helpers

  defp update_config(%Request{options: options} = request, key, value) do
    %{request | options: Map.put(options, key, value)}
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

  defp merge_pipelines(base, custom) do
    # Simple merge - in real implementation, might want smarter merging
    base ++ custom
  end

  ## Legacy API Support

  @doc false
  @deprecated "Use ExLLM.stream/4 instead"
  def stream_chat(provider, messages, opts \\ %{}) do
    Logger.warning("ExLLM.stream_chat/3 is deprecated. Use ExLLM.stream/4 instead.")

    stream(provider, messages, Map.put(opts, :stream, true), fn chunk ->
      # Default callback that does nothing
      chunk
    end)
  end

  @doc false
  @deprecated "Use provider configuration instead"
  def default_model(provider) do
    case provider do
      :openai -> "gpt-4"
      :anthropic -> "claude-3-5-sonnet-20241022"
      :gemini -> "gemini-2.0-flash-exp"
      :groq -> "llama-3.3-70b-instruct"
      :mistral -> "mistral-large-latest"
      :ollama -> "llama3.2"
      _ -> "unknown"
    end
  end

  @doc false
  @deprecated "Use ExLLM.chat/3 with embeddings pipeline"
  def embeddings(_provider, _input, _opts \\ %{}) do
    {:error, "Embeddings not yet implemented in pipeline architecture"}
  end

  @doc false
  @deprecated "Use provider configuration"
  def list_models(_provider) do
    {:error, "Model listing not yet implemented in pipeline architecture"}
  end
end
