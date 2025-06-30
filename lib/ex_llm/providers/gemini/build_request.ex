defmodule ExLLM.Providers.Gemini.BuildRequest do
  @moduledoc """
  Pipeline plug for building Gemini API requests.
  """

  use ExLLM.Plug

  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.Shared.ConfigHelper

  alias ExLLM.Providers.Gemini.Content.{
    Content,
    GenerateContentRequest,
    GenerationConfig,
    Part,
    SafetySetting,
    Tool
  }

  @impl true
  def call(request, _opts) do
    config = request.assigns.config
    api_key = request.assigns.api_key
    messages = request.messages
    options = request.options

    model =
      Map.get(
        options,
        :model,
        Map.get(config, :model) || ConfigHelper.ensure_default_model(:gemini)
      )

    body = build_content_request(messages, options)
    headers = build_headers()
    streaming = Map.get(options, :stream, false)
    url = build_url(model, api_key, config, streaming)

    request
    |> Map.put(:provider_request, body)
    |> Request.assign(:model, model)
    |> Request.assign(:request_body, body)
    |> Request.assign(:request_headers, headers)
    |> Request.assign(:request_url, url)
    |> Request.assign(:timeout, 60_000)
  end

  defp build_url(model, api_key, config, streaming) do
    base_url =
      Map.get(config, :base_url) ||
        System.get_env("GEMINI_API_BASE") ||
        "https://generativelanguage.googleapis.com/v1beta"

    endpoint = if streaming, do: "streamGenerateContent", else: "generateContent"
    "#{base_url}/models/#{model}:#{endpoint}?key=#{api_key}"
  end

  defp build_headers() do
    [
      {"Content-Type", "application/json"}
    ]
  end

  defp build_content_request(messages, options) do
    contents =
      messages
      |> Enum.map(&convert_message_to_content/1)
      |> merge_consecutive_same_role()

    {system_instruction, contents} = extract_system_instruction(contents)

    %GenerateContentRequest{
      contents: contents,
      system_instruction: system_instruction,
      generation_config: build_generation_config(options),
      safety_settings: build_safety_settings(options),
      tools: build_tools(options)
    }
  end

  defp convert_message_to_content(%{role: role, content: content}) do
    %Content{
      role: convert_role(role),
      parts: [%Part{text: content}]
    }
  end

  defp convert_message_to_content(message) when is_map(message) do
    role = Map.get(message, "role", "user")
    content = Map.get(message, "content", "")

    %Content{
      role: convert_role(role),
      parts: [%Part{text: content}]
    }
  end

  defp convert_role("system"), do: "user"
  defp convert_role("assistant"), do: "model"
  defp convert_role(role), do: to_string(role)

  defp merge_consecutive_same_role(contents) do
    contents
    |> Enum.reduce([], fn content, acc ->
      case acc do
        [] ->
          [content]

        [%Content{role: last_role} = last | rest] ->
          if last_role == content.role do
            merged = %Content{
              role: last_role,
              parts: last.parts ++ content.parts
            }

            [merged | rest]
          else
            [content | acc]
          end
      end
    end)
    |> Enum.reverse()
  end

  defp extract_system_instruction([%Content{role: "user", parts: parts} = first | rest]) do
    case parts do
      [%Part{text: text}] when is_binary(text) ->
        if String.starts_with?(text, "System: ") or String.starts_with?(text, "[System]") do
          system_content = %Content{role: "system", parts: parts}
          {system_content, rest}
        else
          {nil, [first | rest]}
        end

      _ ->
        {nil, [first | rest]}
    end
  end

  defp extract_system_instruction(contents), do: {nil, contents}

  defp build_generation_config(options) do
    base_config = %{
      temperature: Map.get(options, :temperature),
      top_p: Map.get(options, :top_p),
      top_k: Map.get(options, :top_k),
      max_output_tokens: Map.get(options, :max_tokens),
      stop_sequences: Map.get(options, :stop_sequences),
      response_mime_type: Map.get(options, :response_mime_type)
    }

    advanced_config =
      base_config
      |> maybe_add_field(:response_modalities, Map.get(options, :response_modalities))
      |> maybe_add_field(:speech_config, Map.get(options, :speech_config))
      |> maybe_add_field(:thinking_config, Map.get(options, :thinking_config))

    if Enum.any?(advanced_config, fn {_k, v} -> v != nil end) do
      struct(GenerationConfig, advanced_config)
    else
      nil
    end
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  defp build_safety_settings(options) do
    case Map.get(options, :safety_settings) do
      nil ->
        nil

      settings ->
        Enum.map(settings, fn setting ->
          %SafetySetting{
            category: setting[:category] || setting["category"],
            threshold: setting[:threshold] || setting["threshold"]
          }
        end)
    end
  end

  defp build_tools(options) do
    case Map.get(options, :tools) do
      nil ->
        nil

      tools ->
        tools
        |> List.wrap()
        |> Enum.map(&convert_tool/1)
    end
  end

  defp convert_tool(tool) when is_map(tool) do
    cond do
      Map.has_key?(tool, :function_declarations) or Map.has_key?(tool, "function_declarations") ->
        %Tool{
          function_declarations: tool[:function_declarations] || tool["function_declarations"]
        }

      Map.has_key?(tool, "name") or Map.has_key?(tool, :name) ->
        %Tool{
          function_declarations: [tool]
        }

      true ->
        %Tool{
          function_declarations: []
        }
    end
  end
end
