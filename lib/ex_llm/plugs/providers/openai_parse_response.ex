defmodule ExLLM.Plugs.Providers.OpenAIParseResponse do
  @moduledoc """
  Parses the response from OpenAI API calls.

  This plug transforms the OpenAI-specific response format into
  the standardized ExLLM response format.

  ## Response Structure

  The parsed response includes:
  - Message content
  - Token usage information
  - Function/tool calls if present
  - Model information
  - Finish reason

  ## Examples

      plug ExLLM.Plugs.Providers.OpenAIParseResponse
  """

  use ExLLM.Plug
  alias ExLLM.Types.LLMResponse

  @impl true
  def call(%Request{response: nil} = request, _opts) do
    request
    |> Request.halt_with_error(%{
      plug: __MODULE__,
      error: :missing_response,
      message: "No response to parse. Did ExecuteRequest run?"
    })
  end

  def call(%Request{response: %Tesla.Env{body: body}} = request, _opts) when is_map(body) do
    case parse_response(body, request) do
      {:ok, parsed} ->
        request
        |> Map.put(:result, parsed)
        |> Request.put_metadata(:model_used, parsed.model)
        |> Request.put_metadata(:tokens_used, parsed.usage)
        |> Request.assign(:response_parsed, true)

      {:error, reason} ->
        request
        |> Request.halt_with_error(%{
          plug: __MODULE__,
          error: :parse_error,
          message: "Failed to parse OpenAI response: #{inspect(reason)}",
          body: body
        })
    end
  end

  def call(%Request{response: %Tesla.Env{body: body}} = request, _opts) do
    request
    |> Request.halt_with_error(%{
      plug: __MODULE__,
      error: :invalid_response_format,
      message: "Expected map response body, got: #{inspect(body)}",
      body: body
    })
  end

  defp parse_response(%{"error" => error}, _request) do
    {:error, parse_error(error)}
  end

  defp parse_response(%{"choices" => choices, "usage" => usage} = response, request) do
    # Extract the first choice (handle n > 1 later if needed)
    case List.first(choices) do
      nil ->
        {:error, :no_choices}

      choice ->
        parsed = %LLMResponse{
          content: extract_content(choice),
          model: response["model"] || request.config[:model],
          usage: parse_usage(usage),
          finish_reason: choice["finish_reason"],
          metadata:
            Map.merge(response["metadata"] || %{}, %{
              role: extract_role(choice),
              provider: request.provider,
              raw_response: response
            })
        }

        # Add optional fields
        parsed =
          parsed
          |> maybe_add_function_call(choice)
          |> maybe_add_tool_calls(choice)
          |> maybe_add_system_fingerprint(response)

        {:ok, parsed}
    end
  end

  defp parse_response(response, _request) do
    {:error, {:unexpected_format, response}}
  end

  defp parse_error(%{"message" => message, "type" => type, "code" => code}) do
    %{
      message: message,
      type: type,
      code: code
    }
  end

  defp parse_error(%{"message" => message}) do
    %{message: message}
  end

  defp parse_error(error) do
    %{error: error}
  end

  defp extract_content(%{"message" => %{"content" => content}}) when not is_nil(content) do
    content
  end

  defp extract_content(%{"message" => %{"tool_calls" => tool_calls}}) when is_list(tool_calls) do
    # For tool calls, we might want to format them specially
    format_tool_calls(tool_calls)
  end

  defp extract_content(%{"message" => %{"function_call" => function_call}}) do
    # Legacy function calling
    format_function_call(function_call)
  end

  defp extract_content(_), do: ""

  defp extract_role(%{"message" => %{"role" => role}}), do: role
  defp extract_role(_), do: "assistant"

  defp parse_usage(%{
         "prompt_tokens" => prompt,
         "completion_tokens" => completion,
         "total_tokens" => total
       }) do
    %{
      prompt_tokens: prompt,
      completion_tokens: completion,
      total_tokens: total
    }
  end

  defp parse_usage(%{"prompt_tokens" => prompt, "completion_tokens" => completion}) do
    %{
      prompt_tokens: prompt,
      completion_tokens: completion,
      total_tokens: prompt + completion
    }
  end

  defp parse_usage(_), do: %{}

  defp maybe_add_function_call(parsed, %{"message" => %{"function_call" => fc}})
       when not is_nil(fc) do
    %{parsed | function_call: parse_function_call(fc)}
  end

  defp maybe_add_function_call(parsed, _), do: parsed

  defp maybe_add_tool_calls(parsed, %{"message" => %{"tool_calls" => tc}}) when is_list(tc) do
    %{parsed | tool_calls: Enum.map(tc, &parse_tool_call/1)}
  end

  defp maybe_add_tool_calls(parsed, _), do: parsed

  defp maybe_add_system_fingerprint(parsed, %{"system_fingerprint" => fp}) when not is_nil(fp) do
    %{parsed | metadata: Map.put(parsed.metadata, :system_fingerprint, fp)}
  end

  defp maybe_add_system_fingerprint(parsed, _), do: parsed

  defp parse_function_call(%{"name" => name, "arguments" => args}) do
    %{
      name: name,
      arguments: parse_arguments(args)
    }
  end

  defp parse_function_call(fc), do: fc

  defp parse_tool_call(%{"id" => id, "type" => type, "function" => function}) do
    %{
      id: id,
      type: type,
      function: parse_function_call(function)
    }
  end

  defp parse_tool_call(tc), do: tc

  defp parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      _ -> args
    end
  end

  defp parse_arguments(args), do: args

  defp format_tool_calls(tool_calls) do
    # For now, just return a string representation
    # In a real app, this might be handled differently
    tool_names =
      Enum.map(tool_calls, fn tc ->
        tc["function"]["name"]
      end)

    "[Tool calls: #{Enum.join(tool_names, ", ")}]"
  end

  defp format_function_call(%{"name" => name}) do
    "[Function call: #{name}]"
  end

  defp format_function_call(_), do: "[Function call]"
end
