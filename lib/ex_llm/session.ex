defmodule ExLLM.Session do
  @moduledoc """
  Session management for ExLLM - handles conversation sessions with LLM providers.

  ExLLM.Session provides pure functional operations for managing conversation sessions,
  including message history, token tracking, and session persistence. All operations
  are stateless and return updated session structs.

  ## Quick Start

      # Create a new session
      session = ExLLM.Session.new("anthropic")

      # Add messages
      session = ExLLM.Session.add_message(session, "user", "Hello!")
      session = ExLLM.Session.add_message(session, "assistant", "Hi there!")

      # Get messages
      messages = ExLLM.Session.get_messages(session)

      # Update token usage
      session = ExLLM.Session.update_token_usage(session, %{input_tokens: 10, output_tokens: 15})

  ## Features

  - **Pure Functional**: All operations are stateless and immutable
  - **Message Management**: Add, retrieve, and filter conversation messages
  - **Token Tracking**: Track input/output token usage across conversations
  - **Context Storage**: Store arbitrary metadata with sessions
  - **Session Persistence**: Serialize/deserialize sessions to/from JSON
  - **LLM Integration**: Seamlessly works with ExLLM providers

  ## Session Structure

  Sessions are represented by `ExLLM.Session.Types.Session` structs containing:
  - `id` - Unique session identifier
  - `llm_backend` - LLM backend name (optional)
  - `messages` - List of conversation messages
  - `context` - Arbitrary metadata map
  - `created_at`/`updated_at` - Timestamps
  - `token_usage` - Token consumption tracking
  - `name` - Human-readable session name (optional)
  """

  alias ExLLM.Session.Types

  @doc """
  Create a new session with the specified backend.

  ## Parameters
  - `backend` - LLM backend to use (optional)
  - `opts` - Additional options (`:name` for session name)

  ## Returns
  A new Session struct.

  ## Examples

      session = ExLLM.Session.new("anthropic")
      session = ExLLM.Session.new("openai", name: "My Chat")
  """
  @spec new(String.t() | nil, keyword()) :: Types.Session.t()
  def new(backend \\ nil, opts \\ []) do
    name = Keyword.get(opts, :name)

    %Types.Session{
      id: generate_session_id(),
      llm_backend: backend,
      messages: [],
      context: %{},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      token_usage: %{input_tokens: 0, output_tokens: 0},
      name: name
    }
  end

  @doc """
  Add a message to the session.

  ## Parameters
  - `session` - The session to update
  - `role` - Message role ("user", "assistant", etc.)
  - `content` - Message content
  - `opts` - Additional message metadata

  ## Returns
  Updated session with the new message.

  ## Examples

      session = ExLLM.Session.add_message(session, "user", "Hello!")
      session = ExLLM.Session.add_message(session, "assistant", "Hi there!", timestamp: DateTime.utc_now())
  """
  @spec add_message(Types.Session.t(), String.t(), String.t(), keyword()) :: Types.Session.t()
  def add_message(session, role, content, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    message =
      %{
        role: role,
        content: content,
        timestamp: timestamp
      }
      |> merge_additional_opts(opts, [:timestamp])

    updated_messages = session.messages ++ [message]

    %{session | messages: updated_messages, updated_at: DateTime.utc_now()}
  end

  @doc """
  Get messages from the session, optionally with a limit.

  ## Parameters
  - `session` - The session to get messages from
  - `limit` - Maximum number of messages to return (optional)

  ## Returns
  List of messages, most recent first if limited.

  ## Examples

      all_messages = ExLLM.Session.get_messages(session)
      last_5 = ExLLM.Session.get_messages(session, 5)
  """
  @spec get_messages(Types.Session.t(), non_neg_integer() | nil) :: [Types.message()]
  def get_messages(session, limit \\ nil) do
    messages = session.messages

    case limit do
      nil ->
        messages

      n when is_integer(n) and n > 0 ->
        messages |> Enum.take(-n)

      _ ->
        messages
    end
  end

  @doc """
  Update the token usage for the session.

  ## Parameters
  - `session` - The session to update
  - `usage` - Token usage map with `:input_tokens` and `:output_tokens`

  ## Returns
  Updated session with new token usage.

  ## Examples

      session = ExLLM.Session.update_token_usage(session, %{input_tokens: 100, output_tokens: 150})
  """
  @spec update_token_usage(Types.Session.t(), Types.token_usage()) :: Types.Session.t()
  def update_token_usage(session, usage) do
    current_usage = session.token_usage || %{input_tokens: 0, output_tokens: 0}

    new_usage = %{
      input_tokens: current_usage.input_tokens + Map.get(usage, :input_tokens, 0),
      output_tokens: current_usage.output_tokens + Map.get(usage, :output_tokens, 0)
    }

    %{session | token_usage: new_usage, updated_at: DateTime.utc_now()}
  end

  @doc """
  Set context for the session.

  ## Parameters
  - `session` - The session to update
  - `context` - Context map to set

  ## Returns
  Updated session with new context.

  ## Examples

      session = ExLLM.Session.set_context(session, %{temperature: 0.7, max_tokens: 1000})
  """
  @spec set_context(Types.Session.t(), Types.context()) :: Types.Session.t()
  def set_context(session, context) do
    %{session | context: context, updated_at: DateTime.utc_now()}
  end

  @doc """
  Clear all messages from the session.

  ## Parameters
  - `session` - The session to clear

  ## Returns
  Updated session with empty message list.

  ## Examples

      session = ExLLM.Session.clear_messages(session)
  """
  @spec clear_messages(Types.Session.t()) :: Types.Session.t()
  def clear_messages(session) do
    %{session | messages: [], updated_at: DateTime.utc_now()}
  end

  @doc """
  Set the name of the session.

  ## Parameters
  - `session` - The session to update
  - `name` - New session name

  ## Returns
  Updated session with new name.

  ## Examples

      session = ExLLM.Session.set_name(session, "My Important Chat")
  """
  @spec set_name(Types.Session.t(), String.t() | nil) :: Types.Session.t()
  def set_name(session, name) do
    %{session | name: name, updated_at: DateTime.utc_now()}
  end

  @doc """
  Get the total token count for the session.

  ## Parameters
  - `session` - The session to analyze

  ## Returns
  Total token count (input + output).

  ## Examples

      total = ExLLM.Session.total_tokens(session)
  """
  @spec total_tokens(Types.Session.t()) :: non_neg_integer()
  def total_tokens(session) do
    case session.token_usage do
      nil -> 0
      usage -> Map.get(usage, :input_tokens, 0) + Map.get(usage, :output_tokens, 0)
    end
  end

  @doc """
  Serialize session to JSON.

  ## Parameters
  - `session` - The session to serialize

  ## Returns
  `{:ok, json_string}` on success, `{:error, reason}` on failure.

  ## Examples

      {:ok, json} = ExLLM.Session.to_json(session)
  """
  @spec to_json(Types.Session.t()) :: {:ok, String.t()} | {:error, term()}
  def to_json(session) do
    session_map = %{
      id: session.id,
      llm_backend: session.llm_backend,
      messages: session.messages,
      context: session.context,
      created_at: DateTime.to_iso8601(session.created_at),
      updated_at: DateTime.to_iso8601(session.updated_at),
      token_usage: session.token_usage,
      name: session.name
    }

    Jason.encode(session_map)
  end

  @doc """
  Deserialize session from JSON.

  ## Parameters
  - `json_string` - JSON string to deserialize

  ## Returns
  `{:ok, session}` on success, `{:error, reason}` on failure.

  ## Examples

      {:ok, session} = ExLLM.Session.from_json(json_string)
  """
  @spec from_json(String.t()) :: {:ok, Types.Session.t()} | {:error, term()}
  def from_json(json_string) do
    with {:ok, data} <- Jason.decode(json_string),
         {:ok, created_at} <- parse_datetime(data["created_at"]),
         {:ok, updated_at} <- parse_datetime(data["updated_at"]) do
      session = %Types.Session{
        id: data["id"],
        llm_backend: data["llm_backend"],
        messages: data["messages"] || [],
        context: data["context"] || %{},
        created_at: created_at,
        updated_at: updated_at,
        token_usage: normalize_token_usage(data["token_usage"]),
        name: data["name"]
      }

      {:ok, session}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp merge_additional_opts(message, opts, exclude_keys) do
    additional_opts =
      opts
      |> Keyword.drop(exclude_keys)
      |> Enum.into(%{})

    Map.merge(message, additional_opts)
  end

  defp parse_datetime(nil), do: {:error, "datetime is nil"}

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_datetime(_), do: {:error, "invalid datetime format"}

  defp normalize_token_usage(nil), do: nil

  defp normalize_token_usage(usage) when is_map(usage) do
    %{
      input_tokens: Map.get(usage, "input_tokens") || Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, "output_tokens") || Map.get(usage, :output_tokens, 0)
    }
  end
end