defmodule ExLLM.Pipeline.Request do
  @moduledoc """
  The core request structure that flows through the ExLLM pipeline.

  Similar to Plug.Conn but designed specifically for LLM operations. This struct
  carries all the data needed throughout the request lifecycle, from initial user
  input through to the final response.

  ## Fields

    * `:id` - Unique identifier for this request
    * `:provider` - The LLM provider atom (e.g., `:openai`, `:anthropic`)
    * `:messages` - List of message maps for the conversation
    * `:options` - User-provided options for this request
    * `:config` - Merged configuration from all sources
    * `:halted` - Whether the pipeline should stop processing
    * `:state` - Current state of the request (`:pending`, `:executing`, `:completed`, `:error`)
    * `:tesla_client` - The configured Tesla HTTP client
    * `:provider_request` - The formatted request body for the provider
    * `:response` - Raw response from the provider
    * `:result` - Parsed result in ExLLM format
    * `:assigns` - Map for inter-plug communication
    * `:private` - Map for internal/private data
    * `:metadata` - Request metadata (timing, tokens, cost)
    * `:errors` - List of errors encountered
    * `:stream_pid` - PID of streaming process if applicable
    * `:stream_ref` - Reference for streaming process
  """

  @type state :: :pending | :executing | :streaming | :completed | :error

  @type t :: %__MODULE__{
          # Request identification
          id: String.t(),
          provider: atom(),

          # Core request data
          messages: list(map()),
          options: map(),

          # Configuration (merged from various sources)
          config: map(),

          # Pipeline state
          halted: boolean(),
          state: state(),

          # Provider-specific  
          tesla_client: term() | nil,
          provider_request: map() | nil,

          # Response data
          response: term() | nil,
          result: term() | nil,

          # Extensibility
          assigns: map(),
          private: map(),

          # Tracking
          metadata: map(),
          errors: list(map()),

          # Streaming
          stream_pid: pid() | nil,
          stream_ref: reference() | nil
        }

  @enforce_keys [:id, :provider, :messages]
  defstruct [
    :id,
    :provider,
    messages: [],
    options: %{},
    config: %{},
    halted: false,
    state: :pending,
    tesla_client: nil,
    provider_request: nil,
    response: nil,
    result: nil,
    assigns: %{},
    private: %{},
    metadata: %{
      start_time: nil,
      end_time: nil,
      duration_ms: nil,
      tokens_used: %{},
      cost: nil
    },
    errors: [],
    stream_pid: nil,
    stream_ref: nil
  ]

  @doc """
  Creates a new request with a unique ID.

  ## Examples

      iex> request = ExLLM.Pipeline.Request.new(:openai, [%{role: "user", content: "Hello"}])
      iex> request.provider
      :openai
      iex> request.state
      :pending
  """
  @spec new(atom(), list(map()), map() | keyword()) :: t()
  def new(provider, messages, options \\ %{}) do
    %__MODULE__{
      id: generate_id(),
      provider: provider,
      messages: messages,
      options: normalize_options(options),
      state: :pending
    }
  end

  # Convert options to map format to ensure consistency
  defp normalize_options(options) when is_map(options), do: options

  defp normalize_options(options) when is_list(options) do
    if Keyword.keyword?(options) do
      Enum.into(options, %{})
    else
      %{}
    end
  end

  defp normalize_options(_), do: %{}

  @doc """
  Halts the pipeline execution.

  When a request is halted, no further plugs in the pipeline will be executed.

  ## Examples

      iex> request = ExLLM.Pipeline.Request.new(:openai, [])
      iex> halted_request = ExLLM.Pipeline.Request.halt(request)
      iex> halted_request.halted
      true
  """
  @spec halt(t()) :: t()
  def halt(%__MODULE__{} = request) do
    %{request | halted: true}
  end

  @doc """
  Assigns a value to the request.

  Assigns are meant to be used as a storage mechanism for inter-plug communication.
  The assigns storage is meant to be used by libraries and frameworks to avoid writing 
  to the request struct directly.

  ## Examples

      iex> request = ExLLM.Pipeline.Request.new(:openai, [])
      iex> request = ExLLM.Pipeline.Request.assign(request, :auth_token, "secret")
      iex> request.assigns.auth_token
      "secret"
  """
  @spec assign(t(), atom(), any()) :: t()
  def assign(%__MODULE__{} = request, key, value) when is_atom(key) do
    %{request | assigns: Map.put(request.assigns, key, value)}
  end

  @doc """
  Assigns multiple values to the request.

  ## Examples

      iex> request = ExLLM.Pipeline.Request.new(:openai, [])
      iex> request = ExLLM.Pipeline.Request.assign(request, auth: "token", model: "gpt-4")
      iex> request.assigns
      %{auth: "token", model: "gpt-4"}
  """
  @spec assign(t(), keyword() | map()) :: t()
  def assign(%__MODULE__{} = request, assigns) when is_list(assigns) or is_map(assigns) do
    Enum.reduce(assigns, request, fn {k, v}, acc ->
      assign(acc, k, v)
    end)
  end

  @doc """
  Puts private data in the request.

  Private data is meant for internal use by the pipeline infrastructure and should
  not be accessed by plugs or external code.

  ## Examples

      iex> request = ExLLM.Pipeline.Request.new(:openai, [])
      iex> request = ExLLM.Pipeline.Request.put_private(request, :internal_flag, true)
      iex> request.private.internal_flag
      true
  """
  @spec put_private(t(), atom(), any()) :: t()
  def put_private(%__MODULE__{} = request, key, value) when is_atom(key) do
    %{request | private: Map.put(request.private, key, value)}
  end

  @doc """
  Updates the request state.

  ## Examples

      iex> request = ExLLM.Pipeline.Request.new(:openai, [])
      iex> request = ExLLM.Pipeline.Request.put_state(request, :executing)
      iex> request.state
      :executing
  """
  @spec put_state(t(), state()) :: t()
  def put_state(%__MODULE__{} = request, state)
      when state in [:pending, :executing, :streaming, :completed, :error] do
    %{request | state: state}
  end

  @doc """
  Adds an error to the request.

  Errors are accumulated in a list and can be inspected after pipeline execution.
  Adding an error does not automatically halt the pipeline - use `halt/1` for that.

  ## Examples

      iex> request = ExLLM.Pipeline.Request.new(:openai, [])
      iex> error = %{plug: MyPlug, reason: :api_error, message: "API key invalid"}
      iex> request = ExLLM.Pipeline.Request.add_error(request, error)
      iex> length(request.errors)
      1
  """
  @spec add_error(t(), map()) :: t()
  def add_error(%__MODULE__{} = request, error) when is_map(error) do
    %{request | errors: [error | request.errors]}
  end

  @doc """
  Adds an error and halts the request in one operation.

  This is a convenience function that combines `add_error/2` and `halt/1`.

  ## Examples

      iex> request = ExLLM.Pipeline.Request.new(:openai, [])
      iex> error = %{reason: :invalid_provider}
      iex> request = ExLLM.Pipeline.Request.halt_with_error(request, error)
      iex> request.halted
      true
      iex> length(request.errors)
      1
  """
  @spec halt_with_error(t(), map()) :: t()
  def halt_with_error(%__MODULE__{} = request, error) when is_map(error) do
    request
    |> add_error(error)
    |> halt()
    |> put_state(:error)
  end

  @doc """
  Updates metadata for the request.

  ## Examples

      iex> request = ExLLM.Pipeline.Request.new(:openai, [])
      iex> request = ExLLM.Pipeline.Request.put_metadata(request, :tokens, 100)
      iex> request.metadata.tokens
      100
  """
  @spec put_metadata(t(), atom(), any()) :: t()
  def put_metadata(%__MODULE__{} = request, key, value) when is_atom(key) do
    %{request | metadata: Map.put(request.metadata, key, value)}
  end

  @doc """
  Merges a map into the request metadata.

  ## Examples

      iex> request = ExLLM.Pipeline.Request.new(:openai, [])
      iex> request = ExLLM.Pipeline.Request.merge_metadata(request, %{tokens: 100, cost: 0.02})
      iex> request.metadata
      %{tokens: 100, cost: 0.02, start_time: nil, end_time: nil, duration_ms: nil, tokens_used: %{}}
  """
  @spec merge_metadata(t(), map()) :: t()
  def merge_metadata(%__MODULE__{} = request, metadata) when is_map(metadata) do
    %{request | metadata: Map.merge(request.metadata, metadata)}
  end

  # Private functions

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
