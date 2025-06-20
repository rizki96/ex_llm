defmodule ExLLM.Infrastructure.LoggerWrapper do
  @moduledoc """
  A wrapper around Elixir's Logger that uses functions instead of macros.
  This avoids Dialyzer issues with Logger macros while maintaining the same API.
  """

  @doc "Log a debug message"
  def debug(chardata_or_fun, metadata \\ []) do
    if Logger.level() |> Logger.compare_levels(:debug) != :lt do
      Logger.bare_log(:debug, chardata_or_fun, metadata)
    end
  end

  @doc "Log an info message"
  def info(chardata_or_fun, metadata \\ []) do
    if Logger.level() |> Logger.compare_levels(:info) != :lt do
      Logger.bare_log(:info, chardata_or_fun, metadata)
    end
  end

  @doc "Log a warning message"
  def warning(chardata_or_fun, metadata \\ []) do
    if Logger.level() |> Logger.compare_levels(:warning) != :lt do
      Logger.bare_log(:warning, chardata_or_fun, metadata)
    end
  end

  @doc "Log a warning message (alias)"
  def warn(chardata_or_fun, metadata \\ []) do
    warning(chardata_or_fun, metadata)
  end

  @doc "Log an error message"
  def error(chardata_or_fun, metadata \\ []) do
    if Logger.level() |> Logger.compare_levels(:error) != :lt do
      Logger.bare_log(:error, chardata_or_fun, metadata)
    end
  end
end