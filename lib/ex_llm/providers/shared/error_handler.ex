defmodule ExLLM.Providers.Shared.ErrorHandler do
  @moduledoc false

  alias ExLLM.Infrastructure.Error, as: Error

  @doc """
  Handle provider-specific errors and convert to standard ExLLM errors.

  ## Examples

      # OpenAI-style error
      ErrorHandler.handle_provider_error(:openai, 429, %{
        "error" => %{
          "type" => "rate_limit_error",
          "message" => "Rate limit exceeded"
        }
      })
      
      # Anthropic-style error  
      ErrorHandler.handle_provider_error(:anthropic, 400, %{
        "error" => %{
          "type" => "invalid_request_error",
          "message" => "max_tokens required"
        }
      })
  """
  @spec handle_provider_error(atom(), integer(), map() | String.t()) :: {:error, term()}
  def handle_provider_error(provider, status, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> handle_provider_error(provider, status, parsed)
      {:error, _} -> Error.api_error(status, body)
    end
  end

  # OpenAI-compatible providers that use the same error format
  @openai_compatible_providers [:openai, :groq, :mistral, :perplexity, :xai, :together_ai]

  def handle_provider_error(provider, status, %{"error" => error})
      when provider in @openai_compatible_providers and is_map(error) do
    handle_openai_error(status, error)
  end

  def handle_provider_error(:anthropic, status, %{"error" => error}) when is_map(error) do
    handle_anthropic_error(status, error)
  end

  def handle_provider_error(:gemini, status, %{"error" => error}) when is_map(error) do
    handle_gemini_error(status, error)
  end

  def handle_provider_error(:openrouter, status, %{"error" => error}) do
    handle_openrouter_error(status, error)
  end

  def handle_provider_error(:ollama, status, %{"error" => error}) when is_binary(error) do
    handle_ollama_error(status, error)
  end

  def handle_provider_error(:bedrock, status, body) when is_map(body) do
    handle_bedrock_error(status, body)
  end

  def handle_provider_error(:cohere, status, body) when is_map(body) do
    handle_cohere_error(status, body)
  end

  def handle_provider_error(:replicate, status, body) when is_map(body) do
    handle_replicate_error(status, body)
  end

  def handle_provider_error(:huggingface, status, body) when is_map(body) do
    handle_huggingface_error(status, body)
  end

  def handle_provider_error(:vertex_ai, status, %{"error" => error}) do
    handle_vertex_ai_error(status, error)
  end

  def handle_provider_error(:azure, status, %{"error" => error}) do
    handle_azure_error(status, error)
  end

  def handle_provider_error(_provider, status, body) do
    Error.api_error(status, body)
  end

  @doc """
  Extract error message from various response formats.
  """
  @spec extract_error_message(map()) :: String.t() | nil
  def extract_error_message(%{"error" => %{"message" => message}}), do: message
  def extract_error_message(%{"error" => message}) when is_binary(message), do: message
  def extract_error_message(%{"message" => message}), do: message
  def extract_error_message(%{"detail" => detail}), do: detail
  def extract_error_message(_), do: nil

  @doc """
  Check if an error is retryable based on status code and error type.
  """
  @spec retryable_error?(integer(), map() | term()) :: boolean()
  def retryable_error?(status, _error) when status in [429, 502, 503, 504], do: true

  def retryable_error?(status, %{"error" => %{"type" => type}}) do
    status == 500 or type in ["server_error", "overloaded_error"]
  end

  def retryable_error?(_, _), do: false

  @doc """
  Extract retry-after header value if present.
  """
  @spec get_retry_after(list({String.t(), String.t()})) :: integer() | nil
  def get_retry_after(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} -> parse_retry_after(value)
      nil -> nil
    end
  end

  # Private functions

  defp handle_openai_error(status, %{"type" => type, "message" => message}) do
    case type do
      "authentication_error" -> Error.authentication_error(message)
      "invalid_api_key" -> Error.authentication_error(message)
      "rate_limit_error" -> Error.rate_limit_error(message)
      "invalid_request_error" -> Error.validation_error(:request, message)
      "model_not_found" -> Error.validation_error(:model, message)
      "context_length_exceeded" -> Error.validation_error(:context, message)
      "server_error" -> Error.service_unavailable(message)
      _ -> Error.api_error(status, %{type: type, message: message})
    end
  end

  defp handle_openai_error(status, error) do
    message = extract_error_message(error) || "Unknown error"
    Error.api_error(status, message)
  end

  defp handle_anthropic_error(status, %{"type" => type, "message" => message}) do
    case type do
      "authentication_error" -> Error.authentication_error(message)
      "permission_error" -> Error.authentication_error(message)
      "rate_limit_error" -> Error.rate_limit_error(message)
      "invalid_request_error" -> Error.validation_error(:request, message)
      "not_found_error" -> {:error, :not_found}
      "overloaded_error" -> Error.service_unavailable(message)
      _ -> Error.api_error(status, %{type: type, message: message})
    end
  end

  defp handle_anthropic_error(status, error) do
    message = extract_error_message(error) || "Unknown error"
    Error.api_error(status, message)
  end

  defp handle_gemini_error(status, %{"code" => code, "message" => message}) do
    case code do
      401 -> Error.authentication_error(message)
      403 -> Error.authentication_error(message)
      429 -> Error.rate_limit_error(message)
      400 -> Error.validation_error(:request, message)
      404 -> {:error, :not_found}
      503 -> Error.service_unavailable(message)
      _ -> Error.api_error(status, %{code: code, message: message})
    end
  end

  defp handle_gemini_error(status, error) do
    message = extract_error_message(error) || "Unknown error"
    Error.api_error(status, message)
  end

  defp handle_openrouter_error(status, %{"code" => code, "message" => message}) do
    case code do
      "invalid_api_key" -> Error.authentication_error(message)
      "rate_limit_exceeded" -> Error.rate_limit_error(message)
      "context_length_exceeded" -> Error.validation_error(:context, message)
      "model_not_found" -> Error.validation_error(:model, message)
      _ -> Error.api_error(status, %{code: code, message: message})
    end
  end

  defp handle_openrouter_error(status, error) when is_binary(error) do
    Error.api_error(status, error)
  end

  defp handle_openrouter_error(status, error) do
    message = extract_error_message(error) || "Unknown error"
    Error.api_error(status, message)
  end

  defp parse_retry_after(value) do
    case Integer.parse(value) do
      # Convert to milliseconds
      {seconds, ""} -> seconds * 1000
      _ -> nil
    end
  end

  # New provider-specific error handlers

  defp handle_ollama_error(status, message) when is_binary(message) do
    cond do
      String.contains?(message, "model not found") ->
        Error.validation_error(:model, message)

      String.contains?(message, "context length") ->
        Error.validation_error(:context, message)

      status == 503 ->
        Error.service_unavailable(message)

      true ->
        Error.api_error(status, message)
    end
  end

  defp handle_bedrock_error(status, body) do
    # AWS Bedrock errors
    case body do
      %{"__type" => type, "message" => message} ->
        handle_aws_error_type(type, message, status)

      %{"message" => message} ->
        Error.api_error(status, message)

      _ ->
        Error.api_error(status, body)
    end
  end

  defp handle_aws_error_type(type, message, status) do
    case type do
      "AccessDeniedException" -> Error.authentication_error(message)
      "ThrottlingException" -> Error.rate_limit_error(message)
      "ValidationException" -> Error.validation_error(:request, message)
      "ResourceNotFoundException" -> {:error, :not_found}
      "ModelStreamErrorException" -> Error.service_unavailable(message)
      "ModelTimeoutException" -> {:error, :timeout}
      _ -> Error.api_error(status, %{type: type, message: message})
    end
  end

  defp handle_cohere_error(status, body) do
    case body do
      %{"message" => message} ->
        cond do
          status == 401 -> Error.authentication_error(message)
          status == 429 -> Error.rate_limit_error(message)
          status == 400 -> Error.validation_error(:request, message)
          true -> Error.api_error(status, message)
        end

      _ ->
        Error.api_error(status, body)
    end
  end

  defp handle_replicate_error(status, body) do
    case body do
      %{"detail" => detail} ->
        cond do
          status == 401 -> Error.authentication_error(detail)
          status == 422 -> Error.validation_error(:request, detail)
          status == 429 -> Error.rate_limit_error(detail)
          true -> Error.api_error(status, detail)
        end

      %{"error" => error} ->
        Error.api_error(status, error)

      _ ->
        Error.api_error(status, body)
    end
  end

  defp handle_huggingface_error(status, body) do
    case body do
      %{"error" => error} when is_binary(error) ->
        cond do
          String.contains?(error, "authorization") ->
            Error.authentication_error(error)

          String.contains?(error, "rate limit") ->
            Error.rate_limit_error(error)

          true ->
            Error.api_error(status, error)
        end

      %{"error" => error_map} when is_map(error_map) ->
        message = error_map["message"] || inspect(error_map)
        Error.api_error(status, message)

      _ ->
        Error.api_error(status, body)
    end
  end

  defp handle_vertex_ai_error(status, %{"code" => code, "message" => message}) do
    # Google Cloud errors
    case code do
      401 -> Error.authentication_error(message)
      403 -> Error.authentication_error(message)
      429 -> Error.rate_limit_error(message)
      400 -> Error.validation_error(:request, message)
      404 -> {:error, :not_found}
      _ -> Error.api_error(status, %{code: code, message: message})
    end
  end

  defp handle_vertex_ai_error(status, error) do
    message = extract_error_message(error) || "Unknown error"
    Error.api_error(status, message)
  end

  defp handle_azure_error(status, %{"code" => code, "message" => message}) do
    # Azure OpenAI errors
    case code do
      "Unauthorized" -> Error.authentication_error(message)
      "InvalidApiKey" -> Error.authentication_error(message)
      "RateLimitExceeded" -> Error.rate_limit_error(message)
      "InvalidRequest" -> Error.validation_error(:request, message)
      "ContentFilter" -> Error.validation_error(:content, message)
      _ -> Error.api_error(status, %{code: code, message: message})
    end
  end

  defp handle_azure_error(status, error) do
    message = extract_error_message(error) || "Unknown error"
    Error.api_error(status, message)
  end

  @doc """
  Normalize error responses across providers for consistent handling.

  Returns a standardized error tuple.
  """
  @spec normalize_error(atom(), integer(), term()) :: {:error, term()}
  def normalize_error(provider, status, body) do
    handle_provider_error(provider, status, body)
  end

  @doc """
  Check if an error should trigger a retry based on provider-specific rules.
  """
  @spec should_retry?(atom(), integer(), term()) :: boolean()
  # Overloaded
  def should_retry?(:anthropic, 529, _), do: true
  # Rate limit
  def should_retry?(:openai, 429, _), do: true
  # Service unavailable
  def should_retry?(:openai, 503, _), do: true
  def should_retry?(:bedrock, _, %{"__type" => "ThrottlingException"}), do: true
  def should_retry?(:bedrock, _, %{"__type" => "ModelStreamErrorException"}), do: true
  def should_retry?(:gemini, 429, _), do: true
  def should_retry?(:gemini, 503, _), do: true
  def should_retry?(_, status, _) when status in [500, 502, 503, 504], do: true
  def should_retry?(_, _, _), do: false
end
