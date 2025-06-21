defmodule ExLLM.Plugs.Cache do
  @moduledoc """
  Caches LLM responses to avoid redundant API calls.

  This plug checks if a cached response exists for the current request.
  If found, it halts the pipeline and returns the cached response.
  Otherwise, it allows the request to proceed and caches the response
  after a successful API call.

  ## Options

    * `:ttl` - Time to live for cached entries in seconds (default: 300)
    * `:cache_key_fn` - Custom function to generate cache keys
    * `:skip_cache` - Boolean to skip caching for this request
    
  ## Examples

      plug ExLLM.Plugs.Cache, ttl: 600
      
      # With custom cache key
      plug ExLLM.Plugs.Cache,
        cache_key_fn: fn request ->
          provider = request.provider
          model = request.config[:model] || "default"
          messages_hash = :crypto.hash(:sha256, :erlang.term_to_binary(request.messages))
                          |> Base.encode16(case: :lower)
          "\#{provider}:\#{model}:\#{messages_hash}"
        end
  """

  use ExLLM.Plug
  alias ExLLM.Infrastructure.Cache
  alias ExLLM.Infrastructure.Logger

  # 5 minutes
  @default_ttl 300

  @impl true
  def init(opts) do
    opts
    |> Keyword.put_new(:ttl, @default_ttl)
    |> Keyword.validate!([:ttl, :cache_key_fn, :skip_cache])
  end

  @impl true
  def call(%Request{} = request, opts) do
    if skip_cache?(request, opts) do
      request
    else
      cache_key = generate_cache_key(request, opts)

      case Cache.get(cache_key) do
        {:ok, cached_response} ->
          # Cache hit - halt pipeline and return cached response
          handle_cache_hit(request, cached_response, cache_key)

        :miss ->
          # Cache miss - continue pipeline and set up cache write
          handle_cache_miss(request, cache_key, opts)
      end
    end
  end

  defp skip_cache?(request, opts) do
    # Skip caching if explicitly disabled or cache is not enabled
    opts[:skip_cache] ||
      request.config[:skip_cache] ||
      request.config[:cache] == false
  end

  defp generate_cache_key(request, opts) do
    case opts[:cache_key_fn] do
      nil ->
        # Default cache key generation
        default_cache_key(request)

      cache_key_fn when is_function(cache_key_fn, 1) ->
        cache_key_fn.(request)
    end
  end

  defp default_cache_key(request) do
    # Create a stable hash of the request
    key_data = %{
      provider: request.provider,
      messages: normalize_messages(request.messages),
      model: request.config[:model],
      temperature: request.config[:temperature],
      max_tokens: request.config[:max_tokens],
      tools: request.config[:tools],
      functions: request.config[:functions]
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(key_data))
    |> Base.encode16(case: :lower)
  end

  defp normalize_messages(messages) do
    # Normalize messages to ensure consistent cache keys
    Enum.map(messages, fn msg ->
      %{
        role: msg[:role] || msg["role"],
        content: msg[:content] || msg["content"]
      }
    end)
  end

  defp handle_cache_hit(request, cached_response, cache_key) do
    Logger.debug("Cache hit for key: #{cache_key}")

    # Emit telemetry event
    :telemetry.execute(
      [:ex_llm, :cache, :hit],
      %{},
      %{
        provider: request.provider,
        cache_key: cache_key
      }
    )

    request
    |> Map.put(:result, cached_response)
    |> Request.put_state(:completed)
    |> Request.assign(:cache_hit, true)
    |> Request.assign(:cache_key, cache_key)
    |> Request.halt()
  end

  defp handle_cache_miss(request, cache_key, opts) do
    Logger.debug("Cache miss for key: #{cache_key}")

    # Emit telemetry event
    :telemetry.execute(
      [:ex_llm, :cache, :miss],
      %{},
      %{
        provider: request.provider,
        cache_key: cache_key
      }
    )

    # Store cache key and TTL for later use by a cache write plug
    request
    |> Request.assign(:cache_key, cache_key)
    |> Request.assign(:cache_ttl, opts[:ttl])
    |> Request.assign(:should_cache, true)
  end
end
