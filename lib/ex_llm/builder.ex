defmodule ExLLM.Builder do
  @moduledoc """
  Chat Builder API for ExLLM.

  This module provides a fluent builder interface for constructing and executing
  LLM chat requests. The builder pattern allows you to chain configuration calls
  and provides fine-grained control over pipeline execution.

  ## Features

  - **Fluent Interface**: Chain configuration calls for readable code
  - **Pipeline Control**: Fine-grained control over the execution pipeline
  - **Custom Plugs**: Add custom processing steps to the pipeline
  - **Context Management**: Configure context strategies and caching
  - **Debugging Support**: Inspect pipeline and builder state

  ## Examples

      # Basic builder usage
      {:ok, response} = 
        ExLLM.Builder.build(:openai, messages)
        |> ExLLM.Builder.with_model("gpt-4")
        |> ExLLM.Builder.with_temperature(0.7)
        |> ExLLM.Builder.execute()
        
      # Advanced configuration
      {:ok, response} = 
        ExLLM.Builder.build(:anthropic, messages)
        |> ExLLM.Builder.with_model("claude-3-opus")
        |> ExLLM.Builder.with_cache(ttl: 3600)
        |> ExLLM.Builder.with_context_strategy(:smart, max_tokens: 8000)
        |> ExLLM.Builder.execute()
        
      # Streaming with builder
      stream = 
        ExLLM.Builder.build(:openai, messages)
        |> ExLLM.Builder.with_model("gpt-4")
        |> ExLLM.Builder.stream(fn chunk -> IO.write(chunk.content) end)
  """

  alias ExLLM.ChatBuilder

  @doc """
  Create a new chat builder for the specified provider and messages.

  This is the entry point for the builder API. Creates a ChatBuilder struct
  that can be configured with additional method calls.

  ## Parameters

    * `provider` - The LLM provider atom (e.g., `:openai`, `:anthropic`)
    * `messages` - List of message maps with `:role` and `:content`

  ## Examples

      builder = ExLLM.Builder.build(:openai, [
        %{role: "user", content: "Hello!"}
      ])

  ## Returns

  Returns a `ChatBuilder` struct that can be further configured with other
  builder functions.
  """
  @spec build(atom(), list()) :: ChatBuilder.t()
  def build(provider, messages) do
    ChatBuilder.new(provider, messages)
  end

  @doc """
  Set the model for the chat request.

  ## Parameters

    * `builder` - The ChatBuilder struct
    * `model` - Model identifier string (e.g., "gpt-4", "claude-3-opus")

  ## Examples

      builder
      |> ExLLM.Builder.with_model("gpt-4")

  ## Returns

  Returns the updated ChatBuilder struct.
  """
  @spec with_model(ChatBuilder.t(), String.t()) :: ChatBuilder.t()
  def with_model(builder, model) do
    ChatBuilder.with_model(builder, model)
  end

  @doc """
  Set the temperature for controlling randomness.

  ## Parameters

    * `builder` - The ChatBuilder struct
    * `temperature` - Float between 0.0 (deterministic) and 2.0 (very random)

  ## Examples

      builder
      |> ExLLM.Builder.with_temperature(0.7)

  ## Returns

  Returns the updated ChatBuilder struct.
  """
  @spec with_temperature(ChatBuilder.t(), float()) :: ChatBuilder.t()
  def with_temperature(builder, temperature) do
    ChatBuilder.with_temperature(builder, temperature)
  end

  @doc """
  Set the maximum number of tokens in the response.

  ## Parameters

    * `builder` - The ChatBuilder struct
    * `max_tokens` - Maximum tokens to generate (integer)

  ## Examples

      builder
      |> ExLLM.Builder.with_max_tokens(1000)

  ## Returns

  Returns the updated ChatBuilder struct.
  """
  @spec with_max_tokens(ChatBuilder.t(), integer()) :: ChatBuilder.t()
  def with_max_tokens(builder, max_tokens) do
    ChatBuilder.with_max_tokens(builder, max_tokens)
  end

  @doc """
  Add a custom plug to the pipeline.

  Allows insertion of custom processing steps at specific points in the
  execution pipeline.

  ## Parameters

    * `builder` - The ChatBuilder struct
    * `plug` - The plug module or {module, options} tuple
    * `opts` - Additional plug options

  ## Examples

      builder
      |> ExLLM.Builder.with_plug(MyCustomPlug, position: :before_request)

  ## Returns

  Returns the updated ChatBuilder struct.
  """
  @spec with_plug(ChatBuilder.t(), module() | {module(), keyword()}, keyword()) :: ChatBuilder.t()
  def with_plug(builder, plug, opts \\ []) do
    ChatBuilder.with_custom_plug(builder, plug, opts)
  end

  @doc """
  Execute the chat request with the configured builder.

  Runs the complete pipeline with all configured options and returns
  the response from the LLM provider.

  ## Parameters

    * `builder` - The configured ChatBuilder struct

  ## Examples

      {:ok, response} = 
        builder
        |> ExLLM.Builder.execute()

  ## Returns

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  """
  @spec execute(ChatBuilder.t()) :: {:ok, term()} | {:error, term()}
  def execute(builder) do
    ChatBuilder.execute(builder)
  end

  @doc """
  Stream the chat request with the configured builder.

  Executes the request in streaming mode, calling the provided callback
  function for each chunk of the response.

  ## Parameters

    * `builder` - The configured ChatBuilder struct
    * `callback` - Function to call for each streaming chunk

  ## Examples

      stream = 
        builder
        |> ExLLM.Builder.stream(fn chunk -> IO.write(chunk.content) end)

  ## Returns

  Returns a stream that can be consumed to get response chunks.
  """
  @spec stream(ChatBuilder.t(), function()) :: Enumerable.t()
  def stream(builder, callback) do
    ChatBuilder.stream(builder, callback)
  end

  @doc """
  Enable response caching with optional TTL.

  Caches responses to improve performance and reduce costs for repeated
  requests with identical parameters.

  ## Parameters

    * `builder` - The ChatBuilder struct
    * `opts` - Caching options

  ## Options

    * `:ttl` - Time-to-live in seconds (default: 3600)
    * `:key` - Custom cache key (optional)

  ## Examples

      builder
      |> ExLLM.Builder.with_cache(ttl: 1800)

  ## Returns

  Returns the updated ChatBuilder struct.
  """
  @spec with_cache(ChatBuilder.t(), keyword()) :: ChatBuilder.t()
  def with_cache(builder, opts \\ []) do
    ChatBuilder.with_cache(builder, opts)
  end

  @doc """
  Disable response caching.

  Ensures that the request bypasses any caching mechanisms and always
  makes a fresh request to the provider.

  ## Parameters

    * `builder` - The ChatBuilder struct

  ## Examples

      builder
      |> ExLLM.Builder.without_cache()

  ## Returns

  Returns the updated ChatBuilder struct.
  """
  @spec without_cache(ChatBuilder.t()) :: ChatBuilder.t()
  def without_cache(builder) do
    ChatBuilder.without_cache(builder)
  end

  @doc """
  Disable cost tracking for this request.

  Skips cost calculation and tracking, which can improve performance
  for high-volume scenarios where cost tracking is not needed.

  ## Parameters

    * `builder` - The ChatBuilder struct

  ## Examples

      builder
      |> ExLLM.Builder.without_cost_tracking()

  ## Returns

  Returns the updated ChatBuilder struct.
  """
  @spec without_cost_tracking(ChatBuilder.t()) :: ChatBuilder.t()
  def without_cost_tracking(builder) do
    ChatBuilder.without_cost_tracking(builder)
  end

  @doc """
  Add a custom plug to the pipeline.

  Alternative name for `with_plug/3` for backward compatibility.

  ## Parameters

    * `builder` - The ChatBuilder struct
    * `plug` - The plug module or {module, options} tuple
    * `opts` - Additional plug options

  ## Examples

      builder
      |> ExLLM.Builder.with_custom_plug(MyPlug, priority: :high)

  ## Returns

  Returns the updated ChatBuilder struct.
  """
  @spec with_custom_plug(ChatBuilder.t(), module() | {module(), keyword()}, keyword()) ::
          ChatBuilder.t()
  def with_custom_plug(builder, plug, opts \\ []) do
    ChatBuilder.with_custom_plug(builder, plug, opts)
  end

  @doc """
  Configure context management strategy.

  Sets how the builder handles message context when it exceeds model limits.

  ## Parameters

    * `builder` - The ChatBuilder struct
    * `strategy` - Strategy atom (`:sliding_window`, `:smart`, `:truncate`)
    * `opts` - Strategy-specific options

  ## Strategies

    * `:sliding_window` - Keep recent messages, drop old ones
    * `:smart` - Intelligently preserve important messages
    * `:truncate` - Simple truncation from the beginning

  ## Examples

      builder
      |> ExLLM.Builder.with_context_strategy(:smart, preserve_system: true)

  ## Returns

  Returns the updated ChatBuilder struct.
  """
  @spec with_context_strategy(ChatBuilder.t(), atom(), keyword()) :: ChatBuilder.t()
  def with_context_strategy(builder, strategy, opts \\ []) do
    ChatBuilder.with_context_strategy(builder, strategy, opts)
  end

  @doc """
  Get the execution pipeline for debugging purposes.

  Returns the internal pipeline that will be used to execute the request.
  Useful for debugging and understanding the request flow.

  ## Parameters

    * `builder` - The ChatBuilder struct

  ## Examples

      pipeline = ExLLM.Builder.inspect_pipeline(builder)
      IO.inspect(pipeline)

  ## Returns

  Returns the pipeline struct that will be used for execution.
  """
  @spec inspect_pipeline(ChatBuilder.t()) :: term()
  def inspect_pipeline(builder) do
    ChatBuilder.inspect_pipeline(builder)
  end

  @doc """
  Get debug information about the builder state.

  Returns detailed information about the current builder configuration,
  including all set options and internal state.

  ## Parameters

    * `builder` - The ChatBuilder struct

  ## Examples

      debug_info = ExLLM.Builder.debug_info(builder)
      IO.inspect(debug_info)

  ## Returns

  Returns a map with debug information about the builder state.
  """
  @spec debug_info(ChatBuilder.t()) :: map()
  def debug_info(builder) do
    ChatBuilder.debug_info(builder)
  end
end
