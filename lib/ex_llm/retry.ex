defmodule ExLLM.Retry do
  @moduledoc """
  Request retry logic with exponential backoff for ExLLM.

  Provides configurable retry mechanisms for failed API requests with
  support for different backoff strategies and retry conditions.

  ## Features

  - Exponential backoff with jitter
  - Configurable retry conditions
  - Per-provider retry policies
  - Circuit breaker pattern
  - Request deduplication

  ## Usage

      # With default retry policy
      ExLLM.Retry.with_retry fn ->
        ExLLM.chat(:openai, messages)
      end
      
      # With custom retry options
      ExLLM.Retry.with_retry fn ->
        ExLLM.chat(:anthropic, messages)
      end,
        max_attempts: 5,
        base_delay: 1000,
        max_delay: 30_000,
        jitter: true
  """

  alias ExLLM.Logger

  @default_max_attempts 3
  # 1 second
  @default_base_delay 1_000
  # 60 seconds
  @default_max_delay 60_000
  @default_multiplier 2

  defmodule RetryPolicy do
    @moduledoc """
    Defines a retry policy for a specific provider or operation.
    """
    defstruct [
      :max_attempts,
      :base_delay,
      :max_delay,
      :multiplier,
      :jitter,
      :retry_on,
      :circuit_breaker
    ]

    @type t :: %__MODULE__{
            max_attempts: non_neg_integer(),
            base_delay: non_neg_integer(),
            max_delay: non_neg_integer(),
            multiplier: number(),
            jitter: boolean(),
            retry_on: (term() -> boolean()) | nil,
            circuit_breaker: map() | nil
          }
  end

  defmodule CircuitBreaker do
    @moduledoc """
    Circuit breaker to prevent cascading failures.
    """
    defstruct [
      :failure_threshold,
      :reset_timeout,
      :half_open_requests,
      :state,
      :failure_count,
      :last_failure_time,
      :success_count
    ]

    @type state :: :closed | :open | :half_open

    @type t :: %__MODULE__{
            failure_threshold: non_neg_integer(),
            reset_timeout: non_neg_integer(),
            half_open_requests: non_neg_integer(),
            state: state(),
            failure_count: non_neg_integer(),
            last_failure_time: DateTime.t() | nil,
            success_count: non_neg_integer()
          }
  end

  @doc """
  Executes a function with retry logic.

  ## Options

  - `:max_attempts` - Maximum number of attempts (default: 3)
  - `:base_delay` - Initial delay in milliseconds (default: 1000)
  - `:max_delay` - Maximum delay in milliseconds (default: 60000)
  - `:multiplier` - Backoff multiplier (default: 2)
  - `:jitter` - Add random jitter to delays (default: true)
  - `:retry_on` - Function to determine if error is retryable
  """
  def with_retry(fun, opts \\ []) do
    policy = build_policy(opts)
    provider = Keyword.get(opts, :provider, :unknown)
    execute_with_retry(fun, policy, 1, provider)
  end

  @doc """
  Executes a function with retry logic for a specific provider.
  """
  def with_provider_retry(provider, fun, opts \\ []) do
    provider_policy = get_provider_policy(provider)
    policy = merge_policies(provider_policy, build_policy(opts))
    execute_with_retry(fun, policy, 1, provider)
  end

  @doc """
  Checks if an error should trigger a retry.
  """
  def should_retry?(error, attempt, policy) do
    cond do
      attempt >= policy.max_attempts -> false
      policy.retry_on != nil -> policy.retry_on.(error)
      true -> default_retry_condition(error)
    end
  end

  @doc """
  Calculates the delay before the next retry attempt.
  """
  def calculate_delay(attempt, policy) do
    base_delay = policy.base_delay * :math.pow(policy.multiplier, attempt - 1)
    delay = min(round(base_delay), policy.max_delay)

    if policy.jitter do
      add_jitter(delay)
    else
      delay
    end
  end

  @doc """
  Default retry policies for providers.
  """
  def get_provider_policy(provider) do
    case provider do
      :openai ->
        %RetryPolicy{
          max_attempts: 3,
          base_delay: 1_000,
          max_delay: 60_000,
          multiplier: 2,
          jitter: true,
          retry_on: &openai_retry_condition/1
        }

      :anthropic ->
        %RetryPolicy{
          max_attempts: 3,
          base_delay: 2_000,
          max_delay: 30_000,
          multiplier: 2,
          jitter: true,
          retry_on: &anthropic_retry_condition/1
        }

      :bedrock ->
        %RetryPolicy{
          max_attempts: 5,
          base_delay: 1_000,
          max_delay: 20_000,
          multiplier: 2,
          jitter: true,
          retry_on: &bedrock_retry_condition/1
        }

      _ ->
        default_policy()
    end
  end

  # Private functions

  defp execute_with_retry(fun, policy, attempt, provider) do
    start_time = System.monotonic_time(:millisecond)

    case fun.() do
      {:ok, _} = success ->
        log_success(attempt, start_time, provider)
        success

      {:error, reason} = error ->
        if should_retry?(reason, attempt, policy) do
          delay = calculate_delay(attempt, policy)
          log_retry(attempt, reason, delay, provider, policy)

          Process.sleep(delay)
          execute_with_retry(fun, policy, attempt + 1, provider)
        else
          log_failure(attempt, reason, provider)
          error
        end

      other ->
        other
    end
  rescue
    exception ->
      if should_retry?(exception, attempt, policy) do
        delay = calculate_delay(attempt, policy)
        log_retry(attempt, exception, delay, provider, policy)

        Process.sleep(delay)
        execute_with_retry(fun, policy, attempt + 1, provider)
      else
        log_failure(attempt, exception, provider)
        reraise exception, __STACKTRACE__
      end
  end

  defp build_policy(opts) do
    %RetryPolicy{
      max_attempts: Keyword.get(opts, :max_attempts, @default_max_attempts),
      base_delay: Keyword.get(opts, :base_delay, @default_base_delay),
      max_delay: Keyword.get(opts, :max_delay, @default_max_delay),
      multiplier: Keyword.get(opts, :multiplier, @default_multiplier),
      jitter: Keyword.get(opts, :jitter, true),
      retry_on: Keyword.get(opts, :retry_on)
    }
  end

  defp merge_policies(base, override) do
    %RetryPolicy{
      max_attempts: override.max_attempts || base.max_attempts,
      base_delay: override.base_delay || base.base_delay,
      max_delay: override.max_delay || base.max_delay,
      multiplier: override.multiplier || base.multiplier,
      jitter: (override.jitter != nil && override.jitter) || base.jitter,
      retry_on: override.retry_on || base.retry_on
    }
  end

  defp default_policy do
    %RetryPolicy{
      max_attempts: @default_max_attempts,
      base_delay: @default_base_delay,
      max_delay: @default_max_delay,
      multiplier: @default_multiplier,
      jitter: true
    }
  end

  defp default_retry_condition(error) do
    case error do
      # Network errors
      {:network_error, _} -> true
      {:timeout, _} -> true
      {:closed, _} -> true
      %Req.TransportError{} -> true
      # Rate limits
      {:api_error, %{status: 429}} -> true
      # Server errors
      {:api_error, %{status: status}} when status >= 500 -> true
      # Specific provider errors
      {:error, "stream timeout"} -> true
      {:error, "stream interrupted"} -> true
      # Everything else
      _ -> false
    end
  end

  defp openai_retry_condition(error) do
    case error do
      # OpenAI specific rate limit with retry-after
      {:api_error, %{status: 429, headers: headers}} ->
        # Check for Retry-After header
        case List.keyfind(headers, "retry-after", 0) do
          {_, retry_after} ->
            # Sleep for the specified time if reasonable
            case Integer.parse(retry_after) do
              {seconds, _} when seconds <= 60 ->
                Process.sleep(seconds * 1000)
                true

              _ ->
                true
            end

          _ ->
            true
        end

      # Model overloaded
      {:api_error, %{status: 503}} ->
        true

      # Default conditions
      other ->
        default_retry_condition(other)
    end
  end

  defp anthropic_retry_condition(error) do
    case error do
      # Anthropic overloaded
      {:api_error, %{status: 529}} -> true
      # Default conditions
      other -> default_retry_condition(other)
    end
  end

  defp bedrock_retry_condition(error) do
    case error do
      # AWS throttling
      {:api_error, %{body: %{"__type" => "ThrottlingException"}}} -> true
      # AWS service unavailable
      {:api_error, %{body: %{"__type" => "ServiceUnavailableException"}}} -> true
      # Default conditions
      other -> default_retry_condition(other)
    end
  end

  defp add_jitter(delay) do
    # Add up to 25% random jitter
    jitter_amount = round(delay * 0.25 * :rand.uniform())
    delay + jitter_amount
  end

  defp log_retry(attempt, reason, delay, provider, policy) do
    Logger.log_retry(provider, attempt, policy.max_attempts, reason, delay)
  end

  defp log_success(attempt, start_time, _provider) do
    if attempt > 1 do
      duration = System.monotonic_time(:millisecond) - start_time
      # Log successful retry recovery
      Logger.info("Request succeeded after #{attempt} attempts (#{duration}ms)")
    end
  end

  defp log_failure(attempt, reason, provider) do
    # Log final failure after all retries
    Logger.error("Request failed after #{attempt} attempts", [
      provider: provider,
      attempts: attempt,
      reason: inspect(reason)
    ])
  end
end
