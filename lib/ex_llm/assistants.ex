defmodule ExLLM.Assistants do
  @moduledoc """
  OpenAI Assistants API functionality for ExLLM.

  This module provides functions for working with OpenAI's Assistants API,
  including creating assistants, managing conversation threads, and running
  assistant interactions.

  ## Features

  - **Assistant Management**: Create, list, update, and delete AI assistants
  - **Thread Management**: Create conversation threads for multi-turn interactions
  - **Message Handling**: Add messages to threads and manage conversation flow
  - **Assistant Execution**: Run assistants on threads with custom instructions
  - **Provider Support**: Currently supports OpenAI with extensible architecture

  ## Examples

      # Create an assistant
      {:ok, assistant} = ExLLM.Assistants.create_assistant(:openai,
        name: "Math Tutor",
        instructions: "You are a helpful math tutor.",
        model: "gpt-4"
      )
      
      # Create a conversation thread
      {:ok, thread} = ExLLM.Assistants.create_thread(:openai)
      
      # Add a message to the thread
      {:ok, message} = ExLLM.Assistants.create_message(:openai, thread.id, 
        "What is 2 + 2?")
      
      # Run the assistant
      {:ok, run} = ExLLM.Assistants.run_assistant(:openai, thread.id, assistant.id)
  """

  alias ExLLM.API.Delegator

  @doc """
  Create an AI assistant.

  Creates a new AI assistant with the specified configuration. Assistants are
  AI agents that can use models, tools, and knowledge to respond to user queries.

  ## Parameters

    * `provider` - The provider to use (currently only `:openai` supported)
    * `opts` - Configuration options for the assistant

  ## Options

    * `:name` - Name of the assistant (required)
    * `:instructions` - System instructions for the assistant (required)
    * `:model` - Model to use (e.g., "gpt-4", "gpt-3.5-turbo")
    * `:description` - Description of the assistant
    * `:tools` - List of tools the assistant can use
    * `:file_ids` - List of file IDs for knowledge retrieval
    * `:metadata` - Custom metadata for the assistant

  ## Examples

      # Create a basic assistant
      {:ok, assistant} = ExLLM.Assistants.create_assistant(:openai,
        name: "Code Helper",
        instructions: "You are a helpful coding assistant.",
        model: "gpt-4"
      )

      # Create an assistant with tools
      {:ok, assistant} = ExLLM.Assistants.create_assistant(:openai,
        name: "Data Analyst",
        instructions: "You help analyze data and create visualizations.",
        model: "gpt-4",
        tools: [%{type: "code_interpreter"}]
      )

  ## Response Format

      {:ok, %{
        id: "asst_abc123",
        object: "assistant",
        name: "Code Helper",
        instructions: "You are a helpful coding assistant.",
        model: "gpt-4",
        tools: [],
        file_ids: [],
        metadata: %{}
      }}
  """
  @spec create_assistant(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_assistant(provider, opts \\ []) do
    case Delegator.delegate(:create_assistant, provider, [opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List AI assistants.

  Retrieves a list of assistants associated with your account. Results can be
  filtered and paginated using the provided options.

  ## Parameters

    * `provider` - The provider to use (currently only `:openai` supported)  
    * `opts` - Query options for filtering and pagination

  ## Options

    * `:limit` - Number of assistants to retrieve (1-100, default: 20)
    * `:order` - Sort order: "asc" or "desc" (default: "desc")
    * `:after` - Cursor for pagination (assistant ID)
    * `:before` - Cursor for pagination (assistant ID)

  ## Examples

      # List all assistants
      {:ok, response} = ExLLM.Assistants.list_assistants(:openai)

      # List with pagination
      {:ok, response} = ExLLM.Assistants.list_assistants(:openai, limit: 10, order: "asc")

  ## Response Format

      {:ok, %{
        object: "list",
        data: [
          %{
            id: "asst_abc123",
            name: "Code Helper",
            instructions: "You are a helpful coding assistant.",
            # ... other assistant fields
          }
        ],
        first_id: "asst_abc123",
        last_id: "asst_xyz789",
        has_more: false
      }}
  """
  @spec list_assistants(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_assistants(provider, opts \\ []) do
    case Delegator.delegate(:list_assistants, provider, [opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieve an AI assistant by ID.

  Gets detailed information about a specific assistant including its configuration,
  tools, and metadata.

  ## Parameters

    * `provider` - The provider to use (currently only `:openai` supported)
    * `assistant_id` - The ID of the assistant to retrieve
    * `opts` - Additional options (currently unused)

  ## Examples

      {:ok, assistant} = ExLLM.Assistants.get_assistant(:openai, "asst_abc123")

  ## Response Format

      {:ok, %{
        id: "asst_abc123",
        object: "assistant", 
        name: "Code Helper",
        instructions: "You are a helpful coding assistant.",
        model: "gpt-4",
        tools: [],
        file_ids: [],
        metadata: %{},
        created_at: 1699024600
      }}
  """
  @spec get_assistant(atom(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_assistant(provider, assistant_id, opts \\ []) do
    case Delegator.delegate(:get_assistant, provider, [assistant_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Update an AI assistant.

  Modifies the configuration of an existing assistant. You can update any of the
  assistant's properties including name, instructions, model, tools, and metadata.

  ## Parameters

    * `provider` - The provider to use (currently only `:openai` supported)
    * `assistant_id` - The ID of the assistant to update
    * `updates` - Map of updates to apply
    * `opts` - Additional options (currently unused)

  ## Update Fields

    * `:name` - New name for the assistant
    * `:instructions` - New system instructions
    * `:model` - New model to use
    * `:description` - New description
    * `:tools` - New list of tools
    * `:file_ids` - New list of file IDs
    * `:metadata` - New metadata

  ## Examples

      # Update assistant name and instructions
      {:ok, assistant} = ExLLM.Assistants.update_assistant(:openai, "asst_abc123", %{
        name: "Advanced Code Helper",
        instructions: "You are an expert coding assistant specializing in Python."
      })

      # Add tools to an assistant
      {:ok, assistant} = ExLLM.Assistants.update_assistant(:openai, "asst_abc123", %{
        tools: [%{type: "code_interpreter"}, %{type: "retrieval"}]
      })

  ## Response Format

      {:ok, %{
        id: "asst_abc123",
        object: "assistant",
        name: "Advanced Code Helper",
        instructions: "You are an expert coding assistant specializing in Python.",
        model: "gpt-4",
        tools: [%{type: "code_interpreter"}],
        file_ids: [],
        metadata: %{}
      }}
  """
  @spec update_assistant(atom(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def update_assistant(provider, assistant_id, updates, opts \\ []) do
    case Delegator.delegate(:update_assistant, provider, [assistant_id, updates, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Delete an AI assistant.

  Permanently deletes an assistant. This action cannot be undone. All associated
  threads and runs will no longer have access to this assistant.

  ## Parameters

    * `provider` - The provider to use (currently only `:openai` supported)
    * `assistant_id` - The ID of the assistant to delete
    * `opts` - Additional options (currently unused)

  ## Examples

      {:ok, result} = ExLLM.Assistants.delete_assistant(:openai, "asst_abc123")

  ## Response Format

      {:ok, %{
        id: "asst_abc123",
        object: "assistant.deleted",
        deleted: true
      }}
  """
  @spec delete_assistant(atom(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def delete_assistant(provider, assistant_id, opts \\ []) do
    case Delegator.delegate(:delete_assistant, provider, [assistant_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Create a conversation thread.

  Creates a new thread for managing a conversation between a user and an assistant.
  Threads maintain conversation context and can be used for multi-turn interactions.

  ## Parameters

    * `provider` - The provider to use (currently only `:openai` supported)
    * `opts` - Configuration options for the thread

  ## Options

    * `:messages` - List of initial messages for the thread
    * `:metadata` - Custom metadata for the thread

  ## Examples

      # Create an empty thread
      {:ok, thread} = ExLLM.Assistants.create_thread(:openai)

      # Create a thread with initial messages
      {:ok, thread} = ExLLM.Assistants.create_thread(:openai,
        messages: [
          %{role: "user", content: "Hello! I need help with Python."}
        ]
      )

      # Create a thread with metadata
      {:ok, thread} = ExLLM.Assistants.create_thread(:openai,
        metadata: %{user_id: "user_123", session_id: "session_456"}
      )

  ## Response Format

      {:ok, %{
        id: "thread_abc123",
        object: "thread",
        created_at: 1699024600,
        metadata: %{}
      }}
  """
  @spec create_thread(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_thread(provider, opts \\ []) do
    case Delegator.delegate(:create_thread, provider, [opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Create a message in a thread.

  Adds a new message to an existing conversation thread. Messages can include
  text content and file attachments.

  ## Parameters

    * `provider` - The provider to use (currently only `:openai` supported)
    * `thread_id` - The ID of the thread to add the message to
    * `content` - The content of the message (string)
    * `opts` - Additional message options

  ## Options

    * `:role` - Message role: "user" or "assistant" (default: "user")
    * `:file_ids` - List of file IDs to attach to the message
    * `:metadata` - Custom metadata for the message

  ## Examples

      # Add a simple user message
      {:ok, message} = ExLLM.Assistants.create_message(:openai, "thread_abc123", 
        "Can you help me debug this Python code?")

      # Add a message with file attachments
      {:ok, message} = ExLLM.Assistants.create_message(:openai, "thread_abc123",
        "Please review this code file.",
        file_ids: ["file_abc123"]
      )

      # Add a message with metadata
      {:ok, message} = ExLLM.Assistants.create_message(:openai, "thread_abc123",
        "What's the weather like?",
        metadata: %{intent: "weather_query"}
      )

  ## Response Format

      {:ok, %{
        id: "msg_abc123",
        object: "thread.message",
        created_at: 1699024600,
        thread_id: "thread_abc123",
        role: "user",
        content: [
          %{
            type: "text",
            text: %{value: "Can you help me debug this Python code?"}
          }
        ],
        file_ids: [],
        assistant_id: nil,
        run_id: nil,
        metadata: %{}
      }}
  """
  @spec create_message(atom(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def create_message(provider, thread_id, content, opts \\ []) do
    case Delegator.delegate(:create_message, provider, [thread_id, content, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Run an assistant on a thread.

  Executes an assistant on a conversation thread, generating responses based on
  the thread's message history and the assistant's configuration.

  ## Parameters

    * `provider` - The provider to use (currently only `:openai` supported)
    * `thread_id` - The ID of the thread to run the assistant on
    * `assistant_id` - The ID of the assistant to run
    * `opts` - Run configuration options

  ## Options

    * `:model` - Override the assistant's default model
    * `:instructions` - Additional instructions for this run
    * `:tools` - Override the assistant's tools for this run
    * `:metadata` - Custom metadata for the run

  ## Examples

      # Run assistant with default settings
      {:ok, run} = ExLLM.Assistants.run_assistant(:openai, "thread_abc123", "asst_abc123")

      # Run with custom instructions
      {:ok, run} = ExLLM.Assistants.run_assistant(:openai, "thread_abc123", "asst_abc123",
        instructions: "Please be extra concise in your response."
      )

      # Run with metadata
      {:ok, run} = ExLLM.Assistants.run_assistant(:openai, "thread_abc123", "asst_abc123",
        metadata: %{request_id: "req_123"}
      )

  ## Response Format

      {:ok, %{
        id: "run_abc123",
        object: "thread.run",
        created_at: 1699024600,
        thread_id: "thread_abc123",
        assistant_id: "asst_abc123",
        status: "queued",
        required_action: nil,
        last_error: nil,
        expires_at: 1699111000,
        started_at: nil,
        cancelled_at: nil,
        failed_at: nil,
        completed_at: nil,
        model: "gpt-4",
        instructions: "You are a helpful coding assistant.",
        tools: [],
        file_ids: [],
        metadata: %{}
      }}
  """
  @spec run_assistant(atom(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def run_assistant(provider, thread_id, assistant_id, opts \\ []) do
    case Delegator.delegate(:run_assistant, provider, [thread_id, assistant_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
