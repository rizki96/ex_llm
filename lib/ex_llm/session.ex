defmodule ExLLM.Session do
  @moduledoc """
  Session management functionality for ExLLM.

  This module provides functions for managing conversation sessions, including
  message history, token usage tracking, and session persistence. Sessions
  enable stateful conversations across multiple interactions while maintaining
  context and history.

  ## Features

  - **Conversation Management**: Track message history and conversation flow
  - **Token Usage**: Monitor token consumption across conversation turns
  - **Session Persistence**: Save and load sessions to/from files or JSON
  - **Context Integration**: Automatic context management for chat sessions
  - **Immutable Design**: Functional approach with immutable session updates

  ## Examples

      # Create a new session
      session = ExLLM.Session.new_session(:openai, model: "gpt-4")
      
      # Add messages to the session
      session = ExLLM.Session.add_message(session, "user", "Hello!")
      session = ExLLM.Session.add_message(session, "assistant", "Hi there!")
      
      # Chat with session (automatically manages context)
      {:ok, response, updated_session} = ExLLM.Session.chat_session(session, "How are you?")
      
      # Save and load sessions
      ExLLM.Session.save_session(session, "conversation.json")
      loaded_session = ExLLM.Session.load_session("conversation.json")
  """

  alias ExLLM.Core.Session, as: CoreSession
  alias ExLLM.Types.Session

  @doc """
  Create a new session for conversation management.

  Sessions track message history, token usage, and conversation state across
  multiple interactions with LLM providers.

  ## Parameters

    * `provider` - The LLM provider atom (e.g., `:openai`, `:anthropic`)
    * `opts` - Session configuration options

  ## Options

    * `:model` - Default model for the session
    * `:max_tokens` - Token limit for the session
    * `:context_strategy` - Context management strategy
    * `:system_message` - System message for the session

  ## Examples

      # Basic session
      session = ExLLM.Session.new_session(:openai, model: "gpt-4")
      
      # Session with configuration
      session = ExLLM.Session.new_session(:anthropic,
        model: "claude-3-opus",
        max_tokens: 4000,
        system_message: "You are a helpful assistant."
      )

  ## Returns

  Returns a new session struct that can be used for conversation management.
  """
  @spec new_session(atom(), keyword()) :: Session.t()
  def new_session(provider, opts \\ []) do
    CoreSession.new(provider, opts)
  end

  @doc """
  Add a message to a session.

  Appends a new message to the session's conversation history. The session
  is immutable, so this returns a new session with the message added.

  ## Parameters

    * `session` - The session struct
    * `role` - Message role ("user", "assistant", "system")
    * `content` - Message content (string)

  ## Examples

      session = ExLLM.Session.add_message(session, "user", "What is the weather like?")
      session = ExLLM.Session.add_message(session, "assistant", "I don't have access to current weather data.")

  ## Returns

  Returns the updated session with the new message added.
  """
  @spec add_message(Session.t(), String.t(), String.t()) :: Session.t()
  def add_message(session, role, content) do
    CoreSession.add_message(session, role, content)
  end

  @doc """
  Get all messages from a session.

  Retrieves the complete message history from the session in chronological order.

  ## Parameters

    * `session` - The session struct

  ## Examples

      messages = ExLLM.Session.get_messages(session)
      # => [
      #   %{role: "user", content: "Hello!"},
      #   %{role: "assistant", content: "Hi there!"}
      # ]

  ## Returns

  Returns a list of message maps with `:role` and `:content` keys.
  """
  @spec get_messages(Session.t()) :: [map()]
  def get_messages(session) do
    CoreSession.get_messages(session)
  end

  @doc """
  Get session messages with optional limit.

  Retrieves messages from the session, optionally limiting the number of
  messages returned. Useful for pagination or getting recent messages.

  ## Parameters

    * `session` - The session struct
    * `limit` - Maximum number of messages to return (optional)

  ## Examples

      # Get all messages
      all_messages = ExLLM.Session.get_session_messages(session)
      
      # Get last 5 messages
      recent_messages = ExLLM.Session.get_session_messages(session, 5)

  ## Returns

  Returns a list of message maps, limited to the specified count if provided.
  """
  @spec get_session_messages(Session.t(), integer() | nil) :: [map()]
  def get_session_messages(session, limit \\ nil) do
    messages = CoreSession.get_messages(session)
    if limit, do: Enum.take(messages, -limit), else: messages
  end

  @doc """
  Add a message to a session.

  Alternative function name for `add_message/3` for backward compatibility.

  ## Parameters

    * `session` - The session struct
    * `role` - Message role ("user", "assistant", "system")
    * `content` - Message content (string)

  ## Examples

      session = ExLLM.Session.add_session_message(session, "user", "Hello!")

  ## Returns

  Returns the updated session with the new message added.
  """
  @spec add_session_message(Session.t(), String.t(), String.t()) :: Session.t()
  def add_session_message(session, role, content) do
    CoreSession.add_message(session, role, content)
  end

  @doc """
  Get total token usage for a session.

  Calculates the total number of tokens used across all messages in the
  session. Useful for tracking costs and managing context limits.

  ## Parameters

    * `session` - The session struct

  ## Examples

      total_tokens = ExLLM.Session.session_token_usage(session)
      # => 1250

  ## Returns

  Returns an integer representing the total token count for the session.
  """
  @spec session_token_usage(Session.t()) :: integer()
  def session_token_usage(session) do
    CoreSession.total_tokens(session)
  end

  @doc """
  Clear all messages from a session.

  Removes all messages from the session while preserving the session
  configuration and metadata.

  ## Parameters

    * `session` - The session struct

  ## Examples

      cleared_session = ExLLM.Session.clear_session(session)

  ## Returns

  Returns a new session with all messages removed.
  """
  @spec clear_session(Session.t()) :: Session.t()
  def clear_session(session) do
    CoreSession.clear_messages(session)
  end

  @doc """
  Save a session to a file.

  Persists the session data to a JSON file for later retrieval. The file
  includes all messages, metadata, and configuration.

  ## Parameters

    * `session` - The session struct
    * `file_path` - Path where the session should be saved

  ## Examples

      :ok = ExLLM.Session.save_session(session, "my_conversation.json")

  ## Returns

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec save_session(Session.t(), String.t()) :: :ok | {:error, term()}
  def save_session(session, file_path) do
    CoreSession.save_to_file(session, file_path)
  end

  @doc """
  Save a session to JSON string.

  Converts the session to a JSON string representation for storage or
  transmission. Alternative to file-based saving.

  ## Parameters

    * `session` - The session struct

  ## Examples

      json_string = ExLLM.Session.save_session(session)

  ## Returns

  Returns a JSON string representation of the session.
  """
  @spec save_session(Session.t()) :: {:ok, String.t()} | {:error, term()}
  def save_session(session) do
    CoreSession.to_json(session)
  end

  @doc """
  Load a session from file path or JSON string.

  Intelligently determines whether the input is a file path or JSON string
  and loads the session accordingly.

  ## Parameters

    * `input` - File path string or JSON string

  ## Examples

      # Load from file
      session = ExLLM.Session.load_session("my_conversation.json")
      
      # Load from JSON string
      json = ~s({"provider": "openai", "messages": []})
      session = ExLLM.Session.load_session(json)

  ## Returns

  Returns the loaded session struct or raises an error if loading fails.
  """
  @spec load_session(String.t()) :: {:ok, Session.t()} | {:error, term()}
  def load_session(input) when is_binary(input) do
    # Determine if input is JSON or file path
    if String.starts_with?(String.trim(input), "{") do
      # Looks like JSON
      CoreSession.from_json(input)
    else
      # Assume it's a file path
      CoreSession.load_from_file(input)
    end
  end

  @doc """
  Perform a chat with a session, managing context automatically.

  Executes a chat request within the context of a session, automatically
  adding the user message, performing the chat, and adding the assistant
  response to the session.

  ## Parameters

    * `session` - The session struct
    * `user_message` - User's message content
    * `opts` - Chat options (same as `ExLLM.chat/3`)

  ## Examples

      {:ok, response, updated_session} = ExLLM.Session.chat_session(session, 
        "What is machine learning?",
        temperature: 0.7
      )

  ## Returns

  Returns `{:ok, response, updated_session}` on success or `{:error, reason}` 
  on failure. The response contains the assistant's reply, and the updated 
  session includes both the user message and assistant response.
  """
  @spec chat_session(Session.t(), String.t(), keyword()) ::
          {:ok, term(), Session.t()} | {:error, term()}
  def chat_session(session, user_message, opts \\ []) do
    # Add user message to session
    updated_session = add_message(session, "user", user_message)

    # Get current messages for the chat
    messages = get_messages(updated_session)

    # Merge session config with provided options (opts take precedence)
    # Handle both atom and string keys (from JSON deserialization)
    session_config =
      (Map.get(session.context, :config) || Map.get(session.context, "config", %{}))
      |> Enum.map(fn
        {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
        {k, v} -> {k, v}
      end)

    merged_opts = Keyword.merge(session_config, opts)

    # Perform the chat with the session's provider (stored in llm_backend)
    case ExLLM.chat(session.llm_backend, messages, merged_opts) do
      {:ok, response} ->
        # Add assistant response to session
        session_with_message = add_message(updated_session, "assistant", response.content)

        # Update token usage if available
        final_session =
          if response.usage do
            ExLLM.Core.Session.update_token_usage(session_with_message, response.usage)
          else
            session_with_message
          end

        {:ok, response, final_session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Alternative interface for chat_session/3.

  Performs a chat with a session and returns the response and updated session
  as a tuple within the success case.

  ## Parameters

    * `session` - The session struct
    * `user_message` - User's message content
    * `opts` - Chat options (same as `ExLLM.chat/3`)

  ## Examples

      {:ok, {response, updated_session}} = ExLLM.Session.chat_with_session(session, 
        "Tell me a joke")

  ## Returns

  Returns `{:ok, {response, updated_session}}` on success or `{:error, reason}` 
  on failure.
  """
  @spec chat_with_session(Session.t(), String.t(), keyword()) ::
          {:ok, {term(), Session.t()}} | {:error, term()}
  def chat_with_session(session, user_message, opts \\ []) do
    case chat_session(session, user_message, opts) do
      {:ok, response, updated_session} ->
        {:ok, {response, updated_session}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
