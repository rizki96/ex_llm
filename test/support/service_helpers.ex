defmodule ExLLM.Testing.ServiceHelpers do
  @moduledoc """
  Test helpers for checking local service availability.
  
  Provides functions to check if local services like Ollama and LM Studio
  are running before attempting to run tests that depend on them.
  """

  @doc """
  Check if a local service is available and running.
  
  Returns `{:ok, :available}` if the service is running, or
  `{:error, reason}` if not available.
  """
  def check_service_availability(provider) do
    case provider do
      :ollama -> check_ollama()
      :lmstudio -> check_lmstudio()
      _ -> {:ok, :available}
    end
  end

  @doc """
  Skip test if local service is not available.
  
  Returns `{:skip, reason}` if the service is not running, otherwise `:ok`.
  """
  def skip_unless_service_available(provider) do
    case check_service_availability(provider) do
      {:ok, :available} ->
        :ok
        
      {:error, reason} ->
        {:skip, "Service #{provider} is not available: #{reason}"}
    end
  end

  # Check if Ollama is running by attempting to connect to its API
  defp check_ollama do
    base_url = System.get_env("OLLAMA_HOST", "http://localhost:11434")
    
    client = ExLLM.Providers.Shared.HTTP.Core.client(
      provider: :ollama,
      base_url: base_url
    )
    
    case Tesla.get(client, "/api/tags", opts: [timeout: 5_000]) do
      {:ok, %Tesla.Env{status: 200}} ->
        {:ok, :available}
        
      {:ok, %Tesla.Env{status: status}} ->
        {:error, "unexpected status #{status}"}
        
      {:error, :econnrefused} ->
        {:error, "connection refused - Ollama not running"}
        
      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    _ ->
      {:error, "failed to check Ollama availability"}
  end

  # Check if LM Studio is running
  defp check_lmstudio do
    base_url = System.get_env("LMSTUDIO_HOST", "http://localhost:1234")
    
    client = ExLLM.Providers.Shared.HTTP.Core.client(
      provider: :lmstudio,
      base_url: base_url
    )
    
    # LM Studio uses OpenAI-compatible API
    case Tesla.get(client, "/v1/models", opts: [timeout: 5_000]) do
      {:ok, %Tesla.Env{status: 200}} ->
        {:ok, :available}
        
      {:ok, %Tesla.Env{status: status, body: body}} ->
        # LM Studio sometimes returns 200 with error in body
        if is_map(body) && Map.has_key?(body, "error") do
          {:error, "LM Studio error: #{inspect(body["error"])}"}
        else
          {:error, "unexpected status #{status}"}
        end
        
      {:error, :econnrefused} ->
        {:error, "connection refused - LM Studio not running"}
        
      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    _ ->
      {:error, "failed to check LM Studio availability"}
  end

  @doc """
  Combined helper that checks both capability and service availability.
  
  Use this in tests that require both a specific capability and a running service.
  """
  def skip_unless_configured_supports_and_available(provider, capability) do
    with :ok <- ExLLM.Testing.CapabilityHelpers.skip_unless_configured_and_supports(provider, capability),
         :ok <- skip_unless_service_available(provider) do
      :ok
    end
  end
end