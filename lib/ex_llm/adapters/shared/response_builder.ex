defmodule ExLLM.Adapters.Shared.ResponseBuilder do
  @moduledoc """
  Shared utilities for building standardized responses across adapters.

  Provides consistent response construction for:
  - Chat completions
  - Streaming chunks
  - Function calls
  - Error responses
  - Embeddings
  """

  alias ExLLM.{Cost, Types}

  @doc """
  Build a standard chat response from provider-specific data.

  ## Options
  - `:calculate_cost` - Whether to calculate cost (default: true)
  - `:provider` - Provider name for cost calculation

  ## Examples

      ResponseBuilder.build_chat_response(%{
        "choices" => [%{"message" => %{"content" => "Hello!"}}],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5}
      }, "gpt-4", provider: :openai)
  """
  @spec build_chat_response(map(), String.t(), keyword()) :: Types.LLMResponse.t()
  def build_chat_response(data, model, opts \\ []) do
    provider = Keyword.get(opts, :provider)
    calculate_cost = Keyword.get(opts, :calculate_cost, true)

    # Extract content based on common patterns
    content = extract_content(data)
    usage = extract_usage(data)
    finish_reason = extract_finish_reason(data)

    # Calculate cost if requested and we have usage data
    cost =
      if calculate_cost && usage != nil && provider != nil do
        Cost.calculate(provider, model, usage)
      else
        nil
      end

    %Types.LLMResponse{
      content: content,
      model: model,
      usage: usage,
      finish_reason: finish_reason,
      cost: cost,
      id: data["id"],
      metadata: extract_metadata(data, opts)
    }
  end

  @doc """
  Build a streaming chunk from provider data.
  """
  @spec build_stream_chunk(map(), keyword()) :: Types.StreamChunk.t() | nil
  def build_stream_chunk(data, opts \\ []) do
    case extract_stream_content(data) do
      nil ->
        nil

      {content, finish_reason} ->
        %Types.StreamChunk{
          content: content,
          finish_reason: finish_reason,
          model: Keyword.get(opts, :model),
          id: data["id"],
          metadata: extract_metadata(data, opts)
        }
    end
  end

  @doc """
  Build an embedding response from provider data.
  """
  @spec build_embedding_response(map(), String.t(), keyword()) :: Types.EmbeddingResponse.t()
  def build_embedding_response(data, model, opts \\ []) do
    provider = Keyword.get(opts, :provider)

    embeddings = extract_embeddings(data)
    usage = extract_embedding_usage(data)

    cost =
      if usage != nil && provider != nil do
        Cost.calculate(provider, model, usage)
      else
        nil
      end

    %Types.EmbeddingResponse{
      embeddings: embeddings,
      model: model,
      usage: usage,
      cost: cost
    }
  end

  @doc """
  Build a response with tool calls from provider data.
  """
  @spec build_tool_call_response(map(), String.t(), keyword()) :: Types.LLMResponse.t()
  def build_tool_call_response(data, model, opts \\ []) do
    provider = Keyword.get(opts, :provider)
    calculate_cost = Keyword.get(opts, :calculate_cost, true)

    tool_calls = extract_tool_calls(data)
    usage = extract_usage(data)
    finish_reason = extract_finish_reason(data)

    cost =
      if calculate_cost && usage != nil && provider != nil do
        Cost.calculate(provider, model, usage)
      else
        nil
      end

    %Types.LLMResponse{
      content: nil,
      model: model,
      usage: usage,
      finish_reason: finish_reason,
      cost: cost,
      tool_calls: tool_calls,
      id: data["id"]
    }
  end

  @doc """
  Build an error response from provider data.
  """
  @spec build_error_response(integer(), map() | String.t(), keyword()) :: {:error, term()}
  def build_error_response(status, data, opts \\ []) do
    _provider = Keyword.get(opts, :provider, :unknown)

    case normalize_error_data(data) do
      %{"error" => %{"type" => type, "message" => message}} ->
        categorize_structured_error(type, message)

      %{"error" => %{"message" => message}} ->
        categorize_error_by_status(status, message)

      %{"error" => message} when is_binary(message) ->
        categorize_error_by_status(status, message)

      %{"message" => message} ->
        categorize_error_by_status(status, message)

      %{"detail" => detail} ->
        categorize_error_by_status(status, detail)

      _ ->
        {:error, ExLLM.Error.api_error(status, data)}
    end
  end

  @doc """
  Build a completion response (non-chat format) from provider data.

  Used for providers that support traditional completion endpoints.
  """
  @spec build_completion_response(map(), String.t(), keyword()) :: Types.LLMResponse.t()
  def build_completion_response(data, model, opts \\ []) do
    provider = Keyword.get(opts, :provider)
    calculate_cost = Keyword.get(opts, :calculate_cost, true)

    # Extract text from completion format
    content = extract_completion_content(data)
    usage = extract_usage(data)
    finish_reason = extract_finish_reason(data)

    cost =
      if calculate_cost && usage != nil && provider != nil do
        Cost.calculate(provider, model, usage)
      else
        nil
      end

    %Types.LLMResponse{
      content: content,
      model: model,
      usage: usage,
      finish_reason: finish_reason,
      cost: cost,
      id: data["id"],
      metadata: extract_metadata(data, opts)
    }
  end

  @doc """
  Build an image generation response from provider data.

  Used for DALL-E and similar image generation endpoints.
  """
  @spec build_image_response(map(), String.t(), keyword()) :: map()
  def build_image_response(data, model, opts \\ []) do
    provider = Keyword.get(opts, :provider)

    images = extract_images(data)

    %{
      images: images,
      model: model,
      created: data["created"],
      metadata: extract_metadata(data, opts),
      provider: provider
    }
  end

  @doc """
  Build an audio transcription response from provider data.

  Used for Whisper and similar audio transcription endpoints.
  """
  @spec build_audio_response(map(), String.t(), keyword()) :: map()
  def build_audio_response(data, model, opts \\ []) do
    provider = Keyword.get(opts, :provider)
    response_format = Keyword.get(opts, :response_format, "json")

    content =
      case response_format do
        "text" -> data
        "json" -> data["text"] || data["transcript"]
        "srt" -> data
        "vtt" -> data
        "verbose_json" -> data
        _ -> data["text"] || data
      end

    # For verbose_json format
    metadata =
      if response_format == "verbose_json" do
        %{
          language: data["language"],
          duration: data["duration"],
          segments: data["segments"],
          words: data["words"]
        }
      else
        extract_metadata(data, opts)
      end

    %{
      content: content,
      model: model,
      metadata: metadata,
      provider: provider
    }
  end

  @doc """
  Build a moderation response from provider data.

  Used for content moderation endpoints.
  """
  @spec build_moderation_response(map(), String.t(), keyword()) :: map()
  def build_moderation_response(data, model, opts \\ []) do
    provider = Keyword.get(opts, :provider)

    results = extract_moderation_results(data)

    %{
      results: results,
      model: model,
      flagged: Enum.any?(results, & &1.flagged),
      metadata: extract_metadata(data, opts),
      provider: provider
    }
  end

  @doc """
  Extract metadata from response data.

  Includes timing information, model details, and provider-specific metadata.
  """
  @spec extract_metadata(map(), keyword()) :: map()
  def extract_metadata(data, opts \\ []) do
    # Start with any existing metadata from the data
    metadata = Map.get(data, "metadata", %{})

    # Add timing information if available
    metadata =
      if data["created"] do
        Map.put(metadata, :created_at, data["created"])
      else
        metadata
      end

    # Add model version/details
    metadata =
      if data["model"] do
        Map.put(metadata, :model_version, data["model"])
      else
        metadata
      end

    # Add system fingerprint (OpenAI)
    metadata =
      if data["system_fingerprint"] do
        Map.put(metadata, :system_fingerprint, data["system_fingerprint"])
      else
        metadata
      end

    # Add provider-specific metadata
    provider = Keyword.get(opts, :provider)
    add_provider_metadata(metadata, data, provider)
  end

  @doc """
  Extract and normalize usage data from various formats.

  Maps provider-specific field names to standardized ExLLM format:
  - API field names: prompt_tokens, completion_tokens (OpenAI, OpenRouter, etc.)
  - ExLLM field names: input_tokens, output_tokens
  """
  @spec extract_usage(map()) :: map() | nil
  def extract_usage(data) do
    cond do
      # OpenAI/Anthropic format
      usage = data["usage"] ->
        %{
          input_tokens: usage["prompt_tokens"] || usage["input_tokens"] || 0,
          output_tokens: usage["completion_tokens"] || usage["output_tokens"] || 0,
          total_tokens: usage["total_tokens"] || 0
        }

      # Gemini format
      metadata = data["usageMetadata"] ->
        %{
          input_tokens: metadata["promptTokenCount"] || 0,
          output_tokens: metadata["candidatesTokenCount"] || 0,
          total_tokens: metadata["totalTokenCount"] || 0
        }

      true ->
        nil
    end
  end

  # Private extraction functions

  defp extract_content(data) do
    cond do
      # OpenAI/Groq format
      choices = data["choices"] ->
        get_in(choices, [Access.at(0), "message", "content"])

      # Anthropic format
      content = data["content"] ->
        case content do
          [%{"text" => text} | _] -> text
          text when is_binary(text) -> text
          _ -> nil
        end

      # Gemini format
      candidates = data["candidates"] ->
        get_in(candidates, [Access.at(0), "content", "parts", Access.at(0), "text"])

      true ->
        nil
    end
  end

  defp extract_finish_reason(data) do
    cond do
      # OpenAI format
      choices = data["choices"] ->
        get_in(choices, [Access.at(0), "finish_reason"])

      # Anthropic format
      stop_reason = data["stop_reason"] ->
        stop_reason

      # Gemini format
      candidates = data["candidates"] ->
        get_in(candidates, [Access.at(0), "finishReason"])

      true ->
        nil
    end
  end

  defp extract_stream_content(data) do
    cond do
      # OpenAI stream format
      choices = data["choices"] ->
        delta = get_in(choices, [Access.at(0), "delta"])
        finish = get_in(choices, [Access.at(0), "finish_reason"])
        {delta["content"], finish}

      # Anthropic stream format
      data["type"] == "content_block_delta" ->
        {get_in(data, ["delta", "text"]), nil}

      data["type"] == "message_delta" ->
        {nil, get_in(data, ["delta", "stop_reason"])}

      # End markers
      data["type"] == "message_stop" ->
        {nil, "stop"}

      true ->
        nil
    end
  end

  defp extract_embeddings(data) do
    cond do
      # OpenAI format
      embeddings = data["data"] ->
        Enum.map(embeddings, & &1["embedding"])

      # Single embedding
      embedding = data["embedding"] ->
        [embedding]

      true ->
        []
    end
  end

  defp extract_embedding_usage(data) do
    if usage = data["usage"] do
      %{
        input_tokens: usage["prompt_tokens"] || usage["total_tokens"] || 0,
        # Embeddings don't have output tokens
        output_tokens: 0
      }
    else
      nil
    end
  end

  defp extract_tool_calls(data) do
    cond do
      # OpenAI format
      choices = data["choices"] ->
        message = get_in(choices, [Access.at(0), "message"])
        message["tool_calls"] || []

      # Anthropic format
      content = data["content"] ->
        content
        |> Enum.filter(&(&1["type"] == "tool_use"))
        |> Enum.map(fn tool_use ->
          %{
            "id" => tool_use["id"],
            "type" => "function",
            "function" => %{
              "name" => tool_use["name"],
              "arguments" => Jason.encode!(tool_use["input"] || %{})
            }
          }
        end)

      true ->
        []
    end
  end

  defp normalize_error_data(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{"error" => data}
    end
  end

  defp normalize_error_data(data) when is_map(data), do: data
  defp normalize_error_data(data), do: %{"error" => inspect(data)}

  defp categorize_structured_error("authentication_error", message) do
    {:error, ExLLM.Error.authentication_error(message)}
  end

  defp categorize_structured_error("rate_limit_error", message) do
    {:error, ExLLM.Error.rate_limit_error(message)}
  end

  defp categorize_structured_error("invalid_request_error", message) do
    {:error, ExLLM.Error.validation_error(:request, message)}
  end

  defp categorize_structured_error("insufficient_quota", message) do
    {:error, ExLLM.Error.rate_limit_error(message)}
  end

  defp categorize_structured_error(_, message) do
    {:error, ExLLM.Error.api_error(nil, message)}
  end

  defp categorize_error_by_status(401, message) do
    {:error, ExLLM.Error.authentication_error(message)}
  end

  defp categorize_error_by_status(403, message) do
    {:error, ExLLM.Error.authentication_error(message)}
  end

  defp categorize_error_by_status(429, message) do
    {:error, ExLLM.Error.rate_limit_error(message)}
  end

  defp categorize_error_by_status(503, message) do
    {:error, ExLLM.Error.service_unavailable(message)}
  end

  defp categorize_error_by_status(status, message) do
    {:error, ExLLM.Error.api_error(status, message)}
  end

  # New extraction functions for different response formats

  defp extract_completion_content(data) do
    cond do
      # OpenAI completion format
      choices = data["choices"] ->
        get_in(choices, [Access.at(0), "text"])

      # Direct text field
      text = data["text"] ->
        text

      # Ollama generate format
      response = data["response"] ->
        response

      true ->
        nil
    end
  end

  defp extract_images(data) do
    cond do
      # OpenAI DALL-E format
      images = data["data"] ->
        Enum.map(images, fn img ->
          %{
            url: img["url"],
            b64_json: img["b64_json"],
            revised_prompt: img["revised_prompt"]
          }
        end)

      # Direct images array
      images = data["images"] ->
        images

      true ->
        []
    end
  end

  defp extract_moderation_results(data) do
    cond do
      # OpenAI moderation format
      results = data["results"] ->
        Enum.map(results, fn result ->
          %{
            flagged: result["flagged"],
            categories: result["categories"],
            category_scores: result["category_scores"]
          }
        end)

      # Single result
      result = data["result"] ->
        [result]

      true ->
        []
    end
  end

  defp add_provider_metadata(metadata, data, :openai) do
    metadata
    |> maybe_add_metadata(:service_tier, data["service_tier"])
    |> maybe_add_metadata(:object, data["object"])
  end

  defp add_provider_metadata(metadata, data, :anthropic) do
    metadata
    |> maybe_add_metadata(:stop_sequence, data["stop_sequence"])
    |> maybe_add_metadata(:log_id, data["log_id"])
  end

  defp add_provider_metadata(metadata, data, :gemini) do
    metadata
    |> maybe_add_metadata(:safety_ratings, data["safetyRatings"])
    |> maybe_add_metadata(:citation_metadata, data["citationMetadata"])
  end

  defp add_provider_metadata(metadata, data, :ollama) do
    metadata
    |> maybe_add_metadata(:total_duration, data["total_duration"])
    |> maybe_add_metadata(:load_duration, data["load_duration"])
    |> maybe_add_metadata(:prompt_eval_duration, data["prompt_eval_duration"])
    |> maybe_add_metadata(:eval_duration, data["eval_duration"])
    |> maybe_add_metadata(:context, data["context"])
  end

  defp add_provider_metadata(metadata, data, :openrouter) do
    metadata
    |> maybe_add_metadata(:generation_id, data["generation_id"])
    |> maybe_add_metadata(:provider, data["provider"])
    |> maybe_add_metadata(:latency_ms, data["latency_ms"])
  end

  defp add_provider_metadata(metadata, _data, _provider), do: metadata

  defp maybe_add_metadata(metadata, _key, nil), do: metadata
  defp maybe_add_metadata(metadata, key, value), do: Map.put(metadata, key, value)
end
