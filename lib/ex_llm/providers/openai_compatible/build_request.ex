defmodule ExLLM.Providers.OpenAICompatible.BuildRequest do
  @moduledoc """
  Shared pipeline plug for building OpenAI-compatible API requests.

  This module provides a configurable implementation that can be used by
  any provider that follows the OpenAI API format. Providers can customize
  behavior by passing configuration options.
  """

  alias ExLLM.Providers.Shared.{ConfigHelper, MessageFormatter}

  @doc """
  Creates a BuildRequest plug for an OpenAI-compatible provider.

  ## Options

  - `:provider` - The provider atom (required)
  - `:base_url_env` - Environment variable for base URL (optional)
  - `:default_base_url` - Default base URL if none configured (required)
  - `:api_key_env` - Environment variable for API key (optional)
  - `:default_temperature` - Default temperature (default: 0.7)
  - `:extra_headers` - Additional headers function (optional)

  ## Example

      defmodule ExLLM.Providers.MyProvider.BuildRequest do
        use ExLLM.Providers.OpenAICompatible.BuildRequest,
          provider: :my_provider,
          base_url_env: "MY_PROVIDER_API_BASE",
          default_base_url: "https://api.myprovider.com/v1",
          api_key_env: "MY_PROVIDER_API_KEY"
      end
  """
  defmacro __using__(opts) do
    provider = Keyword.fetch!(opts, :provider)
    base_url_env = Keyword.get(opts, :base_url_env)
    default_base_url = Keyword.fetch!(opts, :default_base_url)
    api_key_env = Keyword.get(opts, :api_key_env)
    default_temperature = Keyword.get(opts, :default_temperature, 0.7)
    extra_headers = Keyword.get(opts, :extra_headers)

    quote do
      use ExLLM.Plug

      alias ExLLM.Pipeline.Request

      @provider unquote(provider)
      @base_url_env unquote(base_url_env)
      @default_base_url unquote(default_base_url)
      @api_key_env unquote(api_key_env)
      @default_temperature unquote(default_temperature)
      @extra_headers unquote(extra_headers)

      @impl true
      def call(request, _opts) do
        # Extract configuration and API key from request
        config = request.assigns.config || %{}
        api_key = request.assigns.api_key
        messages = request.messages
        options = request.options

        # Determine model (options might be keyword list or map)
        model =
          get_option(
            options,
            :model,
            Map.get(config, :model) || ConfigHelper.ensure_default_model(@provider)
          )

        # Build request body and headers
        body = build_request_body(messages, model, config, options)
        headers = build_headers(api_key, config)
        url = "#{get_base_url(config)}/v1/chat/completions"

        request
        |> Map.put(:provider_request, body)
        |> Request.assign(:model, model)
        |> Request.assign(:request_body, body)
        |> Request.assign(:request_headers, headers)
        |> Request.assign(:request_url, url)
        |> Request.assign(:timeout, 60_000)
      end

      defp build_request_body(messages, model, config, options) do
        # Use OpenAI-compatible format
        %{
          model: model,
          messages: MessageFormatter.stringify_message_keys(messages),
          temperature:
            get_option(
              options,
              :temperature,
              Map.get(config, :temperature, @default_temperature)
            )
        }
        |> maybe_add_max_tokens(options, config)
        |> maybe_add_parameters(options)
        |> maybe_add_streaming_options(options)
        |> maybe_add_system_prompt(options)
      end

      defp build_headers(api_key, config) do
        base_headers = [
          {"authorization", "Bearer #{api_key}"}
        ]

        # Add extra headers if defined
        if @extra_headers && function_exported?(__MODULE__, @extra_headers, 2) do
          apply(__MODULE__, @extra_headers, [base_headers, config])
        else
          base_headers
        end
      end

      defp get_base_url(config) do
        Map.get(config, :base_url) ||
          (@base_url_env && System.get_env(@base_url_env)) ||
          @default_base_url
      end

      defp maybe_add_system_prompt(body, options) do
        case get_option(options, :system) do
          nil -> body
          system -> Map.update!(body, :messages, &MessageFormatter.add_system_message(&1, system))
        end
      end

      defp maybe_add_max_tokens(body, options, config) do
        case get_option(options, :max_tokens) || Map.get(config, :max_tokens) do
          nil -> body
          max_tokens -> Map.put(body, :max_tokens, max_tokens)
        end
      end

      defp maybe_add_parameters(body, options) do
        body
        |> maybe_add_param(:top_p, options)
        |> maybe_add_param(:frequency_penalty, options)
        |> maybe_add_param(:presence_penalty, options)
        |> maybe_add_param(:stop, options)
        |> maybe_add_param(:user, options)
        |> maybe_add_param(:seed, options)
        |> maybe_add_param(:response_format, options)
        |> maybe_add_param(:tools, options)
      end

      defp maybe_add_streaming_options(body, options) do
        case get_option(options, :stream) do
          true -> Map.put(body, :stream, true)
          _ -> body
        end
      end

      defp maybe_add_param(body, key, options) do
        case get_option(options, key) do
          nil -> body
          value -> Map.put(body, key, value)
        end
      end

      # Helper to safely get values from keyword list or map
      defp get_option(options, key, default \\ nil) do
        cond do
          is_map(options) -> Map.get(options, key, default)
          Keyword.keyword?(options) -> Keyword.get(options, key, default)
          true -> default
        end
      end

      # Allow overriding
      defoverridable build_request_body: 4, build_headers: 2, get_base_url: 1
    end
  end
end
