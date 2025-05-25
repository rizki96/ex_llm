defmodule ExLLM do
  @moduledoc """
  ExLLM - Unified Elixir client library for Large Language Models.

  ExLLM provides a consistent interface across multiple LLM providers including
  OpenAI, Anthropic Claude, Ollama, and others. It features configuration injection,
  standardized error handling, and streaming support.

  ## Quick Start

      # Using environment variables
      messages = [%{role: "user", content: "Hello!"}]
      {:ok, response} = ExLLM.chat(:anthropic, messages)
      IO.puts(response.content)

      # Using static configuration
      config = %{anthropic: %{api_key: "your-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)
      {:ok, response} = ExLLM.chat(:anthropic, messages, config_provider: provider)

  ## Supported Providers

  - `:anthropic` - Anthropic Claude models
  - `:openai` - OpenAI GPT models  
  - `:ollama` - Local Ollama models
  - More providers coming soon!

  ## Features

  - **Unified Interface**: Same API across all providers
  - **Configuration Injection**: Flexible config management
  - **Streaming Support**: Real-time response streaming
  - **Error Standardization**: Consistent error handling
  - **No Process Dependencies**: Pure functional core
  - **Extensible**: Easy to add new providers

  ## Configuration

  ExLLM supports multiple configuration methods:

  ### Environment Variables

      export OPENAI_API_KEY="sk-..."
      export ANTHROPIC_API_KEY="api-..."
      export OLLAMA_BASE_URL="http://localhost:11434"

  ### Static Configuration

      config = %{
        openai: %{api_key: "sk-...", model: "gpt-4"},
        anthropic: %{api_key: "api-...", model: "claude-3"},
        ollama: %{base_url: "http://localhost:11434", model: "llama2"}
      }
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

  ### Custom Configuration

      defmodule MyConfigProvider do
        @behaviour ExLLM.ConfigProvider
        
        def get([:openai, :api_key]), do: MyApp.get_secret("openai_key")
        def get(_), do: nil
        
        def get_all(), do: %{}
      end

  ## Examples

      # Simple chat
      {:ok, response} = ExLLM.chat(:openai, [
        %{role: "user", content: "What is Elixir?"}
      ])

      # With options
      {:ok, response} = ExLLM.chat(:anthropic, messages,
        model: "claude-3-haiku-20240307",
        temperature: 0.7,
        max_tokens: 1000
      )

      # Streaming
      {:ok, stream} = ExLLM.stream_chat(:openai, messages)
      for chunk <- stream do
        if chunk.content, do: IO.write(chunk.content)
      end

      # Check if provider is configured
      if ExLLM.configured?(:anthropic) do
        {:ok, response} = ExLLM.chat(:anthropic, messages)
      end

      # List available models
      {:ok, models} = ExLLM.list_models(:openai)
      Enum.each(models, fn model ->
        IO.puts(model.name)
      end)
  """

  alias ExLLM.{Cost, Types}

  @providers %{
    anthropic: ExLLM.Adapters.Anthropic
    # openai: ExLLM.Adapters.OpenAI,
    # ollama: ExLLM.Adapters.Ollama
  }

  @type provider :: :anthropic | :openai | :ollama
  @type messages :: [Types.message()]
  @type options :: keyword()

  @doc """
  Send a chat completion request to the specified LLM provider.

  ## Parameters
  - `provider` - The LLM provider (`:anthropic`, `:openai`, `:ollama`)
  - `messages` - List of conversation messages
  - `options` - Options for the request (see module docs)

  ## Returns
  `{:ok, %ExLLM.Types.LLMResponse{}}` on success, `{:error, reason}` on failure.

  ## Examples

      # Simple usage
      {:ok, response} = ExLLM.chat(:anthropic, [
        %{role: "user", content: "Hello!"}
      ])

      # With custom configuration
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(%{
        anthropic: %{api_key: "your-key"}
      })
      {:ok, response} = ExLLM.chat(:anthropic, messages, config_provider: provider)

      # With model override
      {:ok, response} = ExLLM.chat(:openai, messages, model: "gpt-4-turbo")
  """
  @spec chat(provider(), messages(), options()) ::
          {:ok, Types.LLMResponse.t()} | {:error, term()}
  def chat(provider, messages, options \\ []) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        adapter.chat(messages, options)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Send a streaming chat completion request to the specified LLM provider.

  ## Parameters
  - `provider` - The LLM provider (`:anthropic`, `:openai`, `:ollama`)
  - `messages` - List of conversation messages
  - `options` - Options for the request (see module docs)

  ## Returns
  `{:ok, stream}` on success where stream yields `%ExLLM.Types.StreamChunk{}` structs,
  `{:error, reason}` on failure.

  ## Examples

      {:ok, stream} = ExLLM.stream_chat(:anthropic, messages)
      
      # Process the stream
      for chunk <- stream do
        case chunk do
          %{content: content} when content != nil ->
            IO.write(content)
          %{finish_reason: "stop"} ->
            IO.puts("\\nDone!")
          _ ->
            :continue
        end
      end
  """
  @spec stream_chat(provider(), messages(), options()) ::
          {:ok, Types.stream()} | {:error, term()}
  def stream_chat(provider, messages, options \\ []) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        adapter.stream_chat(messages, options)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if the specified provider is properly configured.

  ## Parameters
  - `provider` - The LLM provider to check
  - `options` - Options including configuration provider

  ## Returns
  `true` if configured, `false` otherwise.

  ## Examples

      if ExLLM.configured?(:anthropic) do
        {:ok, response} = ExLLM.chat(:anthropic, messages)
      else
        IO.puts("Anthropic not configured")
      end
  """
  @spec configured?(provider(), options()) :: boolean()
  def configured?(provider, options \\ []) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        adapter.configured?(options)

      {:error, _} ->
        false
    end
  end

  @doc """
  Get the default model for the specified provider.

  ## Parameters
  - `provider` - The LLM provider

  ## Returns
  String model identifier.

  ## Examples

      model = ExLLM.default_model(:anthropic)
      # => "claude-sonnet-4-20250514"
  """
  @spec default_model(provider()) :: String.t() | {:error, term()}
  def default_model(provider) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        adapter.default_model()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  List available models for the specified provider.

  ## Parameters
  - `provider` - The LLM provider
  - `options` - Options including configuration provider

  ## Returns
  `{:ok, [%ExLLM.Types.Model{}]}` on success, `{:error, reason}` on failure.

  ## Examples

      {:ok, models} = ExLLM.list_models(:anthropic)
      Enum.each(models, fn model ->
        IO.puts(model.name)
      end)
  """
  @spec list_models(provider(), options()) ::
          {:ok, [Types.Model.t()]} | {:error, term()}
  def list_models(provider, options \\ []) do
    case get_adapter(provider) do
      {:ok, adapter} ->
        adapter.list_models(options)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Calculate cost for token usage.

  ## Parameters
  - `provider` - LLM provider name
  - `model` - Model name
  - `token_usage` - Map with `:input_tokens` and `:output_tokens`

  ## Returns
  Cost calculation result or error map.

  ## Examples

      usage = %{input_tokens: 1000, output_tokens: 500}
      cost = ExLLM.calculate_cost("openai", "gpt-4", usage)
      # => %{total_cost: 0.06, ...}
  """
  @spec calculate_cost(provider(), String.t(), Types.token_usage()) ::
          Types.cost_result() | %{error: String.t()}
  def calculate_cost(provider, model, token_usage) do
    Cost.calculate(to_string(provider), model, token_usage)
  end

  @doc """
  Estimate token count for text.

  ## Parameters
  - `text` - Text to analyze (string, message map, or list)

  ## Returns
  Estimated token count.

  ## Examples

      tokens = ExLLM.estimate_tokens("Hello, world!")
      # => 4
  """
  @spec estimate_tokens(String.t() | map() | [map()]) :: non_neg_integer()
  def estimate_tokens(text) do
    Cost.estimate_tokens(text)
  end

  @doc """
  Format cost for display.

  ## Parameters
  - `cost` - Cost in dollars

  ## Returns
  Formatted cost string.

  ## Examples

      ExLLM.format_cost(0.0035)
      # => "$0.350¢"
  """
  @spec format_cost(float()) :: String.t()
  def format_cost(cost) do
    Cost.format(cost)
  end

  @doc """
  Get list of supported providers.

  ## Returns
  List of provider atoms.

  ## Examples

      providers = ExLLM.supported_providers()
      # => [:anthropic, :openai, :ollama]
  """
  @spec supported_providers() :: [provider()]
  def supported_providers do
    Map.keys(@providers)
  end

  # Private functions

  defp get_adapter(provider) do
    case Map.get(@providers, provider) do
      nil ->
        {:error, {:unsupported_provider, provider}}

      adapter ->
        {:ok, adapter}
    end
  end
end
