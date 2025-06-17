defmodule ExLLM.Infrastructure.Retry do
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
      ExLLM.Infrastructure.Retry.with_retry fn ->
        ExLLM.chat(:openai, messages)
      end
      
      # With custom retry options
      ExLLM.Infrastructure.Retry.with_retry fn ->
        ExLLM.chat(:anthropic, messages)
      end,
        max_attempts: 5,
        base_delay: 1000,
        max_delay: 30_000,
        jitter: true
  """

  alias ExLLM.Infrastructure.Logger

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

  # Note: The CircuitBreaker struct was previously defined here but is now
  # replaced by the full ExLLM.Infrastructure.CircuitBreaker module implementation

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
  Execute function with combined circuit breaker and retry protection.

  This function integrates circuit breaker protection with ExLLM's existing
  retry logic, providing comprehensive fault tolerance.

  ## Options
    * `:circuit_breaker` - Circuit breaker options (see ExLLM.CircuitBreaker.call/3)
    * `:retry` - Retry options (see with_retry/2)
    * `:circuit_name` - Custom circuit name (default: auto-generated)
  """
  def with_circuit_breaker_retry(fun, opts \\ []) when is_function(fun, 0) do
    {circuit_opts, retry_opts} = split_options(opts)
    circuit_name = Keyword.get(opts, :circuit_name) || generate_circuit_name()

    ExLLM.Infrastructure.CircuitBreaker.call(
      circuit_name,
      fn ->
        with_retry(fun, retry_opts)
      end,
      circuit_opts
    )
  end

  @doc """
  Provider-specific retry with circuit breaker protection.

  Uses provider-specific configurations for both retry and circuit breaker behavior.
  """
  def with_provider_circuit_breaker(provider, fun, opts \\ []) do
    circuit_name = :"#{provider}_circuit"
    provider_config = get_provider_circuit_config(provider)

    # Merge provider defaults with user options
    circuit_opts =
      Keyword.merge(
        provider_config.circuit_breaker,
        Keyword.get(opts, :circuit_breaker, [])
      )

    retry_opts =
      Keyword.merge(
        provider_config.retry,
        Keyword.get(opts, :retry, [])
      )

    ExLLM.Infrastructure.CircuitBreaker.call(
      circuit_name,
      fn ->
        with_retry(fun, retry_opts)
      end,
      circuit_opts
    )
  end

  @doc """
  Enhanced chat function with circuit breaker protection.
  """
  def chat_with_circuit_breaker(provider, messages, opts \\ []) do
    with_provider_circuit_breaker(
      provider,
      fn ->
        ExLLM.chat(provider, messages, opts)
      end,
      opts
    )
  end

  @doc """
  Enhanced streaming with circuit breaker protection.
  """
  def stream_with_circuit_breaker(provider, messages, opts \\ []) do
    # Longer timeout for streams
    circuit_opts = Keyword.put(opts, :timeout, 120_000)

    with_provider_circuit_breaker(
      provider,
      fn ->
        ExLLM.stream_chat(provider, messages, opts)
      end,
      circuit_breaker: circuit_opts
    )
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
    Logger.error("Request failed after #{attempt} attempts",
      provider: provider,
      attempts: attempt,
      reason: inspect(reason)
    )
  end

  # Provider-specific circuit breaker configurations
  defp get_provider_circuit_config(provider) do
    base_config = %{
      circuit_breaker: [
        failure_threshold: 5,
        success_threshold: 3,
        reset_timeout: 30_000,
        timeout: 30_000
      ],
      retry: [
        max_attempts: 3,
        base_delay: 1000,
        max_delay: 30_000,
        jitter: true
      ]
    }

    provider_overrides =
      case provider do
        :openai ->
          %{
            circuit_breaker: [failure_threshold: 3, reset_timeout: 60_000],
            retry: [max_delay: 60_000]
          }

        :anthropic ->
          %{
            circuit_breaker: [failure_threshold: 5, reset_timeout: 30_000],
            retry: [base_delay: 2000]
          }

        :bedrock ->
          %{
            circuit_breaker: [failure_threshold: 7, reset_timeout: 45_000],
            retry: [max_attempts: 5, max_delay: 20_000]
          }

        :gemini ->
          %{
            circuit_breaker: [failure_threshold: 4, reset_timeout: 40_000],
            retry: [base_delay: 1500]
          }

        :groq ->
          %{
            circuit_breaker: [failure_threshold: 3, reset_timeout: 20_000],
            retry: [max_attempts: 2, max_delay: 10_000]
          }

        :ollama ->
          %{
            circuit_breaker: [failure_threshold: 10, reset_timeout: 5_000],
            retry: [max_attempts: 2, base_delay: 500]
          }

        :lmstudio ->
          %{
            circuit_breaker: [failure_threshold: 10, reset_timeout: 5_000],
            retry: [max_attempts: 2, base_delay: 500]
          }

        _ ->
          %{}
      end

    deep_merge(base_config, provider_overrides)
  end

  defp split_options(opts) do
    circuit_breaker_opts = Keyword.get(opts, :circuit_breaker, [])
    retry_opts = Keyword.get(opts, :retry, [])

    # Add any top-level options to retry_opts for backward compatibility
    retry_opts =
      opts
      |> Keyword.drop([:circuit_breaker, :circuit_name])
      |> Keyword.merge(retry_opts)

    {circuit_breaker_opts, retry_opts}
  end

  defp generate_circuit_name do
    "circuit_#{System.unique_integer([:positive])}"
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, left_val, right_val when is_list(left_val) and is_list(right_val) ->
        Keyword.merge(left_val, right_val)

      _key, _left_val, right_val ->
        right_val
    end)
  end
end
