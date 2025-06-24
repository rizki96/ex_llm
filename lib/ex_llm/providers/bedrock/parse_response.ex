defmodule ExLLM.Providers.Bedrock.ParseResponse do
  @moduledoc """
  Parses responses from AWS Bedrock with multi-provider support.

  This plug handles the complexity of parsing responses from different model
  providers through the Bedrock API, where each sub-provider returns responses
  in their own format.
  """

  use ExLLM.Plug

  alias ExLLM.Pipeline.Request
  alias ExLLM.Types

  @impl true
  def call(%Request{state: :completed} = request, _opts) do
    raw_response = request.assigns[:raw_response]
    provider_type = request.assigns[:provider_type]
    model = request.assigns[:model]

    if raw_response && provider_type do
      parse_bedrock_response(request, raw_response, provider_type, model)
    else
      # Not a Bedrock response, pass through
      request
    end
  end

  def call(request, _opts), do: request

  defp parse_bedrock_response(request, raw_response, provider_type, model) do
    case extract_response_body(raw_response) do
      {:ok, body} ->
        case parse_provider_response(provider_type, body) do
          {:ok, content, usage} ->
            llm_response = %Types.LLMResponse{
              content: content,
              model: model,
              usage: usage,
              finish_reason: extract_finish_reason(provider_type, body),
              metadata: extract_metadata(provider_type, body)
            }

            request
            |> Request.assign(:llm_response, llm_response)
            |> Request.assign(:parsed_response, llm_response)

          {:error, reason} ->
            request
            |> Request.add_error(%{
              plug: __MODULE__,
              reason: reason,
              message: "Failed to parse #{provider_type} response: #{inspect(reason)}"
            })
            |> Request.put_state(:error)
            |> Request.halt()
        end

      {:error, reason} ->
        request
        |> Request.add_error(%{
          plug: __MODULE__,
          reason: reason,
          message: "Failed to extract Bedrock response body: #{inspect(reason)}"
        })
        |> Request.put_state(:error)
        |> Request.halt()
    end
  end

  defp extract_response_body(%{body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  defp extract_response_body(%{body: body}) when is_map(body) do
    {:ok, body}
  end

  defp extract_response_body(_) do
    {:error, :invalid_response_format}
  end

  defp parse_provider_response(provider_type, body) do
    case provider_type do
      "anthropic" ->
        parse_anthropic_response(body)

      "amazon" ->
        parse_amazon_response(body)

      "meta" ->
        parse_meta_response(body)

      "cohere" ->
        parse_cohere_response(body)

      "ai21" ->
        parse_ai21_response(body)

      "mistral" ->
        parse_mistral_response(body)

      "writer" ->
        parse_writer_response(body)

      "deepseek" ->
        parse_deepseek_response(body)

      _ ->
        {:error, "Unsupported provider: #{provider_type}"}
    end
  end

  # Anthropic (Claude) response parsing
  defp parse_anthropic_response(body) do
    case body do
      %{"content" => [%{"type" => "text", "text" => text} | _]} = response ->
        usage = extract_anthropic_usage(response)
        {:ok, text, usage}

      %{"content" => [%{"text" => text} | _]} = response ->
        usage = extract_anthropic_usage(response)
        {:ok, text, usage}

      %{"error" => error} ->
        {:error, {:anthropic_error, error}}

      _ ->
        {:error, {:unexpected_format, body}}
    end
  end

  defp extract_anthropic_usage(%{"usage" => usage}) do
    %{
      input_tokens: usage["input_tokens"] || 0,
      output_tokens: usage["output_tokens"] || 0,
      total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
    }
  end

  defp extract_anthropic_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  # Amazon Titan response parsing
  defp parse_amazon_response(body) do
    case body do
      %{"results" => [%{"outputText" => text} | _]} = response ->
        usage = extract_amazon_usage(response)
        {:ok, text, usage}

      %{"error" => error} ->
        {:error, {:amazon_error, error}}

      _ ->
        {:error, {:unexpected_format, body}}
    end
  end

  defp extract_amazon_usage(%{
         "inputTextTokenCount" => input,
         "results" => [%{"tokenCount" => output} | _]
       }) do
    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: input + output
    }
  end

  defp extract_amazon_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  # Meta Llama response parsing
  defp parse_meta_response(body) do
    case body do
      %{"generation" => text} when is_binary(text) ->
        usage = extract_meta_usage(body)
        {:ok, text, usage}

      %{"error" => error} ->
        {:error, {:meta_error, error}}

      _ ->
        {:error, {:unexpected_format, body}}
    end
  end

  defp extract_meta_usage(%{"prompt_token_count" => input, "generation_token_count" => output}) do
    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: input + output
    }
  end

  defp extract_meta_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  # Cohere response parsing
  defp parse_cohere_response(body) do
    case body do
      %{"generations" => [%{"text" => text} | _]} = response ->
        usage = extract_cohere_usage(response)
        {:ok, text, usage}

      %{"error" => error} ->
        {:error, {:cohere_error, error}}

      _ ->
        {:error, {:unexpected_format, body}}
    end
  end

  defp extract_cohere_usage(%{
         "meta" => %{"billed_units" => %{"input_tokens" => input, "output_tokens" => output}}
       }) do
    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: input + output
    }
  end

  defp extract_cohere_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  # AI21 response parsing
  defp parse_ai21_response(body) do
    case body do
      %{"completions" => [%{"data" => %{"text" => text}} | _]} = response ->
        usage = extract_ai21_usage(response)
        {:ok, text, usage}

      %{"error" => error} ->
        {:error, {:ai21_error, error}}

      _ ->
        {:error, {:unexpected_format, body}}
    end
  end

  defp extract_ai21_usage(%{
         "prompt" => %{"tokens" => input_tokens},
         "completions" => [%{"data" => %{"tokens" => output_tokens}} | _]
       }) do
    input = length(input_tokens)
    output = length(output_tokens)

    %{
      input_tokens: input,
      output_tokens: output,
      total_tokens: input + output
    }
  end

  defp extract_ai21_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  # Mistral response parsing
  defp parse_mistral_response(body) do
    case body do
      %{"outputs" => [%{"text" => text} | _]} = response ->
        usage = extract_mistral_usage(response)
        {:ok, text, usage}

      %{"error" => error} ->
        {:error, {:mistral_error, error}}

      _ ->
        {:error, {:unexpected_format, body}}
    end
  end

  defp extract_mistral_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  # Writer response parsing (similar to Anthropic)
  defp parse_writer_response(body) do
    case body do
      %{"content" => [%{"text" => text} | _]} = response ->
        usage = extract_writer_usage(response)
        {:ok, text, usage}

      %{"error" => error} ->
        {:error, {:writer_error, error}}

      _ ->
        {:error, {:unexpected_format, body}}
    end
  end

  defp extract_writer_usage(%{"usage" => usage}) do
    %{
      input_tokens: usage["input_tokens"] || 0,
      output_tokens: usage["output_tokens"] || 0,
      total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
    }
  end

  defp extract_writer_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  # DeepSeek response parsing (similar to Anthropic)
  defp parse_deepseek_response(body) do
    case body do
      %{"content" => [%{"text" => text} | _]} = response ->
        usage = extract_deepseek_usage(response)
        {:ok, text, usage}

      %{"error" => error} ->
        {:error, {:deepseek_error, error}}

      _ ->
        {:error, {:unexpected_format, body}}
    end
  end

  defp extract_deepseek_usage(%{"usage" => usage}) do
    %{
      input_tokens: usage["input_tokens"] || 0,
      output_tokens: usage["output_tokens"] || 0,
      total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
    }
  end

  defp extract_deepseek_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  # Extract finish reason based on provider
  defp extract_finish_reason("anthropic", %{"stop_reason" => reason}), do: reason

  defp extract_finish_reason("amazon", %{"results" => [%{"completionReason" => reason} | _]}),
    do: reason

  defp extract_finish_reason("meta", %{"stop_reason" => reason}), do: reason

  defp extract_finish_reason("cohere", %{"generations" => [%{"finish_reason" => reason} | _]}),
    do: reason

  defp extract_finish_reason("ai21", %{
         "completions" => [%{"finishReason" => %{"reason" => reason}} | _]
       }),
       do: reason

  defp extract_finish_reason("mistral", %{"outputs" => [%{"stop_reason" => reason} | _]}),
    do: reason

  defp extract_finish_reason("writer", %{"stop_reason" => reason}), do: reason
  defp extract_finish_reason("deepseek", %{"stop_reason" => reason}), do: reason
  defp extract_finish_reason(_, _), do: "stop"

  # Extract metadata based on provider
  defp extract_metadata("anthropic", body) do
    %{
      provider: "anthropic",
      bedrock: true,
      model_id: Map.get(body, "model"),
      stop_sequence: Map.get(body, "stop_sequence")
    }
  end

  defp extract_metadata("amazon", body) do
    %{
      provider: "amazon",
      bedrock: true,
      input_text_token_count: Map.get(body, "inputTextTokenCount")
    }
  end

  defp extract_metadata("meta", body) do
    %{
      provider: "meta",
      bedrock: true,
      prompt_token_count: Map.get(body, "prompt_token_count"),
      generation_token_count: Map.get(body, "generation_token_count")
    }
  end

  defp extract_metadata(provider_type, _body) do
    %{
      provider: provider_type,
      bedrock: true
    }
  end
end
