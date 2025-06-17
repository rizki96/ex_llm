defmodule ExLLM.Core.FunctionCalling do
  @moduledoc """
  Function calling support for ExLLM.

  Provides a unified interface for function/tool calling across different LLM providers.
  Each provider has slightly different implementations, but this module normalizes them
  into a consistent API.

  ## Features

  - Unified function definition format
  - Automatic parameter validation
  - Type conversion and coercion
  - Function execution with safety controls
  - Streaming function call support

  ## Usage

      # Define available functions
      functions = [
        %{
          name: "get_weather",
          description: "Get the current weather for a location",
          parameters: %{
            type: "object",
            properties: %{
              location: %{type: "string", description: "City and state"},
              unit: %{type: "string", enum: ["celsius", "fahrenheit"]}
            },
            required: ["location"]
          }
        }
      ]
      
      # Chat with function calling
      {:ok, response} = ExLLM.chat(:openai, messages,
        functions: functions,
        function_call: "auto"  # or "none" or %{name: "specific_function"}
      )
      
      # Handle function calls in response
      case response do
        %{function_call: %{name: name, arguments: args}} ->
          result = execute_function(name, args)
          # Continue conversation with function result
          
        %{content: content} ->
          # Normal response
      end
  """

  # alias ExLLM.Types

  defmodule Function do
    @moduledoc """
    Represents a callable function/tool.
    """
    defstruct [
      :name,
      :description,
      :parameters,
      :handler,
      :validation
    ]

    @type t :: %__MODULE__{
            name: String.t(),
            description: String.t(),
            parameters: map(),
            handler: (map() -> any()) | nil,
            validation: (map() -> {:ok, map()} | {:error, term()}) | nil
          }
  end

  defmodule FunctionCall do
    @moduledoc """
    Represents a function call request from the LLM.
    """
    defstruct [
      :id,
      :name,
      :arguments
    ]

    @type t :: %__MODULE__{
            id: String.t() | nil,
            name: String.t(),
            arguments: map() | String.t()
          }
  end

  defmodule FunctionResult do
    @moduledoc """
    Represents the result of executing a function.
    """
    defstruct [
      :name,
      :result,
      :error
    ]

    @type t :: %__MODULE__{
            name: String.t(),
            result: any(),
            error: term() | nil
          }
  end

  @doc """
  Converts provider-specific function format to unified format.
  """
  def normalize_functions(functions, provider) do
    Enum.map(functions, fn func ->
      normalize_function(func, provider)
    end)
  end

  @doc """
  Normalizes a single function to unified format.
  """
  def normalize_function(func, provider) when is_map(func) do
    do_normalize_function(func, provider)
  end

  @doc """
  Converts unified function format to provider-specific format.
  """
  def format_for_provider(functions, provider) do
    case provider do
      :openai -> format_openai_functions(functions)
      :anthropic -> format_anthropic_tools(functions)
      :bedrock -> format_bedrock_tools(functions)
      :gemini -> format_gemini_functions(functions)
      _ -> {:error, {:unsupported_provider, provider}}
    end
  end

  @doc """
  Parses function calls from LLM response.
  """
  def parse_function_calls(response, provider) do
    case provider do
      :openai -> parse_openai_function_calls(response)
      :anthropic -> parse_anthropic_tool_calls(response)
      :bedrock -> parse_bedrock_tool_calls(response)
      :gemini -> parse_gemini_function_calls(response)
      _ -> {:error, {:unsupported_provider, provider}}
    end
  end

  @doc """
  Validates function call arguments against schema.
  """
  def validate_arguments(function_call, function_schema) do
    with {:ok, parsed_args} <- parse_arguments(function_call.arguments),
         {:ok, validated} <- validate_against_schema(parsed_args, function_schema.parameters) do
      {:ok, %{function_call | arguments: validated}}
    end
  end

  @doc """
  Executes a function call safely.
  """
  def execute_function(function_call, available_functions) do
    with {:ok, function} <- find_function(function_call.name, available_functions),
         {:ok, validated_call} <- validate_arguments(function_call, function),
         {:ok, result} <- safe_execute(function, validated_call.arguments) do
      {:ok,
       %FunctionResult{
         name: function_call.name,
         result: result
       }}
    else
      {:error, reason} ->
        {:error,
         %FunctionResult{
           name: function_call.name,
           error: reason
         }}
    end
  end

  @doc """
  Formats function results for conversation continuation.
  """
  def format_function_result(result, provider) do
    case provider do
      :openai -> format_openai_function_result(result)
      :anthropic -> format_anthropic_tool_result(result)
      :bedrock -> format_bedrock_tool_result(result)
      :gemini -> format_gemini_function_result(result)
      _ -> {:error, {:unsupported_provider, provider}}
    end
  end

  # Private functions

  defp do_normalize_function(func, :openai) when is_map(func) do
    %Function{
      name: func["name"] || Map.get(func, :name),
      description: func["description"] || Map.get(func, :description, ""),
      parameters: func["parameters"] || Map.get(func, :parameters),
      handler: func["handler"] || func[:handler]
    }
  end

  defp do_normalize_function(func, :anthropic) when is_map(func) do
    %Function{
      name: func["name"] || Map.get(func, :name),
      description: func["description"] || Map.get(func, :description, ""),
      parameters:
        func["input_schema"] || Map.get(func, :input_schema) || func["parameters"] ||
          Map.get(func, :parameters),
      handler: func["handler"] || func[:handler]
    }
  end

  defp do_normalize_function(func, _provider) when is_map(func) do
    %Function{
      name: func["name"] || Map.get(func, :name),
      description: func["description"] || Map.get(func, :description, ""),
      parameters: func["parameters"] || Map.get(func, :parameters),
      handler: func["handler"] || func[:handler]
    }
  end

  # OpenAI format
  defp format_openai_functions(functions) do
    Enum.map(functions, fn func ->
      %{
        "name" => func.name,
        "description" => func.description,
        "parameters" => func.parameters
      }
    end)
  end

  # Anthropic format (tools)
  defp format_anthropic_tools(functions) do
    Enum.map(functions, fn func ->
      %{
        "name" => func.name,
        "description" => func.description,
        "input_schema" => func.parameters
      }
    end)
  end

  # Bedrock format (varies by model)
  defp format_bedrock_tools(functions) do
    # Bedrock uses different formats for different models
    # This is a simplified version
    Enum.map(functions, fn func ->
      %{
        "toolSpec" => %{
          "name" => func.name,
          "description" => func.description,
          "inputSchema" => %{
            "json" => func.parameters
          }
        }
      }
    end)
  end

  # Gemini format
  defp format_gemini_functions(functions) do
    Enum.map(functions, fn func ->
      %{
        "name" => func.name,
        "description" => func.description,
        "parameters" => func.parameters
      }
    end)
  end

  # Parse OpenAI function calls
  defp parse_openai_function_calls(%{"choices" => [%{"message" => message} | _]}) do
    case message do
      %{"function_call" => call} ->
        {:ok,
         [
           %FunctionCall{
             name: call["name"],
             arguments: call["arguments"]
           }
         ]}

      %{"tool_calls" => tool_calls} when is_list(tool_calls) ->
        calls =
          Enum.map(tool_calls, fn tc ->
            %FunctionCall{
              id: tc["id"],
              name: tc["function"]["name"],
              arguments: tc["function"]["arguments"]
            }
          end)

        {:ok, calls}

      _ ->
        {:ok, []}
    end
  end

  defp parse_openai_function_calls(_), do: {:ok, []}

  # Parse Anthropic tool calls
  defp parse_anthropic_tool_calls(%{"content" => content}) when is_list(content) do
    tool_uses =
      content
      |> Enum.filter(fn item -> item["type"] == "tool_use" end)
      |> Enum.map(fn tool_use ->
        %FunctionCall{
          id: tool_use["id"],
          name: tool_use["name"],
          arguments: tool_use["input"]
        }
      end)

    {:ok, tool_uses}
  end

  defp parse_anthropic_tool_calls(_), do: {:ok, []}

  # Parse Bedrock tool calls (simplified)
  defp parse_bedrock_tool_calls(_response) do
    # Bedrock format varies by model
    # This is a placeholder implementation
    {:ok, []}
  end

  # Parse Gemini function calls
  defp parse_gemini_function_calls(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    function_calls =
      parts
      |> Enum.filter(fn part -> Map.has_key?(part, "functionCall") end)
      |> Enum.map(fn part ->
        call = part["functionCall"]

        %FunctionCall{
          name: call["name"],
          arguments: call["args"]
        }
      end)

    {:ok, function_calls}
  end

  defp parse_gemini_function_calls(_), do: {:ok, []}

  @doc """
  Parse function call arguments from JSON string to map.

  ## Parameters
  - `arguments` - JSON string or map containing function arguments

  ## Returns
  - `{:ok, args_map}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, args} = ExLLM.Core.FunctionCalling.parse_arguments("{\"location\": \"NYC\"}")
      # => {:ok, %{"location" => "NYC"}}
  """
  @spec parse_arguments(String.t() | map()) :: {:ok, map()} | {:error, atom()}
  def parse_arguments(args) when is_map(args), do: {:ok, args}

  def parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def parse_arguments(_), do: {:error, :invalid_arguments}

  defp validate_against_schema(args, schema) do
    # Simple validation - can be enhanced with JSON Schema validation
    required = Map.get(schema, "required", [])
    properties = Map.get(schema, "properties", %{})

    # Check required fields
    case check_required_fields(args, required) do
      :ok ->
        # Basic type validation
        validate_properties(args, properties)

      {:error, _} = error ->
        error
    end
  end

  defp check_required_fields(args, required) do
    missing =
      Enum.filter(required, fn field ->
        not Map.has_key?(args, field)
      end)

    if missing == [] do
      :ok
    else
      {:error, {:missing_required_fields, missing}}
    end
  end

  defp validate_properties(args, properties) do
    Enum.reduce(args, {:ok, %{}}, fn
      {key, value}, {:ok, acc} ->
        validate_property(key, value, properties, acc)

      _, error ->
        error
    end)
  end

  defp validate_property(key, value, properties, acc) do
    if property = properties[key] do
      case validate_type(value, property["type"]) do
        :ok -> {:ok, Map.put(acc, key, value)}
        {:error, _} = err -> err
      end
    else
      # Allow additional properties by default
      {:ok, Map.put(acc, key, value)}
    end
  end

  defp validate_type(value, "string") when is_binary(value), do: :ok
  defp validate_type(value, "number") when is_number(value), do: :ok
  defp validate_type(value, "integer") when is_integer(value), do: :ok
  defp validate_type(value, "boolean") when is_boolean(value), do: :ok
  defp validate_type(value, "array") when is_list(value), do: :ok
  defp validate_type(value, "object") when is_map(value), do: :ok
  defp validate_type(_, type), do: {:error, {:type_mismatch, type}}

  defp find_function(name, functions) do
    case Enum.find(functions, fn f -> f.name == name end) do
      nil -> {:error, {:function_not_found, name}}
      func -> {:ok, func}
    end
  end

  defp safe_execute(function, args) do
    if function.handler do
      try do
        result = function.handler.(args)
        {:ok, result}
      rescue
        e -> {:error, {:execution_error, Exception.message(e)}}
      catch
        :throw, value -> {:error, {:execution_error, value}}
        :exit, reason -> {:error, {:execution_error, reason}}
      end
    else
      {:error, :no_handler}
    end
  end

  # Format results for different providers

  defp format_openai_function_result(%FunctionResult{error: nil} = result) do
    %{
      role: "function",
      name: result.name,
      content: Jason.encode!(result.result)
    }
  end

  defp format_openai_function_result(%FunctionResult{error: error} = result) do
    %{
      role: "function",
      name: result.name,
      content: Jason.encode!(%{error: inspect(error)})
    }
  end

  defp format_anthropic_tool_result(%FunctionResult{error: nil} = result) do
    %{
      type: "tool_result",
      # This should be the tool_use_id from the request
      tool_use_id: result.name,
      content: Jason.encode!(result.result)
    }
  end

  defp format_anthropic_tool_result(%FunctionResult{error: error} = result) do
    %{
      type: "tool_result",
      tool_use_id: result.name,
      content: Jason.encode!(%{error: inspect(error)}),
      is_error: true
    }
  end

  defp format_bedrock_tool_result(result) do
    # Placeholder - Bedrock format varies by model
    %{
      content: Jason.encode!(result.result || %{error: result.error})
    }
  end

  defp format_gemini_function_result(%FunctionResult{} = result) do
    %{
      functionResponse: %{
        name: result.name,
        response: result.result || %{error: inspect(result.error)}
      }
    }
  end
end
