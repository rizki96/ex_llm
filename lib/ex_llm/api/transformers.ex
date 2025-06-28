defmodule ExLLM.API.Transformers do
  @moduledoc """
  Argument transformation functions for provider-specific API calls.

  Each transformer function handles the conversion of unified API arguments
  to provider-specific formats as needed.
  """

  @doc """
  Transform arguments for OpenAI upload_file function.

  OpenAI requires the :purpose to be extracted and passed as a separate parameter.

  ## Input
  [file_path, opts]

  ## Output  
  [file_path, purpose, config_opts]
  """
  @spec transform_upload_args([term()]) :: [term()]
  def transform_upload_args([file_path, opts]) when is_list(opts) do
    purpose = Keyword.get(opts, :purpose, "user_data")
    config_opts = Keyword.delete(opts, :purpose)
    [file_path, purpose, config_opts]
  end

  def transform_upload_args([file_path, opts]) when is_map(opts) do
    purpose = Map.get(opts, :purpose, "user_data")
    config_opts = Map.delete(opts, :purpose)
    [file_path, purpose, config_opts]
  end

  def transform_upload_args(args) do
    # Fallback - return as-is if unexpected format
    args
  end

  @doc """
  Preprocess arguments for Gemini fine-tuning.

  Builds a Gemini tuning request from dataset and options.

  ## Input
  [dataset, opts]

  ## Output
  [tuning_request, config_opts]
  """
  @spec preprocess_gemini_tuning([term()]) :: [term()]
  def preprocess_gemini_tuning([dataset, opts]) do
    tuning_request = build_gemini_tuning_request(dataset, opts)
    config_opts = extract_config_opts(opts)
    [tuning_request, config_opts]
  end

  @doc """
  Preprocess arguments for OpenAI fine-tuning.

  Builds OpenAI tuning parameters from training file and options.

  ## Input
  [training_file, opts]

  ## Output
  [tuning_params, config_opts]
  """
  @spec preprocess_openai_tuning([term()]) :: [term()]
  def preprocess_openai_tuning([training_file, opts]) do
    tuning_params = build_openai_tuning_params(training_file, opts)
    config_opts = extract_config_opts(opts)
    [tuning_params, config_opts]
  end

  @doc """
  Transform arguments for Gemini knowledge base creation.

  Builds corpus data structure from name and options.

  ## Input
  [name, opts]

  ## Output
  [corpus_data, config_opts]
  """
  @spec transform_knowledge_base_args([term()]) :: [term()]
  def transform_knowledge_base_args([name, opts]) do
    corpus_data = %{name: name, display_name: Keyword.get(opts, :display_name, name)}
    config_opts = Keyword.delete(opts, :display_name)
    [corpus_data, config_opts]
  end

  @doc """
  Transform arguments for Gemini knowledge base listing.

  Adds empty filter map as first argument.

  ## Input
  [opts]

  ## Output
  [{}, opts]
  """
  @spec transform_list_knowledge_bases_args([term()]) :: [term()]
  def transform_list_knowledge_bases_args([opts]) do
    [%{}, opts]
  end

  @doc """
  Transform arguments for Gemini get document.

  Gemini's get_document uses full document name, ignoring knowledge_base.

  ## Input
  [knowledge_base, document_id, opts]

  ## Output
  [document_id, opts]
  """
  @spec transform_get_document_args([term()]) :: [term()]
  def transform_get_document_args([_knowledge_base, document_id, opts]) do
    [document_id, opts]
  end

  @doc """
  Transform arguments for Gemini delete document.

  Gemini's delete_document uses full document name, ignoring knowledge_base.

  ## Input
  [knowledge_base, document_id, opts]

  ## Output
  [document_id, opts]
  """
  @spec transform_delete_document_args([term()]) :: [term()]
  def transform_delete_document_args([_knowledge_base, document_id, opts]) do
    [document_id, opts]
  end

  @doc """
  Transform arguments for Gemini semantic search.

  Builds semantic retriever configuration and preprocesses arguments for generate_answer.

  ## Input
  [knowledge_base, query, opts]

  ## Output
  [model, contents, answer_style, search_opts]
  """
  @spec transform_semantic_search_args([term()]) :: [term()]
  def transform_semantic_search_args([knowledge_base, query, opts]) when is_binary(query) do
    model = Keyword.get(opts, :model, "models/gemini-1.5-flash")
    answer_style = Keyword.get(opts, :answer_style, :abstractive)
    max_chunks_count = Keyword.get(opts, :max_chunks_count, 5)

    # Build contents for the question
    contents = [
      %{
        parts: [%{text: query}],
        role: "user"
      }
    ]

    # Build semantic retriever options
    semantic_retriever = %{
      source: knowledge_base,
      query: %{parts: [%{text: query}]},
      max_chunks_count: max_chunks_count
    }

    # Build final search options
    search_opts =
      opts
      |> Keyword.put(:semantic_retriever, semantic_retriever)
      |> Keyword.delete(:max_chunks_count)
      |> Keyword.delete(:model)
      |> Keyword.delete(:answer_style)

    [model, contents, answer_style, search_opts]
  end

  # Private helper functions

  defp build_gemini_tuning_request(dataset, opts) do
    # Extract Gemini-specific tuning options
    base_model = Keyword.get(opts, :base_model, "gemini-1.5-flash")
    display_name = Keyword.get(opts, :display_name)
    temperature = Keyword.get(opts, :temperature)
    top_p = Keyword.get(opts, :top_p)
    top_k = Keyword.get(opts, :top_k)

    # Build the tuning request structure
    request = %{
      base_model: "models/#{base_model}",
      tuning_task: %{
        training_data: %{
          examples: %{
            examples: convert_to_gemini_dataset_map(dataset)
          }
        }
      }
    }

    # Add optional display name
    request =
      if display_name do
        Map.put(request, :display_name, display_name)
      else
        request
      end

    # Add hyperparameters if specified
    hyperparameters = %{}

    hyperparameters =
      if temperature,
        do: Map.put(hyperparameters, :learning_rate, temperature),
        else: hyperparameters

    hyperparameters =
      if top_p, do: Map.put(hyperparameters, :batch_size, top_p), else: hyperparameters

    hyperparameters =
      if top_k, do: Map.put(hyperparameters, :epoch_count, top_k), else: hyperparameters

    if map_size(hyperparameters) > 0 do
      put_in(request, [:tuning_task, :hyperparameters], hyperparameters)
    else
      request
    end
  end

  defp build_openai_tuning_params(training_file, opts) do
    # Extract OpenAI-specific tuning options
    model = Keyword.get(opts, :model, "gpt-3.5-turbo")
    validation_file = Keyword.get(opts, :validation_file)
    suffix = Keyword.get(opts, :suffix)
    n_epochs = Keyword.get(opts, :n_epochs, "auto")
    batch_size = Keyword.get(opts, :batch_size, "auto")
    learning_rate_multiplier = Keyword.get(opts, :learning_rate_multiplier, "auto")

    # Build the parameters map
    params = %{
      model: model,
      training_file: training_file
    }

    # Add optional parameters
    params =
      if validation_file, do: Map.put(params, :validation_file, validation_file), else: params

    params = if suffix, do: Map.put(params, :suffix, suffix), else: params
    params = if n_epochs != "auto", do: Map.put(params, :n_epochs, n_epochs), else: params
    params = if batch_size != "auto", do: Map.put(params, :batch_size, batch_size), else: params

    params =
      if learning_rate_multiplier != "auto",
        do: Map.put(params, :learning_rate_multiplier, learning_rate_multiplier),
        else: params

    params
  end

  defp convert_to_gemini_dataset_map(dataset) when is_list(dataset) do
    Enum.map(dataset, &convert_example_to_gemini_format/1)
  end

  defp convert_to_gemini_dataset_map(dataset) when is_map(dataset) do
    # If already in the right format, return as-is
    if Map.has_key?(dataset, "examples") or Map.has_key?(dataset, :examples) do
      dataset
    else
      # Convert single example
      [convert_example_to_gemini_format(dataset)]
    end
  end

  defp convert_example_to_gemini_format(%{"input" => input, "output" => output}) do
    %{
      text_input: input,
      output: output
    }
  end

  defp convert_example_to_gemini_format(%{input: input, output: output}) do
    %{
      text_input: input,
      output: output
    }
  end

  defp convert_example_to_gemini_format(%{"text_input" => _, "output" => _} = example) do
    # Already in Gemini format
    example
  end

  defp convert_example_to_gemini_format(%{text_input: _, output: _} = example) do
    # Already in Gemini format (atom keys)
    example
  end

  defp convert_example_to_gemini_format(example) do
    # Fallback - return as-is
    example
  end

  @doc """
  Transform arguments for OpenAI assistant creation.

  Builds assistant parameters from options.

  ## Input
  [opts]

  ## Output
  [params, config_opts]
  """
  @spec transform_create_assistant_args([term()]) :: [term()]
  def transform_create_assistant_args([opts]) do
    params = build_assistant_params(opts)
    config_opts = extract_config_opts(opts)
    [params, config_opts]
  end

  @doc """
  Transform arguments for OpenAI thread creation.

  Builds thread parameters from options.

  ## Input
  [opts]

  ## Output
  [params, config_opts]
  """
  @spec transform_create_thread_args([term()]) :: [term()]
  def transform_create_thread_args([opts]) do
    params = build_thread_params(opts)
    config_opts = extract_config_opts(opts)
    [params, config_opts]
  end

  @doc """
  Transform arguments for OpenAI message creation.

  Builds message parameters from content and options.

  ## Input
  [thread_id, content, opts]

  ## Output
  [thread_id, params, config_opts]
  """
  @spec transform_create_message_args([term()]) :: [term()]
  def transform_create_message_args([thread_id, content, opts]) do
    params = build_message_params(content, opts)
    config_opts = extract_config_opts(opts)
    [thread_id, params, config_opts]
  end

  @doc """
  Transform arguments for OpenAI assistant run.

  Builds run parameters from assistant_id and options.

  ## Input
  [thread_id, assistant_id, opts]

  ## Output
  [thread_id, params, config_opts]
  """
  @spec transform_run_assistant_args([term()]) :: [term()]
  def transform_run_assistant_args([thread_id, assistant_id, opts]) do
    params = build_run_params(assistant_id, opts)
    config_opts = extract_config_opts(opts)
    [thread_id, params, config_opts]
  end

  # Private helper functions

  defp build_assistant_params(opts) do
    params = %{}

    opts
    |> Enum.reduce(params, fn
      {:model, model}, acc -> Map.put(acc, :model, model)
      {:name, name}, acc -> Map.put(acc, :name, name)
      {:description, desc}, acc -> Map.put(acc, :description, desc)
      {:instructions, inst}, acc -> Map.put(acc, :instructions, inst)
      {:tools, tools}, acc -> Map.put(acc, :tools, tools)
      {:file_ids, files}, acc -> Map.put(acc, :file_ids, files)
      {:metadata, meta}, acc -> Map.put(acc, :metadata, meta)
      _other, acc -> acc
    end)
    |> Map.put_new(:model, "gpt-4.1-nano")
  end

  defp build_thread_params(opts) do
    params = %{}

    opts
    |> Enum.reduce(params, fn
      {:messages, messages}, acc -> Map.put(acc, :messages, messages)
      {:metadata, meta}, acc -> Map.put(acc, :metadata, meta)
      _other, acc -> acc
    end)
  end

  defp build_message_params(content, opts) do
    params = %{
      content: content,
      role: Keyword.get(opts, :role, "user")
    }

    opts
    |> Enum.reduce(params, fn
      {:file_ids, files}, acc -> Map.put(acc, :file_ids, files)
      {:metadata, meta}, acc -> Map.put(acc, :metadata, meta)
      # Already handled
      {:role, _}, acc -> acc
      _other, acc -> acc
    end)
  end

  defp build_run_params(assistant_id, opts) do
    params = %{assistant_id: assistant_id}

    opts
    |> Enum.reduce(params, fn
      {:instructions, inst}, acc -> Map.put(acc, :instructions, inst)
      {:tools, tools}, acc -> Map.put(acc, :tools, tools)
      {:metadata, meta}, acc -> Map.put(acc, :metadata, meta)
      {:stream, stream}, acc -> Map.put(acc, :stream, stream)
      _other, acc -> acc
    end)
  end

  @doc """
  Transform arguments for Gemini token counting.

  Builds count tokens request from content.

  ## Input
  [model, content]

  ## Output
  [model, request]
  """
  @spec transform_count_tokens_args([term()]) :: [term()]
  def transform_count_tokens_args([model, content]) do
    request = build_count_tokens_request(content)
    [model, request]
  end

  defp build_count_tokens_request(content) when is_binary(content) do
    # Simple string content
    text_content = %ExLLM.Providers.Gemini.Content.Content{
      parts: [%ExLLM.Providers.Gemini.Content.Part{text: content}],
      role: "user"
    }

    %ExLLM.Providers.Gemini.Tokens.CountTokensRequest{
      contents: [text_content]
    }
  end

  defp build_count_tokens_request(messages) when is_list(messages) do
    # Convert messages to Gemini Content format
    contents =
      Enum.map(messages, fn message ->
        role = Map.get(message, :role, "user")
        content = Map.get(message, :content, "")

        %ExLLM.Providers.Gemini.Content.Content{
          parts: [%ExLLM.Providers.Gemini.Content.Part{text: content}],
          role: role
        }
      end)

    %ExLLM.Providers.Gemini.Tokens.CountTokensRequest{
      contents: contents
    }
  end

  defp build_count_tokens_request(%ExLLM.Providers.Gemini.Tokens.CountTokensRequest{} = request) do
    # Already in the correct format
    request
  end

  defp build_count_tokens_request(content) do
    # Fallback for unknown content types
    %ExLLM.Providers.Gemini.Tokens.CountTokensRequest{
      contents: [
        %ExLLM.Providers.Gemini.Content.Content{
          parts: [%ExLLM.Providers.Gemini.Content.Part{text: inspect(content)}],
          role: "user"
        }
      ]
    }
  end

  defp extract_config_opts(opts) do
    # Remove transformation-specific keys and keep only config-related ones
    transformation_keys = [
      :base_model,
      :display_name,
      :temperature,
      :top_p,
      :top_k,
      :model,
      :validation_file,
      :suffix,
      :n_epochs,
      :batch_size,
      :learning_rate_multiplier,
      :purpose,
      :name,
      :description,
      :instructions,
      :tools,
      :file_ids,
      :metadata,
      :messages,
      :role,
      :stream
    ]

    Enum.reject(opts, fn {key, _value} -> key in transformation_keys end)
  end
end
