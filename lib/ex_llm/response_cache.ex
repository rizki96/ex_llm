defmodule ExLLM.ResponseCache do
  @moduledoc """
  Response caching system for collecting and storing real provider responses.

  This module allows ExLLM to cache actual responses from providers like OpenAI,
  Anthropic, OpenRouter, etc., and later replay them in tests using the Mock adapter.

  ## Usage

  ### Automatic Response Caching
  Enable caching in your environment:

      # Cache all responses during testing
      export EX_LLM_CACHE_RESPONSES=true
      export EX_LLM_CACHE_DIR="/path/to/cache/responses"

  ### Manual Response Caching

      # Store a response
      ExLLM.ResponseCache.store_response("openai", request_key, response_data)
      
      # Retrieve a cached response
      cached = ExLLM.ResponseCache.get_response("openai", request_key)
      
      # Load all responses for a provider
      responses = ExLLM.ResponseCache.load_provider_responses("anthropic")

  ### Integration with Mock Adapter

      # Configure mock to use cached responses from OpenAI
      ExLLM.ResponseCache.configure_mock_provider("openai")
      
      # Use cached responses in tests
      {:ok, response} = ExLLM.chat(messages, provider: :mock)

  ## Cache Structure

  Responses are stored in JSON files organized by provider:

      cache/
      ├── openai/
      │   ├── chat_completions.json
      │   ├── embeddings.json
      │   └── streaming.json
      ├── anthropic/
      │   ├── messages.json
      │   └── streaming.json
      └── openrouter/
          ├── chat_completions.json
          └── models.json

  Each file contains an array of cached request/response pairs with metadata.
  """

  require Logger

  @cache_dir_env "EX_LLM_CACHE_DIR"
  @cache_enabled_env "EX_LLM_CACHE_RESPONSES"
  @default_cache_dir Path.join([System.tmp_dir(), "ex_llm_cache"])

  defmodule CacheEntry do
    @moduledoc false
    defstruct [
      :request_hash,
      :provider,
      :endpoint,
      :request_data,
      :response_data,
      :cached_at,
      :model,
      :response_time_ms
    ]
  end

  @doc """
  Returns true if response caching is enabled.
  """
  def caching_enabled? do
    case System.get_env(@cache_enabled_env) do
      value when value in ["true", "1", "yes"] -> true
      _ -> false
    end
  end

  @doc """
  Returns the cache directory path.
  """
  def cache_dir do
    System.get_env(@cache_dir_env, @default_cache_dir)
  end

  @doc """
  Stores a response from the unified cache system.

  This is called by ExLLM.Cache when disk persistence is enabled.
  """
  def store_from_cache(
        cache_key,
        cached_response,
        provider,
        endpoint,
        request_metadata,
        disk_path \\ nil
      ) do
    # When called from unified cache, we don't need to check environment variable
    # since the cache system has already determined persistence should be enabled
    try do
      # Use provided disk path or default
      cache_dir_to_use = disk_path || cache_dir()

      entry = %CacheEntry{
        request_hash: cache_key,
        provider: to_string(provider || "unknown"),
        endpoint: endpoint,
        request_data: request_metadata,
        response_data: cached_response,
        cached_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        model: extract_model_from_response(cached_response),
        response_time_ms: 0
      }

      cache_file = Path.join([cache_dir_to_use, to_string(provider), "#{endpoint}.json"])
      ensure_cache_dir(cache_file)

      existing_entries = load_cache_file(cache_file)
      updated_entries = [entry | existing_entries] |> Enum.uniq_by(& &1.request_hash)

      save_cache_file(cache_file, updated_entries)

      Logger.debug("Persisted cache entry for #{provider}/#{endpoint}: #{cache_key}")
      :ok
    rescue
      error ->
        Logger.warning("Failed to persist cache entry: #{inspect(error)}")
        :error
    end
  end

  @doc """
  Stores a response in the cache.
  """
  def store_response(provider, endpoint, request_data, response_data, opts \\ []) do
    if caching_enabled?() do
      try do
        entry = %CacheEntry{
          request_hash: generate_request_hash(request_data),
          provider: provider,
          endpoint: endpoint,
          request_data: sanitize_request(request_data),
          response_data: sanitize_response(response_data),
          cached_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          model: extract_model(request_data, response_data),
          response_time_ms: Keyword.get(opts, :response_time_ms, 0)
        }

        cache_file = get_cache_file(provider, endpoint)
        ensure_cache_dir(cache_file)

        existing_entries = load_cache_file(cache_file)
        updated_entries = [entry | existing_entries] |> Enum.uniq_by(& &1.request_hash)

        save_cache_file(cache_file, updated_entries)

        Logger.debug("Cached response for #{provider}/#{endpoint}: #{entry.request_hash}")
        :ok
      rescue
        error ->
          Logger.warning("Failed to cache response: #{inspect(error)}")
          :error
      end
    else
      :disabled
    end
  end

  @doc """
  Retrieves a cached response matching the request.
  """
  def get_response(provider, endpoint, request_data) do
    try do
      request_hash = generate_request_hash(sanitize_request(request_data))
      cache_file = get_cache_file(provider, endpoint)

      case load_cache_file(cache_file) do
        [] ->
          # Try fuzzy matching with normalized endpoint
          find_similar_cached_response(provider, request_data)

        entries ->
          case Enum.find(entries, fn entry -> entry.request_hash == request_hash end) do
            nil ->
              # Try fuzzy matching if exact match fails
              find_similar_cached_response(provider, request_data)

            entry ->
              entry
          end
      end
    rescue
      _ -> nil
    end
  end

  @doc """
  Loads all cached responses for a provider.
  """
  def load_provider_responses(provider) do
    provider_dir = Path.join(cache_dir(), provider)

    if File.exists?(provider_dir) do
      provider_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.flat_map(fn file ->
        cache_file = Path.join(provider_dir, file)
        load_cache_file(cache_file)
      end)
    else
      []
    end
  end

  @doc """
  Configures the Mock adapter to use cached responses from a specific provider.
  """
  def configure_mock_provider(provider) when is_binary(provider) do
    # Convert to atom only for known providers
    case safe_provider_to_atom(provider) do
      atom when is_atom(atom) -> configure_mock_provider(atom)
      _ -> :no_cache
    end
  end

  def configure_mock_provider(provider) when is_atom(provider) do
    responses = load_provider_responses(to_string(provider))

    if length(responses) > 0 do
      # Create a response handler that looks up cached responses
      handler = fn messages, options ->
        endpoint = determine_endpoint(options)

        request_data = %{
          messages: messages,
          model: Keyword.get(options, :model),
          temperature: Keyword.get(options, :temperature),
          max_tokens: Keyword.get(options, :max_tokens)
        }

        case get_response(to_string(provider), endpoint, request_data) do
          %CacheEntry{response_data: cached_response} ->
            # Convert cached response to ExLLM format
            convert_cached_response(cached_response, provider)

          nil ->
            # Fallback to default mock response
            %{
              content: "Default mock response",
              model: "mock-model",
              usage: %{input_tokens: 10, output_tokens: 20}
            }
        end
      end

      ExLLM.Adapters.Mock.set_response_handler(handler)

      Logger.info(
        "Configured Mock adapter with #{length(responses)} cached responses from #{provider}"
      )

      :ok
    else
      Logger.warning("No cached responses found for provider: #{provider}")
      :no_cache
    end
  end

  @doc """
  Lists all available providers with cached responses.
  """
  def list_cached_providers do
    cache_dir()
    |> File.ls()
    |> case do
      {:ok, dirs} ->
        dirs
        |> Enum.filter(fn dir ->
          File.dir?(Path.join(cache_dir(), dir))
        end)
        |> Enum.map(fn dir ->
          response_count = dir |> load_provider_responses() |> length()
          {dir, response_count}
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Clears all cached responses for a provider.
  """
  def clear_provider_cache(provider) do
    provider_dir = Path.join(cache_dir(), provider)

    if File.exists?(provider_dir) do
      File.rm_rf!(provider_dir)
      Logger.info("Cleared cache for provider: #{provider}")
      :ok
    else
      :not_found
    end
  end

  @doc """
  Clears all cached responses.
  """
  def clear_all_cache do
    if File.exists?(cache_dir()) do
      File.rm_rf!(cache_dir())
      Logger.info("Cleared all response cache")
      :ok
    else
      :not_found
    end
  end

  # Private helper functions

  defp generate_request_hash(request_data) do
    try do
      normalized = normalize_request_for_hashing(request_data)
      converted = convert_structs_to_maps(normalized)

      # Sort keys for consistent ordering
      sorted_data =
        case converted do
          map when is_map(map) ->
            map |> Map.to_list() |> Enum.sort() |> Enum.into(%{})

          other ->
            other
        end

      json_string = Jason.encode!(sorted_data)
      hash = :crypto.hash(:sha256, json_string)
      Base.encode16(hash, case: :lower)
    rescue
      _error ->
        # Fallback to inspect-based hash if JSON encoding fails
        normalized = normalize_request_for_hashing(request_data)
        inspect_string = inspect(normalized, pretty: true)
        hash = :crypto.hash(:sha256, inspect_string)
        Base.encode16(hash, case: :lower)
    end
  end

  defp normalize_request_for_hashing(request_data) when is_map(request_data) do
    request_data
    # Remove nil values that can cause hash mismatches
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
    # Remove keys that shouldn't affect cache lookup
    # Stream flag doesn't affect response content
    |> Map.drop([:stream, "stream"])
    # Internal options
    |> Map.drop([:config_provider, "config_provider"])
    # Internal options
    |> Map.drop([:track_cost, "track_cost"])
  end

  defp normalize_request_for_hashing(request_data), do: request_data

  defp sanitize_request(request_data) do
    # Remove sensitive data like API keys and convert structs to maps
    request_data
    |> convert_structs_to_maps()
    |> Map.drop(["api_key", :api_key])
    |> Map.drop(["authorization", :authorization])
  end

  defp sanitize_response(response_data) do
    # Remove or mask any sensitive response data if needed and convert structs
    convert_structs_to_maps(response_data)
  end

  defp extract_model(request_data, response_data) do
    cond do
      is_map(response_data) and Map.has_key?(response_data, "model") ->
        response_data["model"]

      is_map(request_data) and Map.has_key?(request_data, "model") ->
        request_data["model"]

      is_map(request_data) and Map.has_key?(request_data, :model) ->
        request_data[:model]

      true ->
        "unknown"
    end
  end

  defp extract_model_from_response(response_data) do
    cond do
      is_map(response_data) and Map.has_key?(response_data, "model") ->
        response_data["model"]

      is_map(response_data) and Map.has_key?(response_data, :model) ->
        response_data[:model]

      is_struct(response_data) and Map.has_key?(response_data, :model) ->
        response_data.model

      true ->
        "unknown"
    end
  end

  defp get_cache_file(provider, endpoint) do
    Path.join([cache_dir(), provider, "#{endpoint}.json"])
  end

  defp ensure_cache_dir(cache_file) do
    # Cache directory is controlled by configuration, not user input
    # sobelow_skip ["Traversal.FileModule"]
    cache_file
    |> Path.dirname()
    |> File.mkdir_p!()
  end

  defp load_cache_file(cache_file) do
    # Cache file path is controlled by configuration, not user input
    # sobelow_skip ["Traversal.FileModule"]
    if File.exists?(cache_file) do
      # sobelow_skip ["Traversal.FileModule"]
      cache_file
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(&struct(CacheEntry, atomize_keys(&1)))
    else
      []
    end
  rescue
    _ -> []
  end

  defp save_cache_file(cache_file, entries) do
    json_data =
      entries
      |> Enum.map(&Map.from_struct/1)
      |> convert_structs_to_maps()
      |> Jason.encode!(pretty: true)

    # Cache file path is controlled by configuration, not user input
    # sobelow_skip ["Traversal.FileModule"]
    File.write!(cache_file, json_data)
  end

  defp atomize_keys(map) when is_map(map) do
    for {key, val} <- map, into: %{} do
      cond do
        # Only atomize known keys for cache entries
        is_binary(key) -> {safe_atomize_cache_key(key), atomize_keys(val)}
        is_atom(key) -> {key, atomize_keys(val)}
        true -> {key, atomize_keys(val)}
      end
    end
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value

  # Safe atomization of known cache entry keys
  defp safe_atomize_cache_key(key) when is_binary(key) do
    case key do
      # CacheEntry struct fields
      "request_hash" -> :request_hash
      "provider" -> :provider
      "endpoint" -> :endpoint
      "request_data" -> :request_data
      "response_data" -> :response_data
      "cached_at" -> :cached_at
      "model" -> :model
      "response_time_ms" -> :response_time_ms
      # Common fields in request/response data
      "key" -> :key
      "response" -> :response
      "timestamp" -> :timestamp
      "metadata" -> :metadata
      "messages" -> :messages
      "content" -> :content
      "role" -> :role
      "usage" -> :usage
      "input_tokens" -> :input_tokens
      "output_tokens" -> :output_tokens
      "total_tokens" -> :total_tokens
      "cost" -> :cost
      "id" -> :id
      "finish_reason" -> :finish_reason
      "function_call" -> :function_call
      "tool_calls" -> :tool_calls
      # OpenAI/Compatible format fields
      "choices" -> :choices
      "message" -> :message
      "prompt_tokens" -> :prompt_tokens
      "completion_tokens" -> :completion_tokens
      # Anthropic format fields
      "stop_reason" -> :stop_reason
      "text" -> :text
      # Ollama format fields
      "done" -> :done
      "prompt_eval_count" -> :prompt_eval_count
      "eval_count" -> :eval_count
      # Keep as string if not a known key
      _ -> key
    end
  end

  defp determine_endpoint(options) do
    cond do
      Keyword.get(options, :stream) == true -> "streaming"
      Keyword.has_key?(options, :functions) or Keyword.has_key?(options, :tools) -> "chat"
      # Normalize all chat endpoints to "chat"
      true -> "chat"
    end
  end

  defp convert_cached_response(cached_response, provider) do
    # Convert provider-specific response format to ExLLM format
    case provider do
      :openai -> convert_openai_response(cached_response)
      :anthropic -> convert_anthropic_response(cached_response)
      :openrouter -> convert_openrouter_response(cached_response)
      :ollama -> convert_ollama_response(cached_response)
      _ -> cached_response
    end
  end

  defp convert_openai_response(response) do
    %{
      content:
        get_in(response, ["choices", Access.at(0), "message", "content"]) ||
          get_in(response, [:choices, Access.at(0), :message, :content]) || "",
      model: response["model"] || response[:model] || "gpt-3.5-turbo",
      usage: %{
        input_tokens:
          get_in(response, ["usage", "prompt_tokens"]) ||
            get_in(response, [:usage, :prompt_tokens]) || 0,
        output_tokens:
          get_in(response, ["usage", "completion_tokens"]) ||
            get_in(response, [:usage, :completion_tokens]) || 0
      },
      finish_reason:
        get_in(response, ["choices", Access.at(0), "finish_reason"]) ||
          get_in(response, [:choices, Access.at(0), :finish_reason]),
      id: response["id"] || response[:id]
    }
  end

  defp convert_anthropic_response(response) do
    %{
      content:
        get_in(response, ["content", Access.at(0), "text"]) ||
          get_in(response, [:content, Access.at(0), :text]) || "",
      model: response["model"] || response[:model] || "claude-3-5-sonnet",
      usage: %{
        input_tokens:
          get_in(response, ["usage", "input_tokens"]) ||
            get_in(response, [:usage, :input_tokens]) || 0,
        output_tokens:
          get_in(response, ["usage", "output_tokens"]) ||
            get_in(response, [:usage, :output_tokens]) || 0
      },
      finish_reason: response["stop_reason"] || response[:stop_reason],
      id: response["id"] || response[:id]
    }
  end

  defp convert_openrouter_response(response) do
    # OpenRouter uses OpenAI format
    convert_openai_response(response)
  end

  defp convert_ollama_response(response) do
    %{
      content: response["message"]["content"] || response["response"] || "",
      model: response["model"] || "llama2",
      usage: %{
        input_tokens: get_in(response, ["prompt_eval_count"]) || 0,
        output_tokens: get_in(response, ["eval_count"]) || 0
      },
      finish_reason: if(response["done"], do: "stop", else: nil),
      id: "ollama-#{System.system_time(:millisecond)}"
    }
  end

  defp convert_structs_to_maps(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end

  defp convert_structs_to_maps(%Date{} = date) do
    Date.to_iso8601(date)
  end

  defp convert_structs_to_maps(%Time{} = time) do
    Time.to_iso8601(time)
  end

  defp convert_structs_to_maps(%NaiveDateTime{} = datetime) do
    NaiveDateTime.to_iso8601(datetime)
  end

  defp convert_structs_to_maps(data) when is_struct(data) do
    data
    |> Map.from_struct()
    |> convert_structs_to_maps()
  end

  defp convert_structs_to_maps(data) when is_map(data) do
    for {key, value} <- data, into: %{} do
      {key, convert_structs_to_maps(value)}
    end
  end

  defp convert_structs_to_maps(data) when is_list(data) do
    Enum.map(data, &convert_structs_to_maps/1)
  end

  defp convert_structs_to_maps(data), do: data

  defp find_similar_cached_response(provider, request_data) do
    provider_dir = Path.join(cache_dir(), provider)

    if File.exists?(provider_dir) do
      # Try different endpoint variations
      endpoints_to_try = ["chat", "chat_completions", "streaming", "messages"]
      find_in_endpoints(endpoints_to_try, request_data, provider)
    else
      nil
    end
  end

  defp find_in_endpoints(endpoints, request_data, provider) do
    Enum.reduce_while(endpoints, nil, fn endpoint, _acc ->
      cache_file = get_cache_file(provider, endpoint)

      case check_endpoint_cache(cache_file, request_data) do
        nil -> {:cont, nil}
        entry -> {:halt, entry}
      end
    end)
  end

  defp check_endpoint_cache(cache_file, request_data) do
    case load_cache_file(cache_file) do
      [] -> nil
      entries -> find_by_message_similarity(entries, request_data)
    end
  end

  defp find_by_message_similarity(entries, request_data) do
    target_messages = extract_messages(request_data)

    if target_messages do
      Enum.find(entries, fn entry ->
        cached_messages = extract_messages(entry.request_data)
        messages_similar?(target_messages, cached_messages)
      end)
    else
      # If no messages to compare, return first entry as fallback
      List.first(entries)
    end
  end

  defp extract_messages(request_data) when is_map(request_data) do
    request_data[:messages] || request_data["messages"]
  end

  defp extract_messages(_), do: nil

  defp messages_similar?(messages1, messages2) when is_list(messages1) and is_list(messages2) do
    # Simple similarity check - same number of messages and same content in last message
    length(messages1) == length(messages2) and
      last_message_content(messages1) == last_message_content(messages2)
  end

  defp messages_similar?(_, _), do: false

  defp last_message_content(messages) when is_list(messages) and length(messages) > 0 do
    last_msg = List.last(messages)

    case last_msg do
      %{content: content} when is_binary(content) -> content
      %{"content" => content} when is_binary(content) -> content
      _ -> nil
    end
  end

  defp last_message_content(_), do: nil

  # Safe conversion of provider names to atoms
  defp safe_provider_to_atom(provider) when is_binary(provider) do
    case provider do
      "openai" -> :openai
      "anthropic" -> :anthropic
      "gemini" -> :gemini
      "groq" -> :groq
      "ollama" -> :ollama
      "openrouter" -> :openrouter
      "bedrock" -> :bedrock
      "mistral" -> :mistral
      "cohere" -> :cohere
      "perplexity" -> :perplexity
      "deepseek" -> :deepseek
      "together_ai" -> :together_ai
      "anyscale" -> :anyscale
      "replicate" -> :replicate
      "xai" -> :xai
      "bumblebee" -> :bumblebee
      "mock" -> :mock
      # Return as string if not a known provider
      _ -> provider
    end
  end
end
