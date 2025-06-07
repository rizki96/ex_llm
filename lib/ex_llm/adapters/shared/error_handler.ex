defmodule ExLLM.Adapters.Shared.ErrorHandler do
  @moduledoc """
  Shared error handling utilities for ExLLM adapters.

  Provides consistent error handling patterns across all provider adapters,
  including provider-specific error parsing and standardization.
  """

  alias ExLLM.Error

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

  def handle_provider_error(:openai, status, %{"error" => error}) when is_map(error) do
    handle_openai_error(status, error)
  end

  def handle_provider_error(:anthropic, status, %{"error" => error}) when is_map(error) do
    handle_anthropic_error(status, error)
  end

  def handle_provider_error(:groq, status, %{"error" => error}) do
    # Groq uses OpenAI-compatible errors
    handle_openai_error(status, error)
  end

  def handle_provider_error(:gemini, status, %{"error" => error}) when is_map(error) do
    handle_gemini_error(status, error)
  end

  def handle_provider_error(:openrouter, status, %{"error" => error}) do
    handle_openrouter_error(status, error)
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
end
