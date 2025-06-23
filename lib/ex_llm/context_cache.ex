defmodule ExLLM.ContextCache do
  @moduledoc """
  Context Caching functionality for ExLLM.

  Context caching allows you to cache large amounts of input content (like
  long documents, system instructions, or tool definitions) and reuse it
  across multiple requests. This can significantly reduce costs and improve
  performance by avoiding the need to re-send and re-process the same
  content repeatedly.

  ## Supported Providers

  - **Gemini**: Caches content for reuse in subsequent `generateContent` calls.

  ## Examples

      # 1. Define the content to cache
      content_to_cache = %{
        model: "models/gemini-1.5-pro-latest",
        contents: [
          %{role: "user", parts: [%{text: "Here is a very long document..."}]}
        ],
        ttl: "3600s" # Cache for 1 hour
      }

      # 2. Create the cached content
      {:ok, cached_content} = ExLLM.ContextCache.create_cached_context(:gemini, content_to_cache)
      # => {:ok, %{name: "cachedContents/abc-123", ...}}

      # 3. Use the cached content in a chat request
      # (This part is handled by the provider's implementation, but conceptually
      # you would reference `cached_content.name` in your chat call)

      # 4. List all cached contexts
      {:ok, response} = ExLLM.ContextCache.list_cached_contexts(:gemini)

      # 5. Get a specific cached context
      {:ok, details} = ExLLM.ContextCache.get_cached_context(:gemini, cached_content.name)

      # 6. Delete the cached context when no longer needed
      :ok = ExLLM.ContextCache.delete_cached_context(:gemini, cached_content.name)
  """

  alias ExLLM.API.Delegator

  @doc """
  Creates cached content for efficient reuse across multiple requests.

  Context caching allows you to cache large amounts of input content and reuse
  it across multiple requests, reducing costs and improving performance.

  ## Parameters
    * `provider` - The LLM provider (currently only `:gemini` supported)
    * `content` - The content to cache (can be messages, system instructions, etc.)
    * `opts` - Options for caching

  ## Options for Gemini
    * `:model` - Model to use for caching (required)
    * `:display_name` - Human-readable name for the cached content
    * `:ttl` - Time-to-live in seconds (e.g., 3600 for 1 hour)
    * `:system_instruction` - System instruction content
    * `:tools` - Tools available to the model
    * `:config_provider` - Configuration provider

  ## Examples

      # Cache conversation context
      request = %{
        model: "models/gemini-1.5-pro",
        contents: [
          %{role: "user", parts: [%{text: "Long document content..."}]}
        ],
        ttl: "3600s"
      }
      {:ok, cached} = ExLLM.ContextCache.create_cached_context(:gemini, request)

  ## Return Value

  Returns `{:ok, cached_content}` with the cached content details, or `{:error, reason}`.
  """
  @spec create_cached_context(atom(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def create_cached_context(provider, content, opts \\ []) do
    case Delegator.delegate(:create_cached_context, provider, [content, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves cached content by name.

  ## Parameters
    * `provider` - The LLM provider (currently only `:gemini` supported)
    * `name` - The cached content name (e.g., "cachedContents/abc-123")
    * `opts` - Options for retrieval

  ## Examples

      {:ok, cached} = ExLLM.ContextCache.get_cached_context(:gemini, "cachedContents/abc-123")

  ## Return Value

  Returns `{:ok, cached_content}` with the cached content details, or `{:error, reason}`.
  """
  @spec get_cached_context(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_cached_context(provider, name, opts \\ []) do
    case Delegator.delegate(:get_cached_context, provider, [name, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates cached content with new information.

  ## Parameters
    * `provider` - The LLM provider (currently only `:gemini` supported)
    * `name` - The cached content name to update
    * `updates` - Map of updates to apply
    * `opts` - Options for the update

  ## Options
    * `:config_provider` - Configuration provider

  ## Examples

      updates = %{
        display_name: "Updated name",
        ttl: "7200s"
      }
      {:ok, updated} = ExLLM.ContextCache.update_cached_context(:gemini, "cachedContents/abc-123", updates)

  ## Return Value

  Returns `{:ok, updated_content}` with the updated cached content, or `{:error, reason}`.
  """
  @spec update_cached_context(atom(), String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def update_cached_context(provider, name, updates, opts \\ []) do
    case Delegator.delegate(:update_cached_context, provider, [name, updates, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes cached content.

  ## Parameters
    * `provider` - The LLM provider (currently only `:gemini` supported)
    * `name` - The cached content name to delete
    * `opts` - Options for deletion

  ## Examples

      :ok = ExLLM.ContextCache.delete_cached_context(:gemini, "cachedContents/abc-123")

  ## Return Value

  Returns `:ok` if successful, or `{:error, reason}` if failed.
  """
  @spec delete_cached_context(atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete_cached_context(provider, name, opts \\ []) do
    case Delegator.delegate(:delete_cached_context, provider, [name, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all cached content.

  ## Parameters
    * `provider` - The LLM provider (currently only `:gemini` supported)
    * `opts` - Options for listing

  ## Options for Gemini
    * `:page_size` - Number of results per page (max 100)
    * `:page_token` - Token for pagination
    * `:config_provider` - Configuration provider

  ## Examples

      {:ok, %{cached_contents: contents, next_page_token: token}} = ExLLM.ContextCache.list_cached_contexts(:gemini)
      
      # With pagination
      {:ok, %{cached_contents: more_contents}} = ExLLM.ContextCache.list_cached_contexts(:gemini, 
        page_token: token, page_size: 50)

  ## Return Value

  Returns `{:ok, %{cached_contents: list, next_page_token: token}}` or `{:error, reason}`.
  """
  @spec list_cached_contexts(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_cached_contexts(provider, opts \\ []) do
    case Delegator.delegate(:list_cached_contexts, provider, [opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
