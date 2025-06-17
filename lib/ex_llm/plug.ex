defmodule ExLLM.Plug do
  @moduledoc """
  The behaviour that all ExLLM pipeline plugs must implement.

  An ExLLM plug is a module that implements two functions:

    * `init/1` - Initializes the plug options at compile time or runtime
    * `call/2` - Performs the plug's logic on the request
    
  ## Example

  Here's a simple plug that adds authentication headers:

      defmodule MyApp.AuthPlug do
        @behaviour ExLLM.Plug
        
        @impl true
        def init(opts) do
          # Validate and prepare options
          Keyword.validate!(opts, [:api_key])
        end
        
        @impl true
        def call(request, opts) do
          api_key = opts[:api_key] || get_api_key_from_config()
          
          request
          |> ExLLM.Pipeline.Request.assign(:auth_header, "Bearer \#{api_key}")
        end
        
        defp get_api_key_from_config do
          Application.get_env(:my_app, :api_key)
        end
      end

  ## Using the `use` macro

  For convenience, you can `use ExLLM.Plug` which will:

    * Add the `@behaviour ExLLM.Plug` annotation
    * Provide default implementations of `init/1` and `call/2`
    * Import helpful functions for working with requests
    
  Example:

      defmodule MyApp.LoggingPlug do
        use ExLLM.Plug
        
        require Logger
        
        @impl true
        def call(request, _opts) do
          Logger.info("Processing request \#{request.id} for provider \#{request.provider}")
          request
        end
      end

  ## Halting the pipeline

  A plug can halt the pipeline by calling `ExLLM.Pipeline.Request.halt/1`:

      def call(request, _opts) do
        if some_condition? do
          request
          |> ExLLM.Pipeline.Request.add_error(%{reason: :unauthorized})
          |> ExLLM.Pipeline.Request.halt()
        else
          request
        end
      end

  When a request is halted, no subsequent plugs in the pipeline will be executed.
  """

  alias ExLLM.Pipeline.Request

  @type opts :: keyword() | map() | any()

  @doc """
  Initializes the plug options.

  This function is called when the plug is first initialized, either at compile time
  (when used in a pipeline module) or at runtime (when added dynamically).

  The return value of this function will be passed as the second argument to `call/2`.

  ## Examples

      def init(opts) do
        Keyword.validate!(opts, [:timeout, :retries])
      end
      
      def init(opts) when is_binary(opts) do
        String.to_atom(opts)
      end
  """
  @callback init(opts) :: opts

  @doc """
  Performs the plug's logic on the request.

  This function receives the current request and the options returned by `init/1`.
  It must return an updated request struct.

  ## Examples

      def call(request, opts) do
        timeout = opts[:timeout] || 5000
        
        request
        |> Request.assign(:timeout, timeout)
        |> Request.put_metadata(:plug_executed, __MODULE__)
      end
  """
  @callback call(request :: Request.t(), opts) :: Request.t()

  @doc """
  Provides default implementations and imports for plugs.

  When you `use ExLLM.Plug`, the following happens:

    * The module is marked with `@behaviour ExLLM.Plug`
    * Default implementations of `init/1` and `call/2` are provided
    * The `ExLLM.Pipeline.Request` module is aliased for convenience
    
  ## Options

    * `:init` - Set to `false` to skip generating a default `init/1` function
    * `:call` - Set to `false` to skip generating a default `call/2` function
    
  ## Examples

      defmodule MyPlug do
        use ExLLM.Plug
        
        @impl true
        def call(request, _opts) do
          # Your plug logic here
          request
        end
      end
      
      defmodule MyConfigurablePlug do
        use ExLLM.Plug, call: false
        
        @impl true
        def init(opts) do
          # Custom initialization
          Keyword.validate!(opts, [:required_option])
        end
        
        @impl true
        def call(request, opts) do
          # Custom logic using validated opts
          request
        end
      end
  """
  defmacro __using__(opts \\ []) do
    opts = Keyword.validate!(opts, init: true, call: true)

    quote do
      @behaviour ExLLM.Plug

      alias ExLLM.Pipeline.Request

      if unquote(opts[:init]) do
        @doc false
        @impl true
        def init(opts), do: opts

        defoverridable init: 1
      end

      if unquote(opts[:call]) do
        @doc false
        @impl true
        def call(request, _opts), do: request

        defoverridable call: 2
      end
    end
  end

  @doc """
  Helper function to run a plug with its initialization.

  This is useful for testing or running plugs outside of a pipeline.

  ## Examples

      iex> request = Request.new(:openai, [%{role: "user", content: "Hello"}])
      iex> ExLLM.Plug.run(request, {MyPlug, timeout: 5000})
      %Request{...}
      
      iex> ExLLM.Plug.run(request, MyPlug)
      %Request{...}
  """
  @spec run(Request.t(), module() | {module(), opts}) :: Request.t()
  def run(%Request{} = request, plug) when is_atom(plug) do
    run(request, {plug, []})
  end

  def run(%Request{} = request, {plug, opts}) when is_atom(plug) do
    initialized_opts = plug.init(opts)
    plug.call(request, initialized_opts)
  end

  @doc """
  Checks if a module implements the ExLLM.Plug behaviour.

  ## Examples

      iex> ExLLM.Plug.plug?(MyApp.AuthPlug)
      true
      
      iex> ExLLM.Plug.plug?(String)
      false
  """
  @spec plug?(module()) :: boolean()
  def plug?(module) when is_atom(module) do
    behaviours =
      module.module_info(:attributes)
      |> Keyword.get(:behaviour, [])

    ExLLM.Plug in behaviours
  end
end
