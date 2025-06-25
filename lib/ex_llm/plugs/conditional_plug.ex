defmodule ExLLM.Plugs.ConditionalPlug do
  @moduledoc """
  A plug that conditionally executes one of two plugs based on a condition.

  This allows dynamic pipeline behavior based on request properties.

  ## Options

  - `:condition` - A function that takes the request and returns a boolean
  - `:if_true` - The plug to execute if the condition is true
  - `:if_false` - The plug to execute if the condition is false

  ## Example

      {ConditionalPlug, [
        condition: fn request -> request.options[:stream] == true end,
        if_true: {ExecuteStreamRequest, []},
        if_false: {ExecuteRequest, []}
      ]}
  """

  use ExLLM.Plug

  @impl true
  def init(opts) do
    unless Keyword.has_key?(opts, :condition) do
      raise ArgumentError, "ConditionalPlug requires a :condition option"
    end

    unless Keyword.has_key?(opts, :if_true) and Keyword.has_key?(opts, :if_false) do
      raise ArgumentError, "ConditionalPlug requires both :if_true and :if_false options"
    end

    opts
  end

  @impl true
  def call(request, opts) do
    condition_fn = opts[:condition]

    if condition_fn.(request) do
      {plug_module, plug_opts} = opts[:if_true]
      plug_module.call(request, plug_module.init(plug_opts))
    else
      {plug_module, plug_opts} = opts[:if_false]
      plug_module.call(request, plug_module.init(plug_opts))
    end
  end
end
