defmodule ExLLM.Plugs.Providers.OpenAIPrepareRequest do
  @moduledoc """
  Prepares the request body for OpenAI API calls.

  This plug transforms the standardized ExLLM message format into
  the specific format required by OpenAI's API.

  ## Supported Features

  - Text messages
  - System messages
  - Multi-turn conversations
  - Function calling
  - Vision (image inputs)
  - Response format specification
  - Streaming configuration

  ## Examples

      plug ExLLM.Plugs.Providers.OpenAIPrepareRequest
  """

  use ExLLM.Plug

  @impl true
  def call(%Request{messages: messages, config: config, provider: provider} = request, _opts) do
    body = build_request_body(messages, config, provider)

    request
    |> Map.put(:provider_request, body)
    |> Request.assign(:request_prepared, true)
  end

  defp build_request_body(messages, config, provider) do
    # Get the provider's default model instead of hardcoding
    default_model =
      case provider do
        :openai -> "gpt-4"
        :groq -> "llama-3.1-8b-instant"
        _ -> "gpt-4"
      end

    %{
      model: config[:model] || default_model,
      messages: format_messages(messages),
      temperature: config[:temperature],
      max_tokens: config[:max_tokens],
      top_p: config[:top_p],
      frequency_penalty: config[:frequency_penalty],
      presence_penalty: config[:presence_penalty],
      stop: config[:stop],
      stream: config[:stream] || false,
      n: config[:n] || 1,
      user: config[:user]
    }
    |> maybe_add_functions(config)
    |> maybe_add_tools(config)
    |> maybe_add_response_format(config)
    |> maybe_add_seed(config)
    |> compact()
  end

  defp format_messages(messages) do
    Enum.map(messages, &format_message/1)
  end

  defp format_message(%{role: role, content: content} = message) do
    base = %{
      "role" => to_string(role),
      "content" => format_content(content)
    }

    # Add optional fields
    base
    |> maybe_add_name(message)
    |> maybe_add_function_call(message)
    |> maybe_add_tool_calls(message)
  end

  defp format_message(message) when is_map(message) do
    # Handle both atom and string keys
    role = message[:role] || message["role"]
    content = message[:content] || message["content"]

    format_message(%{role: role, content: content})
  end

  defp format_content(content) when is_binary(content), do: content

  defp format_content(content) when is_list(content) do
    # Handle multimodal content
    Enum.map(content, fn
      %{type: "text", text: text} ->
        %{"type" => "text", "text" => text}

      %{type: "image", image: image_data} ->
        format_image_content(image_data)

      %{type: "image_url", image_url: url} ->
        %{"type" => "image_url", "image_url" => %{"url" => url}}

      # Handle string keys too
      %{"type" => _type} = item ->
        item

      other ->
        other
    end)
  end

  defp format_content(content), do: content

  defp format_image_content(%{url: url} = image) do
    base = %{"type" => "image_url", "image_url" => %{"url" => url}}

    if image[:detail] do
      put_in(base, ["image_url", "detail"], image.detail)
    else
      base
    end
  end

  defp format_image_content(%{data: data, media_type: media_type}) do
    %{
      "type" => "image_url",
      "image_url" => %{
        "url" => "data:#{media_type};base64,#{data}"
      }
    }
  end

  defp maybe_add_name(message_map, %{name: name}) when not is_nil(name) do
    Map.put(message_map, "name", name)
  end

  defp maybe_add_name(message_map, _), do: message_map

  defp maybe_add_function_call(message_map, %{function_call: fc}) when not is_nil(fc) do
    Map.put(message_map, "function_call", fc)
  end

  defp maybe_add_function_call(message_map, _), do: message_map

  defp maybe_add_tool_calls(message_map, %{tool_calls: tc}) when not is_nil(tc) do
    Map.put(message_map, "tool_calls", tc)
  end

  defp maybe_add_tool_calls(message_map, _), do: message_map

  defp maybe_add_functions(body, %{functions: functions}) when is_list(functions) do
    Map.put(body, :functions, functions)
  end

  defp maybe_add_functions(body, _), do: body

  defp maybe_add_tools(body, %{tools: tools}) when is_list(tools) do
    # Convert to OpenAI tool format if needed
    formatted_tools =
      Enum.map(tools, fn
        %{type: _} = tool -> tool
        function -> %{"type" => "function", "function" => function}
      end)

    Map.put(body, :tools, formatted_tools)
  end

  defp maybe_add_tools(body, _), do: body

  defp maybe_add_response_format(body, %{response_format: format}) do
    Map.put(body, :response_format, format)
  end

  defp maybe_add_response_format(body, _), do: body

  defp maybe_add_seed(body, %{seed: seed}) when is_integer(seed) do
    Map.put(body, :seed, seed)
  end

  defp maybe_add_seed(body, _), do: body

  defp compact(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
