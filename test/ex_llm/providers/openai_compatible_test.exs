defmodule ExLLM.Providers.OpenAICompatibleTest do
  use ExUnit.Case, async: false

  alias ExLLM.Infrastructure.ConfigProvider.Static
  alias ExLLM.Providers.OpenAICompatible
  alias ExLLM.Types
  alias ExLLM.Testing.ConfigProviderHelper

  # This module defines a shared test suite for any provider that implements
  # the OpenAICompatible behavior. It tests the common contract for chat,
  # streaming, configuration, and error handling.

  # A mock provider to demonstrate testing of provider-specific features.
  defmodule FakeMistral do
    use ExLLM.Providers.OpenAICompatible,
      provider: :fake_mistral,
      base_url: "http://localhost/v1",
      models: ["mistral-model"]

    # Override to add special params not in the base OpenAI spec
    @impl OpenAICompatible
    def transform_request(request, options) do
      request
      |> add_optional_param(options, :safe_prompt, "safe_prompt")
      |> add_optional_param(options, :random_seed, "random_seed")
    end

    # Required callbacks
    @impl ExLLM.Provider
    def default_model(), do: "mistral-model"

    # Override to avoid loading from config file
    defoverridable ensure_default_model: 0

    defp ensure_default_model do
      "mistral-model"
    end

    # These are not callbacks, they're helper functions
    def default_model_transformer(model, _options), do: model
    def format_model_name(model), do: model
  end

  # List of providers to test.
  # Format: {Module, :atom, %{special_options}, [:special_features_to_test]}
  @providers [
    {ExLLM.Providers.Groq, :groq, %{}, []},
    {ExLLM.Providers.XAI, :xai, %{}, []},
    {FakeMistral, :fake_mistral, %{safe_prompt: true, random_seed: 123},
     [:safe_prompt, :random_seed]}
  ]

  setup do
    # Disable Tesla.Mock for these tests since they use Bypass
    original_mock_setting = Application.get_env(:ex_llm, :use_tesla_mock, false)
    Application.put_env(:ex_llm, :use_tesla_mock, false)

    bypass = Bypass.open()

    on_exit(fn ->
      Application.put_env(:ex_llm, :use_tesla_mock, original_mock_setting)
    end)

    %{bypass: bypass, base_url: "http://localhost:#{bypass.port}/v1"}
  end

  # Generate tests for each provider listed in @providers
  for {provider_module, provider_atom, special_opts, special_features} <- @providers do
    describe "#{provider_module}" do
      setup %{bypass: _bypass, base_url: base_url} do
        config = %{
          unquote(provider_atom) => %{
            api_key: "test-key",
            base_url: base_url
          }
        }

        {:ok, pid} = Static.start_link(config)
        %{config_provider: pid}
      end

      test "configured?/1 returns true with API key", %{config_provider: pid} do
        assert unquote(provider_module).configured?(config_provider: pid)
      end

      test "configured?/1 returns false without API key" do
        restore_env = ConfigProviderHelper.disable_env_api_keys()

        try do
          {:ok, pid} = Static.start_link(%{unquote(provider_atom) => %{}})
          refute unquote(provider_module).configured?(config_provider: pid)
        after
          restore_env.()
        end
      end

      test "list_models/1 fetches and parses models", %{bypass: bypass, config_provider: pid} do
        # Some providers (like XAI) override list_models completely and don't use API fetching
        if unquote(provider_atom) in [:xai] do
          {:ok, models} = unquote(provider_module).list_models(config_provider: pid)
          assert is_list(models)
          assert length(models) > 0
          # Just verify basic structure for providers that use static configs
          first_model = List.first(models)
          assert %Types.Model{} = first_model
          assert is_binary(first_model.id)
        else
          response_body = """
          {
            "object": "list",
            "data": [
              { "id": "model-1", "object": "model" },
              { "id": "model-2-vision", "object": "model" },
              { "id": "whisper-large-v3", "object": "model" }
            ]
          }
          """

          Bypass.stub(bypass, "GET", "/v1/models", fn conn ->
            Plug.Conn.resp(conn, 200, response_body)
          end)

          {:ok, models} = unquote(provider_module).list_models(config_provider: pid, source: :api)

          assert is_list(models)

          # Groq provider has a filter_model/1 implementation that removes non-LLM models.
          if unquote(provider_atom) == :groq do
            refute Enum.any?(models, &(&1.id == "whisper-large-v3"))
            assert length(models) == 2
          else
            assert Enum.any?(models, &(&1.id == "whisper-large-v3"))
            assert length(models) == 3
          end

          model1 = Enum.find(models, &(&1.id == "model-1"))
          assert %Types.Model{} = model1
          assert model1.capabilities.supports_vision == false
          model2 = Enum.find(models, &(&1.id == "model-2-vision"))
          assert %Types.Model{} = model2
          assert model2.capabilities.supports_vision == true
        end
      end

      test "chat/2 sends a valid request and parses response", %{
        bypass: bypass,
        config_provider: pid
      } do
        test_pid = self()

        Bypass.stub(bypass, "POST", "/v1/chat/completions", fn conn ->
          # Capture request details
          {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
          body = Jason.decode!(raw_body)

          # Send request details to test process
          send(
            test_pid,
            {:request_captured, conn.method, conn.request_path, conn.req_headers, body}
          )

          Plug.Conn.resp(conn, 200, """
          {
            "id": "chatcmpl-123", "object": "chat.completion", "created": 1677652288, "model": "test-model",
            "choices": [{"index": 0, "message": {"role": "assistant", "content": "Hello there!"}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 9, "completion_tokens": 12, "total_tokens": 21}
          }
          """)
        end)

        messages = [%{role: "user", content: "Hi"}]

        {:ok, response} =
          unquote(provider_module).chat(messages, model: "test-model", config_provider: pid)

        assert %Types.LLMResponse{} = response
        assert response.content == "Hello there!"
        assert response.finish_reason == "stop"
        assert response.usage.total_tokens == 21

        # Verify request details
        assert_receive {:request_captured, method, path, headers, body}
        assert method == "POST"
        assert path == "/v1/chat/completions"
        assert {"authorization", "Bearer test-key"} in headers
        assert body["model"] == "test-model"
        assert body["messages"] == [%{"role" => "user", "content" => "Hi"}]
      end

      test "chat/2 with common options sends correct request body", %{
        bypass: bypass,
        config_provider: pid
      } do
        test_pid = self()

        Bypass.stub(bypass, "POST", "/v1/chat/completions", fn conn ->
          # Capture request details
          {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
          body = Jason.decode!(raw_body)

          # Send body to test process
          send(test_pid, {:request_body, body})

          Plug.Conn.resp(conn, 200, """
          {
            "id": "chatcmpl-123", "object": "chat.completion", "created": 1677652288, "model": "test-model",
            "choices": [{"index": 0, "message": {"role": "assistant", "content": ""}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}
          }
          """)
        end)

        options = [
          model: "test-model",
          temperature: 3.0,
          max_tokens: 100,
          top_p: 0.9,
          stop: ["stop1", "stop2", "stop3", "stop4", "stop5"],
          config_provider: pid
        ]

        :ok = unquote(provider_module).chat([%{role: "user", content: "Hi"}], options) |> elem(0)

        assert_receive {:request_body, body}

        # Groq has special handling in its transform_request/2 override
        if unquote(provider_atom) == :groq do
          assert body["temperature"] == 2.0
          assert body["stop"] == ["stop1", "stop2", "stop3", "stop4"]
        else
          assert body["temperature"] == 3.0
          assert body["stop"] == ["stop1", "stop2", "stop3", "stop4", "stop5"]
        end

        assert body["max_tokens"] == 100
        assert body["top_p"] == 0.9
      end

      test "stream_chat/2 sends a streaming request", %{bypass: bypass, config_provider: pid} do
        Bypass.stub(bypass, "POST", "/v1/chat/completions", fn conn ->
          {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
          body = Jason.decode!(raw_body)
          assert body["stream"] == true
          Plug.Conn.resp(conn, 200, "data: [DONE]\n\n")
        end)

        messages = [%{role: "user", content: "Hi"}]

        {:ok, stream} =
          unquote(provider_module).stream_chat(messages,
            model: "test-model",
            config_provider: pid
          )

        # Stream.resource/3 returns a function, not a %Stream{} struct
        assert is_function(stream)
      end

      test "parse_stream_chunk/1 correctly parses SSE data" do
        provider_module = unquote(provider_module)

        content_json = ~s|{"choices":[{"delta":{"content":"Hello"}}],"id":"1"}|
        {:ok, content_chunk} = provider_module.parse_stream_chunk(content_json)
        assert %ExLLM.Types.StreamChunk{content: "Hello", finish_reason: nil} = content_chunk

        finish_json = ~s|{"choices":[{"delta":{}, "finish_reason":"stop"}],"id":"1"}|
        {:ok, finish_chunk} = provider_module.parse_stream_chunk(finish_json)
        assert %ExLLM.Types.StreamChunk{content: "", finish_reason: "stop"} = finish_chunk

        assert {:error, :invalid_json} = provider_module.parse_stream_chunk("not json")
      end

      # Error handling
      test "chat/2 handles authentication error (401)", %{bypass: bypass, config_provider: pid} do
        Bypass.stub(bypass, "POST", "/v1/chat/completions", fn conn ->
          Plug.Conn.resp(conn, 401, ~s|{"error": "Invalid API key"}|)
        end)

        {:error, error} =
          unquote(provider_module).chat([%{role: "user", content: "Hi"}], config_provider: pid)

        # Handle both direct error maps and nested error structures
        case error do
          %{type: :authentication_error} ->
            :ok

          %{error: %{type: :authentication_error}} ->
            :ok

          {:connection_failed, %{type: :authentication_error, status_code: 401}} ->
            :ok

          {:connection_failed, %{type: :authentication_error}} ->
            :ok

          other ->
            # Check if it contains authentication error anywhere in the structure
            error_str = inspect(error)

            if String.contains?(error_str, "authentication_error") or
                 String.contains?(error_str, "Invalid API key") or
                 String.contains?(error_str, "status: 401") do
              :ok
            else
              flunk("Expected authentication error, got: #{inspect(other)}")
            end
        end
      end

      test "chat/2 handles rate limit error (429)", %{bypass: bypass, config_provider: pid} do
        Bypass.stub(bypass, "POST", "/v1/chat/completions", fn conn ->
          Plug.Conn.resp(conn, 429, ~s|{"error": "Rate limit exceeded"}|)
        end)

        {:error, error} =
          unquote(provider_module).chat([%{role: "user", content: "Hi"}], config_provider: pid)

        # Handle both direct error maps and nested error structures
        case error do
          %{type: :rate_limit_error} ->
            :ok

          %{error: %{type: :rate_limit_error}} ->
            :ok

          {:connection_failed, %{type: :rate_limit_error, status_code: 429}} ->
            :ok

          {:connection_failed, %{type: :rate_limit_error}} ->
            :ok

          other ->
            # Check if it contains rate limit error anywhere in the structure
            error_str = inspect(error)

            if String.contains?(error_str, "rate_limit_error") or
                 String.contains?(error_str, "Rate limit exceeded") or
                 String.contains?(error_str, "status: 429") do
              :ok
            else
              flunk("Expected rate limit error, got: #{inspect(other)}")
            end
        end
      end

      test "chat/2 handles server error (500)", %{bypass: bypass, config_provider: pid} do
        Bypass.stub(bypass, "POST", "/v1/chat/completions", fn conn ->
          Plug.Conn.resp(conn, 500, "Internal Server Error")
        end)

        {:error, error} =
          unquote(provider_module).chat([%{role: "user", content: "Hi"}], config_provider: pid)

        # Handle both direct error maps and nested error structures
        case error do
          %{type: :api_error, status_code: 500} ->
            :ok

          %{error: %{type: :api_error, status_code: 500}} ->
            :ok

          {:connection_failed, %{type: :api_error, status_code: 500}} ->
            :ok

          {:connection_failed, %{status_code: 500}} ->
            :ok

          other ->
            # Check if it contains server error anywhere in the structure
            error_str = inspect(error)

            if String.contains?(error_str, "api_error") or
                 String.contains?(error_str, "Internal Server Error") or
                 String.contains?(error_str, "status: 500") do
              :ok
            else
              flunk("Expected API error with status 500, got: #{inspect(other)}")
            end
        end
      end

      # Provider-specific feature tests
      if length(special_features) > 0 do
        test "chat/2 with special options sends correct request body", %{
          bypass: bypass,
          config_provider: pid
        } do
          test_pid = self()

          Bypass.stub(bypass, "POST", "/v1/chat/completions", fn conn ->
            # Capture request details
            {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
            body = Jason.decode!(raw_body)

            # Send body to test process
            send(test_pid, {:request_body, body})

            Plug.Conn.resp(conn, 200, """
            {
              "id": "chatcmpl-123", "object": "chat.completion", "created": 1677652288, "model": "test-model",
              "choices": [{"index": 0, "message": {"role": "assistant", "content": ""}, "finish_reason": "stop"}],
              "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}
            }
            """)
          end)

          options =
            [model: "test-model", config_provider: pid]
            |> Keyword.merge(Enum.to_list(unquote(Macro.escape(special_opts))))

          :ok =
            unquote(provider_module).chat([%{role: "user", content: "Hi"}], options) |> elem(0)

          assert_receive {:request_body, body}

          for {key, value} <- unquote(Macro.escape(special_opts)) do
            assert body[to_string(key)] == value
          end
        end
      end
    end
  end
end
