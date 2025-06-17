defmodule ExLLM.Infrastructure.Error do
  @moduledoc """
  Standardized error types and utilities for ExLLM.

  This module defines consistent error patterns used throughout ExLLM
  to provide predictable error handling for library consumers.

  ## Error Patterns

  All functions should return either `{:ok, result}` or `{:error, reason}`.

  Error reasons follow these patterns:

  ### Simple Errors (atoms)
  - `:not_found` - Resource not found
  - `:not_connected` - Connection not established
  - `:invalid_config` - Configuration is invalid
  - `:not_configured` - Required configuration missing
  - `:timeout` - Operation timed out
  - `:unauthorized` - Authentication failed

  ### Complex Errors (tuples)
  - `{:api_error, details}` - API call failed
  - `{:validation, field, message}` - Validation failed
  - `{:connection_failed, reason}` - Connection failure
  - `{:json_parse_error, reason}` - JSON parsing failed

  ## Examples

      # Simple error
      {:error, :not_found}

      # API error with details
      {:error, {:api_error, %{status: 404, body: "Not found"}}}

      # Validation error
      {:error, {:validation, :name, "cannot be empty"}}

      # Connection error
      {:error, {:connection_failed, :timeout}}
  """

  @type simple_error ::
          :not_found
          | :not_connected
          | :invalid_config
          | :not_configured
          | :timeout
          | :unauthorized
          | :no_token_usage
          | :server_not_found
          | :unsupported_format

  @type complex_error ::
          {:api_error, map()}
          | {:validation, atom(), String.t()}
          | {:connection_failed, term()}
          | {:json_parse_error, term()}
          | {:invalid_file_type, term()}

  @type error_reason :: simple_error() | complex_error()

  @type result(success_type) :: {:ok, success_type} | {:error, error_reason()}

  @doc """
  Creates a standardized API error.

  ## Parameters
  - `status` - HTTP status code
  - `body` - Response body (string or map)

  ## Returns
  API error tuple
  """
  @spec api_error(integer(), term()) :: {:error, {:api_error, map()}}
  def api_error(status, body) do
    {:error, {:api_error, %{status: status, body: body}}}
  end

  @doc """
  Creates a standardized validation error.

  ## Parameters
  - `field` - Field name (atom)
  - `message` - Error message (string)

  ## Returns
  Validation error tuple
  """
  @spec validation_error(atom(), String.t()) :: {:error, {:validation, atom(), String.t()}}
  def validation_error(field, message) do
    {:error, {:validation, field, message}}
  end

  @doc """
  Creates a standardized connection failure error.

  ## Parameters
  - `reason` - Underlying failure reason

  ## Returns
  Connection error tuple
  """
  @spec connection_error(term()) :: {:error, {:connection_failed, term()}}
  def connection_error(reason) do
    {:error, {:connection_failed, reason}}
  end

  @doc """
  Creates a standardized JSON parsing error.

  ## Parameters
  - `reason` - JSON parsing failure reason

  ## Returns
  JSON parse error tuple
  """
  @spec json_parse_error(term()) :: {:error, {:json_parse_error, term()}}
  def json_parse_error(reason) do
    {:error, {:json_parse_error, reason}}
  end

  @doc """
  Checks if a value is an error tuple.

  ## Parameters
  - `value` - Value to check

  ## Returns
  Boolean indicating if value is an error tuple
  """
  @spec error?(term()) :: boolean()
  def error?({:error, _}), do: true
  def error?(_), do: false

  @doc """
  Extracts error reason from error tuple.

  ## Parameters
  - `error_tuple` - Error tuple

  ## Returns
  Error reason or nil if not an error tuple
  """
  @spec get_error_reason({:error, error_reason()} | term()) :: error_reason() | nil
  def get_error_reason({:error, reason}), do: reason
  def get_error_reason(_), do: nil

  @doc """
  Creates a standardized authentication error.

  ## Parameters
  - `message` - Error message

  ## Returns
  Authentication error
  """
  @spec authentication_error(String.t()) :: {:error, {:authentication_error, String.t()}}
  def authentication_error(message) do
    {:error, {:authentication_error, message}}
  end

  @doc """
  Creates a standardized rate limit error.

  ## Parameters
  - `message` - Error message

  ## Returns
  Rate limit error
  """
  @spec rate_limit_error(String.t()) :: {:error, {:rate_limit_error, String.t()}}
  def rate_limit_error(message) do
    {:error, {:rate_limit_error, message}}
  end

  @doc """
  Creates a standardized unknown error.

  ## Parameters
  - `reason` - Error reason

  ## Returns
  Unknown error
  """
  @spec unknown_error(term()) :: {:error, {:unknown_error, term()}}
  def unknown_error(reason) do
    {:error, {:unknown_error, reason}}
  end

  @doc """
  Creates a service unavailable error.

  ## Parameters
  - `message` - Error message

  ## Returns
  Service unavailable error
  """
  @spec service_unavailable(String.t()) :: {:error, {:service_unavailable, String.t()}}
  def service_unavailable(message) do
    {:error, {:service_unavailable, message}}
  end
end
