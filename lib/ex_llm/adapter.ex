defmodule ExLLM.Adapter do
  @moduledoc """
  Behaviour for LLM backend adapters.

  This defines the common interface that all LLM adapters must implement,
  enabling a unified API across different providers.

  ## Example Implementation

      defmodule MyAdapter do
        @behaviour ExLLM.Adapter
        alias ExLLM.Types
        
        @impl true
        def chat(messages, options \\ []) do
          # Implementation here
          {:ok, %Types.LLMResponse{content: "Hello"}}
        end
        
        @impl true
        def stream_chat(messages, options \\ []) do
          # Implementation here
          {:ok, stream}
        end
        
        @impl true
        def configured?(options \\ []) do
          # Check if adapter is configured
          true
        end
        
        @impl true
        def default_model() do
          "my-model"
        end
        
        @impl true
        def list_models(options \\ []) do
          {:ok, ["model1", "model2"]}
        end
      end

  ## Options

  All adapter functions accept an options keyword list that can include:

  - `:config_provider` - Configuration provider for API keys and settings
  - `:model` - Override the default model for this request
  - `:temperature` - Control randomness (0.0 to 1.0)
  - `:max_tokens` - Maximum tokens in response
  - `:timeout` - Request timeout in milliseconds

  ## Configuration Injection

  Adapters support configuration injection through the `:config_provider` option:

      # Use environment variables
      ExLLM.OpenAI.chat(messages, config_provider: ExLLM.ConfigProvider.Env)
      
      # Use static config
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(%{
        openai: %{api_key: "sk-..."}
      })
      ExLLM.OpenAI.chat(messages, config_provider: provider)
  """

  alias ExLLM.Types

  @doc """
  Send a chat completion request to the LLM.

  ## Parameters
  - `messages` - List of conversation messages
  - `options` - Adapter options (see module documentation)

  ## Returns
  `{:ok, %ExLLM.Types.LLMResponse{}}` on success, `{:error, reason}` on failure.
  """
  @callback chat(messages :: [Types.message()], options :: Types.adapter_options()) ::
              {:ok, Types.LLMResponse.t()} | {:error, term()}

  @doc """
  Send a streaming chat completion request to the LLM.

  ## Parameters
  - `messages` - List of conversation messages  
  - `options` - Adapter options (see module documentation)

  ## Returns
  `{:ok, stream}` on success where stream yields `%ExLLM.Types.StreamChunk{}` structs,
  `{:error, reason}` on failure.
  """
  @callback stream_chat(messages :: [Types.message()], options :: Types.adapter_options()) ::
              {:ok, Types.stream()} | {:error, term()}

  @doc """
  Check if the adapter is properly configured and ready to use.

  ## Parameters  
  - `options` - Adapter options (see module documentation)

  ## Returns
  `true` if configured, `false` otherwise.
  """
  @callback configured?(options :: Types.adapter_options()) :: boolean()

  @doc """
  Get the default model for this adapter.

  ## Returns
  String model identifier.
  """
  @callback default_model() :: String.t()

  @doc """
  List available models for this adapter.

  ## Parameters
  - `options` - Adapter options (see module documentation)

  ## Returns
  `{:ok, [%ExLLM.Types.Model{}]}` on success, `{:error, reason}` on failure.
  """
  @callback list_models(options :: Types.adapter_options()) ::
              {:ok, [Types.Model.t()]} | {:error, term()}
end
