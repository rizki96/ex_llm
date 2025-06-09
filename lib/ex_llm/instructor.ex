defmodule ExLLM.Instructor do
  @moduledoc """
  Structured output support for ExLLM using instructor_ex.

  This module provides integration with the `instructor` library to enable
  structured outputs with validation when using ExLLM. It allows you to
  define expected response structures using Ecto schemas and automatically
  validates and retries LLM responses.

  ## Supported Providers

  The following providers support structured outputs through Instructor:
  - `:anthropic` - Claude models
  - `:openai` - GPT models
  - `:gemini` - Google Gemini models
  - `:ollama` - Local Ollama models
  - `:groq` - Groq cloud models
  - `:xai` - X.AI Grok models

  Other providers (`:bedrock`, `:openrouter`, `:bumblebee`) do not currently
  support structured outputs through Instructor.

  ## Requirements

  This module requires the `instructor` dependency:

      {:instructor, "~> 0.1.0"}

  ## Usage

  ### Basic Example

      defmodule EmailClassification do
        use Ecto.Schema
        use Instructor.Validator

        @llm_doc "Classification of an email as spam or not spam"
        
        @primary_key false
        embedded_schema do
          field :classification, Ecto.Enum, values: [:spam, :not_spam]
          field :confidence, :float
          field :reason, :string
        end

        @impl true
        def validate_changeset(changeset) do
          changeset
          |> Ecto.Changeset.validate_required([:classification, :confidence, :reason])
          |> Ecto.Changeset.validate_number(:confidence, 
              greater_than_or_equal_to: 0.0,
              less_than_or_equal_to: 1.0
            )
        end
      end

      # Use with ExLLM
      {:ok, result} = ExLLM.Instructor.chat(:anthropic, [
        %{role: "user", content: "Is this spam? 'You won a million dollars!'"}
      ], response_model: EmailClassification)

      # result is now an EmailClassification struct
      # %EmailClassification{classification: :spam, confidence: 0.95, reason: "..."}

  ### With Retries

      {:ok, result} = ExLLM.Instructor.chat(:anthropic, messages,
        response_model: UserProfile,
        max_retries: 3,
        temperature: 0.7
      )

  ### With Simple Maps

      # Define expected structure
      response_model = %{
        name: :string,
        age: :integer,
        tags: {:array, :string}
      }

      {:ok, result} = ExLLM.Instructor.chat(:anthropic, messages,
        response_model: response_model
      )

  ## Integration with ExLLM

  The structured output functionality is also available through the main
  ExLLM module when instructor is installed:

      {:ok, response} = ExLLM.chat(:anthropic, messages,
        response_model: EmailClassification,
        max_retries: 2
      )
  """

  alias ExLLM.Types

  @doc """
  Check if instructor is available.

  Since instructor is now a required dependency, this always returns `true`.

  ## Returns
  `true` (always)

  ## Examples

      # This is now always true, but kept for backwards compatibility
      if ExLLM.Instructor.available?() do
        # Use structured outputs
      end
  """
  @spec available?() :: boolean()
  def available?, do: true

  @doc """
  Send a chat request with structured output validation.

  ## Parameters
  - `provider` - The LLM provider to use
  - `messages` - List of conversation messages
  - `options` - Options including `:response_model` and standard chat options

  ## Options
  - `:response_model` - Required. Ecto schema module or simple type specification
  - `:max_retries` - Number of retries for validation errors (default: 0)
  - All standard ExLLM.chat/3 options

  ## Returns
  - `{:ok, struct}` where struct matches the response_model
  - `{:error, reason}` on failure

  ## Examples

      # With Ecto schema
      {:ok, classification} = ExLLM.Instructor.chat(:anthropic, messages,
        response_model: EmailClassification,
        max_retries: 3
      )

      # With simple type spec
      {:ok, data} = ExLLM.Instructor.chat(:openai, messages,
        response_model: %{name: :string, age: :integer}
      )
  """
  @spec chat(ExLLM.provider(), ExLLM.messages(), keyword()) ::
          {:ok, struct() | map()} | {:error, term()}
  def chat(provider, messages, options) do
    do_structured_chat(provider, messages, options)
  end

  @doc """
  Transform a regular ExLLM response into a structured output.

  This function is useful when you already have a response from ExLLM
  and want to parse it into a structured format.

  ## Parameters
  - `response` - An ExLLM.Types.LLMResponse struct
  - `response_model` - The expected structure (Ecto schema or type spec)

  ## Returns
  - `{:ok, struct}` on successful parsing and validation
  - `{:error, reason}` on failure

  ## Examples

      {:ok, response} = ExLLM.chat(:anthropic, messages)
      {:ok, structured} = ExLLM.Instructor.parse_response(response, UserProfile)
  """
  @spec parse_response(Types.LLMResponse.t(), module() | map()) ::
          {:ok, struct() | map()} | {:error, term()}
  def parse_response(response, response_model) do
    do_parse_response(response, response_model)
  end

  # Private implementation
  defp do_structured_chat(provider, messages, options) do
    response_model = Keyword.fetch!(options, :response_model)

    case get_instructor_adapter(provider) do
      {:error, reason} ->
        {:error, reason}

      :mock_direct ->
        handle_mock_structured_output(provider, messages, options, response_model)

      adapter ->
        execute_instructor_chat(provider, messages, options, response_model, adapter)
    end
  end

  defp get_instructor_adapter(provider) do
    case provider do
      :anthropic -> Instructor.Adapters.Anthropic
      :openai -> Instructor.Adapters.OpenAI
      :ollama -> Instructor.Adapters.Ollama
      :gemini -> Instructor.Adapters.Gemini
      :groq -> Instructor.Adapters.Groq
      :xai -> Instructor.Adapters.XAI
      :mock -> :mock_direct
      :bumblebee -> {:error, :unsupported_provider_for_instructor}
      _ -> {:error, :unsupported_provider_for_instructor}
    end
  end

  defp execute_instructor_chat(provider, messages, options, response_model, adapter) do
    # Prepare all options
    instructor_opts = prepare_instructor_options(options, response_model, messages)
    config_opts = get_provider_config(provider, options)
    merged_opts = Keyword.merge(config_opts, instructor_opts)

    # Build params and config
    params = build_instructor_params(provider, merged_opts, options)
    config = build_instructor_config(provider, merged_opts, adapter)

    # Execute the request
    call_instructor(params, config)
  end

  defp prepare_instructor_options(options, response_model, messages) do
    options
    |> Keyword.take([:model, :temperature, :max_tokens, :max_retries])
    |> Keyword.put(:response_model, response_model)
    |> Keyword.put(:messages, prepare_messages_for_instructor(messages))
  end

  defp build_instructor_params(provider, merged_opts, options) do
    model = get_model_for_instructor(provider, merged_opts, options)

    base_params = [
      model: model,
      response_model: merged_opts[:response_model],
      messages: merged_opts[:messages],
      max_retries: merged_opts[:max_retries] || 0
    ]

    base_params
    |> add_temperature_if_present(merged_opts)
    |> add_max_tokens_for_provider(provider, merged_opts)
  end

  defp get_model_for_instructor(provider, merged_opts, options) do
    merged_opts[:model] || Keyword.get(options, :model) || ExLLM.default_model(provider)
  end

  defp add_temperature_if_present(params, opts) do
    if opts[:temperature] do
      Keyword.put(params, :temperature, opts[:temperature])
    else
      params
    end
  end

  defp add_max_tokens_for_provider(params, :anthropic, opts) do
    Keyword.put(params, :max_tokens, opts[:max_tokens] || 4096)
  end

  defp add_max_tokens_for_provider(params, _provider, opts) do
    if opts[:max_tokens] do
      Keyword.put(params, :max_tokens, opts[:max_tokens])
    else
      params
    end
  end

  defp build_instructor_config(:ollama, merged_opts, adapter) do
    base_url = merged_opts[:base_url] || "http://localhost:11434"
    [adapter: adapter, base_url: base_url]
  end

  defp build_instructor_config(_provider, _merged_opts, adapter) do
    [adapter: adapter]
  end

  defp call_instructor(params, config) do
    case apply(Instructor, :chat_completion, [params, config]) do
      {:ok, result} ->
        {:ok, result}

      {:error, errors} when is_list(errors) ->
        {:error, format_validation_errors(errors)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_parse_response(%Types.LLMResponse{content: content}, response_model) do
    # Extract JSON from the content (handle markdown-wrapped JSON)
    json_content = extract_json_from_content(content)

    # Try to parse the content as JSON and validate against the model
    with {:ok, json} <- Jason.decode(json_content),
         {:ok, validated} <- validate_against_model(json, response_model) do
      {:ok, validated}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:json_decode_error, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_json_from_content(content) do
    # Try to extract JSON from markdown code blocks
    case Regex.run(~r/```(?:json)?\s*\n?(.*?)\n?```/s, content) do
      [_, json] ->
        String.trim(json)

      nil ->
        # Try to find JSON object or array directly
        case Regex.run(~r/(\{[\s\S]*\}|\[[\s\S]*\])/s, content) do
          [_, json] -> json
          nil -> content
        end
    end
  end

  defp prepare_messages_for_instructor(messages) do
    Enum.map(messages, fn msg ->
      %{
        role: Map.get(msg, :role, "user"),
        content: Map.get(msg, :content, "")
      }
    end)
  end

  defp get_provider_config(provider, options) do
    config_provider = Keyword.get(options, :config_provider, ExLLM.ConfigProvider.Env)

    provider
    |> build_provider_config(config_provider)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp build_provider_config(:mock, _config_provider) do
    [model: "mock-model"]
  end

  defp build_provider_config(:ollama, config_provider) do
    model = get_model_config(:ollama, config_provider)
    cleaned_model = strip_ollama_prefix(model)
    base_url = config_provider.get(:ollama, :base_url) || "http://localhost:11434"

    [base_url: base_url, model: cleaned_model]
  end

  defp build_provider_config(provider, config_provider)
       when provider in [:anthropic, :openai, :gemini, :groq, :xai] do
    [model: get_model_config(provider, config_provider)]
  end

  defp build_provider_config(_provider, _config_provider) do
    []
  end

  defp get_model_config(provider, config_provider) do
    config_provider.get(provider, :model) || ExLLM.ModelConfig.get_default_model(provider)
  end

  defp strip_ollama_prefix(model) do
    case String.split(model || "", "/", parts: 2) do
      ["ollama", actual_model] -> actual_model
      _ -> model
    end
  end

  defp validate_against_model(data, response_model) when is_atom(response_model) do
    cond do
      function_exported?(response_model, :changeset, 2) ->
        validate_with_changeset(response_model, data)

      function_exported?(response_model, :validate_changeset, 1) ->
        validate_with_instructor_validator(response_model, data)

      function_exported?(response_model, :__schema__, 1) ->
        validate_with_schema(response_model, data)

      true ->
        {:error, :invalid_response_model}
    end
  end

  defp validate_against_model(data, type_spec) when is_map(type_spec) do
    # Simple type validation
    validate_simple_types(data, type_spec)
  end

  defp validate_with_changeset(response_model, data) do
    changeset = apply(response_model, :changeset, [struct(response_model), data])
    apply_changeset_result(changeset)
  end

  defp validate_with_instructor_validator(response_model, data) do
    base_struct = struct(response_model)
    fields = Map.keys(base_struct) -- [:__struct__, :__meta__]

    changeset = Ecto.Changeset.cast(base_struct, data, fields)
    validated_changeset = apply(response_model, :validate_changeset, [changeset])

    apply_changeset_result(validated_changeset)
  end

  defp validate_with_schema(response_model, data) do
    base_struct = struct(response_model)
    fields = response_model.__schema__(:fields)
    changeset = Ecto.Changeset.cast(base_struct, data, fields)

    apply_changeset_result(changeset)
  end

  defp apply_changeset_result(changeset) do
    if changeset.valid? do
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    else
      {:error, format_changeset_errors(changeset)}
    end
  end

  defp validate_simple_types(data, type_spec) do
    result =
      Enum.reduce_while(type_spec, %{}, fn {key, type}, acc ->
        str_key = to_string(key)

        case validate_type(Map.get(data, str_key), type) do
          {:ok, value} ->
            {:cont, Map.put(acc, key, value)}

          {:error, reason} ->
            {:halt, {:error, {key, reason}}}
        end
      end)

    case result do
      {:error, _} = error -> error
      validated -> {:ok, validated}
    end
  end

  defp validate_type(value, :string) when is_binary(value), do: {:ok, value}
  defp validate_type(value, :integer) when is_integer(value), do: {:ok, value}
  defp validate_type(value, :float) when is_float(value), do: {:ok, value}
  defp validate_type(value, :float) when is_integer(value), do: {:ok, value * 1.0}
  defp validate_type(value, :boolean) when is_boolean(value), do: {:ok, value}

  defp validate_type(value, {:array, type}) when is_list(value) do
    validated = Enum.map(value, &validate_type(&1, type))

    case Enum.find(validated, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(validated, fn {:ok, v} -> v end)}
      error -> error
    end
  end

  defp validate_type(_, type), do: {:error, {:invalid_type, type}}

  defp format_validation_errors(errors) when is_list(errors) do
    formatted =
      Enum.map(errors, fn
        {field, {msg, _opts}} -> "#{field}: #{msg}"
        {field, msg} when is_binary(msg) -> "#{field}: #{msg}"
        error -> inspect(error)
      end)

    {:validation_failed, formatted}
  end

  defp format_changeset_errors(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    {:validation_failed, errors}
  end

  @doc """
  Create a simple schema module at runtime.

  This is a convenience function for creating simple schemas without
  defining a full module.

  ## Parameters
  - `fields` - Map of field names to types
  - `validations` - Optional list of validation functions

  ## Examples

      schema = ExLLM.Instructor.simple_schema(%{
        name: :string,
        age: :integer,
        email: :string
      }, [
        {:validate_format, :email, ~r/@/}
      ])

      {:ok, result} = ExLLM.Instructor.chat(:anthropic, messages,
        response_model: schema
      )
  """
  @spec simple_schema(map(), keyword()) :: module() | {:error, term()}
  def simple_schema(_fields, _validations \\ []) do
    unless available?() do
      {:error, :instructor_not_available}
    else
      # This would require runtime module creation which is complex
      # For now, return an error suggesting to use type specs instead
      {:error, :use_type_spec_instead}
    end
  end

  # Handle mock provider structured output directly
  defp handle_mock_structured_output(provider, messages, options, response_model) do
    # Get regular chat response from mock
    chat_opts = Keyword.drop(options, [:response_model, :max_retries])

    case ExLLM.chat(provider, messages, chat_opts) do
      {:ok, response} ->
        # Try to parse the response as structured data
        parse_response(response, response_model)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
