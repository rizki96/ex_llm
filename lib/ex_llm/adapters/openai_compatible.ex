defmodule ExLLM.Adapters.OpenAICompatible do
  alias ExLLM.{Types, ModelConfig}
  alias ExLLM.Adapters.Shared.{ConfigHelper, HTTPClient, ErrorHandler, MessageFormatter, StreamingBehavior}
  
  @moduledoc """
  Base implementation for OpenAI-compatible API providers.
  
  Many LLM providers follow OpenAI's API format, allowing for shared implementation.
  This module provides common functionality that can be reused across providers.
  
  ## Usage
  
  Create a new adapter by using this module:
  
      defmodule ExLLM.Adapters.MyProvider do
        use ExLLM.Adapters.OpenAICompatible,
          provider: :my_provider,
          base_url: "https://api.myprovider.com/v1",
          models: ["model-1", "model-2"]
          
        # Override any functions as needed
        defp transform_request(request, _options) do
          # Custom request transformation
          request
        end
      end
  """

  @doc """
  Defines callbacks for OpenAI-compatible adapters.
  """
  @callback get_base_url(config :: map()) :: String.t()
  @callback get_api_key(config :: map()) :: String.t() | nil
  @callback transform_request(request :: map(), options :: keyword()) :: map()
  @callback transform_response(response :: map(), options :: keyword()) :: map()
  @callback get_headers(api_key :: String.t(), options :: keyword()) :: list({String.t(), String.t()})
  @callback parse_error(response :: map()) :: {:error, term()}
  @callback filter_model(model :: map()) :: boolean()
  @callback parse_model(model :: map()) :: Types.Model.t()

  # Common helper functions that can be used by any adapter
  
  @doc """
  Formats a model ID into a human-readable name.
  """
  def format_model_name(model_id) do
    model_id
    |> String.split(["-", "_", "/"])
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  
  @doc """
  Default model transformer for configuration data.
  """
  def default_model_transformer(model_id, config) do
    %Types.Model{
      id: to_string(model_id),
      name: format_model_name(to_string(model_id)),
      description: "Model: #{to_string(model_id)}",
      context_window: Map.get(config, :context_window, 4096),
      capabilities: %{
        supports_streaming: :streaming in Map.get(config, :capabilities, []),
        supports_functions: :function_calling in Map.get(config, :capabilities, []),
        supports_vision: :vision in Map.get(config, :capabilities, []),
        features: Map.get(config, :capabilities, [])
      }
    }
  end

  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)
    default_base_url = Keyword.get(opts, :base_url)
    supported_models = Keyword.get(opts, :models, [])
    
    quote do
      @behaviour ExLLM.Adapter
      @behaviour ExLLM.Adapters.OpenAICompatible
      @behaviour ExLLM.Adapters.Shared.StreamingBehavior
      
      alias ExLLM.{Error, Types, ModelConfig}
      alias ExLLM.Adapters.Shared.{ConfigHelper, HTTPClient, ErrorHandler, MessageFormatter, StreamingBehavior}
      require Logger
      
      @provider unquote(provider)
      @default_base_url unquote(default_base_url)
      @supported_models unquote(supported_models)
      
      # Default implementations
      
      @impl ExLLM.Adapter
      def chat(messages, options \\ []) do
        with :ok <- MessageFormatter.validate_messages(messages),
             config_provider <- ConfigHelper.get_config_provider(options),
             config <- ConfigHelper.get_config(@provider, config_provider),
             api_key <- get_api_key(config),
             {:ok, _} <- validate_api_key(api_key) do
          
          do_chat(messages, options, config, api_key)
        end
      end
      
      defp validate_api_key(nil), do: {:error, "#{provider_name()} API key not configured"}
      defp validate_api_key(""), do: {:error, "#{provider_name()} API key not configured"}
      defp validate_api_key(_), do: {:ok, :valid}
      
      @impl ExLLM.Adapter
      def stream_chat(messages, options \\ [], callback) when is_function(callback, 1) do
        config_provider = get_config_provider(options)
        config = get_config(config_provider)
        
        api_key = get_api_key(config)
        if !api_key || api_key == "" do
          {:error, "#{provider_name()} API key not configured"}
        else
          do_stream_chat(messages, options, callback, config, api_key)
        end
      end
      
      @impl ExLLM.Adapter
      def configured?(options \\ []) do
        config_provider = get_config_provider(options)
        config = get_config(config_provider)
        
        case get_api_key(config) do
          nil -> false
          "" -> false
          _ -> true
        end
      end
      
      @impl ExLLM.Adapter
      def list_models(options \\ []) do
        config_provider = get_config_provider(options)
        config = get_config(config_provider)
        
        # Use ModelLoader with API fetching by default
        ExLLM.ModelLoader.load_models(provider_atom(),
          Keyword.merge(options, [
            api_fetcher: fn(_opts) -> fetch_models_from_api(config) end,
            config_transformer: &default_model_transformer/2
          ])
        )
      end
      
      # Common implementation functions
      
      defp do_chat(messages, options, config, api_key) do
        model = Keyword.get(options, :model, get_default_model(config))
        
        request = build_chat_request(messages, model, options)
        request = transform_request(request, options)
        
        headers = get_headers(api_key, options)
        url = "#{get_base_url(config)}/chat/completions"
        
        case send_request(url, request, headers) do
          {:ok, response} ->
            response = transform_response(response, options)
            parse_chat_response(response, model, options)
          {:error, error} ->
            handle_error(error)
        end
      end
      
      defp do_stream_chat(messages, options, callback, config, api_key) do
        model = Keyword.get(options, :model, get_default_model(config))
        
        request = build_chat_request(messages, model, options)
        request = Map.put(request, "stream", true)
        request = transform_request(request, options)
        
        headers = get_headers(api_key, options)
        url = "#{get_base_url(config)}/chat/completions"
        
        stream_id = generate_stream_id()
        
        Task.async(fn ->
          send_stream_request(url, request, headers, callback, stream_id)
        end)
        
        {:ok, stream_id}
      end
      
      
      defp build_chat_request(messages, model, options) do
        request = %{
          "model" => model,
          "messages" => format_messages(messages)
        }
        
        # Add optional parameters
        request = add_optional_param(request, options, :temperature, "temperature")
        request = add_optional_param(request, options, :max_tokens, "max_tokens")
        request = add_optional_param(request, options, :top_p, "top_p")
        request = add_optional_param(request, options, :frequency_penalty, "frequency_penalty")
        request = add_optional_param(request, options, :presence_penalty, "presence_penalty")
        request = add_optional_param(request, options, :stop, "stop")
        request = add_optional_param(request, options, :user, "user")
        
        # Handle functions/tools
        if functions = Keyword.get(options, :functions) do
          request = Map.put(request, "tools", format_tools(functions))
          request = Map.put(request, "tool_choice", "auto")
        end
        
        request
      end
      
      defp format_messages(messages) do
        Enum.map(messages, fn msg ->
          %{
            "role" => to_string(msg.role || msg["role"]),
            "content" => to_string(msg.content || msg["content"])
          }
        end)
      end
      
      defp format_tools(functions) do
        Enum.map(functions, fn func ->
          %{
            "type" => "function",
            "function" => %{
              "name" => func[:name] || func["name"],
              "description" => func[:description] || func["description"],
              "parameters" => func[:parameters] || func["parameters"]
            }
          }
        end)
      end
      
      defp add_optional_param(request, options, key, param_name) do
        case Keyword.get(options, key) do
          nil -> request
          value -> Map.put(request, param_name, value)
        end
      end
      
      defp send_request(url, body, headers, method \\ :post) do
        opts = [
          headers: headers,
          receive_timeout: 60_000
        ]
        
        case method do
          :get ->
            Req.get(url, opts)
          :post ->
            Req.post(url, [json: body] ++ opts)
        end
        |> case do
          {:ok, %{status: status, body: body}} when status in 200..299 ->
            {:ok, body}
          {:ok, %{status: status, body: body}} ->
            {:error, %{status: status, body: body}}
          {:error, reason} ->
            {:error, %{network_error: reason}}
        end
      end
      
      defp send_stream_request(url, body, headers, callback, stream_id) do
        parent = self()
        
        Req.post(url, 
          json: body,
          headers: headers,
          receive_timeout: 60_000,
          into: fn {:data, data}, acc ->
            process_stream_chunk(data, callback, acc)
          end
        )
        |> case do
          {:ok, _} ->
            callback.(%Types.StreamChunk{
              content: "",
              finish_reason: "stop"
            })
          {:error, reason} ->
            Logger.error("Stream error: #{inspect(reason)}")
            callback.(%Types.StreamChunk{
              content: "Stream error: #{inspect(reason)}",
              finish_reason: "error"
            })
        end
      end
      
      defp process_stream_chunk(data, callback, buffer) do
        lines = String.split(buffer <> data, "\n")
        {complete_lines, [last_line]} = Enum.split(lines, -1)
        
        Enum.each(complete_lines, fn line ->
          case parse_sse_line(line) do
            {:ok, chunk_data} ->
              case parse_stream_chunk(chunk_data) do
                {:ok, chunk} -> callback.(chunk)
                _ -> :ok
              end
            _ ->
              :ok
          end
        end)
        
        {:cont, last_line}
      end
      
      defp parse_sse_line(line) do
        line = String.trim(line)
        
        cond do
          line == "" -> :skip
          String.starts_with?(line, "data: [DONE]") -> :done
          String.starts_with?(line, "data: ") ->
            json_str = String.replace_prefix(line, "data: ", "")
            case Jason.decode(json_str) do
              {:ok, data} -> {:ok, data}
              _ -> :skip
            end
          true -> :skip
        end
      end
      
      # Streaming behavior callback implementation
      @impl ExLLM.Adapters.Shared.StreamingBehavior
      def parse_stream_chunk(data) when is_binary(data) do
        case Jason.decode(data) do
          {:ok, parsed} -> parse_stream_chunk(parsed)
          {:error, _} -> {:error, :invalid_json}
        end
      end
      
      def parse_stream_chunk(data) when is_map(data) do
        case get_in(data, ["choices", Access.at(0), "delta"]) do
          nil -> 
            {:ok, StreamingBehavior.create_text_chunk("")}
          delta ->
            content = Map.get(delta, "content", "")
            finish_reason = get_in(data, ["choices", Access.at(0), "finish_reason"])
            
            chunk = StreamingBehavior.create_text_chunk(content, finish_reason: finish_reason)
            {:ok, chunk}
        end
      end
      
      defp parse_chat_response(response, model, options) do
        case response do
          %{"choices" => [choice | _], "usage" => usage} ->
            content = get_in(choice, ["message", "content"]) || ""
            finish_reason = choice["finish_reason"]
            
            # Handle function calls
            function_call = get_in(choice, ["message", "function_call"])
            tool_calls = get_in(choice, ["message", "tool_calls"])
            
            response_struct = %Types.LLMResponse{
              content: content,
              model: model,
              finish_reason: finish_reason,
              usage: %{
                input_tokens: usage["prompt_tokens"] || 0,
                output_tokens: usage["completion_tokens"] || 0
              },
              function_call: function_call,
              tool_calls: tool_calls
            }
            
            # Add cost tracking
            response_struct = add_cost_tracking(response_struct, options)
            
            {:ok, response_struct}
          _ ->
            {:error, Error.json_parse_error("Invalid response format")}
        end
      end
      
      # Default filter_model implementation (can be overridden)
      @impl ExLLM.Adapters.OpenAICompatible
      def filter_model(%{"id" => _id}) do
        # Override in specific adapters to filter out non-LLM models
        true
      end
      
      # Legacy parse_model for backward compatibility
      @impl ExLLM.Adapters.OpenAICompatible
      def parse_model(%{"id" => id} = model) do
        parse_api_model(model)
      end
      
      defp add_cost_tracking(response, options) do
        if Keyword.get(options, :track_cost, true) && response.usage do
          cost = ExLLM.Cost.calculate(@provider, response.model, response.usage)
          if Map.has_key?(cost, :error) do
            response
          else
            %{response | cost: cost}
          end
        else
          response
        end
      end
      
      defp handle_error(%{status: status, body: body}) do
        parse_error(%{status: status, body: body})
      end
      
      defp handle_error(%{network_error: reason}) do
        {:error, Error.connection_error(reason)}
      end
      
      defp handle_error(error) do
        {:error, Error.unknown_error(error)}
      end
      
      defp generate_stream_id do
        "stream_#{:erlang.unique_integer([:positive])}"
      end
      
      defp get_config_provider(options) do
        Keyword.get(
          options,
          :config_provider,
          Application.get_env(:ex_llm, :config_provider, ExLLM.ConfigProvider.Default)
        )
      end
      
      defp get_config(config_provider) do
        case config_provider do
          provider when is_atom(provider) ->
            provider.get_all(@provider)
          provider when is_pid(provider) ->
            ExLLM.ConfigProvider.Static.get_all(provider)
            |> Map.get(@provider, %{})
        end
      end
      
      defp get_default_model(config) do
        Map.get(config, :model) || 
        ModelConfig.get_default_model(@provider)
      end
      
      defp get_model_context_window(model_id) do
        ModelConfig.get_context_window(@provider, model_id) || 4096
      end
      
      defp get_model_capabilities(model_id) do
        ModelConfig.get_capabilities(@provider, model_id) || 
        ["streaming", "function_calling"]
      end
      
      defp provider_name do
        @provider |> to_string() |> String.capitalize()
      end
      
      # Default callback implementations (can be overridden)
      
      @impl ExLLM.Adapters.OpenAICompatible
      def get_base_url(config) do
        Map.get(config, :base_url) || @default_base_url
      end
      
      @impl ExLLM.Adapters.OpenAICompatible  
      def get_api_key(config) do
        Map.get(config, :api_key)
      end
      
      @impl ExLLM.Adapters.OpenAICompatible
      def get_headers(api_key, _options) do
        [
          {"authorization", "Bearer #{api_key}"},
          {"content-type", "application/json"}
        ]
      end
      
      @impl ExLLM.Adapters.OpenAICompatible
      def transform_request(request, _options) do
        # Default: no transformation
        request
      end
      
      @impl ExLLM.Adapters.OpenAICompatible
      def transform_response(response, _options) do
        # Default: no transformation
        response
      end
      
      @impl ExLLM.Adapters.OpenAICompatible
      def parse_error(%{status: 401}) do
        {:error, Error.authentication_error("Invalid API key")}
      end
      
      def parse_error(%{status: 429, body: body}) do
        {:error, Error.rate_limit_error(inspect(body))}
      end
      
      def parse_error(%{status: status, body: body}) when status >= 500 do
        {:error, Error.api_error(status, body)}
      end
      
      def parse_error(%{status: status, body: body}) do
        {:error, Error.api_error(status, body)}
      end
      
      # Common helper functions for model management
      
      defp fetch_models_from_api(config) do
        api_key = get_api_key(config)
        
        if !api_key || api_key == "" do
          {:error, "No API key available"}
        else
          headers = get_headers(api_key, [])
          url = "#{get_base_url(config)}/models"
          
          case send_request(url, %{}, headers, :get) do
            {:ok, %{"data" => models}} when is_list(models) ->
              parsed_models = models
              |> Enum.filter(&filter_model/1)
              |> Enum.map(&parse_api_model/1)
              |> Enum.sort_by(& &1.id)
              
              {:ok, parsed_models}
              
            {:ok, _} ->
              {:error, "Invalid API response format"}
              
            {:error, reason} ->
              {:error, "API error: #{inspect(reason)}"}
          end
        end
      end
      
      defp parse_api_model(model) do
        model_id = model["id"]
        
        %Types.Model{
          id: model_id,
          name: format_model_name(model_id),
          description: generate_model_description(model_id),
          context_window: model["context_window"] || get_model_context_window(model_id),
          capabilities: %{
            supports_streaming: true,
            supports_functions: check_function_support(model, model_id),
            supports_vision: check_vision_support(model, model_id),
            features: build_features_list(model, model_id)
          }
        }
      end
      
      
      defp generate_model_description(model_id) do
        "#{provider_name()} model: #{model_id}"
      end
      
      defp check_function_support(model, model_id) do
        model["supports_tools"] || 
        model["supports_functions"] || 
        String.contains?(model_id, ["turbo", "gpt-4", "claude-3", "gemini"])
      end
      
      defp check_vision_support(model, model_id) do
        model["supports_vision"] || 
        String.contains?(model_id, ["vision", "visual", "image", "multimodal"])
      end
      
      defp build_features_list(model, model_id) do
        features = ["streaming"]
        
        if check_function_support(model, model_id) do
          features = ["function_calling" | features]
        end
        
        if check_vision_support(model, model_id) do
          features = ["vision" | features]
        end
        
        if model["supports_system_messages"] != false do
          features = ["system_messages" | features]
        end
        
        features
      end
      
      defp provider_atom do
        @provider
      end
      
      defp ensure_default_model do
        case ModelConfig.get_default_model(@provider) do
          nil ->
            raise "Missing configuration: No default model found for #{provider_name()}. " <>
                  "Please ensure config/models/#{@provider}.yml exists and contains a 'default_model' field."
          model ->
            model
        end
      end
      
      # Allow overriding all functions
      defoverridable [
        chat: 2,
        stream_chat: 3,
        configured?: 1,
        list_models: 1,
        get_base_url: 1,
        get_api_key: 1,
        get_headers: 2,
        transform_request: 2,
        transform_response: 2,
        parse_error: 1,
        filter_model: 1,
        parse_model: 1,
        fetch_models_from_api: 1,
        parse_api_model: 1,
        generate_model_description: 1,
        check_function_support: 2,
        check_vision_support: 2,
        build_features_list: 2
      ]
    end
  end
end