defmodule ExLLM.Infrastructure.Telemetry.Instrumentation do
  @moduledoc """
  Helper module for adding telemetry instrumentation to ExLLM operations.

  This module provides macros and functions to easily add telemetry to
  existing code with minimal changes. It follows the patterns established
  in the centralized telemetry module.

  ## Usage

  ### Basic Instrumentation

      defmodule MyModule do
        import ExLLM.Infrastructure.Telemetry.Instrumentation
        
        def my_function(args) do
          instrument [:ex_llm, :my_module, :my_function], %{args: args} do
            # Your code here
            {:ok, result}
          end
        end
      end

  ### Provider Instrumentation

      defmodule MyAdapter do
        import ExLLM.Infrastructure.Telemetry.Instrumentation
        
        def call(model, messages, opts) do
          instrument_provider :my_provider, model, opts do
            # API call here
            {:ok, response}
          end
        end
      end

  ### HTTP Instrumentation

      def post_json(url, body, headers, opts) do
        instrument_http :post, url do
          HTTP.Core.post(url, body, headers)
        end
      end
  """

  @doc """
  Instrument a block of code with telemetry events.

  Automatically emits start/stop/exception events and measures duration.
  """
  defmacro instrument(event_prefix, metadata \\ %{}, do: block) do
    quote do
      ExLLM.Infrastructure.Telemetry.span(unquote(event_prefix), unquote(metadata), fn ->
        unquote(block)
      end)
    end
  end

  @doc """
  Instrument a provider API call with standard metadata.
  """
  defmacro instrument_provider(provider, model, opts \\ [], do: block) do
    quote do
      metadata = %{
        provider: unquote(provider),
        model: unquote(model),
        api_key_configured: !is_nil(unquote(opts)[:api_key]),
        stream: Keyword.get(unquote(opts), :stream, false)
      }

      result =
        ExLLM.Infrastructure.Telemetry.span([:ex_llm, :provider, :request], metadata, fn ->
          unquote(block)
        end)

      # Add result metadata for successful calls
      case result do
        {:ok, response} = success ->
          if usage = get_in(response, [:usage]) do
            :telemetry.execute(
              [:ex_llm, :cost, :calculated],
              %{cost: get_in(response, [:cost, :total_cents]) || 0},
              %{
                provider: unquote(provider),
                model: unquote(model),
                tokens: Map.get(usage, :total_tokens, 0),
                cost: get_in(response, [:cost, :total_cents]) || 0
              }
            )
          end

          success

        error ->
          error
      end
    end
  end

  @doc """
  Instrument HTTP requests with standard metadata.
  """
  defmacro instrument_http(method, url, opts \\ [], do: block) do
    quote do
      metadata = %{
        method: unquote(method),
        url: unquote(url),
        timeout: Keyword.get(unquote(opts), :timeout)
      }

      start_time = System.monotonic_time()

      :telemetry.execute(
        [:ex_llm, :http, :request, :start],
        %{system_time: System.system_time()},
        metadata
      )

      try do
        case unquote(block) do
          {:ok, %{status: status} = response} = result ->
            duration = System.monotonic_time() - start_time

            :telemetry.execute(
              [:ex_llm, :http, :request, :stop],
              %{duration: duration, system_time: System.system_time()},
              Map.merge(metadata, %{
                status: status,
                success: status >= 200 and status < 300,
                response_size: byte_size(response.body || "")
              })
            )

            result

          {:error, reason} = error ->
            duration = System.monotonic_time() - start_time

            :telemetry.execute(
              [:ex_llm, :http, :request, :exception],
              %{duration: duration, system_time: System.system_time()},
              Map.merge(metadata, %{
                error: reason,
                success: false
              })
            )

            error

          other ->
            other
        end
      rescue
        exception ->
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:ex_llm, :http, :request, :exception],
            %{duration: duration, system_time: System.system_time()},
            Map.merge(metadata, %{
              error: exception,
              success: false,
              stacktrace: __STACKTRACE__
            })
          )

          reraise exception, __STACKTRACE__
      end
    end
  end

  @doc """
  Instrument cache operations.
  """
  def instrument_cache_lookup(key, lookup_fn) do
    case lookup_fn.() do
      {:ok, value} ->
        :telemetry.execute(
          [:ex_llm, :cache, :lookup, :hit],
          %{},
          %{key: key}
        )

        {:ok, value}

      :error ->
        :telemetry.execute(
          [:ex_llm, :cache, :lookup, :miss],
          %{},
          %{key: key}
        )

        :error
    end
  end

  @doc """
  Instrument cache store operations.
  """
  def instrument_cache_store(key, value, ttl, store_fn) do
    case store_fn.() do
      :ok ->
        :telemetry.execute(
          [:ex_llm, :cache, :store, :success],
          %{size: :erlang.external_size(value)},
          %{key: key, ttl: ttl}
        )

        :ok

      error ->
        error
    end
  end

  @doc """
  Instrument session operations.
  """
  def instrument_session_add_message(session_id, message, tokens) do
    :telemetry.execute(
      [:ex_llm, :session, :message, :added],
      %{tokens: tokens},
      %{
        session_id: session_id,
        role: message.role,
        tokens: tokens,
        message_length: String.length(message.content || "")
      }
    )
  end

  @doc """
  Instrument context truncation.
  """
  def instrument_context_truncation(messages_before, messages_after, tokens_removed) do
    :telemetry.execute(
      [:ex_llm, :context, :truncation, :stop],
      %{
        messages_removed: messages_before - messages_after,
        tokens_removed: tokens_removed
      },
      %{
        messages_before: messages_before,
        messages_after: messages_after,
        truncated: messages_before > messages_after
      }
    )
  end

  @doc """
  Instrument streaming operations.
  """
  def instrument_stream_start(provider, model) do
    :telemetry.execute(
      [:ex_llm, :stream, :start],
      %{system_time: System.system_time()},
      %{provider: provider, model: model}
    )
  end

  def instrument_stream_chunk(provider, model, chunk_size) do
    :telemetry.execute(
      [:ex_llm, :stream, :chunk],
      %{chunk_size: chunk_size},
      %{provider: provider, model: model}
    )
  end

  def instrument_stream_complete(provider, model, total_chunks, duration) do
    :telemetry.execute(
      [:ex_llm, :stream, :stop],
      %{
        duration: duration,
        total_chunks: total_chunks
      },
      %{
        provider: provider,
        model: model,
        success: true
      }
    )
  end

  @doc """
  Helper to extract usage information from various response formats.
  """
  def extract_usage_metadata(response) do
    case response do
      %{usage: usage} when is_map(usage) ->
        %{
          input_tokens: Map.get(usage, :input_tokens, 0),
          output_tokens: Map.get(usage, :output_tokens, 0),
          total_tokens: Map.get(usage, :total_tokens, 0)
        }

      %{token_usage: usage} when is_map(usage) ->
        %{
          input_tokens: Map.get(usage, :prompt_tokens, 0),
          output_tokens: Map.get(usage, :completion_tokens, 0),
          total_tokens: Map.get(usage, :total_tokens, 0)
        }

      _ ->
        %{}
    end
  end

  @doc """
  Helper to check if a cost threshold has been exceeded.
  """
  def check_cost_threshold(cost_cents, threshold_cents) when cost_cents > threshold_cents do
    :telemetry.execute(
      [:ex_llm, :cost, :threshold, :exceeded],
      %{cost: cost_cents},
      %{
        cost: cost_cents,
        threshold: threshold_cents,
        exceeded_by: cost_cents - threshold_cents
      }
    )
  end

  def check_cost_threshold(_, _), do: :ok
end
