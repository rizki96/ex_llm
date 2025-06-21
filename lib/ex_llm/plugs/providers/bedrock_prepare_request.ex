defmodule ExLLM.Plugs.Providers.BedrockPrepareRequest do
  @moduledoc """
  Prepares a request for AWS Bedrock API.

  AWS Bedrock has different request formats for different model families:
  - Claude (Anthropic)
  - Titan (Amazon)
  - Llama (Meta)
  - Command (Cohere)
  - Mistral

  This plug detects the model family and formats the request accordingly.
  """

  use ExLLM.Plug
  alias ExLLM.Infrastructure.Logger

  @impl true
  def call(%Request{config: config} = request, _opts) do
    model = config[:model] || "anthropic.claude-v2"
    body = build_request_body(request, model)

    # Set the endpoint based on the model
    endpoint = determine_endpoint(model, config[:stream] || false)

    request
    |> Map.put(:provider_request, body)
    |> Request.assign(:http_path, endpoint)
    |> Request.assign(:bedrock_model, model)
    |> Request.assign(:request_prepared, true)
  end

  defp build_request_body(%Request{messages: messages, config: config}, model) do
    cond do
      String.contains?(model, "claude") ->
        build_claude_request(messages, config)

      String.contains?(model, "titan") ->
        build_titan_request(messages, config)

      String.contains?(model, "llama") ->
        build_llama_request(messages, config)

      String.contains?(model, "command") ->
        build_cohere_request(messages, config)

      String.contains?(model, "mistral") ->
        build_mistral_request(messages, config)

      true ->
        # Default to Claude format
        build_claude_request(messages, config)
    end
  end

  defp build_claude_request(messages, config) do
    # Claude on Bedrock uses Anthropic's message format
    {system_messages, other_messages} = Enum.split_with(messages, &(&1[:role] == "system"))

    body = %{
      messages: Enum.map(other_messages, &format_claude_message/1),
      max_tokens: config[:max_tokens] || 4096,
      temperature: config[:temperature] || 0.7
    }

    # Add system message if present
    case system_messages do
      [] -> body
      [%{content: content} | _] -> Map.put(body, :system, content)
    end
  end

  defp format_claude_message(%{role: "user", content: content}) do
    %{"role" => "user", "content" => content}
  end

  defp format_claude_message(%{role: "assistant", content: content}) do
    %{"role" => "assistant", "content" => content}
  end

  defp format_claude_message(%{role: _, content: content}) do
    # Default unknown roles to user
    %{"role" => "user", "content" => content}
  end

  defp build_titan_request(messages, config) do
    # Amazon Titan format
    %{
      inputText: format_conversation(messages),
      textGenerationConfig: %{
        maxTokenCount: config[:max_tokens] || 4096,
        temperature: config[:temperature] || 0.7,
        topP: config[:top_p] || 0.9
      }
    }
  end

  defp build_llama_request(messages, config) do
    # Meta Llama format
    %{
      prompt: format_conversation(messages),
      max_gen_len: config[:max_tokens] || 512,
      temperature: config[:temperature] || 0.7,
      top_p: config[:top_p] || 0.9
    }
  end

  defp build_cohere_request(messages, config) do
    # Cohere Command format
    %{
      prompt: format_conversation(messages),
      max_tokens: config[:max_tokens] || 4096,
      temperature: config[:temperature] || 0.7
    }
  end

  defp build_mistral_request(messages, config) do
    # Mistral format (similar to OpenAI)
    %{
      messages: Enum.map(messages, &format_openai_style_message/1),
      max_tokens: config[:max_tokens] || 4096,
      temperature: config[:temperature] || 0.7
    }
  end

  defp format_openai_style_message(%{role: role, content: content}) do
    %{"role" => to_string(role), "content" => content}
  end

  defp format_conversation(messages) do
    messages
    |> Enum.map(fn %{role: role, content: content} ->
      "#{String.capitalize(to_string(role))}: #{content}"
    end)
    |> Enum.join("\n\n")
  end

  defp determine_endpoint(model, streaming) do
    model_id = normalize_model_id(model)

    if streaming do
      "/model/#{model_id}/invoke-with-response-stream"
    else
      "/model/#{model_id}/invoke"
    end
  end

  defp normalize_model_id(model) do
    # Bedrock model IDs need to be in specific format
    # e.g., "anthropic.claude-v2" or "amazon.titan-text-express-v1"
    if String.contains?(model, ".") do
      model
    else
      # Try to infer the full model ID
      cond do
        String.contains?(model, "claude") -> "anthropic.#{model}"
        String.contains?(model, "titan") -> "amazon.#{model}"
        String.contains?(model, "llama") -> "meta.#{model}"
        String.contains?(model, "command") -> "cohere.#{model}"
        String.contains?(model, "mistral") -> "mistral.#{model}"
        true -> model
      end
    end
  end
end
