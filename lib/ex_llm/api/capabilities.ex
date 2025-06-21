defmodule ExLLM.API.Capabilities do
  @moduledoc """
  Provider capability registry for the unified API delegation system.

  This module defines which providers support which operations and how
  to handle argument transformations for each provider.
  """

  @type capability_type :: :direct | atom()
  @type provider_capability :: {module(), atom(), capability_type()}
  @type capability_map :: %{atom() => %{atom() => provider_capability()}}

  # Registry of all provider capabilities.
  #
  # Format: %{operation => %{provider => {module, function, transformation_type}}}
  #
  # Transformation types:
  # - :direct - No argument transformation needed
  # - :transform_upload_args - Extract :purpose for OpenAI upload_file
  # - :preprocess_gemini_tuning - Build Gemini tuning request
  # - :preprocess_openai_tuning - Build OpenAI tuning params
  @capabilities %{
    # File Management (4 functions)
    upload_file: %{
      gemini: {ExLLM.Providers.Gemini.Files, :upload_file, :direct},
      openai: {ExLLM.Providers.OpenAI, :upload_file, :transform_upload_args}
    },
    list_files: %{
      gemini: {ExLLM.Providers.Gemini.Files, :list_files, :direct},
      openai: {ExLLM.Providers.OpenAI, :list_files, :direct}
    },
    get_file: %{
      gemini: {ExLLM.Providers.Gemini.Files, :get_file, :direct},
      openai: {ExLLM.Providers.OpenAI, :get_file, :direct}
    },
    delete_file: %{
      gemini: {ExLLM.Providers.Gemini.Files, :delete_file, :direct},
      openai: {ExLLM.Providers.OpenAI, :delete_file, :direct}
    },

    # Context Caching (5 functions) - Gemini only
    create_cached_context: %{
      gemini: {ExLLM.Providers.Gemini.Caching, :create_cached_content, :direct}
    },
    get_cached_context: %{
      gemini: {ExLLM.Providers.Gemini.Caching, :get_cached_content, :direct}
    },
    update_cached_context: %{
      gemini: {ExLLM.Providers.Gemini.Caching, :update_cached_content, :direct}
    },
    delete_cached_context: %{
      gemini: {ExLLM.Providers.Gemini.Caching, :delete_cached_content, :direct}
    },
    list_cached_contexts: %{
      gemini: {ExLLM.Providers.Gemini.Caching, :list_cached_contents, :direct}
    },

    # Knowledge Bases (9 functions) - Gemini only
    create_knowledge_base: %{
      gemini: {ExLLM.Providers.Gemini.Corpus, :create_corpus, :transform_knowledge_base_args}
    },
    list_knowledge_bases: %{
      gemini: {ExLLM.Providers.Gemini.Corpus, :list_corpora, :transform_list_knowledge_bases_args}
    },
    get_knowledge_base: %{
      gemini: {ExLLM.Providers.Gemini.Corpus, :get_corpus, :direct}
    },
    delete_knowledge_base: %{
      gemini: {ExLLM.Providers.Gemini.Corpus, :delete_corpus, :direct}
    },
    add_document: %{
      gemini: {ExLLM.Providers.Gemini.Document, :create_document, :direct}
    },
    list_documents: %{
      gemini: {ExLLM.Providers.Gemini.Document, :list_documents, :direct}
    },
    get_document: %{
      gemini: {ExLLM.Providers.Gemini.Document, :get_document, :transform_get_document_args}
    },
    delete_document: %{
      gemini: {ExLLM.Providers.Gemini.Document, :delete_document, :transform_delete_document_args}
    },
    semantic_search: %{
      gemini: {ExLLM.Providers.Gemini.QA, :generate_answer, :transform_semantic_search_args}
    },

    # Fine-tuning (4 functions)
    create_fine_tune: %{
      gemini: {ExLLM.Providers.Gemini.Tuning, :create_tuned_model, :preprocess_gemini_tuning},
      openai: {ExLLM.Providers.OpenAI, :create_fine_tuning_job, :preprocess_openai_tuning}
    },
    list_fine_tunes: %{
      gemini: {ExLLM.Providers.Gemini.Tuning, :list_tuned_models, :direct},
      openai: {ExLLM.Providers.OpenAI, :list_fine_tuning_jobs, :direct}
    },
    get_fine_tune: %{
      gemini: {ExLLM.Providers.Gemini.Tuning, :get_tuned_model, :direct},
      openai: {ExLLM.Providers.OpenAI, :get_fine_tuning_job, :direct}
    },
    cancel_fine_tune: %{
      gemini: {ExLLM.Providers.Gemini.Tuning, :delete_tuned_model, :direct},
      openai: {ExLLM.Providers.OpenAI, :cancel_fine_tuning_job, :direct}
    },

    # Assistants (8 functions) - OpenAI only
    create_assistant: %{
      openai: {ExLLM.Providers.OpenAI, :create_assistant, :transform_create_assistant_args}
    },
    list_assistants: %{
      openai: {ExLLM.Providers.OpenAI, :list_assistants, :direct}
    },
    get_assistant: %{
      openai: {ExLLM.Providers.OpenAI, :get_assistant, :direct}
    },
    update_assistant: %{
      openai: {ExLLM.Providers.OpenAI, :update_assistant, :direct}
    },
    delete_assistant: %{
      openai: {ExLLM.Providers.OpenAI, :delete_assistant, :direct}
    },
    create_thread: %{
      openai: {ExLLM.Providers.OpenAI, :create_thread, :transform_create_thread_args}
    },
    create_message: %{
      openai: {ExLLM.Providers.OpenAI, :create_message, :transform_create_message_args}
    },
    run_assistant: %{
      openai: {ExLLM.Providers.OpenAI, :create_run, :transform_run_assistant_args}
    },

    # Batch Processing (3 functions) - Anthropic only
    create_batch: %{
      anthropic: {ExLLM.Providers.Anthropic, :create_message_batch, :direct}
    },
    get_batch: %{
      anthropic: {ExLLM.Providers.Anthropic, :get_message_batch, :direct}
    },
    cancel_batch: %{
      anthropic: {ExLLM.Providers.Anthropic, :cancel_message_batch, :direct}
    },

    # Token Counting - Gemini only
    count_tokens: %{
      gemini: {ExLLM.Providers.Gemini.Tokens, :count_tokens, :transform_count_tokens_args}
    }
  }

  @doc """
  Get the capability configuration for a specific operation and provider.

  Returns the {module, function, transformation_type} tuple or nil if not supported.
  """
  @spec get_capability(atom(), atom()) :: provider_capability() | nil
  def get_capability(operation, provider) do
    @capabilities
    |> Map.get(operation, %{})
    |> Map.get(provider)
  end

  @doc """
  Check if a provider supports a specific operation.
  """
  @spec supports?(atom(), atom()) :: boolean()
  def supports?(operation, provider) do
    get_capability(operation, provider) != nil
  end

  @doc """
  Get all providers that support a specific operation.
  """
  @spec get_providers(atom()) :: [atom()]
  def get_providers(operation) do
    @capabilities
    |> Map.get(operation, %{})
    |> Map.keys()
  end

  @doc """
  Get all operations supported by a specific provider.
  """
  @spec get_operations(atom()) :: [atom()]
  def get_operations(provider) do
    @capabilities
    |> Enum.filter(fn {_operation, providers} ->
      Map.has_key?(providers, provider)
    end)
    |> Enum.map(fn {operation, _providers} -> operation end)
  end

  @doc """
  Get all registered capabilities.
  """
  @spec all_capabilities() :: capability_map()
  def all_capabilities, do: @capabilities

  @doc """
  Get summary statistics about the capability registry.
  """
  @spec stats() :: %{
          total_operations: non_neg_integer(),
          total_capabilities: non_neg_integer(),
          providers: [atom()],
          operations_by_provider: %{atom() => non_neg_integer()}
        }
  def stats do
    all_providers =
      @capabilities
      |> Enum.flat_map(fn {_op, providers} -> Map.keys(providers) end)
      |> Enum.uniq()
      |> Enum.sort()

    operations_by_provider =
      Enum.into(all_providers, %{}, fn provider ->
        operation_count = get_operations(provider) |> length()
        {provider, operation_count}
      end)

    total_capabilities =
      @capabilities
      |> Enum.map(fn {_op, providers} -> map_size(providers) end)
      |> Enum.sum()

    %{
      total_operations: map_size(@capabilities),
      total_capabilities: total_capabilities,
      providers: all_providers,
      operations_by_provider: operations_by_provider
    }
  end
end
