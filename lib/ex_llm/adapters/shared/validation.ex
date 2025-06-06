defmodule ExLLM.Adapters.Shared.Validation do
  @moduledoc """
  Shared validation functions for ExLLM adapters.
  
  This module provides common validation patterns used across different
  adapters to ensure consistency and reduce code duplication.
  """

  @doc """
  Validates an API key is present and not empty.
  
  ## Examples
  
      iex> Validation.validate_api_key("sk-1234567890")
      {:ok, :valid}
      
      iex> Validation.validate_api_key(nil)
      {:error, "API key not configured"}
      
      iex> Validation.validate_api_key("")
      {:error, "API key not configured"}
  """
  @spec validate_api_key(String.t() | nil) :: {:ok, :valid} | {:error, String.t()}
  def validate_api_key(nil), do: {:error, "API key not configured"}
  def validate_api_key(""), do: {:error, "API key not configured"}
  def validate_api_key(_api_key), do: {:ok, :valid}
  
  @doc """
  Validates a base URL is properly formatted.
  
  ## Examples
  
      iex> Validation.validate_base_url("https://api.example.com")
      {:ok, :valid}
      
      iex> Validation.validate_base_url("not-a-url")
      {:error, "Invalid base URL format"}
  """
  @spec validate_base_url(String.t() | nil) :: {:ok, :valid} | {:error, String.t()}
  def validate_base_url(nil), do: {:ok, :valid}  # nil is OK, will use default
  def validate_base_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
        {:ok, :valid}
      _ ->
        {:error, "Invalid base URL format"}
    end
  end
  def validate_base_url(_), do: {:error, "Invalid base URL format"}
end