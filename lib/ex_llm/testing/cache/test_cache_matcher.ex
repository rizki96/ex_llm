defmodule ExLLM.Testing.TestCacheMatcher do
  @moduledoc """
  Intelligent matching of requests to cached responses.

  This module provides sophisticated request-to-cache matching strategies
  including exact matching, fuzzy matching, content-based matching, and
  test context-aware matching for the automatic test response caching system.
  """

  alias ExLLM.Testing.TestCacheDetector

  @type match_result ::
          {:ok, map()}
          | :miss

  @type cached_request :: map()

  @doc """
  Find exact match for a request in cached responses.
  """
  @spec exact_match(map(), [cached_request()]) :: match_result()
  def exact_match(request, cached_requests) do
    case Enum.find(cached_requests, fn cached ->
           request == cached.request
         end) do
      nil -> :miss
      cached -> {:ok, cached}
    end
  end

  @doc """
  Find fuzzy match for a request with configurable tolerance.
  """
  @spec fuzzy_match(map(), [cached_request()], float()) :: match_result()
  def fuzzy_match(request, cached_requests, tolerance \\ 0.9) do
    matches =
      cached_requests
      |> Enum.map(fn cached ->
        similarity = calculate_similarity(request, cached.request)
        {cached, similarity}
      end)
      |> Enum.filter(fn {_cached, similarity} -> similarity >= tolerance end)
      |> Enum.sort_by(fn {_cached, similarity} -> similarity end, :desc)

    case matches do
      [{cached, _similarity} | _] -> {:ok, cached}
      [] -> :miss
    end
  end

  @doc """
  Find semantic match based on request content similarity.
  """
  @spec semantic_match(map(), [cached_request()]) :: match_result()
  def semantic_match(request, cached_requests) do
    # Extract message content for semantic comparison
    request_content = extract_message_content(request)

    matches =
      cached_requests
      |> Enum.map(fn cached ->
        cached_content = extract_message_content(cached.request)
        # Simple semantic similarity based on content overlap
        similarity = calculate_semantic_similarity(request_content, cached_content)
        {cached, similarity}
      end)
      |> Enum.filter(fn {_cached, similarity} -> similarity >= 0.5 end)
      |> Enum.sort_by(fn {_cached, similarity} -> similarity end, :desc)

    case matches do
      [{cached, _similarity} | _] -> {:ok, cached}
      [] -> :miss
    end
  end

  @doc """
  Find context-aware match considering test module and tags.
  """
  @spec context_match(map(), [cached_request()], map()) :: match_result()
  def context_match(request, cached_requests, test_context) do
    _request_sig = generate_request_signature(request)
    current_context = normalize_test_context(test_context)

    # First try exact match within same test context
    context_matches =
      Enum.filter(cached_requests, fn cached ->
        cached_context =
          normalize_test_context(Map.get(cached, :metadata, %{}) |> Map.get(:test_context, %{}))

        contexts_match?(current_context, cached_context)
      end)

    # If we found context matches, try to match the request
    if length(context_matches) > 0 do
      case exact_match(request, context_matches) do
        {:ok, _} = result ->
          result

        :miss ->
          # Fallback to fuzzy match within context with lower threshold
          fuzzy_match(request, context_matches, 0.7)
      end
    else
      # No context matches found
      :miss
    end
  end

  @doc """
  Find best match using comprehensive strategy.
  """
  @spec find_best_match(map(), [cached_request()], atom()) :: match_result()
  def find_best_match(request, cached_requests, strategy \\ :comprehensive) do
    case strategy do
      :exact_only ->
        exact_match(request, cached_requests)

      :fuzzy_tolerant ->
        fuzzy_match(request, cached_requests, 0.8)

      :semantic ->
        semantic_match(request, cached_requests)

      :context_aware ->
        test_context = TestCacheDetector.get_current_test_context()

        case test_context do
          {:ok, context} -> context_match(request, cached_requests, context)
          :error -> exact_match(request, cached_requests)
        end

      :comprehensive ->
        # Try strategies in order of preference
        case exact_match(request, cached_requests) do
          {:ok, _} = result ->
            result

          :miss ->
            case fuzzy_match(request, cached_requests, 0.9) do
              {:ok, _} = result -> result
              :miss -> semantic_match(request, cached_requests)
            end
        end
    end
  end

  @doc """
  Calculate similarity score between two requests.
  """
  @spec calculate_similarity(map(), map()) :: float()
  def calculate_similarity(request1, request2) do
    # Short circuit for identical requests
    if request1 == request2 do
      1.0
    else
      # Normalize requests for comparison
      norm1 = normalize_request(request1)
      norm2 = normalize_request(request2)

      # Calculate component similarities
      url_sim = if norm1.url == norm2.url, do: 1.0, else: string_similarity(norm1.url, norm2.url)
      body_sim = map_similarity(norm1.body, norm2.body)
      headers_sim = headers_similarity(norm1.headers, norm2.headers)

      # Weighted average
      url_sim * 0.3 + body_sim * 0.6 + headers_sim * 0.1
    end
  end

  @doc """
  Normalize request for comparison.
  """
  @spec normalize_request(map()) :: map()
  def normalize_request(request) do
    %{
      url: Map.get(request, :url, ""),
      body: sanitize_body_for_matching(Map.get(request, :body, %{})),
      headers: sanitize_headers_for_matching(Map.get(request, :headers, []))
    }
  end

  @doc """
  Extract message content from request for semantic matching.
  """
  @spec extract_message_content(map()) :: String.t()
  def extract_message_content(request) do
    case get_in(request, [:body, "messages"]) do
      messages when is_list(messages) ->
        messages
        |> Enum.map(fn msg ->
          case msg do
            %{"content" => content} when is_binary(content) -> content
            _ -> ""
          end
        end)
        |> Enum.join(" ")

      _ ->
        ""
    end
  end

  # Private functions

  def generate_request_signature(request) do
    %{
      url: Map.get(request, :url, ""),
      body_hash:
        :crypto.hash(:sha256, :erlang.term_to_binary(Map.get(request, :body, %{})))
        |> Base.encode16(),
      method: Map.get(request, :method, "POST"),
      headers_signature: generate_headers_signature(Map.get(request, :headers, []))
    }
  end

  defp generate_headers_signature(headers) do
    headers
    |> Enum.reject(fn {key, _value} ->
      String.downcase(key) in ["authorization", "x-api-key", "date", "x-request-id"]
    end)
    |> Enum.sort()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16()
  end

  defp calculate_semantic_similarity(content1, content2) do
    # If content is exactly the same (including order), high similarity
    if content1 == content2 do
      1.0
    else
      # Simple word overlap similarity
      words1 = String.split(String.downcase(content1), ~r/\s+/) |> MapSet.new()
      words2 = String.split(String.downcase(content2), ~r/\s+/) |> MapSet.new()

      intersection = MapSet.intersection(words1, words2) |> MapSet.size()
      union = MapSet.union(words1, words2) |> MapSet.size()

      # Use Jaccard coefficient for similarity
      base_similarity = if union == 0, do: 0.0, else: intersection / union

      # For reordered content with same words, heavily penalize
      # This ensures that message order matters for semantic matching
      if base_similarity == 1.0 and content1 != content2 do
        # Same words but different order - not semantically equivalent
        0.1
      else
        # Boost similarity for semantic matches (common important words)
        # "capital of France" and "capital city of France" should have high similarity
        if intersection >= 2 and base_similarity > 0.5 do
          # Boost but cap at 1.0
          result = min(base_similarity * 1.5, 1.0)
          result
        else
          base_similarity
        end
      end
    end
  end

  defp contexts_match?(context1, context2) do
    # More flexible context matching - if both module and test_name match
    context1.module == context2.module and
      context1.test_name == context2.test_name
  end

  defp normalize_test_context(context) do
    %{
      module: Map.get(context, :module, nil),
      test_name: Map.get(context, :test_name, ""),
      tags: Map.get(context, :tags, [])
    }
  end

  defp string_similarity(str1, str2) do
    # Use Jaro distance for string similarity
    # Returns value between 0.0 and 1.0
    String.jaro_distance(str1, str2)
  end

  defp map_similarity(map1, map2) do
    keys = MapSet.union(MapSet.new(Map.keys(map1)), MapSet.new(Map.keys(map2)))

    if MapSet.size(keys) == 0 do
      1.0
    else
      scores =
        Enum.map(keys, fn key ->
          val1 = Map.get(map1, key)
          val2 = Map.get(map2, key)

          cond do
            val1 == val2 ->
              1.0

            is_map(val1) and is_map(val2) ->
              map_similarity(val1, val2)

            is_number(val1) and is_number(val2) ->
              # For numbers, calculate relative similarity
              diff = abs(val1 - val2)
              max_val = max(abs(val1), abs(val2))
              if max_val == 0, do: 1.0, else: 1.0 - min(diff / max_val, 1.0)

            true ->
              0.0
          end
        end)

      Enum.sum(scores) / length(scores)
    end
  end

  defp headers_similarity(headers1, headers2) do
    # Compare headers ignoring sensitive ones
    norm1 = normalize_headers(headers1)
    norm2 = normalize_headers(headers2)

    if Enum.empty?(norm1) and Enum.empty?(norm2) do
      1.0
    else
      matching = Enum.count(norm1, fn h1 -> h1 in norm2 end)
      total = max(Enum.count(norm1), Enum.count(norm2))
      matching / total
    end
  end

  defp normalize_headers(headers) do
    headers
    |> Enum.reject(fn {key, _value} ->
      String.downcase(key) in ["authorization", "x-api-key", "date", "x-request-id"]
    end)
    |> Enum.sort()
  end

  defp sanitize_body_for_matching(body) when is_map(body) do
    # Remove sensitive and variable fields for matching
    sensitive_keys = ["api_key", "authorization", "token", "timestamp", "nonce"]

    body
    |> Map.drop(sensitive_keys)
    |> Enum.map(fn {k, v} ->
      key_str = String.downcase(to_string(k))

      if key_str in sensitive_keys do
        {k, "[REDACTED]"}
      else
        {k, sanitize_nested_value(v)}
      end
    end)
    |> Enum.into(%{})
    |> sort_map_keys()
  end

  defp sanitize_body_for_matching(body), do: body

  defp sanitize_nested_value(value) when is_map(value) do
    sanitize_body_for_matching(value)
  end

  defp sanitize_nested_value(value) when is_list(value) do
    Enum.map(value, &sanitize_nested_value/1)
  end

  defp sanitize_nested_value(value), do: value

  defp sort_map_keys(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
    |> Enum.map(fn {k, v} ->
      {k, if(is_map(v), do: sort_map_keys(v), else: v)}
    end)
    |> Enum.into(%{})
  end

  defp sanitize_headers_for_matching(headers) do
    headers
    |> Enum.reject(fn {key, _value} ->
      String.downcase(key) in ["authorization", "x-api-key", "date", "x-request-id", "user-agent"]
    end)
    |> Enum.sort()
  end
end
