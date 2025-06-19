defmodule ExLLM.Core.FunctionCallingTest do
  use ExUnit.Case, async: true
  alias ExLLM.Core.FunctionCalling
  alias ExLLM.Core.FunctionCalling.{Function, FunctionCall, FunctionResult}

  describe "normalize_function/2" do
    setup do
      base_function = %{
        name: "get_weather",
        description: "Get the current weather for a location",
        parameters: %{
          type: "object",
          properties: %{
            location: %{
              type: "string",
              description: "The city and state, e.g. San Francisco, CA"
            },
            unit: %{
              type: "string",
              enum: ["celsius", "fahrenheit"],
              description: "Temperature unit"
            }
          },
          required: ["location"]
        }
      }

      {:ok, function: base_function}
    end

    @tag :function_calling
    test "OpenAI format (returns Function struct)", %{function: function} do
      normalized = FunctionCalling.normalize_function(function, :openai)
      assert %Function{} = normalized
      assert normalized.name == "get_weather"
      assert normalized.description == "Get the current weather for a location"
      assert normalized.parameters == function.parameters
    end

    @tag :function_calling
    test "Anthropic format (accepts input_schema)", %{function: function} do
      # Test with input_schema field
      anthropic_func = %{
        name: "get_weather",
        description: "Get the current weather for a location",
        input_schema: function.parameters
      }

      normalized = FunctionCalling.normalize_function(anthropic_func, :anthropic)
      assert %Function{} = normalized
      assert normalized.name == "get_weather"
      assert normalized.description == "Get the current weather for a location"
      assert normalized.parameters == function.parameters
    end

    @tag :function_calling
    test "Unknown provider returns Function struct", %{function: function} do
      normalized = FunctionCalling.normalize_function(function, :unknown)
      assert %Function{} = normalized
      assert normalized.name == "get_weather"
      assert normalized.parameters == function.parameters
    end

    test "handles missing optional fields" do
      minimal_function = %{
        name: "simple_function",
        parameters: %{
          type: "object",
          properties: %{}
        }
      }

      normalized = FunctionCalling.normalize_function(minimal_function, :anthropic)
      assert %Function{} = normalized
      assert normalized.name == "simple_function"
      assert normalized.parameters == minimal_function.parameters
    end

    @tag :function_calling
    test "preserves handler function" do
      handler = fn _args -> {:ok, "handled"} end

      function_with_handler = %{
        name: "test",
        parameters: %{type: "object"},
        handler: handler
      }

      normalized = FunctionCalling.normalize_function(function_with_handler, :openai)
      assert normalized.handler == handler
    end
  end

  describe "normalize_functions/2" do
    @tag :function_calling
    test "normalizes multiple functions" do
      functions = [
        %{name: "func1", parameters: %{type: "object"}},
        %{name: "func2", parameters: %{type: "object"}}
      ]

      normalized = FunctionCalling.normalize_functions(functions, :openai)
      assert length(normalized) == 2
      assert Enum.all?(normalized, &match?(%Function{}, &1))
    end
  end

  describe "format_for_provider/2" do
    setup do
      function = %Function{
        name: "get_weather",
        description: "Get weather info",
        parameters: %{
          type: "object",
          properties: %{location: %{type: "string"}},
          required: ["location"]
        }
      }

      {:ok, function: function}
    end

    @tag :function_calling
    test "formats for OpenAI", %{function: function} do
      formatted = FunctionCalling.format_for_provider([function], :openai)

      assert [openai_func] = formatted
      assert openai_func["name"] == "get_weather"
      assert openai_func["description"] == "Get weather info"
      assert openai_func["parameters"] == function.parameters
    end

    @tag :function_calling
    test "formats for Anthropic", %{function: function} do
      formatted = FunctionCalling.format_for_provider([function], :anthropic)

      assert [anthropic_tool] = formatted
      assert anthropic_tool["name"] == "get_weather"
      assert anthropic_tool["description"] == "Get weather info"
      assert anthropic_tool["input_schema"] == function.parameters
      refute Map.has_key?(anthropic_tool, "parameters")
    end

    @tag :function_calling
    test "formats for Gemini", %{function: function} do
      formatted = FunctionCalling.format_for_provider([function], :gemini)

      assert [gemini_func] = formatted
      assert gemini_func["name"] == "get_weather"
      assert gemini_func["description"] == "Get weather info"
      assert gemini_func["parameters"] == function.parameters
    end

    @tag :function_calling
    test "formats for Bedrock", %{function: function} do
      formatted = FunctionCalling.format_for_provider([function], :bedrock)

      assert [bedrock_tool] = formatted
      assert bedrock_tool["toolSpec"]["name"] == "get_weather"
      assert bedrock_tool["toolSpec"]["description"] == "Get weather info"
      assert bedrock_tool["toolSpec"]["inputSchema"]["json"] == function.parameters
    end

    test "returns error for unsupported provider" do
      assert {:error, {:unsupported_provider, :unknown}} =
               FunctionCalling.format_for_provider([], :unknown)
    end
  end

  describe "parse_function_calls/2" do
    @tag :function_calling
    test "parses OpenAI function call" do
      response = %{
        "choices" => [
          %{
            "message" => %{
              "function_call" => %{
                "name" => "get_weather",
                "arguments" => ~s({"location": "San Francisco"})
              }
            }
          }
        ]
      }

      assert {:ok, [call]} = FunctionCalling.parse_function_calls(response, :openai)
      assert %FunctionCall{} = call
      assert call.name == "get_weather"
      assert call.arguments == ~s({"location": "San Francisco"})
    end

    @tag :function_calling
    test "parses OpenAI tool calls" do
      response = %{
        "choices" => [
          %{
            "message" => %{
              "tool_calls" => [
                %{
                  "id" => "call_123",
                  "function" => %{
                    "name" => "get_weather",
                    "arguments" => ~s({"location": "NYC"})
                  }
                }
              ]
            }
          }
        ]
      }

      assert {:ok, [call]} = FunctionCalling.parse_function_calls(response, :openai)
      assert call.id == "call_123"
      assert call.name == "get_weather"
      assert call.arguments == ~s({"location": "NYC"})
    end

    @tag :function_calling
    test "parses Anthropic tool use" do
      response = %{
        "content" => [
          %{"type" => "text", "text" => "Let me check the weather"},
          %{
            "type" => "tool_use",
            "id" => "toolu_123",
            "name" => "get_weather",
            "input" => %{"location" => "Paris"}
          }
        ]
      }

      assert {:ok, [call]} = FunctionCalling.parse_function_calls(response, :anthropic)
      assert call.id == "toolu_123"
      assert call.name == "get_weather"
      assert call.arguments == %{"location" => "Paris"}
    end

    @tag :function_calling
    test "parses Gemini function calls" do
      response = %{
        "candidates" => [
          %{
            "content" => %{
              "parts" => [
                %{
                  "functionCall" => %{
                    "name" => "get_weather",
                    "args" => %{"location" => "Tokyo"}
                  }
                }
              ]
            }
          }
        ]
      }

      assert {:ok, [call]} = FunctionCalling.parse_function_calls(response, :gemini)
      assert call.name == "get_weather"
      assert call.arguments == %{"location" => "Tokyo"}
    end

    @tag :function_calling
    test "returns empty list when no function calls" do
      assert {:ok, []} = FunctionCalling.parse_function_calls(%{}, :openai)
      assert {:ok, []} = FunctionCalling.parse_function_calls(%{"content" => []}, :anthropic)
    end

    test "returns error for unsupported provider" do
      assert {:error, {:unsupported_provider, :unknown}} =
               FunctionCalling.parse_function_calls(%{}, :unknown)
    end
  end

  describe "validate_arguments/2" do
    setup do
      function_schema = %Function{
        name: "get_weather",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "location" => %{"type" => "string"},
            "unit" => %{"type" => "string", "enum" => ["celsius", "fahrenheit"]}
          },
          "required" => ["location"]
        }
      }

      {:ok, schema: function_schema}
    end

    test "validates correct arguments", %{schema: schema} do
      call = %FunctionCall{
        name: "get_weather",
        arguments: %{"location" => "San Francisco", "unit" => "celsius"}
      }

      assert {:ok, validated} = FunctionCalling.validate_arguments(call, schema)
      assert validated.arguments == %{"location" => "San Francisco", "unit" => "celsius"}
    end

    test "validates with string arguments", %{schema: schema} do
      call = %FunctionCall{
        name: "get_weather",
        arguments: ~s({"location": "San Francisco"})
      }

      assert {:ok, validated} = FunctionCalling.validate_arguments(call, schema)
      assert validated.arguments == %{"location" => "San Francisco"}
    end

    test "rejects missing required fields", %{schema: schema} do
      call = %FunctionCall{
        name: "get_weather",
        arguments: %{"unit" => "celsius"}
      }

      assert {:error, {:missing_required_fields, ["location"]}} =
               FunctionCalling.validate_arguments(call, schema)
    end

    test "rejects invalid JSON", %{schema: schema} do
      call = %FunctionCall{
        name: "get_weather",
        arguments: "invalid json {"
      }

      assert {:error, :invalid_json} = FunctionCalling.validate_arguments(call, schema)
    end

    test "allows additional properties", %{schema: schema} do
      call = %FunctionCall{
        name: "get_weather",
        arguments: %{"location" => "SF", "extra" => "data"}
      }

      assert {:ok, validated} = FunctionCalling.validate_arguments(call, schema)
      assert validated.arguments["extra"] == "data"
    end
  end

  describe "execute_function/2" do
    @tag :function_calling
    test "executes function with handler" do
      function = %Function{
        name: "calculate",
        parameters: %{},
        handler: fn args ->
          args["a"] + args["b"]
        end
      }

      call = %FunctionCall{
        name: "calculate",
        arguments: %{"a" => 5, "b" => 3}
      }

      assert {:ok, result} = FunctionCalling.execute_function(call, [function])
      assert %FunctionResult{} = result
      assert result.name == "calculate"
      assert result.result == 8
      assert result.error == nil
    end

    @tag :function_calling
    test "returns error for unknown function" do
      call = %FunctionCall{name: "unknown", arguments: %{}}

      assert {:error, result} = FunctionCalling.execute_function(call, [])
      assert %FunctionResult{} = result
      assert result.name == "unknown"
      assert result.error == {:function_not_found, "unknown"}
    end

    test "returns error when handler missing" do
      function = %Function{
        name: "test",
        parameters: %{}
        # No handler
      }

      call = %FunctionCall{name: "test", arguments: %{}}

      assert {:error, result} = FunctionCalling.execute_function(call, [function])
      assert result.error == :no_handler
    end

    test "handles execution errors gracefully" do
      function = %Function{
        name: "failing",
        parameters: %{},
        handler: fn _args ->
          raise "Execution failed"
        end
      }

      call = %FunctionCall{name: "failing", arguments: %{}}

      assert {:error, result} = FunctionCalling.execute_function(call, [function])
      assert {:execution_error, "Execution failed"} = result.error
    end

    test "validates arguments before execution" do
      function = %Function{
        name: "strict",
        parameters: %{
          "type" => "object",
          "properties" => %{"required_field" => %{"type" => "string"}},
          "required" => ["required_field"]
        },
        handler: fn args -> args end
      }

      call = %FunctionCall{name: "strict", arguments: %{}}

      assert {:error, result} = FunctionCalling.execute_function(call, [function])
      assert {:missing_required_fields, ["required_field"]} = result.error
    end
  end

  describe "format_function_result/2" do
    test "formats success result for OpenAI" do
      result = %FunctionResult{
        name: "get_weather",
        result: %{temp: 72, conditions: "sunny"}
      }

      formatted = FunctionCalling.format_function_result(result, :openai)

      assert formatted.role == "function"
      assert formatted.name == "get_weather"
      # JSON key order may vary
      {:ok, content} = Jason.decode(formatted.content)
      assert content == %{"temp" => 72, "conditions" => "sunny"}
    end

    test "formats error result for OpenAI" do
      result = %FunctionResult{
        name: "get_weather",
        error: "Location not found"
      }

      formatted = FunctionCalling.format_function_result(result, :openai)

      assert formatted.role == "function"
      assert formatted.name == "get_weather"
      assert formatted.content =~ "error"
      assert formatted.content =~ "Location not found"
    end

    @tag :function_calling
    test "formats result for Anthropic" do
      result = %FunctionResult{
        name: "toolu_123",
        result: "Success"
      }

      formatted = FunctionCalling.format_function_result(result, :anthropic)

      assert formatted.type == "tool_result"
      assert formatted.tool_use_id == "toolu_123"
      assert formatted.content == ~s("Success")
    end

    @tag :function_calling
    test "formats error for Anthropic" do
      result = %FunctionResult{
        name: "toolu_123",
        error: "Failed"
      }

      formatted = FunctionCalling.format_function_result(result, :anthropic)

      assert formatted.type == "tool_result"
      assert formatted.tool_use_id == "toolu_123"
      assert formatted.is_error == true
      assert formatted.content =~ "error"
    end

    test "formats result for Gemini" do
      result = %FunctionResult{
        name: "calculate",
        result: 42
      }

      formatted = FunctionCalling.format_function_result(result, :gemini)

      assert formatted.functionResponse.name == "calculate"
      assert formatted.functionResponse.response == 42
    end

    test "returns error for unsupported provider" do
      result = %FunctionResult{name: "test", result: "data"}

      assert {:error, {:unsupported_provider, :unknown}} =
               FunctionCalling.format_function_result(result, :unknown)
    end
  end

  describe "integration flow" do
    @tag :function_calling
    test "complete function calling workflow" do
      # 1. Define function
      handler = fn args ->
        case args["operation"] do
          "add" -> args["a"] + args["b"]
          "multiply" -> args["a"] * args["b"]
        end
      end

      function = %{
        name: "calculate",
        description: "Perform calculations",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "operation" => %{"type" => "string", "enum" => ["add", "multiply"]},
            "a" => %{"type" => "number"},
            "b" => %{"type" => "number"}
          },
          "required" => ["operation", "a", "b"]
        },
        handler: handler
      }

      # 2. Normalize function
      normalized = FunctionCalling.normalize_function(function, :anthropic)
      assert %Function{} = normalized

      # 3. Format for provider
      formatted = FunctionCalling.format_for_provider([normalized], :anthropic)
      assert [tool] = formatted
      assert tool["input_schema"] == function.parameters

      # 4. Parse function call from response
      response = %{
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "toolu_calc",
            "name" => "calculate",
            "input" => %{"operation" => "add", "a" => 5, "b" => 3}
          }
        ]
      }

      assert {:ok, [call]} = FunctionCalling.parse_function_calls(response, :anthropic)

      # 5. Execute function
      assert {:ok, result} = FunctionCalling.execute_function(call, [normalized])
      assert result.result == 8

      # 6. Format result for response
      formatted_result = FunctionCalling.format_function_result(result, :anthropic)
      assert formatted_result.type == "tool_result"
      assert formatted_result.content == "8"
    end
  end
end
