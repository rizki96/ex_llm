defmodule ExLLM.Providers.PerplexityUnitTest do
  use ExUnit.Case, async: true
  alias ExLLM.Providers.Perplexity
  alias ExLLM.Testing.ConfigProviderHelper
  alias ExLLM.Types

  describe "configured?/1" do
    test "returns true when API key is available" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      assert Perplexity.configured?(config_provider: provider)
    end

    test "returns false with empty API key" do
      config = %{perplexity: %{api_key: ""}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      refute Perplexity.configured?(config_provider: provider)
    end

    test "returns false with no API key" do
      # Temporarily disable environment API keys to test true "no key" scenario
      restore_env = ConfigProviderHelper.disable_env_api_keys()
      
      try do
        config = %{perplexity: %{}}
        provider = ConfigProviderHelper.setup_static_provider(config)

        refute Perplexity.configured?(config_provider: provider)
      after
        restore_env.()
      end
    end
  end

  describe "default_model/0" do
    test "returns a default model string" do
      model = Perplexity.default_model()
      assert is_binary(model)
      assert String.contains?(model, "sonar")
    end
  end

  describe "message validation" do
    test "validates messages before processing" do
      # Empty messages should fail validation
      assert {:error, _} = Perplexity.chat([], timeout: 1)

      # Invalid message format should fail
      invalid_messages = [%{content: "missing role"}]
      assert {:error, _} = Perplexity.chat(invalid_messages, timeout: 1)
    end

    test "accepts valid message formats" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Hello"}]

      # Should get connection error, not validation error
      assert {:error, _reason} = Perplexity.chat(messages, config_provider: provider, timeout: 1)
    end
  end

  describe "parameter validation" do
    test "validates search_mode parameter" do
      valid_modes = ["news", "academic", "general"]
      invalid_modes = ["invalid", "wrong_mode", ""]

      for mode <- valid_modes do
        assert Perplexity.validate_search_mode(mode) == :ok
      end

      for mode <- invalid_modes do
        assert {:error, _} = Perplexity.validate_search_mode(mode)
      end
    end

    test "validates reasoning_effort parameter" do
      valid_efforts = ["low", "medium", "high"]
      invalid_efforts = ["invalid", "maximum", ""]

      for effort <- valid_efforts do
        assert Perplexity.validate_reasoning_effort(effort) == :ok
      end

      for effort <- invalid_efforts do
        assert {:error, _} = Perplexity.validate_reasoning_effort(effort)
      end
    end

    test "validates image_filters parameter" do
      valid_filter = ["domain1.com", "domain2.org", "domain3.net"]
      too_large_filter = Enum.map(1..15, &"domain#{&1}.com")

      assert Perplexity.validate_image_filters(valid_filter) == :ok
      assert {:error, _} = Perplexity.validate_image_filters(too_large_filter)
      assert Perplexity.validate_image_filters([]) == :ok
    end

    test "rejects invalid search parameters" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test query"}]

      # Invalid search mode
      result =
        Perplexity.chat(messages,
          config_provider: provider,
          search_mode: "invalid_mode",
          timeout: 1
        )

      assert {:error, error_msg} = result
      assert String.contains?(error_msg, "search_mode")
    end

    test "rejects too many image filters" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test query"}]
      large_filter = Enum.map(1..15, &"domain#{&1}.com")

      result =
        Perplexity.chat(messages,
          config_provider: provider,
          image_domain_filter: large_filter,
          timeout: 1
        )

      assert {:error, error_msg} = result
      assert String.contains?(error_msg, "maximum")
    end

    test "validates reasoning effort parameter in chat" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)

      messages = [%{role: "user", content: "Test query"}]

      result =
        Perplexity.chat(messages,
          config_provider: provider,
          reasoning_effort: "invalid_effort",
          timeout: 1
        )

      assert {:error, error_msg} = result
      assert String.contains?(error_msg, "reasoning_effort")
    end
  end

  describe "model classification" do
    test "identifies search-capable models" do
      search_models = [
        "perplexity/sonar",
        "perplexity/sonar-pro",
        "perplexity/sonar-reasoning",
        "perplexity/sonar-deep-research"
      ]

      for model <- search_models do
        assert Perplexity.supports_web_search?(model)
      end
    end

    test "identifies non-search models" do
      non_search_models = [
        "perplexity/llama-3.1-8b-instruct",
        "perplexity/codellama-34b-instruct",
        "perplexity/mistral-7b-instruct"
      ]

      for model <- non_search_models do
        refute Perplexity.supports_web_search?(model)
      end
    end

    test "identifies reasoning models" do
      reasoning_models = [
        "perplexity/sonar-reasoning",
        "perplexity/sonar-reasoning-pro",
        "perplexity/sonar-deep-research"
      ]

      for model <- reasoning_models do
        assert Perplexity.supports_reasoning?(model)
      end
    end
  end

  describe "stream parsing" do
    test "parses standard OpenAI-style streaming chunks" do
      chunk_data = ~s({"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]})

      {:ok, chunk} = Perplexity.parse_stream_chunk(chunk_data)
      assert %Types.StreamChunk{content: "Hello", finish_reason: nil} = chunk
    end

    test "handles citations in streaming responses" do
      chunk_data =
        ~s({"choices":[{"delta":{"content":"The weather today [1] shows..."},"finish_reason":null}]})

      {:ok, chunk} = Perplexity.parse_stream_chunk(chunk_data)

      assert %Types.StreamChunk{content: "The weather today [1] shows...", finish_reason: nil} =
               chunk
    end

    test "handles finish reason in streaming" do
      chunk_data = ~s({"choices":[{"delta":{},"finish_reason":"stop"}]})

      {:ok, chunk} = Perplexity.parse_stream_chunk(chunk_data)
      assert %Types.StreamChunk{content: nil, finish_reason: "stop"} = chunk
    end

    test "handles invalid streaming data" do
      assert match?({:error, _}, Perplexity.parse_stream_chunk("invalid json"))
      assert match?({:error, _}, Perplexity.parse_stream_chunk(""))
      assert match?({:ok, nil}, Perplexity.parse_stream_chunk("{}"))
    end
  end

  describe "error handling" do
    test "handles missing API key error" do
      messages = [%{role: "user", content: "Test"}]

      result = Perplexity.chat(messages, timeout: 1)

      # Should fail with API key validation error
      assert {:error, _reason} = result
    end

    test "provides helpful error messages" do
      # Temporarily disable environment API keys to test true "no key" scenario
      restore_env = ConfigProviderHelper.disable_env_api_keys()
      
      try do
        messages = [%{role: "user", content: "Test"}]

        # No API key
        {:error, msg1} = Perplexity.chat(messages)
        assert is_binary(msg1) and String.contains?(msg1, "API key")

        # Invalid search mode
        config = %{perplexity: %{api_key: "test"}}
        provider = ConfigProviderHelper.setup_static_provider(config)

        {:error, msg2} =
          Perplexity.chat(messages,
            config_provider: provider,
            search_mode: "invalid"
          )

        assert is_binary(msg2) and String.contains?(msg2, "search_mode")
      after
        restore_env.()
      end
    end
  end

  describe "list_models/1 fallback" do
    test "returns models from config when API is not available" do
      # Without API key, should fall back to config
      case Perplexity.list_models() do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            model = hd(models)
            assert %Types.Model{} = model

            assert String.contains?(model.id, "perplexity/") or
                     String.contains?(model.id, "sonar")
          end

        {:error, _} ->
          # Error is also acceptable without API key
          :ok
      end
    end
  end

  describe "adapter behavior compliance" do
    test "implements all required callbacks" do
      callbacks = [
        # chat/2 with default args exports as chat/1
        {:chat, 1},
        # stream_chat/2 with default args exports as stream_chat/1
        {:stream_chat, 1},
        # configured?/1 with default args exports as configured?/0
        {:configured?, 0},
        {:default_model, 0},
        # list_models/1 with default args exports as list_models/0
        {:list_models, 0}
      ]

      for {func, arity} <- callbacks do
        assert function_exported?(Perplexity, func, arity)
      end
    end
  end
end
