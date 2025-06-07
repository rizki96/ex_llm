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
    assert_receive pattern, timeout
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
end
