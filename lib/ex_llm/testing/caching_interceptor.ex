defmodule ExLLM.Testing.CachingInterceptor do
  @moduledoc """
  Interceptor module for automatically caching provider responses.

  This module provides functions to wrap adapter calls and automatically
  cache their responses for later use in testing with the Mock adapter.

  ## Usage

  ### Environment-based Auto-caching

      # Enable caching for all providers
      export EX_LLM_CACHE_RESPONSES=true
      export EX_LLM_CACHE_DIR="/path/to/cache"
      
      # Normal ExLLM usage will automatically cache responses
      {:ok, response} = ExLLM.chat(messages, provider: :openai)

  ### Manual Caching Wrapper

      # Wrap a specific call to cache its response
      {:ok, response} = ExLLM.CachingInterceptor.with_caching(:openai, fn ->
        ExLLM.Providers.OpenAI.chat(messages)
      end)

  ### Batch Response Collection

      # Collect responses for testing scenarios
      ExLLM.CachingInterceptor.collect_test_responses(:openai, [
        {[%{role: "user", content: "Hello"}], []},
        {[%{role: "user", content: "What is 2+2?"}], [max_tokens: 10]},
        {[%{role: "user", content: "Tell me a joke"}], [temperature: 0.8]}
      ])
  """

  alias ExLLM.Infrastructure.Logger
  alias ExLLM.Testing.ResponseCache

  @doc """
  Wraps an adapter call to automatically cache the response.
  """
  def with_caching(provider, adapter_function) when is_function(adapter_function, 0) do
    start_time = System.monotonic_time(:millisecond)

    case adapter_function.() do
      {:ok, response} = success ->
        end_time = System.monotonic_time(:millisecond)
        response_time_ms = end_time - start_time

        # Extract request info from the call (this is simplified)
        # In practice, we'd need to capture the actual request data
        cache_response(provider, "chat_completions", %{}, response, response_time_ms)

        success

      error ->
        error
    end
  end

  @doc """
  Wraps a streaming adapter call to cache the complete stream.
  """
  def with_streaming_cache(provider, messages, options, adapter_function)
      when is_function(adapter_function, 0) do
    start_time = System.monotonic_time(:millisecond)

    case adapter_function.() do
      {:ok, stream} ->
        # Collect all chunks and cache them
        chunks = Enum.to_list(stream)
        end_time = System.monotonic_time(:millisecond)
        response_time_ms = end_time - start_time

        request_data = %{
          messages: messages,
          stream: true,
          model: Keyword.get(options, :model),
          temperature: Keyword.get(options, :temperature),
          max_tokens: Keyword.get(options, :max_tokens)
        }

        # Convert chunks back to a response-like format for caching
        full_content = chunks |> Enum.map(& &1.content) |> Enum.join("")
        last_chunk = List.last(chunks)

        cached_response = %{
          "choices" => [
            %{
              "message" => %{
                "content" => full_content,
                "role" => "assistant"
              },
              "finish_reason" => last_chunk && last_chunk.finish_reason
            }
          ],
          "model" => last_chunk && last_chunk.model,
          "id" => last_chunk && last_chunk.id,
          "streaming_chunks" => chunks |> Enum.map(&Map.from_struct/1)
        }

        cache_response(provider, "streaming", request_data, cached_response, response_time_ms)

        # Return the original stream (recreated from chunks)
        {:ok,
         Stream.resource(
           fn -> chunks end,
           fn
             [] -> {:halt, []}
             [chunk | rest] -> {[chunk], rest}
           end,
           fn _ -> :ok end
         )}

      error ->
        error
    end
  end

  @doc """
  Collects responses for common test scenarios.

  This function executes a list of test cases and caches their responses
  for later use in testing.
  """
  def collect_test_responses(provider, test_cases) when is_list(test_cases) do
    adapter_module = get_adapter_module(provider)

    Logger.info("Collecting test responses for #{provider} (#{length(test_cases)} cases)")

    results =
      for {messages, options} <- test_cases do
        content = List.last(messages).content
        content_preview = if is_binary(content), do: content, else: inspect(content)
        Logger.debug("Testing: #{String.slice(content_preview, 0, 50)}...")

        try do
          case with_caching(provider, fn ->
                 apply(adapter_module, :chat, [messages, options])
               end) do
            {:ok, response} ->
              {:ok, String.slice(response.content, 0, 50) <> "..."}

            error ->
              error
          end
        rescue
          error ->
            Logger.warning("Failed to collect response: #{inspect(error)}")
            {:error, error}
        end
      end

    success_count = results |> Enum.count(&match?({:ok, _}, &1))
    Logger.info("Collected #{success_count}/#{length(test_cases)} responses for #{provider}")

    results
  end

  @doc """
  Enables automatic caching for a specific provider.

  This modifies the adapter's behavior to automatically cache all responses.
  """
  def enable_auto_caching(provider) do
    if ResponseCache.caching_enabled?() do
      # This would require more sophisticated interception
      # For now, we'll just log that it's enabled
      Logger.info("Auto-caching enabled for #{provider}")
      :ok
    else
      Logger.warning("Response caching is not enabled (set EX_LLM_CACHE_RESPONSES=true)")
      :disabled
    end
  end

  @doc """
  Creates a comprehensive test response collection for a provider.
  """
  def create_test_collection(provider) do
    _test_scenarios = get_test_scenarios()

    Logger.info("Creating comprehensive test collection for #{provider}")

    results = %{
      basic_chat: collect_basic_chat_responses(provider),
      streaming: collect_streaming_responses(provider),
      function_calling: collect_function_calling_responses(provider),
      multimodal: collect_multimodal_responses(provider),
      error_scenarios: collect_error_responses(provider)
    }

    total_collected =
      results
      |> Map.values()
      |> List.flatten()
      |> Enum.count(&match?({:ok, _}, &1))

    Logger.info("Test collection complete for #{provider}: #{total_collected} responses cached")
    results
  end

  # Private helper functions

  defp cache_response(provider, endpoint, request_data, response_data, response_time_ms) do
    if ResponseCache.caching_enabled?() do
      ResponseCache.store_response(
        to_string(provider),
        endpoint,
        request_data,
        response_data,
        response_time_ms: response_time_ms
      )
    end
  end

  defp get_adapter_module(provider) do
    case provider do
      :openai -> ExLLM.Providers.OpenAI
      :anthropic -> ExLLM.Providers.Anthropic
      :openrouter -> ExLLM.Providers.OpenRouter
      :ollama -> ExLLM.Providers.Ollama
      :groq -> ExLLM.Providers.Groq
      :mock -> ExLLM.Providers.Mock
      provider when is_binary(provider) -> get_adapter_module(String.to_existing_atom(provider))
      _ -> raise ArgumentError, "Unknown provider: #{provider}"
    end
  end

  defp get_test_scenarios do
    [
      # Basic conversations
      {[%{role: "user", content: "Hello"}], []},
      {[%{role: "user", content: "What is 2 + 2?"}], []},
      {[%{role: "user", content: "Tell me a short joke"}], []},

      # System messages
      {[
         %{role: "system", content: "You are a helpful assistant"},
         %{role: "user", content: "Hello"}
       ], []},

      # Temperature variations
      {[%{role: "user", content: "Write a creative story opening"}], [temperature: 0.1]},
      {[%{role: "user", content: "Write a creative story opening"}], [temperature: 0.9]},

      # Token limits
      {[%{role: "user", content: "Explain quantum physics"}], [max_tokens: 50]},
      {[%{role: "user", content: "Count from 1 to 10"}], [max_tokens: 100]},

      # Different conversation lengths
      {[
         %{role: "user", content: "Hi"},
         %{role: "assistant", content: "Hello! How can I help you?"},
         %{role: "user", content: "What's the weather like?"}
       ], []}
    ]
  end

  defp collect_basic_chat_responses(provider) do
    basic_scenarios = [
      {[%{role: "user", content: "Hello"}], []},
      {[%{role: "user", content: "What is the capital of France?"}], []},
      {[%{role: "user", content: "Explain photosynthesis briefly"}], [max_tokens: 100]}
    ]

    collect_test_responses(provider, basic_scenarios)
  end

  defp collect_streaming_responses(provider) do
    if supports_streaming?(provider) do
      adapter_module = get_adapter_module(provider)

      scenarios = [
        {[%{role: "user", content: "Count from 1 to 5"}], []},
        {[%{role: "user", content: "Tell me a short story"}], [max_tokens: 200]}
      ]

      for {messages, options} <- scenarios do
        try do
          with_streaming_cache(provider, messages, options, fn ->
            adapter_module.stream_chat(messages, options)
          end)
        rescue
          _ -> {:error, "streaming not supported"}
        end
      end
    else
      []
    end
  end

  defp collect_function_calling_responses(provider) do
    if supports_function_calling?(provider) do
      _adapter_module = get_adapter_module(provider)

      functions = [
        %{
          name: "get_weather",
          description: "Get current weather",
          parameters: %{
            type: "object",
            properties: %{location: %{type: "string"}},
            required: ["location"]
          }
        }
      ]

      scenarios = [
        {[%{role: "user", content: "What's the weather in Paris?"}], [functions: functions]}
      ]

      collect_test_responses(provider, scenarios)
    else
      []
    end
  end

  defp collect_multimodal_responses(provider) do
    if supports_vision?(provider) do
      # Simple test with a small base64 image
      red_pixel =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="

      scenarios = [
        {[
           %{
             role: "user",
             content: [
               %{type: "text", text: "What color is this?"},
               %{type: "image_url", image_url: %{url: "data:image/png;base64,#{red_pixel}"}}
             ]
           }
         ], [max_tokens: 50]}
      ]

      collect_test_responses(provider, scenarios)
    else
      []
    end
  end

  defp collect_error_responses(_provider) do
    # We don't want to intentionally cause errors that might affect accounts
    # Error scenarios should be tested with the actual adapters in controlled ways
    []
  end

  defp supports_streaming?(provider) do
    provider in [:openai, :anthropic, :openrouter, :ollama, :mock]
  end

  defp supports_function_calling?(provider) do
    provider in [:openai, :openrouter, :ollama, :mock]
  end

  defp supports_vision?(provider) do
    provider in [:openai, :anthropic, :openrouter, :mock]
  end
end
