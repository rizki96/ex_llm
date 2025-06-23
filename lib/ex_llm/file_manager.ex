defmodule ExLLM.FileManager do
  @moduledoc """
  File management functionality for ExLLM.

  This module provides functions for uploading, listing, retrieving, and deleting
  files across different providers like Gemini and OpenAI. These files can be used
  for multimodal models, fine-tuning, and other provider-specific features.

  ## Supported Providers

  - **Gemini**: File uploads for multimodal models, document processing
  - **OpenAI**: File uploads for fine-tuning, assistants, and vision models

  ## Examples

      # Upload a file to Gemini
      {:ok, file} = ExLLM.FileManager.upload_file(:gemini, "/path/to/image.png", 
        display_name: "My Image")
      
      # List OpenAI files
      {:ok, files} = ExLLM.FileManager.list_files(:openai)
      
      # Get file metadata
      {:ok, file_info} = ExLLM.FileManager.get_file(:gemini, "files/abc-123")
      
      # Delete a file
      :ok = ExLLM.FileManager.delete_file(:gemini, "files/abc-123")
  """

  alias ExLLM.API.Delegator

  @doc """
  Upload a file to the provider for use in multimodal models or fine-tuning.

  ## Parameters

    * `provider` - The provider atom (`:gemini` or `:openai`)
    * `file_path` - Path to the file to upload
    * `opts` - Upload options

  ## Options

  For Gemini:
    * `:display_name` - Human-readable name for the file
    * `:mime_type` - Override automatic MIME type detection
    * `:config_provider` - Configuration provider

  For OpenAI:
    * `:purpose` - Purpose of the file ("fine-tune", "assistants", "vision", "user_data", etc.)
    * `:config_provider` - Configuration provider

  ## Examples

      # Upload to Gemini
      {:ok, file} = ExLLM.FileManager.upload_file(:gemini, "/path/to/image.png", 
        display_name: "My Image")
      
      # Upload to OpenAI for fine-tuning
      {:ok, file} = ExLLM.FileManager.upload_file(:openai, "/path/to/training.jsonl",
        purpose: "fine-tune")

  ## Return Value

  Returns `{:ok, file_info}` with file metadata, or `{:error, reason}`.
  """
  @spec upload_file(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def upload_file(provider, file_path, opts \\ []) do
    case Delegator.delegate(:upload_file, provider, [file_path, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List files uploaded to the provider.

  ## Parameters

    * `provider` - The provider atom (`:gemini` or `:openai`)
    * `opts` - Listing options

  ## Options

  For Gemini:
    * `:page_size` - Number of files per page (default: 10)
    * `:page_token` - Token for pagination
    * `:config_provider` - Configuration provider

  For OpenAI:
    * `:purpose` - Filter by file purpose ("fine-tune", "assistants", etc.)
    * `:limit` - Number of files to return (max 100)
    * `:config_provider` - Configuration provider

  ## Examples

      # List Gemini files
      {:ok, response} = ExLLM.FileManager.list_files(:gemini)
      Enum.each(response.files, fn file ->
        IO.puts("File: \#{file.display_name} (\#{file.name})")
      end)
      
      # List OpenAI fine-tuning files
      {:ok, response} = ExLLM.FileManager.list_files(:openai, purpose: "fine-tune")

  ## Return Value

  Returns `{:ok, list_response}` with files and pagination info, or `{:error, reason}`.
  """
  @spec list_files(atom(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_files(provider, opts \\ []) do
    case Delegator.delegate(:list_files, provider, [opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get metadata for a specific file.

  ## Parameters

    * `provider` - The provider atom (currently only `:gemini`)
    * `file_id` - The file identifier
    * `opts` - Request options

  ## Examples

      {:ok, file} = ExLLM.FileManager.get_file(:gemini, "files/abc-123")
      IO.puts("File size: \#{file.size_bytes} bytes")

  ## Return Value

  Returns `{:ok, file_info}` with file metadata, or `{:error, reason}`.
  """
  @spec get_file(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_file(provider, file_id, opts \\ []) do
    case Delegator.delegate(:get_file, provider, [file_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Delete a file from the provider.

  ## Parameters

    * `provider` - The provider atom (currently only `:gemini`)
    * `file_id` - The file identifier
    * `opts` - Request options

  ## Examples

      :ok = ExLLM.FileManager.delete_file(:gemini, "files/abc-123")

  ## Return Value

  Returns `:ok` on success, or `{:error, reason}` on failure.
  """
  @spec delete_file(atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_file(provider, file_id, opts \\ []) do
    case Delegator.delegate(:delete_file, provider, [file_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
