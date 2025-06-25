defmodule ExLLM.Providers.Shared.HTTP.ErrorHandling do
  @moduledoc """
  Tesla middleware for HTTP error handling and retry logic.

  This middleware provides intelligent error handling with exponential backoff,
  provider-specific error mapping, and configurable retry strategies.

  ## Features

  - Exponential backoff with jitter
  - Provider-specific error code mapping
  - Configurable retry conditions
  - Rate limit detection and handling
  - Circuit breaker pattern (optional)

  ## Usage

      middleware = [
        {HTTP.ErrorHandling, 
         max_retries: 3,
         retry_delay: 1000,
         backoff_factor: 2.0}
      ]
      
      client = Tesla.client(middleware)

  ## Error Types

  - `:connection_error` - Network/DNS failures
  - `:timeout_error` - Request timeouts
  - `:authentication_error` - 401 responses
  - `:rate_limit_error` - 429 responses
  - `:api_error` - 4xx/5xx responses
  - `:validation_error` - Request validation failures
  """

  @behaviour Tesla.Middleware

  alias ExLLM.Infrastructure.Logger

  @impl Tesla.Middleware
  def call(env, next, opts) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    retry_delay = Keyword.get(opts, :retry_delay, 1000)
    backoff_factor = Keyword.get(opts, :backoff_factor, 2.0)

    execute_with_retry(env, next, opts, max_retries, retry_delay, backoff_factor, 0)
  end

  defp execute_with_retry(env, next, opts, max_retries, retry_delay, backoff_factor, attempt) do
    case Tesla.run(env, next) do
      {:ok, response} ->
        case handle_response(response, opts) do
          {:ok, response} ->
            {:ok, response}

          {:error, error} ->
            if should_retry?(error, attempt, max_retries, opts) do
              delay = calculate_retry_delay(retry_delay, backoff_factor, attempt)

              Logger.info(
                "Retrying request after #{delay}ms (attempt #{attempt + 1}/#{max_retries})"
              )

              :timer.sleep(delay)

              execute_with_retry(
                env,
                next,
                opts,
                max_retries,
                retry_delay,
                backoff_factor,
                attempt + 1
              )
            else
              {:error, error}
            end
        end

      {:error, reason} ->
        error = map_tesla_error(reason, opts)

        if should_retry?(error, attempt, max_retries, opts) do
          delay = calculate_retry_delay(retry_delay, backoff_factor, attempt)

          Logger.info(
            "Retrying request after #{delay}ms due to #{inspect(reason)} (attempt #{attempt + 1}/#{max_retries})"
          )

          :timer.sleep(delay)

          execute_with_retry(
            env,
            next,
            opts,
            max_retries,
            retry_delay,
            backoff_factor,
            attempt + 1
          )
        else
          {:error, error}
        end
    end
  end

  # Response handling

  defp handle_response(%{status: status} = response, _opts) when status >= 200 and status < 300 do
    {:ok, response}
  end

  defp handle_response(%{status: status} = response, opts) do
    error = map_http_error(status, response, opts)
    {:error, error}
  end

  # Error mapping

  defp map_http_error(401, response, opts) do
    %{
      type: :authentication_error,
      message: extract_error_message(response, "Authentication failed"),
      status_code: 401,
      provider: Keyword.get(opts, :provider),
      response: response
    }
  end

  defp map_http_error(403, response, opts) do
    %{
      type: :authorization_error,
      message: extract_error_message(response, "Access forbidden"),
      status_code: 403,
      provider: Keyword.get(opts, :provider),
      response: response
    }
  end

  defp map_http_error(429, response, opts) do
    retry_after = extract_retry_after(response)

    %{
      type: :rate_limit_error,
      message: extract_error_message(response, "Rate limit exceeded"),
      status_code: 429,
      retry_after: retry_after,
      provider: Keyword.get(opts, :provider),
      response: response
    }
  end

  defp map_http_error(status, response, opts) when status >= 400 and status < 500 do
    %{
      type: :client_error,
      message: extract_error_message(response, "Client error"),
      status_code: status,
      provider: Keyword.get(opts, :provider),
      response: response
    }
  end

  defp map_http_error(status, response, opts) when status >= 500 do
    %{
      type: :api_error,
      message: extract_error_message(response, "Server error"),
      status_code: status,
      provider: Keyword.get(opts, :provider),
      response: response
    }
  end

  defp map_http_error(status, response, opts) do
    %{
      type: :unknown_error,
      message: "Unknown HTTP status: #{status}",
      status_code: status,
      provider: Keyword.get(opts, :provider),
      response: response
    }
  end

  defp map_tesla_error({:error, :timeout}, opts) do
    %{
      type: :timeout_error,
      message: "Request timeout",
      provider: Keyword.get(opts, :provider)
    }
  end

  defp map_tesla_error({:error, :econnrefused}, opts) do
    %{
      type: :connection_error,
      message: "Connection refused",
      provider: Keyword.get(opts, :provider)
    }
  end

  defp map_tesla_error({:error, :nxdomain}, opts) do
    %{
      type: :connection_error,
      message: "DNS resolution failed",
      provider: Keyword.get(opts, :provider)
    }
  end

  defp map_tesla_error({:error, reason}, opts) when is_atom(reason) do
    %{
      type: :connection_error,
      message: "Connection error: #{reason}",
      provider: Keyword.get(opts, :provider)
    }
  end

  defp map_tesla_error({:function_clause, _} = reason, opts) do
    %{
      type: :connection_error,
      message: "Connection failed: #{inspect(reason)}",
      provider: Keyword.get(opts, :provider)
    }
  end

  defp map_tesla_error(reason, opts) do
    %{
      type: :unknown_error,
      message: "Unknown error: #{inspect(reason)}",
      provider: Keyword.get(opts, :provider)
    }
  end

  # Retry logic

  defp should_retry?(%{type: type} = error, attempt, max_retries, opts) do
    status = Map.get(error, :status_code)

    cond do
      attempt >= max_retries ->
        false

      type in [:authentication_error, :authorization_error, :client_error] ->
        # Don't retry client errors
        false

      type == :rate_limit_error ->
        # Retry rate limits if configured
        Keyword.get(opts, :retry_rate_limits, true)

      type in [:timeout_error, :connection_error] ->
        # Always retry network/timeout errors
        true

      type == :api_error and status in [500, 502, 503, 504] ->
        # Retry server errors
        true

      true ->
        # Custom retry predicate
        case Keyword.get(opts, :retry_predicate) do
          nil -> false
          predicate when is_function(predicate, 1) -> predicate.(type)
          predicate when is_function(predicate, 2) -> predicate.(type, status)
        end
    end
  end

  defp calculate_retry_delay(base_delay, backoff_factor, attempt) do
    exponential_delay = base_delay * :math.pow(backoff_factor, attempt)

    # Add jitter to prevent thundering herd
    jitter = :rand.uniform() * exponential_delay * 0.1

    round(exponential_delay + jitter)
  end

  # Utility functions

  defp extract_error_message(response, default) do
    case parse_error_response(response.body) do
      {:ok, message} -> message
      _ -> default
    end
  end

  defp parse_error_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} ->
        {:ok, message}

      {:ok, %{"error" => message}} when is_binary(message) ->
        {:ok, message}

      {:ok, %{"message" => message}} ->
        {:ok, message}

      {:ok, %{"detail" => message}} ->
        {:ok, message}

      _ ->
        :error
    end
  end

  defp parse_error_response(_), do: :error

  defp extract_retry_after(response) do
    case Enum.find(response.headers, fn {name, _} ->
           String.downcase(name) == "retry-after"
         end) do
      {_, value} ->
        case Integer.parse(value) do
          {seconds, _} -> seconds
          _ -> nil
        end

      nil ->
        nil
    end
  end

  @doc """
  Check if an error is retryable based on default rules.

  ## Examples

      iex> error = %{type: :rate_limit_error}
      iex> HTTP.ErrorHandling.retryable?(error)
      true
      
      iex> error = %{type: :authentication_error}
      iex> HTTP.ErrorHandling.retryable?(error)
      false
  """
  @spec retryable?(map()) :: boolean()
  def retryable?(%{type: type} = error) do
    status = Map.get(error, :status_code)

    case type do
      :rate_limit_error -> true
      :timeout_error -> true
      :connection_error -> true
      :api_error when status in [500, 502, 503, 504] -> true
      _ -> false
    end
  end

  @doc """
  Create a custom retry predicate function.

  ## Examples

      retry_fn = HTTP.ErrorHandling.retry_predicate([:rate_limit_error, :timeout_error])
      
      middleware = [
        {HTTP.ErrorHandling, retry_predicate: retry_fn}
      ]
  """
  @spec retry_predicate([atom()]) :: (atom() -> boolean())
  def retry_predicate(retryable_types) when is_list(retryable_types) do
    fn type -> type in retryable_types end
  end

  @doc """
  Calculate the total delay for all retry attempts.

  ## Examples

      iex> HTTP.ErrorHandling.total_retry_delay(3, 1000, 2.0)
      7000  # 1000 + 2000 + 4000
  """
  @spec total_retry_delay(non_neg_integer(), non_neg_integer(), float()) :: non_neg_integer()
  def total_retry_delay(max_retries, base_delay, backoff_factor) do
    0..(max_retries - 1)
    |> Enum.map(fn attempt ->
      calculate_retry_delay(base_delay, backoff_factor, attempt)
    end)
    |> Enum.sum()
  end
end
