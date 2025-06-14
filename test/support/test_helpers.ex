defmodule ExLLM.TestHelpers do
  @moduledoc """
  Common test helper functions for ExLLM test suite.

  Provides utilities for:
  - Mock adapter setup and teardown
  - Cache initialization and cleanup
  - Configuration management
  - Common assertions
  - Test data generation
  """

  import ExUnit.Assertions
  import ExUnit.Callbacks

  @doc """
  Set up a mock adapter with a predefined response.

  ## Examples

      setup_mock_response(%{content: "Hello!", model: "test"})
  """
  def setup_mock_response(response, opts \\ []) do
    ExLLM.Adapters.Mock.start_link(opts)
    ExLLM.Adapters.Mock.set_response(response)
  end

  @doc """
  Set up a mock adapter with an error response.
  """
  def setup_mock_error(error, opts \\ []) do
    ExLLM.Adapters.Mock.start_link(opts)
    ExLLM.Adapters.Mock.set_error(error)
  end

  @doc """
  Set up cache for testing with automatic cleanup.
  """
  def setup_cache_test(context \\ %{}) do
    # Start cache if not already started
    case Process.whereis(ExLLM.Cache) do
      nil ->
        {:ok, _} = ExLLM.Cache.start_link()

      _pid ->
        # Clear existing cache
        ExLLM.Cache.clear()
    end

    on_exit(fn ->
      ExLLM.Cache.clear()
    end)

    context
  end

  @doc """
  Save and restore application configuration.
  """
  def with_config(app, key, value, fun) do
    original = Application.get_env(app, key)
    Application.put_env(app, key, value)

    try do
      fun.()
    after
      if original do
        Application.put_env(app, key, original)
      else
        Application.delete_env(app, key)
      end
    end
  end

  @doc """
  Generate test messages for conversations.
  """
  def generate_messages(count \\ 3) do
    for i <- 1..count do
      role = if rem(i, 2) == 1, do: "user", else: "assistant"

      %{
        role: role,
        content: "Message #{i} from #{role}"
      }
    end
  end

  @doc """
  Generate a test session with messages.
  """
  def generate_test_session(backend \\ "test", message_count \\ 5) do
    session = ExLLM.Session.new(backend)

    Enum.reduce(1..message_count, session, fn i, acc ->
      role = if rem(i, 2) == 1, do: "user", else: "assistant"
      ExLLM.Session.add_message(acc, role, "Message #{i}")
    end)
  end

  @doc """
  Set up stream recovery for testing.
  """
  def setup_stream_recovery_test(context \\ %{}) do
    # Start StreamRecovery if not already started
    case Process.whereis(ExLLM.StreamRecovery) do
      nil ->
        {:ok, _} = ExLLM.StreamRecovery.start_link()

      _pid ->
        :ok
    end

    context
  end

  @doc """
  Assert that a response has expected structure.
  """
  def assert_valid_response(response) do
    assert %ExLLM.Types.LLMResponse{} = response
    assert is_binary(response.content) or is_nil(response.content)
    assert is_map(response.usage) or is_nil(response.usage)

    if response.usage do
      assert is_integer(response.usage.input_tokens) or is_nil(response.usage.input_tokens)
      assert is_integer(response.usage.output_tokens) or is_nil(response.usage.output_tokens)
    end

    response
  end

  @doc """
  Assert that a streaming chunk has expected structure.
  """
  def assert_valid_chunk(chunk) do
    assert %ExLLM.Types.StreamChunk{} = chunk
    assert is_binary(chunk.content) or is_nil(chunk.content)
    assert is_binary(chunk.finish_reason) or is_nil(chunk.finish_reason)

    chunk
  end

  @doc """
  Wait for async messages with timeout.
  """
  def assert_receive_within(pattern, timeout \\ 1000) do
    assert_receive ^pattern, timeout
  end

  @doc """
  Create a temporary file with content and cleanup.
  """
  def with_temp_file(content, fun) do
    path = Path.join(System.tmp_dir!(), "ex_llm_test_#{:rand.uniform(1_000_000)}")
    File.write!(path, content)

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  @doc """
  Skip test if environment variable is not set.
  """
  defmacro skip_without_env(env_var, message \\ nil) do
    quote do
      unless System.get_env(unquote(env_var)) do
        ExUnit.Case.register_attribute(__MODULE__, :skip)
        @skip unquote(message) || "Skipping: #{unquote(env_var)} not set"
      end
    end
  end

  @doc """
  Wait for an eventually consistent condition to become true.

  This is useful for testing APIs that have eventual consistency, like Google's Gemini API
  where resources may not immediately appear in list operations after creation.

  ## Options

  - `:timeout` - Maximum time to wait in milliseconds (default: 10_000)
  - `:interval` - Time between retries in milliseconds (default: 500)
  - `:description` - Description for better error messages (default: "condition")

  ## Examples

      # Wait for a document to appear in listings
      assert_eventually(fn ->
        {:ok, list_response} = Document.list_documents(corpus_id, oauth_token: token)
        Enum.any?(list_response.documents, fn d -> d.name == document.name end)
      end, timeout: 15_000, description: "document to appear in list")
      
      # Wait for a resource to be created and return it
      {:ok, resource} = wait_for_resource(fn ->
        case SomeAPI.get_resource(id) do
          {:ok, resource} -> {:ok, resource}
          {:error, :not_found} -> {:error, :not_found}
          error -> error
        end
      end)
  """
  def assert_eventually(check_fn, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    interval = Keyword.get(opts, :interval, 500)
    description = Keyword.get(opts, :description, "condition")
    max_attempts = div(timeout, interval)

    result =
      Enum.reduce_while(1..max_attempts, false, fn attempt, _acc ->
        case check_fn.() do
          true ->
            {:halt, true}

          false ->
            if attempt < max_attempts do
              Process.sleep(interval)
              {:cont, false}
            else
              {:halt, false}
            end
        end
      end)

    unless result do
      flunk("Expected #{description} to become true within #{timeout}ms, but it didn't")
    end

    result
  end

  @doc """
  Wait for a resource to become available with exponential backoff.

  Similar to `assert_eventually/2` but for operations that return `{:ok, result}` or `{:error, reason}`.
  Uses exponential backoff for more efficient waiting.

  ## Options

  - `:max_attempts` - Maximum number of attempts (default: 5)
  - `:base_delay` - Base delay in milliseconds (default: 1000)
  - `:max_delay` - Maximum delay between attempts (default: 8000)
  - `:description` - Description for better error messages

  ## Examples

      # Wait for a document to be fully available
      {:ok, document} = wait_for_resource(fn ->
        case Document.get_document(document_name, oauth_token: token) do
          {:ok, doc} when not is_nil(doc.display_name) -> {:ok, doc}
          {:ok, _doc} -> {:error, :incomplete}
          error -> error
        end
      end, description: "document to be fully loaded")
  """
  def wait_for_resource(check_fn, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 5)
    base_delay = Keyword.get(opts, :base_delay, 1000)
    max_delay = Keyword.get(opts, :max_delay, 8000)
    description = Keyword.get(opts, :description, "resource")

    Enum.reduce_while(1..max_attempts, {:error, :not_found}, fn attempt, _acc ->
      case check_fn.() do
        {:ok, result} ->
          {:halt, {:ok, result}}

        {:error, _reason} ->
          if attempt < max_attempts do
            delay = min((base_delay * :math.pow(2, attempt - 1)) |> round(), max_delay)
            Process.sleep(delay)
            {:cont, {:error, :not_found}}
          else
            {:halt, {:error, :timeout}}
          end
      end
    end)
    |> case do
      {:error, :timeout} ->
        flunk(
          "Expected #{description} to become available within #{max_attempts} attempts, but it didn't"
        )

      result ->
        result
    end
  end

  @doc """
  Check if we're in a strict consistency testing mode.

  When GEMINI_STRICT_CONSISTENCY=true, tests will use full retry logic.
  When false or unset, tests will use faster, more permissive approaches.
  """
  def strict_consistency_mode?() do
    System.get_env("GEMINI_STRICT_CONSISTENCY") == "true"
  end

  @doc """
  Get timeout for eventual consistency tests based on environment.

  - CI environments get longer timeouts
  - Local development gets shorter timeouts  
  - Strict mode gets the longest timeouts
  """
  def eventual_consistency_timeout() do
    cond do
      strict_consistency_mode?() -> 20_000
      System.get_env("CI") -> 15_000
      true -> 10_000
    end
  end
end
