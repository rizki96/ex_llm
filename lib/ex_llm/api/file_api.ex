defmodule ExLLM.API.FileAPI do
  @moduledoc """
  File management operations using the delegation system.

  This module demonstrates the new delegation pattern for file operations
  across providers. It replaces the repetitive pattern matching functions
  with clean delegation calls.
  """

  alias ExLLM.API.Delegator

  @doc """
  Upload a file to the specified provider.

  ## Parameters
  - `provider` - The provider atom (:gemini, :openai)
  - `file_path` - Path to the file to upload  
  - `opts` - Options (for OpenAI, :purpose will be extracted automatically)

  ## Examples
      
      # Gemini file upload
      {:ok, file} = ExLLM.API.FileAPI.upload_file(:gemini, "/path/to/file.txt", [])
      
      # OpenAI file upload (purpose extracted automatically)
      {:ok, file} = ExLLM.API.FileAPI.upload_file(:openai, "/path/to/file.txt", [purpose: "fine-tune"])
  """
  @spec upload_file(atom(), String.t(), keyword() | map()) :: {:ok, term()} | {:error, String.t()}
  def upload_file(provider, file_path, opts \\ []) do
    case Delegator.delegate(:upload_file, provider, [file_path, opts]) do
      {:ok, result} -> {:ok, result}
      {:error, _} = error -> error
    end
  end

  @doc """
  List files for the specified provider.
  """
  @spec list_files(atom(), keyword() | map()) :: {:ok, term()} | {:error, String.t()}
  def list_files(provider, opts \\ []) do
    case Delegator.delegate(:list_files, provider, [opts]) do
      {:ok, result} -> {:ok, result}
      {:error, _} = error -> error
    end
  end

  @doc """
  Get a specific file by ID for the specified provider.
  """
  @spec get_file(atom(), String.t(), keyword() | map()) :: {:ok, term()} | {:error, String.t()}
  def get_file(provider, file_id, opts \\ []) do
    case Delegator.delegate(:get_file, provider, [file_id, opts]) do
      {:ok, result} -> {:ok, result}
      {:error, _} = error -> error
    end
  end

  @doc """
  Delete a file by ID for the specified provider.
  """
  @spec delete_file(atom(), String.t(), keyword() | map()) :: {:ok, term()} | {:error, String.t()}
  def delete_file(provider, file_id, opts \\ []) do
    case Delegator.delegate(:delete_file, provider, [file_id, opts]) do
      {:ok, result} -> {:ok, result}
      {:error, _} = error -> error
    end
  end

  @doc """
  Check which providers support file operations.
  """
  @spec supported_providers() :: %{atom() => [atom()]}
  def supported_providers do
    %{
      upload_file: Delegator.get_supported_providers(:upload_file),
      list_files: Delegator.get_supported_providers(:list_files),
      get_file: Delegator.get_supported_providers(:get_file),
      delete_file: Delegator.get_supported_providers(:delete_file)
    }
  end
end
