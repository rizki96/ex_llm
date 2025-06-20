defmodule ExLLM.Infrastructure.LoggerMacros do
  @moduledoc """
  Dialyzer-friendly logger macros that wrap Elixir's Logger.
  """

  defmacro __using__(_opts) do
    quote do
      import ExLLM.Infrastructure.LoggerMacros
      
      # Import everything except the problematic macros
      import Logger, except: [debug: 1, debug: 2, info: 1, info: 2, 
                             warning: 1, warning: 2, warn: 1, warn: 2,
                             error: 1, error: 2]
    end
  end

  defmacro log_debug(message, metadata \\ []) do
    quote do
      require Logger
      Logger.debug(unquote(message), unquote(metadata))
    end
  end

  defmacro log_info(message, metadata \\ []) do
    quote do
      require Logger
      Logger.info(unquote(message), unquote(metadata))
    end
  end

  defmacro log_warning(message, metadata \\ []) do
    quote do
      require Logger
      Logger.warning(unquote(message), unquote(metadata))
    end
  end

  defmacro log_error(message, metadata \\ []) do
    quote do
      require Logger
      Logger.error(unquote(message), unquote(metadata))
    end
  end
end