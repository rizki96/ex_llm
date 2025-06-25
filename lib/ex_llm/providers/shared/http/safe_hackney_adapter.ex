defmodule ExLLM.Providers.Shared.HTTP.SafeHackneyAdapter do
  @moduledoc """
  A wrapper around Tesla.Adapter.Hackney that safely handles all error cases,
  including function clause errors from invalid connection attempts.
  """

  @behaviour Tesla.Adapter

  @impl Tesla.Adapter
  def call(env, opts) do
    try do
      case Tesla.Adapter.Hackney.call(env, opts) do
        {:ok, _} = success -> success
        {:error, _} = error -> error
        other -> {:error, {:unexpected_response, other}}
      end
    rescue
      FunctionClauseError ->
        # Handle cases where hackney returns unexpected error formats
        {:error, :connection_failed}
    catch
      :error, {:function_clause, _} ->
        # Handle function clause errors from hackney
        {:error, :connection_failed}

      kind, reason ->
        # Catch any other unexpected errors
        {:error, {:adapter_error, {kind, reason}}}
    end
  end
end
