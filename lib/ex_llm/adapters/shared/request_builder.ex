defmodule ExLLM.Adapters.Shared.RequestBuilder do
  @moduledoc """
  Unified request building for LLM providers.

  This module provides common patterns for building API requests across
  different LLM providers, reducing code duplication and ensuring consistency.

  Features:
  - Common request body construction
  - Optional parameter handling
  - Provider-specific extensions via callbacks
  - Function/tool formatting
  - Message formatting
  """

  @doc """
  Callback for provider-specific request transformations.

  Allows adapters to modify the request after standard building.
  """
  @callback transform_request(map(), keyword()) :: map()

  @doc """
  Callback for provider-specific message formatting.

  Some providers need custom message structures.
  """
  @callback format_messages_for_provider(list(map())) :: list(map())

  # Optional callbacks with default implementations
  @optional_callbacks [transform_request: 2, format_messages_for_provider: 1]

  @doc """
  Build a standard chat completion request.

  ## Options

  Common options supported across providers:
  - `:model` - Model to use
  - `:temperature` - Sampling temperature (0.0 to 2.0)
  - `:max_tokens` - Maximum tokens to generate
  - `:top_p` - Nucleus sampling parameter
  - `:frequency_penalty` - Frequency penalty (-2.0 to 2.0)
  - `:presence_penalty` - Presence penalty (-2.0 to 2.0)
  - `:stop` - Stop sequences
  - `:user` - User identifier
  - `:functions` - Function definitions for function calling
  - `:stream` - Whether to stream the response

  ## Examples

      RequestBuilder.build_chat_request(
        messages,
        "gpt-4",
        temperature: 0.7,
        max_tokens: 1000
      )
  """
  @spec build_chat_request(list(map()), String.t(), keyword()) :: map()
  def build_chat_request(messages, model, options \\ []) do
    %{
      "model" => model,
      "messages" => format_messages(messages)
    }
    |> add_common_parameters(options)
    |> add_function_calling(options)
  end

  @doc """
  Build a request with provider-specific transformations.

  This is the main entry point for adapters that implement the transform_request callback.

  ## Examples

      defmodule MyAdapter do
        @behaviour ExLLM.Adapters.Shared.RequestBuilder
        
        def build_request(messages, model, options) do
          RequestBuilder.build_provider_request(__MODULE__, messages, model, options)
        end
        
        @impl true
        def transform_request(request, options) do
          # Add provider-specific fields
          Map.put(request, "custom_field", "value")
        end
      end
  """
  @spec build_provider_request(module(), list(map()), String.t(), keyword()) :: map()
  def build_provider_request(adapter_module, messages, model, options) do
    # Format messages with provider-specific formatting if available
    formatted_messages =
      if function_exported?(adapter_module, :format_messages_for_provider, 1) do
        adapter_module.format_messages_for_provider(messages)
      else
        format_messages(messages)
      end

    # Build base request
    request =
      %{
        "model" => model,
        "messages" => formatted_messages
      }
      |> add_common_parameters(options)
      |> add_function_calling(options)

    # Apply provider-specific transformations if available
    if function_exported?(adapter_module, :transform_request, 2) do
      adapter_module.transform_request(request, options)
    else
      request
    end
  end

  @doc """
  Add common optional parameters to a request.

  Only adds parameters that are present in options.
  """
  @spec add_common_parameters(map(), keyword()) :: map()
  def add_common_parameters(request, options) do
    request
    |> add_optional_param(options, :temperature, "temperature")
    |> add_optional_param(options, :max_tokens, "max_tokens")
    |> add_optional_param(options, :top_p, "top_p")
    |> add_optional_param(options, :frequency_penalty, "frequency_penalty")
    |> add_optional_param(options, :presence_penalty, "presence_penalty")
    |> add_optional_param(options, :stop, "stop")
    |> add_optional_param(options, :user, "user")
    |> add_optional_param(options, :seed, "seed")
    |> add_optional_param(options, :logprobs, "logprobs")
    |> add_optional_param(options, :top_logprobs, "top_logprobs")
    |> add_optional_param(options, :n, "n")
    |> add_optional_param(options, :stream, "stream")
    |> add_optional_param(options, :response_format, "response_format")
  end

  @doc """
  Add function calling parameters to a request.

  Handles both the older `functions` format and newer `tools` format.
  """
  @spec add_function_calling(map(), keyword()) :: map()
  def add_function_calling(request, options) do
    case Keyword.get(options, :functions) do
      nil ->
        request

      functions when is_list(functions) ->
        # Check if we should use tools format (newer) or functions format (older)
        if Keyword.get(options, :use_tools_format, true) do
          request
          |> Map.put("tools", format_tools(functions))
          |> Map.put("tool_choice", Keyword.get(options, :tool_choice, "auto"))
        else
          request
          |> Map.put("functions", functions)
          |> add_optional_param(options, :function_call, "function_call")
        end

      _ ->
        request
    end
  end

  @doc """
  Format messages for API requests.

  Ensures messages have the correct structure and handles various input formats.
  """
  @spec format_messages(list(map() | keyword())) :: list(map())
  def format_messages(messages) do
    Enum.map(messages, &format_message/1)
  end

  @doc """
  Format functions as tools for the newer OpenAI tools API.
  """
  @spec format_tools(list(map())) :: list(map())
  def format_tools(functions) do
    Enum.map(functions, fn func ->
      %{
        "type" => "function",
        "function" => %{
          "name" => get_string_value(func, [:name, "name"]),
          "description" => get_string_value(func, [:description, "description"]),
          "parameters" => get_map_value(func, [:parameters, "parameters"])
        }
      }
    end)
  end

  @doc """
  Extract system message from a list of messages.

  Returns {system_content, other_messages} tuple.
  Some providers (like Anthropic) handle system messages differently.
  """
  @spec extract_system_message(list(map())) :: {String.t() | nil, list(map())}
  def extract_system_message(messages) do
    case Enum.split_with(messages, fn msg ->
           get_string_value(msg, [:role, "role"]) == "system"
         end) do
      {[], other_messages} ->
        {nil, other_messages}

      {[system_msg | _], other_messages} ->
        {get_string_value(system_msg, [:content, "content"]), other_messages}
    end
  end

  @doc """
  Add an optional parameter to the request if it exists in options.
  """
  @spec add_optional_param(map(), keyword(), atom(), String.t()) :: map()
  def add_optional_param(request, options, key, param_name) do
    case Keyword.get(options, key) do
      nil -> request
      value -> Map.put(request, param_name, value)
    end
  end

  # Private helper functions

  defp format_message(message) when is_map(message) do
    %{
      "role" => get_string_value(message, [:role, "role"]) || "user",
      "content" => get_string_value(message, [:content, "content"]) || ""
    }
    |> maybe_add_name(message)
    |> maybe_add_function_call(message)
    |> maybe_add_tool_calls(message)
  end

  defp format_message(message) when is_list(message) do
    format_message(Enum.into(message, %{}))
  end

  defp maybe_add_name(formatted, original) do
    case get_string_value(original, [:name, "name"]) do
      nil -> formatted
      name -> Map.put(formatted, "name", name)
    end
  end

  defp maybe_add_function_call(formatted, original) do
    case get_map_value(original, [:function_call, "function_call"]) do
      nil -> formatted
      fc -> Map.put(formatted, "function_call", fc)
    end
  end

  defp maybe_add_tool_calls(formatted, original) do
    case get_value(original, [:tool_calls, "tool_calls"]) do
      nil -> formatted
      tc -> Map.put(formatted, "tool_calls", tc)
    end
  end

  defp get_string_value(map, keys) do
    value = get_value(map, keys)
    if is_binary(value), do: value, else: nil
  end

  defp get_map_value(map, keys) do
    value = get_value(map, keys)
    if is_map(value), do: value, else: nil
  end

  defp get_value(_map, []), do: nil

  defp get_value(map, [key | rest]) do
    case Map.get(map, key) do
      nil -> get_value(map, rest)
      value -> value
    end
  end

  @doc """
  Build an embeddings request.

  ## Options
  - `:model` - Embedding model to use
  - `:encoding_format` - Format for the embeddings (e.g., "float", "base64")
  - `:dimensions` - Number of dimensions for the embeddings
  - `:user` - User identifier

  ## Examples

      RequestBuilder.build_embeddings_request(
        ["Hello world", "How are you?"],
        "text-embedding-3-small",
        dimensions: 512
      )
  """
  @spec build_embeddings_request(list(String.t()) | String.t(), String.t(), keyword()) :: map()
  def build_embeddings_request(input, model, options \\ []) do
    %{
      "model" => model,
      "input" => input
    }
    |> add_optional_param(options, :encoding_format, "encoding_format")
    |> add_optional_param(options, :dimensions, "dimensions")
    |> add_optional_param(options, :user, "user")
  end

  @doc """
  Build a completion request (for non-chat models).

  ## Options
  Similar to chat requests but with `prompt` instead of `messages`.
  """
  @spec build_completion_request(String.t(), String.t(), keyword()) :: map()
  def build_completion_request(prompt, model, options \\ []) do
    %{
      "model" => model,
      "prompt" => prompt
    }
    |> add_common_parameters(options)
  end
end
