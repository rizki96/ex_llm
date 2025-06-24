defmodule ExLLM.Providers.Shared.HTTP.TestSupport do
  @moduledoc """
  Test infrastructure and utilities for HTTP client testing.

  This module provides mock response generation, test cache integration,
  debug logging, and test interceptor patterns to support comprehensive
  testing of HTTP operations across all LLM providers.

  ## Features

  - Mock response templates for different providers
  - Test cache with automatic cleanup
  - Request/response capture for assertions
  - Streaming response simulation
  - Error scenario simulation
  - Performance testing utilities

  ## Usage

      # Setup mock responses
      TestSupport.setup_mock_responses(%{
        openai: %{chat: mock_openai_response()},
        anthropic: %{chat: mock_anthropic_response()}
      })
      
      # Capture requests for testing
      TestSupport.start_capture()
      # ... make requests
      requests = TestSupport.get_captured_requests()
  """

  # We'll need these for future development
  # alias ExLLM.Infrastructure.Logger  
  # alias ExLLM.Types

  @doc """
  Setup mock responses for testing.

  ## Parameters
  - `responses` - Map of provider -> endpoint -> response

  ## Example

      responses = %{
        openai: %{
          chat: %{
            status: 200,
            body: %{choices: [%{message: %{content: "Hello"}}]}
          },
          models: %{
            status: 200, 
            body: %{data: [%{id: "gpt-4"}]}
          }
        }
      }
      
      TestSupport.setup_mock_responses(responses)
  """
  @spec setup_mock_responses(map()) :: :ok
  def setup_mock_responses(responses) do
    Application.put_env(:ex_llm, :test_mock_responses, responses)
    :ok
  end

  @doc """
  Get mock response for a provider and endpoint.
  """
  @spec get_mock_response(atom(), atom()) :: map() | nil
  def get_mock_response(provider, endpoint) do
    responses = Application.get_env(:ex_llm, :test_mock_responses, %{})
    get_in(responses, [provider, endpoint])
  end

  @doc """
  Create a standard mock chat response.
  """
  @spec mock_chat_response(String.t(), keyword()) :: map()
  def mock_chat_response(content, opts \\ []) do
    model = Keyword.get(opts, :model, "mock-model")
    _provider = Keyword.get(opts, :provider, :mock)

    %{
      status: 200,
      headers: [{"content-type", "application/json"}],
      body: %{
        id: "chat-#{:rand.uniform(9999)}",
        object: "chat.completion",
        created: System.system_time(:second),
        model: model,
        choices: [
          %{
            index: 0,
            message: %{
              role: "assistant",
              content: content
            },
            finish_reason: "stop"
          }
        ],
        usage: %{
          prompt_tokens: Keyword.get(opts, :prompt_tokens, 10),
          completion_tokens: Keyword.get(opts, :completion_tokens, String.length(content)),
          total_tokens: Keyword.get(opts, :total_tokens, 10 + String.length(content))
        }
      }
    }
  end

  @doc """
  Create a mock streaming chat response.
  """
  @spec mock_streaming_response([String.t()], keyword()) :: [map()]
  def mock_streaming_response(content_chunks, opts \\ []) do
    model = Keyword.get(opts, :model, "mock-model")

    # Content chunks
    chunk_responses =
      content_chunks
      |> Enum.with_index()
      |> Enum.map(fn {content, index} ->
        %{
          id: "chunk-#{index}",
          object: "chat.completion.chunk",
          created: System.system_time(:second),
          model: model,
          choices: [
            %{
              index: 0,
              delta: %{content: content},
              finish_reason: nil
            }
          ]
        }
      end)

    # Final chunk
    final_chunk = %{
      id: "chunk-final",
      object: "chat.completion.chunk",
      created: System.system_time(:second),
      model: model,
      choices: [
        %{
          index: 0,
          delta: %{},
          finish_reason: "stop"
        }
      ]
    }

    chunk_responses ++ [final_chunk]
  end

  @doc """
  Create a mock error response.
  """
  @spec mock_error_response(atom(), String.t(), integer()) :: map()
  def mock_error_response(error_type, message, status_code \\ 400) do
    %{
      status: status_code,
      headers: [{"content-type", "application/json"}],
      body: %{
        error: %{
          type: error_type,
          message: message,
          code: status_code
        }
      }
    }
  end

  @doc """
  Start capturing HTTP requests for testing assertions.
  """
  @spec start_capture() :: :ok
  def start_capture do
    Agent.start_link(fn -> [] end, name: :http_request_capture)
    :ok
  end

  @doc """
  Stop capturing HTTP requests and clean up.
  """
  @spec stop_capture() :: :ok
  def stop_capture do
    case Process.whereis(:http_request_capture) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end
  end

  @doc """
  Capture an HTTP request for later assertion.
  """
  @spec capture_request(Tesla.Env.t()) :: :ok
  def capture_request(env) do
    case Process.whereis(:http_request_capture) do
      nil ->
        :ok

      _pid ->
        request_data = %{
          method: env.method,
          url: env.url,
          headers: env.headers,
          body: env.body,
          timestamp: System.monotonic_time(:millisecond)
        }

        Agent.update(:http_request_capture, fn requests ->
          [request_data | requests]
        end)
    end
  end

  @doc """
  Get all captured HTTP requests.
  """
  @spec get_captured_requests() :: [map()]
  def get_captured_requests do
    case Process.whereis(:http_request_capture) do
      nil ->
        []

      _pid ->
        Agent.get(:http_request_capture, fn requests ->
          Enum.reverse(requests)
        end)
    end
  end

  @doc """
  Clear captured requests.
  """
  @spec clear_captured_requests() :: :ok
  def clear_captured_requests do
    case Process.whereis(:http_request_capture) do
      nil -> :ok
      _pid -> Agent.update(:http_request_capture, fn _ -> [] end)
    end
  end

  @doc """
  Create a test cache with automatic cleanup.
  """
  @spec setup_test_cache(keyword()) :: {:ok, pid()}
  def setup_test_cache(opts \\ []) do
    cache_name = Keyword.get(opts, :name, :test_cache)
    ttl = Keyword.get(opts, :ttl, 60_000)

    # Create isolated ETS table for test
    table = :ets.new(cache_name, [:named_table, :public, :set])

    # Start cleanup process
    cleanup_pid =
      spawn_link(fn ->
        # Wait for TTL to expire
        Process.sleep(ttl * 2)
        :ets.delete(table)
      end)

    {:ok, cleanup_pid}
  end

  @doc """
  Simulate network latency for testing.
  """
  @spec simulate_latency(non_neg_integer()) :: :ok
  def simulate_latency(ms) when ms > 0 do
    Process.sleep(ms)
    :ok
  end

  def simulate_latency(_), do: :ok

  @doc """
  Create a test Tesla client with mock adapter.
  """
  @spec test_client(keyword()) :: Tesla.Client.t()
  def test_client(opts \\ []) do
    mock_responses = Keyword.get(opts, :responses, %{})
    latency = Keyword.get(opts, :latency, 0)

    middleware = [
      {Tesla.Middleware.JSON, engine_opts: [keys: :strings]},
      {__MODULE__.MockAdapter, responses: mock_responses, latency: latency}
    ]

    Tesla.client(middleware)
  end

  @doc """
  Assert that a request was made with specific criteria.

  ## Examples

      TestSupport.assert_request_made(%{
        method: :post,
        url_contains: "/chat/completions",
        headers_include: {"authorization", "Bearer sk-..."}
      })
  """
  @spec assert_request_made(map()) :: boolean()
  def assert_request_made(criteria) do
    requests = get_captured_requests()

    Enum.any?(requests, fn request ->
      check_request_criteria(request, criteria)
    end)
  end

  @doc """
  Get performance metrics from captured requests.
  """
  @spec get_performance_metrics() :: map()
  def get_performance_metrics do
    requests = get_captured_requests()

    if Enum.empty?(requests) do
      %{requests: 0, avg_duration: 0, total_duration: 0}
    else
      durations = calculate_request_durations(requests)

      %{
        requests: length(requests),
        avg_duration: Enum.sum(durations) / length(durations),
        total_duration: Enum.sum(durations),
        min_duration: Enum.min(durations),
        max_duration: Enum.max(durations)
      }
    end
  end

  # Private helper functions

  defp check_request_criteria(request, criteria) do
    Enum.all?(criteria, fn {key, expected} ->
      case key do
        :method -> request.method == expected
        :url -> request.url == expected
        :url_contains -> String.contains?(request.url, expected)
        :headers_include -> expected in request.headers
        :body_contains -> String.contains?(inspect(request.body), expected)
        _ -> true
      end
    end)
  end

  defp calculate_request_durations(requests) do
    if length(requests) < 2 do
      [0]
    else
      requests
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [req1, req2] ->
        req2.timestamp - req1.timestamp
      end)
    end
  end

  defmodule MockAdapter do
    @moduledoc """
    Tesla adapter for mocking HTTP responses in tests.
    """

    @behaviour Tesla.Adapter

    def call(env, opts) do
      responses = Keyword.get(opts, :responses, %{})
      latency = Keyword.get(opts, :latency, 0)

      # Simulate network latency
      if latency > 0 do
        Process.sleep(latency)
      end

      # Capture request if capturing is enabled
      ExLLM.Providers.Shared.HTTP.TestSupport.capture_request(env)

      # Find matching response
      response = find_mock_response(env, responses)

      case response do
        nil ->
          {:error, :no_mock_response}

        mock_response ->
          tesla_response = %Tesla.Env{
            status: mock_response.status,
            headers: mock_response.headers,
            body: encode_response_body(mock_response.body),
            method: env.method,
            url: env.url
          }

          {:ok, tesla_response}
      end
    end

    defp find_mock_response(env, responses) do
      # Try to match by URL pattern
      Enum.find_value(responses, fn {pattern, response} ->
        if url_matches?(env.url, pattern) do
          response
        end
      end)
    end

    defp url_matches?(url, pattern) when is_binary(pattern) do
      String.contains?(url, pattern)
    end

    defp url_matches?(url, pattern) when is_atom(pattern) do
      String.contains?(url, Atom.to_string(pattern))
    end

    defp url_matches?(_url, _pattern), do: false

    defp encode_response_body(body) when is_map(body) do
      Jason.encode!(body)
    end

    defp encode_response_body(body) when is_binary(body) do
      body
    end

    defp encode_response_body(body) do
      to_string(body)
    end
  end

  @doc """
  Provider-specific mock response templates.
  """
  def provider_templates do
    %{
      openai: %{
        chat: fn content ->
          mock_chat_response(content, model: "gpt-4", provider: :openai)
        end,
        models: fn ->
          %{
            status: 200,
            body: %{
              object: "list",
              data: [
                %{id: "gpt-4", object: "model"},
                %{id: "gpt-3.5-turbo", object: "model"}
              ]
            }
          }
        end
      },
      anthropic: %{
        chat: fn content ->
          %{
            status: 200,
            body: %{
              id: "msg_123",
              type: "message",
              role: "assistant",
              content: [%{type: "text", text: content}],
              model: "claude-3-sonnet-20240229",
              usage: %{input_tokens: 10, output_tokens: String.length(content)}
            }
          }
        end
      },
      groq: %{
        chat: fn content ->
          mock_chat_response(content, model: "llama3-70b-8192", provider: :groq)
        end
      }
    }
  end
end
