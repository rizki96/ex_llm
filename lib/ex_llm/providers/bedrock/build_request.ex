defmodule ExLLM.Providers.Bedrock.BuildRequest do
  @moduledoc """
  Builds requests for AWS Bedrock with multi-provider support.

  This plug handles the complexity of AWS Bedrock's multi-provider architecture,
  where different model providers (Anthropic, Amazon, Meta, etc.) require different
  request formats through the same Bedrock API endpoint.

  ## Sub-Provider Support

  - **Anthropic** (claude-*): Messages format with tools support
  - **Amazon** (amazon.*): Titan format with inputText
  - **Meta** (meta.*): Llama format with prompt
  - **Cohere** (cohere.*): Cohere format with prompt
  - **AI21** (ai21.*): AI21 format with prompt
  - **Mistral** (mistral.*): Mistral instruction format
  - **Writer** (writer.*): Writer format (similar to Anthropic)
  - **DeepSeek** (deepseek.*): DeepSeek format (similar to Anthropic)
  """

  use ExLLM.Plug

  alias ExLLM.Pipeline.Request

  @impl true
  def call(%Request{state: :pending} = request, _opts) do
    messages = request.messages
    options = request.options
    config = request.assigns.config || %{}

    # Get model from options
    model = Map.get(options, :model, config[:model] || default_model())

    # Determine provider from model ID
    provider = get_provider_from_model_id(model)

    # Build provider-specific request body
    case build_request_body(provider, model, messages, options) do
      {:ok, body} ->
        # Construct Bedrock API URL
        region = get_region(options, config)
        url = build_bedrock_url(model, region)

        # Prepare headers
        headers = %{
          "content-type" => "application/json",
          "accept" => "application/json"
        }

        request
        |> Request.assign(:provider_request, body)
        |> Request.assign(:model, model)
        |> Request.assign(:provider_type, provider)
        |> Request.assign(:url, url)
        |> Request.assign(:http_method, "POST")
        |> Request.assign(:headers, headers)
        |> Request.assign(:body, body)
        |> Request.assign(:aws_service, "bedrock-runtime")
        |> Request.assign(:aws_region, region)
        |> Request.put_state(:executing)

      {:error, reason} ->
        request
        |> Request.add_error(%{
          plug: __MODULE__,
          reason: reason,
          message: "Failed to build Bedrock request: #{inspect(reason)}"
        })
        |> Request.put_state(:error)
        |> Request.halt()
    end
  end

  def call(request, _opts), do: request

  defp default_model do
    "amazon.nova-lite-v1:0"
  end

  defp get_provider_from_model_id(model_id) do
    case String.split(model_id, ".") do
      [provider | _] -> provider
      _ -> "unknown"
    end
  end

  defp get_region(options, config) do
    Map.get(options, :region) ||
      config[:region] ||
      System.get_env("AWS_REGION") ||
      System.get_env("AWS_DEFAULT_REGION") ||
      "us-east-1"
  end

  defp build_bedrock_url(model_id, region) do
    "https://bedrock-runtime.#{region}.amazonaws.com/model/#{model_id}/invoke"
  end

  defp build_request_body(provider, _model_id, messages, options) do
    case provider do
      "anthropic" ->
        build_anthropic_request(messages, options)

      "amazon" ->
        build_amazon_request(messages, options)

      "meta" ->
        build_meta_request(messages, options)

      "cohere" ->
        build_cohere_request(messages, options)

      "ai21" ->
        build_ai21_request(messages, options)

      "mistral" ->
        build_mistral_request(messages, options)

      "writer" ->
        build_writer_request(messages, options)

      "deepseek" ->
        build_deepseek_request(messages, options)

      _ ->
        {:error, "Unsupported Bedrock provider: #{provider}"}
    end
  end

  # Anthropic (Claude) format
  defp build_anthropic_request(messages, options) do
    body = %{
      messages: format_messages_for_anthropic(messages),
      max_tokens: Map.get(options, :max_tokens, 4096),
      temperature: Map.get(options, :temperature, 0.7),
      anthropic_version: "bedrock-2023-05-31"
    }

    # Add system message if present
    body =
      case extract_system_message(messages) do
        nil -> body
        system_content -> Map.put(body, :system, system_content)
      end

    # Add tools if present
    body =
      case Map.get(options, :tools) do
        nil -> body
        tools -> Map.put(body, :tools, tools)
      end

    {:ok, Jason.encode!(body)}
  end

  # Amazon Titan format
  defp build_amazon_request(messages, options) do
    body = %{
      inputText: messages_to_text(messages),
      textGenerationConfig: %{
        maxTokenCount: Map.get(options, :max_tokens, 4096),
        temperature: Map.get(options, :temperature, 0.7),
        topP: Map.get(options, :top_p, 0.9),
        stopSequences: Map.get(options, :stop, [])
      }
    }

    {:ok, Jason.encode!(body)}
  end

  # Meta Llama format
  defp build_meta_request(messages, options) do
    body = %{
      prompt: format_llama_prompt(messages),
      max_gen_len: Map.get(options, :max_tokens, 512),
      temperature: Map.get(options, :temperature, 0.7),
      top_p: Map.get(options, :top_p, 0.9)
    }

    {:ok, Jason.encode!(body)}
  end

  # Cohere format
  defp build_cohere_request(messages, options) do
    body = %{
      prompt: messages_to_text(messages),
      max_tokens: Map.get(options, :max_tokens, 1000),
      temperature: Map.get(options, :temperature, 0.7),
      p: Map.get(options, :top_p, 0.75),
      k: Map.get(options, :top_k, 0),
      stop_sequences: Map.get(options, :stop, [])
    }

    {:ok, Jason.encode!(body)}
  end

  # AI21 format
  defp build_ai21_request(messages, options) do
    body = %{
      prompt: messages_to_text(messages),
      maxTokens: Map.get(options, :max_tokens, 1000),
      temperature: Map.get(options, :temperature, 0.7),
      topP: Map.get(options, :top_p, 1.0),
      stopSequences: Map.get(options, :stop, [])
    }

    {:ok, Jason.encode!(body)}
  end

  # Mistral format
  defp build_mistral_request(messages, options) do
    body = %{
      prompt: format_mistral_prompt(messages),
      max_tokens: Map.get(options, :max_tokens, 1000),
      temperature: Map.get(options, :temperature, 0.7),
      top_p: Map.get(options, :top_p, 1.0),
      top_k: Map.get(options, :top_k, 50)
    }

    {:ok, Jason.encode!(body)}
  end

  # Writer format (similar to Anthropic)
  defp build_writer_request(messages, options) do
    body = %{
      messages: format_messages_for_anthropic(messages),
      max_tokens: Map.get(options, :max_tokens, 4096),
      temperature: Map.get(options, :temperature, 0.7)
    }

    {:ok, Jason.encode!(body)}
  end

  # DeepSeek format (similar to Anthropic)
  defp build_deepseek_request(messages, options) do
    body = %{
      messages: format_messages_for_anthropic(messages),
      max_tokens: Map.get(options, :max_tokens, 4096),
      temperature: Map.get(options, :temperature, 0.7)
    }

    {:ok, Jason.encode!(body)}
  end

  # Message formatting helpers

  defp format_messages_for_anthropic(messages) do
    messages
    |> Enum.reject(&(&1["role"] == "system" || &1[:role] == :system))
    |> Enum.map(fn msg ->
      %{
        role: normalize_role(msg["role"] || msg[:role]),
        content: msg["content"] || msg[:content]
      }
    end)
  end

  defp extract_system_message(messages) do
    case Enum.find(messages, &(&1["role"] == "system" || &1[:role] == :system)) do
      nil -> nil
      msg -> msg["content"] || msg[:content]
    end
  end

  defp messages_to_text(messages) do
    messages
    |> Enum.map(fn msg ->
      role = normalize_role(msg["role"] || msg[:role])
      content = msg["content"] || msg[:content]
      "#{String.capitalize(to_string(role))}: #{content}"
    end)
    |> Enum.join("\n\n")
  end

  defp format_llama_prompt(messages) do
    # Llama uses specific prompt format with system instructions
    system_msg = extract_system_message(messages)
    user_messages = Enum.reject(messages, &(&1["role"] == "system" || &1[:role] == :system))

    formatted =
      user_messages
      |> Enum.map_join("", fn msg ->
        role = normalize_role(msg["role"] || msg[:role])
        content = msg["content"] || msg[:content]

        case role do
          "user" when system_msg ->
            "<s>[INST] <<SYS>>\n#{system_msg}\n<</SYS>>\n\n#{content} [/INST]"

          "user" ->
            "<s>[INST] #{content} [/INST]"

          "assistant" ->
            " #{content} </s>"

          _ ->
            content
        end
      end)

    formatted
  end

  defp format_mistral_prompt(messages) do
    # Mistral instruction format
    messages
    |> Enum.map_join("", fn msg ->
      role = normalize_role(msg["role"] || msg[:role])
      content = msg["content"] || msg[:content]

      case role do
        "system" ->
          "<s>[INST] #{content}\n"

        "user" ->
          "#{content} [/INST]"

        "assistant" ->
          " #{content} </s><s>[INST] "

        _ ->
          content
      end
    end)
  end

  defp normalize_role(role) when is_atom(role), do: to_string(role)
  defp normalize_role(role) when is_binary(role), do: role
  defp normalize_role(_), do: "user"
end
