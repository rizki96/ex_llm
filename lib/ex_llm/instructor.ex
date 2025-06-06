defmodule ExLLM.Instructor do
  @moduledoc """
  Structured output support for ExLLM using instructor_ex.

  This module provides integration with the `instructor` library to enable
  structured outputs with validation when using ExLLM. It allows you to
  define expected response structures using Ecto schemas and automatically
  validates and retries LLM responses.

  ## Requirements

  This module requires the optional `instructor` dependency:

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

  require Logger
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

      # Convert ExLLM provider to instructor adapter
      adapter =
        case provider do
          :anthropic -> Instructor.Adapters.Anthropic
          :openai -> Instructor.Adapters.OpenAI
          :ollama -> Instructor.Adapters.Ollama
          :gemini -> Instructor.Adapters.Gemini
          :local -> {:error, :unsupported_provider_for_instructor}
          _ -> {:error, :unsupported_provider_for_instructor}
        end

      case adapter do
        {:error, reason} ->
          {:error, reason}

        _adapter_module ->
          # Prepare instructor options
          instructor_opts =
            options
            |> Keyword.take([:model, :temperature, :max_tokens, :max_retries])
            |> Keyword.put(:response_model, response_model)
            |> Keyword.put(:messages, prepare_messages_for_instructor(messages))

          # Get configuration from ExLLM's config provider
          config_opts = get_provider_config(provider, options)

          # Merge configurations (config_opts first, then instructor_opts to allow overrides)
          merged_opts = Keyword.merge(config_opts, instructor_opts)

          # Set up the adapter in config
          adapter = case provider do
            :anthropic -> Instructor.Adapters.Anthropic
            :openai -> Instructor.Adapters.OpenAI
            :ollama -> Instructor.Adapters.Ollama
            :gemini -> Instructor.Adapters.Gemini
            _ -> nil
          end

          # Prepare params for Instructor.chat_completion (first argument)
          params = [
            model: merged_opts[:model],
            response_model: merged_opts[:response_model],
            messages: merged_opts[:messages],
            max_retries: merged_opts[:max_retries] || 0
          ]
          
          # Add optional parameters only if present
          params = if merged_opts[:temperature], do: Keyword.put(params, :temperature, merged_opts[:temperature]), else: params
          params = if merged_opts[:max_tokens], do: Keyword.put(params, :max_tokens, merged_opts[:max_tokens]), else: params

          # Prepare config (second argument) with adapter
          config = [adapter: adapter]

          # Call instructor with params and config as separate arguments
          case apply(Instructor, :chat_completion, [params, config]) do
            {:ok, result} ->
              {:ok, result}

            {:error, errors} when is_list(errors) ->
              # Convert instructor validation errors to ExLLM format
              {:error, format_validation_errors(errors)}

            {:error, reason} ->
              {:error, reason}
          end
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

      case provider do
        :anthropic ->
          [
            model: config_provider.get(:anthropic, :model) || ExLLM.ModelConfig.get_default_model(:anthropic)
          ]

        :openai ->
          [
            model: config_provider.get(:openai, :model) || ExLLM.ModelConfig.get_default_model(:openai)
          ]

        :ollama ->
          [
            base_url: config_provider.get(:ollama, :base_url) || "http://localhost:11434",
            model: config_provider.get(:ollama, :model) || ExLLM.ModelConfig.get_default_model(:ollama)
          ]

        :gemini ->
          [
            model: config_provider.get(:gemini, :model) || ExLLM.ModelConfig.get_default_model(:gemini)
          ]

        _ ->
          []
      end
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    end

    defp validate_against_model(data, response_model) when is_atom(response_model) do
      # Ecto schema validation
      if function_exported?(response_model, :changeset, 2) do
        changeset = apply(response_model, :changeset, [struct(response_model), data])

        if changeset.valid? do
          {:ok, Ecto.Changeset.apply_changes(changeset)}
        else
          {:error, format_changeset_errors(changeset)}
        end
      else
        {:error, :invalid_response_model}
      end
    end

    defp validate_against_model(data, type_spec) when is_map(type_spec) do
      # Simple type validation
      validate_simple_types(data, type_spec)
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
end
