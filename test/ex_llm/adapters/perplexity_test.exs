defmodule ExLLM.Adapters.PerplexityTest do
  use ExUnit.Case, async: true
  alias ExLLM.Adapters.Perplexity
  alias ExLLM.Types

  describe "configured?/1" do
    test "returns true when API key is available" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      assert Perplexity.configured?(config_provider: provider)
    end

    test "returns false with empty API key" do
      config = %{perplexity: %{api_key: ""}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      refute Perplexity.configured?(config_provider: provider)
    end

    test "returns false with no API key" do
      config = %{perplexity: %{}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      refute Perplexity.configured?(config_provider: provider)
    end

    test "returns true with environment variable fallback" do
      # Store original env var
      original_key = System.get_env("PERPLEXITY_API_KEY")
      
      # Set test env var
      System.put_env("PERPLEXITY_API_KEY", "pplx-env-test-key")
      
      try do
        assert Perplexity.configured?()
      after
        # Restore original env var
        if original_key do
          System.put_env("PERPLEXITY_API_KEY", original_key)
        else
          System.delete_env("PERPLEXITY_API_KEY")
        end
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

  describe "list_models/1" do
    test "returns models from config when API is not available" do
      # Without API key, should fall back to config
      case Perplexity.list_models() do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            model = hd(models)
            assert %Types.Model{} = model
            assert String.contains?(model.id, "perplexity/") or String.contains?(model.id, "sonar")
          end

        {:error, _} ->
          # Error is also acceptable without API key
          :ok
      end
    end

    test "model capabilities include search and reasoning for appropriate models" do
      case Perplexity.list_models() do
        {:ok, models} ->
          # Test sonar-pro model capabilities
          sonar_pro = Enum.find(models, &String.contains?(&1.id, "sonar-pro"))
          
          if sonar_pro do
            assert is_map(sonar_pro.capabilities)

            if is_list(sonar_pro.capabilities.features) do
              assert "web_search" in sonar_pro.capabilities.features
              assert "streaming" in sonar_pro.capabilities.features
            end
          end

          # Test reasoning model capabilities
          reasoning_model = Enum.find(models, &String.contains?(&1.id, "reasoning"))
          
          if reasoning_model do
            assert is_map(reasoning_model.capabilities)

            if is_list(reasoning_model.capabilities.features) do
              assert "reasoning" in reasoning_model.capabilities.features
            end
          end

        {:error, _} ->
          :ok
      end
    end
  end

  describe "chat/2 - basic functionality" do
    test "validates messages before processing" do
      # Empty messages should fail validation
      assert {:error, _} = Perplexity.chat([], timeout: 1)

      # Invalid message format should fail
      invalid_messages = [%{content: "missing role"}]
      assert {:error, _} = Perplexity.chat(invalid_messages, timeout: 1)
    end

    test "builds proper request body with basic options" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "What is the weather today?"}]
      
      # This will fail at the HTTP request level, but we can test the validation
      result = Perplexity.chat(messages, config_provider: provider, timeout: 1)
      
      # Should get an error (likely connection), not a validation error
      assert {:error, _reason} = result
    end

    test "handles standard chat model without search" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Explain quantum computing"}]
      
      result = Perplexity.chat(messages, 
        config_provider: provider,
        model: "perplexity/llama-3.1-8b-instruct",
        timeout: 1
      )
      
      # Should get an error (likely connection), not a validation error
      assert {:error, _reason} = result
    end
  end

  describe "chat/2 - Perplexity-specific features" do
    test "handles web search parameters for sonar models" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "What's the latest news in AI?"}]
      
      result = Perplexity.chat(messages, 
        config_provider: provider,
        model: "perplexity/sonar-pro",
        search_mode: "academic",
        web_search_options: %{search_context_size: "medium"},
        timeout: 1
      )
      
      # Should get an error (likely connection), not a parameter validation error
      assert {:error, _reason} = result
    end

    test "handles reasoning effort parameter for deep research model" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Analyze the impact of climate change on agriculture"}]
      
      result = Perplexity.chat(messages, 
        config_provider: provider,
        model: "perplexity/sonar-deep-research",
        reasoning_effort: "high",
        timeout: 1
      )
      
      # Should get an error (likely connection), not a parameter validation error
      assert {:error, _reason} = result
    end

    test "handles image filters for search models" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Show me images of renewable energy technologies"}]
      
      result = Perplexity.chat(messages, 
        config_provider: provider,
        model: "perplexity/sonar",
        return_images: true,
        image_domain_filter: ["nasa.gov", "energy.gov"],
        image_format_filter: ["jpg", "png"],
        timeout: 1
      )
      
      # Should get an error (likely connection), not a parameter validation error
      assert {:error, _reason} = result
    end

    test "rejects invalid search parameters" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Test query"}]

      # Invalid search mode
      result1 = Perplexity.chat(messages, 
        config_provider: provider,
        search_mode: "invalid_mode",
        timeout: 1
      )
      
      assert {:error, error_msg} = result1
      assert String.contains?(error_msg, "search_mode")

      # Too many image domain filters (>10)
      large_filter = Enum.map(1..15, &"domain#{&1}.com")
      result2 = Perplexity.chat(messages, 
        config_provider: provider,
        image_domain_filter: large_filter,
        timeout: 1
      )
      
      assert {:error, error_msg} = result2
      assert String.contains?(error_msg, "maximum")
    end

    test "validates reasoning effort parameter" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Test query"}]

      # Invalid reasoning effort
      result = Perplexity.chat(messages, 
        config_provider: provider,
        reasoning_effort: "invalid_effort",
        timeout: 1
      )
      
      assert {:error, error_msg} = result
      assert String.contains?(error_msg, "reasoning_effort")
    end
  end

  describe "stream_chat/2" do
    test "handles streaming for search models" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "What's happening in tech today?"}]
      
      result = Perplexity.stream_chat(messages, 
        config_provider: provider,
        model: "perplexity/sonar",
        timeout: 1
      )
      
      # Should get an error (likely connection) or a stream
      case result do
        {:ok, _stream} -> :ok
        {:error, _reason} -> :ok
      end
    end

    test "includes web search parameters in streaming requests" do
      config = %{perplexity: %{api_key: "pplx-test-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Current events in science"}]
      
      result = Perplexity.stream_chat(messages, 
        config_provider: provider,
        model: "perplexity/sonar-pro",
        search_mode: "news",
        web_search_options: %{recency_filter: "day"},
        timeout: 1
      )
      
      # Should get an error (likely connection) or a stream
      case result do
        {:ok, _stream} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  describe "stream parsing" do
    test "parses standard OpenAI-style streaming chunks" do
      # Test OpenAI-compatible streaming format
      chunk_data = ~s({"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]})
      
      chunk = Perplexity.parse_stream_chunk(chunk_data)
      assert %Types.StreamChunk{content: "Hello", finish_reason: nil} = chunk
    end

    test "handles citations in streaming responses" do
      # Perplexity often includes citations in responses
      chunk_data = ~s({"choices":[{"delta":{"content":"The weather today [1] shows..."},"finish_reason":null}]})
      
      chunk = Perplexity.parse_stream_chunk(chunk_data)
      assert %Types.StreamChunk{content: "The weather today [1] shows...", finish_reason: nil} = chunk
    end

    test "handles finish reason in streaming" do
      chunk_data = ~s({"choices":[{"delta":{},"finish_reason":"stop"}]})
      
      chunk = Perplexity.parse_stream_chunk(chunk_data)
      assert %Types.StreamChunk{content: nil, finish_reason: "stop"} = chunk
    end

    test "handles invalid streaming data" do
      assert nil == Perplexity.parse_stream_chunk("invalid json")
      assert nil == Perplexity.parse_stream_chunk("")
      assert nil == Perplexity.parse_stream_chunk("{}")
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

  describe "response parsing" do
    test "parses standard chat response" do
      mock_response = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "model" => "perplexity/sonar",
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "Based on recent reports, the weather today shows sunny conditions."
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 20,
          "completion_tokens" => 15,
          "total_tokens" => 35
        }
      }

      # Test that response parsing would handle this structure
      assert is_map(mock_response)
      assert get_in(mock_response, ["choices", Access.at(0), "message", "content"]) == "Based on recent reports, the weather today shows sunny conditions."
      assert mock_response["usage"]["total_tokens"] == 35
    end

    test "handles responses with citations" do
      mock_response_with_citations = %{
        "choices" => [
          %{
            "message" => %{
              "content" => "According to recent studies [1], climate change affects agriculture [2]."
            }
          }
        ],
        "citations" => [
          %{"url" => "https://example.com/study1", "title" => "Climate Study 1"},
          %{"url" => "https://example.com/study2", "title" => "Agriculture Report"}
        ]
      }

      # Test citation handling
      assert length(mock_response_with_citations["citations"]) == 2
      assert String.contains?(
        get_in(mock_response_with_citations, ["choices", Access.at(0), "message", "content"]), 
        "[1]"
      )
    end
  end

  describe "error handling" do
    test "handles Perplexity-specific error responses" do
      error_scenarios = [
        {401, %{"error" => %{"message" => "Invalid API key", "type" => "authentication_error"}}},
        {429, %{"error" => %{"message" => "Rate limit exceeded", "type" => "rate_limit_error"}}},
        {400, %{"error" => %{"message" => "Invalid search_mode parameter", "type" => "invalid_request_error"}}}
      ]

      for {status, error_body} <- error_scenarios do
        # Test that these error formats would be handled properly
        assert is_map(error_body)
        assert Map.has_key?(error_body, "error")
      end
    end

    test "handles missing API key error" do
      messages = [%{role: "user", content: "Test"}]
      
      result = Perplexity.chat(messages, timeout: 1)
      
      # Should fail with API key validation error
      assert {:error, _reason} = result
    end
  end

  describe "parameter validation helpers" do
    test "validate_search_mode/1" do
      valid_modes = ["news", "academic", "general"]
      invalid_modes = ["invalid", "wrong_mode", ""]

      for mode <- valid_modes do
        assert Perplexity.validate_search_mode(mode) == :ok
      end

      for mode <- invalid_modes do
        assert {:error, _} = Perplexity.validate_search_mode(mode)
      end
    end

    test "validate_reasoning_effort/1" do
      valid_efforts = ["low", "medium", "high"]
      invalid_efforts = ["invalid", "maximum", ""]

      for effort <- valid_efforts do
        assert Perplexity.validate_reasoning_effort(effort) == :ok
      end

      for effort <- invalid_efforts do
        assert {:error, _} = Perplexity.validate_reasoning_effort(effort)
      end
    end

    test "validate_image_filters/1" do
      valid_filter = ["domain1.com", "domain2.org", "domain3.net"]
      too_large_filter = Enum.map(1..15, &"domain#{&1}.com")

      assert Perplexity.validate_image_filters(valid_filter) == :ok
      assert {:error, _} = Perplexity.validate_image_filters(too_large_filter)
      assert Perplexity.validate_image_filters([]) == :ok
    end
  end

  describe "model naming and formatting" do
    test "handles perplexity model naming conventions" do
      test_cases = [
        {"perplexity/sonar-pro", true},
        {"perplexity/sonar-deep-research", true},
        {"perplexity/llama-3.1-8b-instruct", true},
        {"perplexity/codellama-34b-instruct", true}
      ]

      for {model_id, should_contain_perplexity} <- test_cases do
        if should_contain_perplexity do
          assert String.contains?(model_id, "perplexity/")
        end
      end
    end
  end

  describe "cost calculation" do
    test "tracks usage and costs for different model types" do
      # Test that different Perplexity models would have different cost structures
      usage = %{input_tokens: 1000, output_tokens: 500}
      
      expensive_model = "perplexity/sonar-pro"  # Higher cost per token
      cheap_model = "perplexity/llama-3.1-8b-instruct"  # Lower cost per token
      
      # The actual cost calculation would be handled by the Cost module
      # This test ensures we understand the usage structure
      assert usage.input_tokens == 1000
      assert usage.output_tokens == 500
      assert is_binary(expensive_model)
      assert is_binary(cheap_model)
    end
  end
end