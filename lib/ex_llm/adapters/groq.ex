defmodule ExLLM.Adapters.Groq do
  @moduledoc """
  Groq adapter for ExLLM.
  
  Groq provides extremely fast inference for open-source models using their
  custom LPU (Language Processing Unit) hardware.
  
  ## Configuration
  
      config :ex_llm,
        groq: [
          api_key: System.get_env("GROQ_API_KEY"),
          base_url: "https://api.groq.com/openai/v1"  # optional
        ]
  
  ## Supported Models
  
  - llama-3.3-70b-versatile
  - llama-3.1-70b-versatile
  - llama-3.1-8b-instant
  - llama3-70b-8192
  - llama3-8b-8192
  - mixtral-8x7b-32768
  - gemma2-9b-it
  - gemma-7b-it
  
  ## Example Usage
  
      messages = [
        %{role: "user", content: "Hello, how are you?"}
      ]
      
      {:ok, response} = ExLLM.Adapters.Groq.chat(messages, model: "llama3-70b-8192")
  """
  
  alias ExLLM.{Error, ModelConfig}
  
  use ExLLM.Adapters.OpenAICompatible,
    provider: :groq,
    base_url: "https://api.groq.com/openai/v1",
    models: [
      "llama-3.3-70b-versatile",
      "llama-3.1-70b-versatile", 
      "llama-3.1-8b-instant",
      "llama3-70b-8192",
      "llama3-8b-8192",
      "mixtral-8x7b-32768",
      "gemma2-9b-it",
      "gemma-7b-it"
    ]
  
  @impl ExLLM.Adapter
  def default_model do
    ModelConfig.get_default_model(:groq)
  end
  
  @impl ExLLM.Adapters.OpenAICompatible
  def get_api_key(config) do
    Map.get(config, :api_key) || System.get_env("GROQ_API_KEY")
  end
  
  @impl ExLLM.Adapters.OpenAICompatible
  def get_headers(api_key, options) do
    base_headers = super(api_key, options)
    
    # Add Groq-specific headers if needed
    base_headers ++ [
      {"x-groq-version", "v1"}
    ]
  end
  
  @impl ExLLM.Adapters.OpenAICompatible
  def transform_request(request, _options) do
    # Groq has some specific parameter handling
    request
    |> handle_groq_stop_sequences()
    |> handle_groq_temperature()
  end
  
  @impl ExLLM.Adapters.OpenAICompatible
  def filter_model(%{"id" => id}) do
    # Only show LLM models, not whisper models
    not String.contains?(id, "whisper")
  end
  
  @impl ExLLM.Adapters.OpenAICompatible
  def parse_error(%{status: 429, body: %{"error" => error}}) do
    # Groq provides rate limit info in headers
    message = error["message"] || "Rate limit exceeded"
    {:error, Error.rate_limit_error("Groq: #{message}")}
  end
  
  def parse_error(%{status: 503}) do
    {:error, Error.service_unavailable("Groq LPU cluster is at capacity")}
  end
  
  def parse_error(response) do
    # Fall back to default error handling
    super(response)
  end
  
  # Private functions
  
  defp handle_groq_stop_sequences(request) do
    # Groq supports max 4 stop sequences
    case Map.get(request, "stop") do
      nil -> request
      stops when is_list(stops) and length(stops) > 4 ->
        Map.put(request, "stop", Enum.take(stops, 4))
      _ -> request
    end
  end
  
  defp handle_groq_temperature(request) do
    # Groq recommends temperature between 0 and 2
    case Map.get(request, "temperature") do
      nil -> request
      temp when temp > 2 -> Map.put(request, "temperature", 2)
      temp when temp < 0 -> Map.put(request, "temperature", 0)
      _ -> request
    end
  end
end