defmodule ExLLM.Cache.Storage do
  @moduledoc """
  Behaviour for cache storage backends.

  This allows ExLLM to support different cache storage mechanisms
  like ETS, Redis, Memcached, etc.
  """

  @doc """
  Initialize the storage backend.
  """
  @callback init(opts :: keyword()) :: {:ok, state :: any()} | {:error, reason :: any()}

  @doc """
  Get a value from the cache.
  """
  @callback get(key :: String.t(), state :: any()) ::
              {:ok, value :: any(), state :: any()} | {:miss, state :: any()}

  @doc """
  Put a value in the cache with expiration time.
  """
  @callback put(key :: String.t(), value :: any(), expires_at :: integer(), state :: any()) ::
              {:ok, state :: any()}

  @doc """
  Delete a key from the cache.
  """
  @callback delete(key :: String.t(), state :: any()) :: {:ok, state :: any()}

  @doc """
  Clear all entries from the cache.
  """
  @callback clear(state :: any()) :: {:ok, state :: any()}

  @doc """
  Get all keys matching a pattern (optional).
  """
  @callback list_keys(pattern :: String.t(), state :: any()) ::
              {:ok, keys :: list(String.t()), state :: any()}

  @doc """
  Get storage info/stats (optional).
  """
  @callback info(state :: any()) :: {:ok, info :: map(), state :: any()}
end
