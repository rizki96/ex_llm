defmodule ExLLM.Providers.XAI do
  @moduledoc """
  Adapter for X.AI's Grok models.

  X.AI provides access to the Grok family of models including Grok-3, Grok-2,
  and their variants with different capabilities (vision, reasoning, etc.).

  ## Configuration

  The adapter requires an API key to be configured:

      config :ex_llm, :xai,
        api_key: System.get_env("XAI_API_KEY")

  Or using environment variables:
  - `XAI_API_KEY` - Your X.AI API key

  ## Supported Models

  - `grok-beta` - Grok Beta with 131K context
  - `grok-2-vision-1212` - Grok 2 with vision support
  - `grok-3-beta` - Grok 3 Beta with reasoning capabilities
  - `grok-3-mini-beta` - Smaller, faster Grok 3 variant

  See `config/models/xai.yml` for the full list of models.

  ## Features

  - ✅ Streaming support
  - ✅ Function calling
  - ✅ Vision support (for vision models)
  - ✅ Web search capabilities
  - ✅ Structured outputs
  - ✅ Tool choice
  - ✅ Reasoning (Grok-3 models)

  ## Example

      # Basic chat
      {:ok, response} = ExLLM.chat(:xai, [
        %{role: "user", content: "What is the meaning of life?"}
      ])

      # With vision
      {:ok, response} = ExLLM.chat(:xai, [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,..."}}
          ]
        }
      ], model: "grok-2-vision-1212")

      # Function calling
      {:ok, response} = ExLLM.chat(:xai, messages,
        model: "grok-beta",
        tools: [weather_tool],
        tool_choice: "auto"
      )
  """

  @behaviour ExLLM.Adapter

  alias ExLLM.{ConfigProvider, Types}

  alias ExLLM.Providers.Shared.{
    ErrorHandler,
    HTTPClient,
    Validation
  }

  @base_url "https://api.x.ai/v1"
  @timeout 300_000

  @impl true
  def chat(messages, options \\ []) do
    with {:ok, config} <- get_config(options),
         {:ok, _} <- Validation.validate_api_key(config.api_key),
         model <- Keyword.get(options, :model, config.model) || default_model(),
         formatted_messages = messages,
         {:ok, request_body} <- build_request_body(formatted_messages, model, options) do
      headers = build_headers(config)

      case HTTPClient.post_json("#{@base_url}/chat/completions", request_body, headers,
             timeout: @timeout
           ) do
        {:ok, response} ->
          parse_response(response, model)

        {:error, {:api_error, %{status: status, body: body}}} ->
          ErrorHandler.handle_provider_error(:xai, status, body)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def stream_chat(messages, options \\ []) do
    with {:ok, config} <- get_config(options),
         {:ok, _} <- Validation.validate_api_key(config.api_key),
         model <- Keyword.get(options, :model, config.model) || default_model(),
         formatted_messages = messages,
         {:ok, request_body} <- build_request_body(formatted_messages, model, options) do
      headers = build_headers(config)
      url = "#{@base_url}/chat/completions"
      parent = self()
      ref = make_ref()

      # Start streaming task
      Task.start(fn ->
        HTTPClient.stream_request(
          url,
          request_body,
          headers,
          fn chunk -> send(parent, {ref, {:chunk, chunk}}) end,
          on_error: fn status, body ->
            send(parent, {ref, {:error, ErrorHandler.handle_provider_error(:xai, status, body)}})
          end
        )

        # Signal stream completion
        send(parent, {ref, :done})
      end)

      # Create stream that processes chunks
      stream =
        Stream.resource(
          fn -> {ref, model, ""} end,
          fn {ref, model, buffer} = state ->
            receive do
              {^ref, {:chunk, data}} ->
                # Accumulate data and parse SSE events
                new_buffer = buffer <> data
                {events, remaining} = extract_sse_events(new_buffer)

                chunks =
                  Enum.flat_map(events, fn event ->
                    case parse_sse_event(event, model) do
                      {:ok, chunk} -> [chunk]
                      _ -> []
                    end
                  end)

                {chunks, {ref, model, remaining}}

              {^ref, :done} ->
                {:halt, state}

              {^ref, {:error, error}} ->
                throw(error)
            after
              100 -> {[], state}
            end
          end,
          fn _ -> :ok end
        )

      {:ok, stream}
    end
  end

  @impl true
  def list_models(_options \\ []) do
    # X.AI doesn't provide a models endpoint, so we return our configured models
    models = ExLLM.ModelConfig.get_all_models(:xai)

    formatted_models =
      Enum.map(models, fn {id, model_data} ->
        # Convert string capabilities to atoms safely
        capabilities =
          model_data
          |> Map.get(:capabilities, [])
          |> Enum.map(fn
            cap when is_binary(cap) ->
              # Only convert known capability atoms
              case cap do
                "chat" -> :chat
                "streaming" -> :streaming
                "function_calling" -> :function_calling
                "vision" -> :vision
                "audio" -> :audio
                "embeddings" -> :embeddings
                "reasoning" -> :reasoning
                _ -> nil
              end

            cap when is_atom(cap) ->
              cap
          end)
          |> Enum.filter(&(&1 != nil))

        %Types.Model{
          id: to_string(id),
          name: "X.AI " <> format_model_name(to_string(id)),
          context_window: Map.get(model_data, :context_window, 131_072),
          max_output_tokens: Map.get(model_data, :max_output_tokens),
          capabilities: capabilities
        }
      end)

    {:ok, formatted_models}
  end

  @impl true
  def embeddings(_input, _options \\ []) do
    {:error, {:not_supported, "X.AI does not currently support embeddings"}}
  end

  @impl true
  def list_embedding_models(_options \\ []) do
    # X.AI doesn't support embeddings yet
    {:ok, []}
  end

  def function_call(messages, functions, options \\ []) do
    # X.AI supports function calling through the tools parameter
    tools =
      Enum.map(functions, fn function ->
        %{
          type: "function",
          function: function
        }
      end)

    options =
      options
      |> Keyword.put(:tools, tools)
      |> Keyword.put_new(:tool_choice, "auto")

    chat(messages, options)
  end

  @impl true
  def configured?(options \\ []) do
    config_provider = Keyword.get(options, :config_provider, ConfigProvider.Env)

    api_key =
      if is_atom(config_provider) do
        config_provider.get(:xai, :api_key)
      else
        # It's a pid (Static provider)
        ExLLM.ConfigProvider.Static.get(config_provider, [:xai, :api_key])
      end

    not is_nil(api_key) and api_key != ""
  end

  @impl true
  def default_model(_options \\ []) do
    ExLLM.ModelConfig.get_default_model(:xai) || "xai/grok-beta"
  end

  # Private functions

  defp get_config(options) do
    config_provider = Keyword.get(options, :config_provider, ConfigProvider.Env)

    config = %{
      api_key: config_provider.get(:xai, :api_key),
      model: Keyword.get(options, :model)
    }

    {:ok, config}
  end

  defp build_headers(config) do
    [
      {"Authorization", "Bearer #{config.api_key}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp build_request_body(messages, model, options) do
    body = %{
      model: model,
      messages: messages,
      stream: Keyword.get(options, :stream, false),
      temperature: Keyword.get(options, :temperature, 0.7),
      max_tokens: Keyword.get(options, :max_tokens),
      top_p: Keyword.get(options, :top_p),
      frequency_penalty: Keyword.get(options, :frequency_penalty),
      presence_penalty: Keyword.get(options, :presence_penalty),
      n: Keyword.get(options, :n, 1)
    }

    # Add optional parameters
    body =
      if tools = Keyword.get(options, :tools) do
        body
        |> Map.put(:tools, tools)
        |> Map.put(:tool_choice, Keyword.get(options, :tool_choice, "auto"))
      else
        body
      end

    body =
      if response_format = Keyword.get(options, :response_format) do
        Map.put(body, :response_format, response_format)
      else
        body
      end

    # Remove nil values
    body =
      body
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.into(%{})

    {:ok, body}
  end

  defp parse_response(response, model) do
    case response do
      %{"choices" => [%{"message" => message} | _]} = response ->
        usage = Map.get(response, "usage", %{})

        # Handle function calls
        content =
          if function_call = Map.get(message, "tool_calls") do
            # Format tool calls for compatibility
            tool_calls =
              Enum.map(function_call, fn call ->
                %{
                  id: Map.get(call, "id"),
                  type: Map.get(call, "type", "function"),
                  function: %{
                    name: get_in(call, ["function", "name"]),
                    arguments: get_in(call, ["function", "arguments"])
                  }
                }
              end)

            %{
              tool_calls: tool_calls,
              content: Map.get(message, "content")
            }
          else
            Map.get(message, "content", "")
          end

        llm_response = %Types.LLMResponse{
          content: content,
          model: model,
          usage: %{
            input_tokens: Map.get(usage, "prompt_tokens", 0),
            output_tokens: Map.get(usage, "completion_tokens", 0)
          },
          cost: calculate_cost(usage, model)
        }

        {:ok, llm_response}

      error ->
        {:error, {:invalid_response, error}}
    end
  end

  defp extract_sse_events(buffer) do
    # Split buffer into events based on double newlines
    parts = String.split(buffer, "\n\n", trim: true)

    # Check if the last part is complete (ends with newline)
    case List.last(parts) do
      nil ->
        {[], buffer}

      last_part ->
        if String.ends_with?(buffer, "\n\n") do
          # All parts are complete events
          {parts, ""}
        else
          # Last part is incomplete
          {Enum.slice(parts, 0..-2//1), last_part}
        end
    end
  end

  defp parse_sse_event(event, model) do
    # Extract data from SSE event
    case Regex.run(~r/^data: (.+)$/m, event) do
      [_, "[DONE]"] ->
        {:ok, :done}

      [_, json_data] ->
        parse_json_event(json_data, model)

      _ ->
        {:error, :invalid_event}
    end
  end

  defp parse_json_event(json_data, model) do
    case Jason.decode(json_data) do
      {:ok, decoded} ->
        parse_decoded_event(decoded, model)

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp parse_decoded_event(%{"choices" => [%{"delta" => delta} | _]}, model) do
    chunk_data = build_chunk_data(delta)

    {:ok,
     %Types.StreamChunk{
       content: chunk_data,
       model: model,
       finish_reason: nil
     }}
  end

  defp parse_decoded_event(%{"choices" => [%{"finish_reason" => reason} | _]}, model)
       when not is_nil(reason) do
    # Final chunk with finish reason
    {:ok,
     %Types.StreamChunk{
       content: "",
       model: model,
       finish_reason: reason
     }}
  end

  defp parse_decoded_event(_, _model) do
    {:error, :invalid_chunk}
  end

  defp build_chunk_data(delta) do
    content = Map.get(delta, "content", "")

    case Map.get(delta, "tool_calls") do
      nil ->
        content

      tool_calls ->
        function_calls = Enum.map(tool_calls, &format_tool_call/1)
        %{content: content, tool_calls: function_calls}
    end
  end

  defp format_tool_call(call) do
    %{
      index: Map.get(call, "index"),
      id: Map.get(call, "id"),
      type: Map.get(call, "type"),
      function: Map.get(call, "function")
    }
  end

  defp calculate_cost(usage, model) do
    model_config = ExLLM.ModelConfig.get_model_config(:xai, model)

    if model_config && model_config.pricing do
      input_tokens = Map.get(usage, "prompt_tokens", 0)
      output_tokens = Map.get(usage, "completion_tokens", 0)

      input_cost = input_tokens * model_config.pricing.input / 1_000_000
      output_cost = output_tokens * model_config.pricing.output / 1_000_000

      %{
        input: input_cost,
        output: output_cost,
        total: input_cost + output_cost
      }
    else
      %{input: 0.0, output: 0.0, total: 0.0}
    end
  end

  defp format_model_name(model_id) do
    model_id
    |> String.replace("xai/", "")
    |> String.replace("-", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
