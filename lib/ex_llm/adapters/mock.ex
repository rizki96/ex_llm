defmodule ExLLM.Adapters.Mock do
  @moduledoc """
  Mock adapter for testing ExLLM integrations.

  This adapter provides predictable responses for testing without making actual API calls.
  It supports all ExLLM features including streaming, function calling, and error simulation.

  ## Configuration

  The mock adapter can be configured with predefined responses or response generators:

      # Static response
      ExLLM.Adapters.Mock.set_response(%{
        content: "Mock response",
        model: "mock-model",
        usage: %{input_tokens: 10, output_tokens: 20}
      })
      
      # Dynamic response based on input
      ExLLM.Adapters.Mock.set_response_handler(fn messages, options ->
        %{content: "You said: \#{List.last(messages).content}"}
      end)
      
      # Simulate errors
      ExLLM.Adapters.Mock.set_error({:api_error, %{status: 500, body: "Server error"}})

  ## Testing Features

  - Capture and inspect requests
  - Simulate various response types
  - Test error handling
  - Validate function calling
  - Test streaming behavior
  """

  @behaviour ExLLM.Adapter

  alias ExLLM.Types
  use Agent

  defmodule State do
    @moduledoc false
    defstruct [
      # :static | :handler | :error | :cached
      :response_mode,
      :static_response,
      :response_handler,
      :error_response,
      :requests,
      :stream_chunks,
      :function_call_response,
      :cached_provider
    ]
  end

  @doc """
  Starts the mock adapter agent.
  """
  def start_link(_opts \\ []) do
    Agent.start_link(
      fn ->
        %State{
          response_mode: :static,
          static_response: default_response(),
          requests: [],
          stream_chunks: default_stream_chunks()
        }
      end,
      name: __MODULE__
    )
  end

  @doc """
  Sets a static response for all requests.
  """
  def set_response(response) do
    ensure_started()

    Agent.update(__MODULE__, fn state ->
      %{state | response_mode: :static, static_response: normalize_response(response)}
    end)
  end

  @doc """
  Sets a dynamic response handler.
  """
  def set_response_handler(handler) when is_function(handler, 2) do
    ensure_started()

    Agent.update(__MODULE__, fn state ->
      %{state | response_mode: :handler, response_handler: handler}
    end)
  end

  @doc """
  Sets an error response.
  """
  def set_error(error) do
    ensure_started()

    Agent.update(__MODULE__, fn state ->
      %{state | response_mode: :error, error_response: error}
    end)
  end

  @doc """
  Sets stream chunks for streaming responses.
  """
  def set_stream_chunks(chunks) do
    ensure_started()

    Agent.update(__MODULE__, fn state ->
      %{state | stream_chunks: chunks}
    end)
  end

  @doc """
  Sets a function call response.
  """
  def set_function_call_response(function_call) do
    ensure_started()

    Agent.update(__MODULE__, fn state ->
      %{state | function_call_response: function_call}
    end)
  end

  @doc """
  Configures the mock adapter to use cached responses from a specific provider.

  This allows the mock adapter to mimic the behavior of real providers using
  previously cached responses.

  ## Examples

      # Use cached OpenAI responses
      ExLLM.Adapters.Mock.use_cached_responses(:openai)
      
      # Use cached Anthropic responses  
      ExLLM.Adapters.Mock.use_cached_responses("anthropic")
      
      # Now mock calls will return realistic responses
      {:ok, response} = ExLLM.chat(messages, provider: :mock)
  """
  def use_cached_responses(provider) when is_binary(provider) do
    use_cached_responses(String.to_existing_atom(provider))
  end

  def use_cached_responses(provider) when is_atom(provider) do
    ensure_started()

    case ExLLM.ResponseCache.configure_mock_provider(provider) do
      :ok ->
        Agent.update(__MODULE__, fn state ->
          %{state | response_mode: :cached, cached_provider: provider}
        end)

        :ok

      :no_cache ->
        {:error, "No cached responses found for provider: #{provider}"}

      error ->
        error
    end
  end

  @doc """
  Lists available cached providers.
  """
  def list_cached_providers do
    ExLLM.ResponseCache.list_cached_providers()
  end

  @doc """
  Returns the currently configured cached provider, if any.
  """
  def get_cached_provider do
    ensure_started()
    Agent.get(__MODULE__, & &1.cached_provider)
  end

  @doc """
  Gets all captured requests.
  """
  def get_requests do
    ensure_started()
    Agent.get(__MODULE__, & &1.requests)
  end

  @doc """
  Gets the last captured request.
  """
  def get_last_request do
    ensure_started()

    Agent.get(__MODULE__, fn state ->
      List.last(state.requests)
    end)
  end

  @doc """
  Clears all captured requests and resets to defaults.
  """
  def reset do
    ensure_started()

    # Clear Application environment mock responses
    Application.delete_env(:ex_llm, :mock_responses)

    try do
      Agent.update(__MODULE__, fn _state ->
        %State{
          response_mode: :static,
          static_response: default_response(),
          requests: [],
          stream_chunks: default_stream_chunks()
        }
      end)
    catch
      :exit, {:noproc, _} ->
        # GenServer is not running, start it and try again
        start_link()

        Agent.update(__MODULE__, fn _state ->
          %State{
            response_mode: :static,
            static_response: default_response(),
            requests: [],
            stream_chunks: default_stream_chunks()
          }
        end)
    end
  end

  # Adapter implementation

  @impl true
  def chat(messages, options \\ []) do
    ensure_started()

    # Capture request
    capture_request(:chat, messages, options)

    # Check for mock response in Application env first
    case Application.get_env(:ex_llm, :mock_responses, %{})[:chat] do
      nil ->
        handle_agent_response(messages, options)

      {:error, _} = error ->
        error

      response when is_function(response, 2) ->
        handle_function_response(response, messages, options)

      responses when is_list(responses) ->
        handle_list_response(responses)

      response ->
        {:ok, normalize_response(response)}
    end
  end

  defp handle_agent_response(messages, options) do
    Agent.get(__MODULE__, fn state ->
      case state.response_mode do
        :static ->
          response = build_response(state.static_response, messages, options)
          {:ok, response}

        :handler ->
          handle_response_handler(state.response_handler, messages, options)

        :error ->
          {:error, state.error_response}
      end
    end)
  end

  defp handle_response_handler(handler, messages, options) do
    case handler.(messages, options) do
      {:ok, _} = result -> result
      {:error, _} = error -> error
      response -> {:ok, normalize_response(response)}
    end
  end

  defp handle_function_response(response_fn, messages, options) do
    case response_fn.(messages, options) do
      {:ok, _} = result -> result
      {:error, _} = error -> error
      response -> {:ok, normalize_response(response)}
    end
  end

  defp handle_list_response(responses) do
    Agent.get_and_update(__MODULE__, fn state ->
      index = Map.get(state, :response_index, 0)
      response = Enum.at(responses, rem(index, length(responses)))
      new_state = Map.put(state, :response_index, index + 1)
      {response, new_state}
    end)
    |> then(fn response -> {:ok, normalize_response(response)} end)
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    ensure_started()

    # Capture request
    capture_request(:stream_chat, messages, options)

    # Check for mock response in Application env first
    case Application.get_env(:ex_llm, :mock_responses, %{})[:stream] do
      nil ->
        handle_agent_stream_response()

      {:error, _} = error ->
        error

      chunks when is_list(chunks) ->
        handle_chunk_list(chunks)

      response when is_function(response, 2) ->
        handle_stream_function(response, messages, options)

      _ ->
        {:error, :invalid_stream_response}
    end
  end

  defp handle_agent_stream_response do
    Agent.get(__MODULE__, fn state ->
      case state.response_mode do
        :error ->
          {:error, state.error_response}

        _ ->
          chunks = prepare_stream_chunks(state)
          stream = create_delayed_stream(chunks)
          {:ok, stream}
      end
    end)
  end

  defp prepare_stream_chunks(state) do
    if state.function_call_response do
      # Include function call in stream
      state.stream_chunks ++
        [
          %Types.StreamChunk{
            content: nil,
            finish_reason: "function_call"
          }
        ]
    else
      state.stream_chunks
    end
  end

  defp create_delayed_stream(chunks) do
    Stream.map(chunks, fn chunk ->
      # Add small delay to simulate real streaming
      Process.sleep(10)
      chunk
    end)
  end

  defp handle_chunk_list(chunks) do
    {:ok,
     Stream.map(chunks, fn
       {:error, reason} -> raise "Stream error: #{inspect(reason)}"
       chunk -> chunk
     end)}
  end

  defp handle_stream_function(response_fn, messages, options) do
    case response_fn.(messages, options) do
      {:ok, stream} -> {:ok, stream}
      {:error, _} = error -> error
      stream -> {:ok, stream}
    end
  end

  @impl true
  def list_models(_options \\ []) do
    ensure_started()

    {:ok,
     [
       %Types.Model{
         id: "mock-model-small",
         name: "Mock Model Small",
         context_window: 4_096
       },
       %Types.Model{
         id: "mock-model-large",
         name: "Mock Model Large",
         context_window: 32_768
       }
     ]}
  end

  @impl true
  def configured?(_options \\ []) do
    true
  end

  @impl true
  def embeddings(inputs, options \\ []) do
    ensure_started()

    # Normalize inputs to list
    inputs = if is_binary(inputs), do: [inputs], else: inputs

    # Check for mock response in Application env first
    case Application.get_env(:ex_llm, :mock_responses, %{})[:embeddings] do
      nil ->
        handle_embeddings_from_options(inputs, options)

      {:error, _} = error ->
        error

      response when is_function(response, 2) ->
        handle_embeddings_function(response, inputs, options)

      response ->
        {:ok, response}
    end
  end

  defp handle_embeddings_from_options(inputs, options) do
    cond do
      # Static mock response
      mock_response = Keyword.get(options, :mock_response) ->
        result = handle_embeddings_response(mock_response, inputs, options)
        capture_if_enabled(:embeddings, inputs, options, result)
        result

      # Error simulation
      mock_error = Keyword.get(options, :mock_error) ->
        {:error, mock_error}

      # Default mock embeddings
      true ->
        generate_default_embeddings(inputs, options)
    end
  end

  defp handle_embeddings_function(response_fn, inputs, options) do
    case response_fn.(inputs, options) do
      {:ok, _} = result -> result
      {:error, _} = error -> error
      response -> {:ok, response}
    end
  end

  defp generate_default_embeddings(inputs, options) do
    # Generate pseudo-semantic embeddings based on content
    embeddings = Enum.map(inputs, &generate_mock_embedding/1)

    response = build_embedding_response(embeddings, inputs, options)
    result = {:ok, response}

    capture_if_enabled(:embeddings, inputs, options, result)
    result
  end

  defp build_embedding_response(embeddings, inputs, options) do
    base_response = %Types.EmbeddingResponse{
      embeddings: embeddings,
      model: Keyword.get(options, :model, "mock-embedding-model"),
      usage: %{
        input_tokens: estimate_tokens(inputs),
        output_tokens: 0
      }
    }

    # Add cost if tracking
    if Keyword.get(options, :track_cost, true) do
      %{
        base_response
        | cost: %{
            total_cost: 0.0,
            input_cost: 0.0,
            output_cost: 0.0,
            currency: "USD"
          }
      }
    else
      base_response
    end
  end

  @impl true
  def list_embedding_models(_options \\ []) do
    # Check for mock response in Application env first
    case Application.get_env(:ex_llm, :mock_responses, %{})[:list_embedding_models] do
      nil ->
        # Default models
        models = [
          %Types.EmbeddingModel{
            name: "mock-embedding-small",
            dimensions: 384,
            max_inputs: 100,
            provider: :mock,
            description: "Small mock embedding model",
            pricing: %{
              input_cost_per_token: 0.0,
              output_cost_per_token: 0.0,
              currency: "USD"
            }
          },
          %Types.EmbeddingModel{
            name: "mock-embedding-large",
            dimensions: 1536,
            max_inputs: 100,
            provider: :mock,
            description: "Large mock embedding model",
            pricing: %{
              input_cost_per_token: 0.0,
              output_cost_per_token: 0.0,
              currency: "USD"
            }
          }
        ]

        {:ok, models}

      models when is_list(models) ->
        {:ok, models}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def default_model do
    "mock-model"
  end

  # Private functions

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp capture_request(type, messages, options) do
    Agent.update(__MODULE__, fn state ->
      request = %{
        type: type,
        messages: messages,
        options: options,
        timestamp: DateTime.utc_now()
      }

      %{state | requests: state.requests ++ [request]}
    end)
  end

  defp normalize_response(%Types.LLMResponse{} = response), do: response

  defp normalize_response(response) when is_map(response) do
    %Types.LLMResponse{
      content: extract_content(response),
      model: get_field(response, :model, "mock-model"),
      usage: normalize_usage(get_field(response, :usage)),
      finish_reason: get_field(response, :finish_reason, "stop"),
      id: get_field(response, :id, generate_id()),
      function_call: get_field(response, :function_call),
      tool_calls: get_field(response, :tool_calls),
      cost: get_field(response, :cost)
    }
  end

  defp normalize_response(content) when is_binary(content) do
    %Types.LLMResponse{
      content: content,
      model: "mock-model",
      usage: %{input_tokens: 10, output_tokens: 20},
      finish_reason: "stop",
      id: generate_id()
    }
  end

  defp extract_content(response) do
    case {Map.has_key?(response, :content), Map.has_key?(response, "content")} do
      {true, _} -> Map.get(response, :content)
      {_, true} -> Map.get(response, "content")
      _ -> "Mock response"
    end
  end

  defp get_field(map, field, default \\ nil) do
    Map.get(map, field) || Map.get(map, to_string(field)) || default
  end

  defp normalize_usage(nil), do: %{input_tokens: 10, output_tokens: 20, total_tokens: 30}

  defp normalize_usage(usage) when is_map(usage) do
    input = usage[:input_tokens] || usage["input_tokens"] || 10
    output = usage[:output_tokens] || usage["output_tokens"] || 20
    total = usage[:total_tokens] || usage["total_tokens"] || input + output

    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: total
    }
  end

  defp build_response(base_response, _messages, _options) do
    base_response
  end

  defp default_response do
    %Types.LLMResponse{
      content: "This is a mock response",
      model: "mock-model",
      usage: %{input_tokens: 10, output_tokens: 20, total_tokens: 30},
      finish_reason: "stop",
      id: generate_id()
    }
  end

  defp default_stream_chunks do
    [
      %Types.StreamChunk{content: "This ", finish_reason: nil},
      %Types.StreamChunk{content: "is ", finish_reason: nil},
      %Types.StreamChunk{content: "a ", finish_reason: nil},
      %Types.StreamChunk{content: "mock ", finish_reason: nil},
      %Types.StreamChunk{content: "stream ", finish_reason: nil},
      %Types.StreamChunk{content: "response", finish_reason: nil},
      %Types.StreamChunk{content: "", finish_reason: "stop"}
    ]
  end

  defp generate_id do
    ("mock-" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)
  end

  defp handle_embeddings_response(mock_response, _inputs, _options) when is_map(mock_response) do
    response = struct(Types.EmbeddingResponse, mock_response)
    {:ok, response}
  end

  defp handle_embeddings_response(embeddings, inputs, options) when is_list(embeddings) do
    response = %Types.EmbeddingResponse{
      embeddings: embeddings,
      model: Keyword.get(options, :model, "mock-embedding-model"),
      usage: %{
        input_tokens: estimate_tokens(inputs),
        output_tokens: 0
      }
    }

    {:ok, response}
  end

  defp estimate_tokens(inputs) when is_list(inputs) do
    # Simple estimation: ~4 characters per token
    Enum.reduce(inputs, 0, fn input, acc ->
      acc + div(String.length(input), 4)
    end)
  end

  defp capture_if_enabled(type, input, options, _result) do
    if Keyword.get(options, :capture_requests, false) do
      capture_request(type, input, options)
    end
  end

  # Generate a mock embedding with some semantic meaning
  defp generate_mock_embedding(text) do
    # Normalize text
    normalized = String.downcase(text)

    # Create a base embedding vector (384 dimensions to match common models)
    embedding = List.duplicate(0.0, 384)

    # Define semantic features and their positions in the embedding
    features = %{
      # Animals/nature (positions 0-49)
      "cat" => {0, 0.8},
      "dog" => {5, 0.8},
      "animal" => {10, 0.6},
      "mat" => {15, 0.3},
      "garden" => {20, 0.7},
      "park" => {25, 0.7},
      "sunny" => {30, 0.9},
      "warm" => {35, 0.8},
      "weather" => {40, 0.7},
      "sun" => {30, 0.85},

      # Technology (positions 50-99)
      "machine" => {50, 0.9},
      "learning" => {55, 0.9},
      "artificial" => {60, 0.9},
      "intelligence" => {65, 0.9},
      "technology" => {70, 0.8},
      "process" => {75, 0.6},
      "natural" => {80, 0.5},
      "language" => {85, 0.7},
      "transform" => {90, 0.6},

      # Actions (positions 100-149)
      "play" => {100, 0.7},
      "fetch" => {105, 0.6},
      "love" => {110, 0.5},
      "sat" => {115, 0.4},
      "sit" => {115, 0.4}
    }

    # Apply features based on words in text
    embedding =
      Enum.reduce(features, embedding, fn {word, {position, strength}}, emb ->
        if String.contains?(normalized, word) do
          # Set the feature at the position with some noise
          List.update_at(emb, position, fn _ ->
            strength + (:rand.uniform() - 0.5) * 0.1
          end)
          |> add_related_features(position, strength * 0.5)
        else
          emb
        end
      end)

    # Add some random noise to make it more realistic
    embedding
    |> Enum.with_index()
    |> Enum.map(fn {val, _idx} ->
      if val == 0.0 do
        # Small random values for unused dimensions
        (:rand.uniform() - 0.5) * 0.1
      else
        # Keep feature values with small noise
        val + (:rand.uniform() - 0.5) * 0.05
      end
    end)
  end

  # Add related features nearby to create more realistic embeddings
  defp add_related_features(embedding, position, strength) do
    # Add decreasing values to nearby positions
    nearby_positions = [
      {position - 2, strength * 0.3},
      {position - 1, strength * 0.5},
      {position + 1, strength * 0.5},
      {position + 2, strength * 0.3}
    ]

    Enum.reduce(nearby_positions, embedding, fn {pos, val}, emb ->
      if pos >= 0 and pos < length(emb) do
        List.update_at(emb, pos, fn current -> current + val end)
      else
        emb
      end
    end)
  end
end
