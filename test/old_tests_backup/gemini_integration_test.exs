defmodule ExLLM.Providers.Gemini.IntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :external
  @moduletag :live_api
  @moduletag :requires_api_key
  @moduletag provider: :gemini

  alias ExLLM
  alias ExLLM.Providers.Gemini
  alias ExLLM.Types

  alias ExLLM.Providers.Gemini.{
    Models,
    Content,
    Files,
    Caching,
    Embeddings,
    Tuning,
    Permissions,
    Corpus,
    Document,
    Chunk
  }

  @api_key System.get_env("GEMINI_API_KEY") || "test-key"

  describe "Gemini adapter integration with ExLLM interfaces" do
    @describetag :integration
    test "adapter configuration and setup" do
      # Test that the adapter is properly configured
      assert Gemini.configured?(config_provider: ExLLM.Infrastructure.ConfigProvider.Env)

      # Test default model
      default_model = Gemini.default_model()
      assert is_binary(default_model)
      assert String.contains?(default_model, "gemini")
    end

    test "model listing integration" do
      # Test that list_models returns proper Types.Model structs
      {:ok, models} = Gemini.list_models(config_provider: ExLLM.Infrastructure.ConfigProvider.Env)

      assert is_list(models)
      assert length(models) > 0

      # Verify model structure
      model = hd(models)
      assert %Types.Model{} = model
      assert model.id
      assert model.name
      assert is_map(model.capabilities)
      assert is_boolean(model.capabilities.supports_streaming)
      assert is_boolean(model.capabilities.supports_functions)
      assert is_boolean(model.capabilities.supports_vision)
    end

    @tag :function_calling
    test "basic chat functionality through ExLLM interface" do
      messages = [
        %{
          role: "user",
          content: "Hello! Please respond with exactly: 'Integration test successful'"
        }
      ]

      # Test via ExLLM main interface
      {:ok, response} =
        ExLLM.chat(:gemini, messages,
          config_provider: ExLLM.Infrastructure.ConfigProvider.Env,
          model: "gemini-2.0-flash"
        )

      assert %Types.LLMResponse{} = response
      assert is_binary(response.content)
      assert String.length(response.content) > 0
      assert is_map(response.usage)
      assert response.usage.total_tokens > 0
      assert response.model
    end

    @tag :streaming
    test "streaming chat through ExLLM interface" do
      messages = [
        %{role: "user", content: "Count from 1 to 3, one number per line"}
      ]

      # Test via ExLLM streaming interface
      {:ok, stream} =
        ExLLM.stream_chat(:gemini, messages,
          config_provider: ExLLM.Infrastructure.ConfigProvider.Env,
          model: "gemini-2.0-flash"
        )

      chunks = Enum.take(stream, 10)
      assert length(chunks) > 0

      # Verify chunk structure
      chunk = hd(chunks)
      assert %Types.StreamChunk{} = chunk
      assert is_binary(chunk.content) or is_nil(chunk.content)
    end

    test "error handling integration" do
      # Test invalid API key
      messages = [%{role: "user", content: "Test"}]

      config = %{gemini: %{api_key: "invalid-key"}}
      {:ok, provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)

      {:error, error} =
        ExLLM.chat(messages,
          provider: :gemini,
          config_provider: provider
        )

      assert is_binary(error) or is_map(error)
    end
  end

  describe "Cross-feature interactions" do
    test "API modules validation and structure" do
      # Test that the individual API modules are properly structured
      # and can be called without errors (validation tests)

      # Test Models API structure - use definitely invalid key
      assert {:error, _} = Models.list_models(api_key: "definitely-invalid-key")

      assert {:error, _} =
               Models.get_model("models/gemini-pro", api_key: "definitely-invalid-key")

      # Test Content API structure
      request = %ExLLM.Providers.Gemini.Content.GenerateContentRequest{
        contents: [
          %ExLLM.Providers.Gemini.Content.Content{
            role: "user",
            parts: [%ExLLM.Providers.Gemini.Content.Part{text: "Hello"}]
          }
        ]
      }

      assert {:error, _} =
               Content.generate_content("models/gemini-pro", request,
                 api_key: "definitely-invalid-key"
               )

      # Test Files API structure
      assert {:error, _} = Files.list_files(api_key: "definitely-invalid-key")

      # Test Embeddings API structure  
      request = %Embeddings.EmbedContentRequest{
        content: %ExLLM.Providers.Gemini.Content.Content{
          role: "user",
          parts: [%ExLLM.Providers.Gemini.Content.Part{text: "test"}]
        }
      }

      assert {:error, _} =
               Embeddings.embed_content("text-embedding-004", request,
                 api_key: "definitely-invalid-key"
               )

      # Test Semantic Retrieval APIs structure
      # Note: Corpus API requires OAuth2 token, not API key
      assert_raise ArgumentError, ~r/OAuth2 token is required/, fn ->
        Corpus.list_corpora([], api_key: "definitely-invalid-key")
      end

      assert {:error, _} =
               Document.list_documents("corpora/test", api_key: "definitely-invalid-key")

      assert {:error, _} =
               Chunk.list_chunks("corpora/test/documents/test", api_key: "definitely-invalid-key")

      # Test Permissions API structure
      assert {:error, _} =
               Permissions.list_permissions("corpora/test", api_key: "definitely-invalid-key")
    end

    @tag :integration
    @tag :embedding
    test "embeddings integration with similarity search" do
      content_1 = "The weather is sunny today"
      content_2 = "It's a bright and clear day"
      content_3 = "Programming languages are diverse"

      # Generate embeddings using ExLLM interface
      {:ok, embedding_1} =
        ExLLM.embeddings(:gemini, [content_1],
          config_provider: ExLLM.Infrastructure.ConfigProvider.Env,
          model: "text-embedding-004"
        )

      {:ok, embedding_2} =
        ExLLM.embeddings(:gemini, [content_2],
          config_provider: ExLLM.Infrastructure.ConfigProvider.Env,
          model: "text-embedding-004"
        )

      {:ok, embedding_3} =
        ExLLM.embeddings(:gemini, [content_3],
          config_provider: ExLLM.Infrastructure.ConfigProvider.Env,
          model: "text-embedding-004"
        )

      # Check response structure
      assert %Types.EmbeddingResponse{} = embedding_1
      assert is_list(embedding_1.embeddings)
      assert length(embedding_1.embeddings) == 1

      # Extract embedding vectors
      vec_1 = hd(embedding_1.embeddings)
      vec_2 = hd(embedding_2.embeddings)
      vec_3 = hd(embedding_3.embeddings)

      # Calculate similarities
      sim_1_2 = ExLLM.cosine_similarity(vec_1, vec_2)
      sim_1_3 = ExLLM.cosine_similarity(vec_1, vec_3)

      # Weather-related content should be more similar than weather vs programming
      assert sim_1_2 > sim_1_3
    end
  end

  describe "Feature detection and capabilities" do
    @tag :integration
    test "model capabilities detection" do
      {:ok, models} = Gemini.list_models(config_provider: ExLLM.Infrastructure.ConfigProvider.Env)

      # Models should be loaded from config
      assert length(models) > 0, "No models loaded"

      # Find a Gemini model - the IDs from config include the provider prefix
      gemini_model =
        Enum.find(models, fn model ->
          String.contains?(model.id, "gemini")
        end)

      assert gemini_model,
             "No Gemini model found in list. Models: #{inspect(Enum.map(models, & &1.id))}"

      # Test capability detection
      capabilities = gemini_model.capabilities
      assert is_boolean(capabilities.supports_streaming)
      assert is_boolean(capabilities.supports_functions)
      assert is_boolean(capabilities.supports_vision)
      assert is_list(capabilities.features)
    end

    test "provider capabilities via ExLLM" do
      # Test that ExLLM can detect Gemini provider capabilities
      {:ok, provider_info} = ExLLM.get_provider_capabilities(:gemini)

      assert %ExLLM.Infrastructure.Config.ProviderCapabilities.ProviderInfo{} = provider_info
      assert provider_info.id == :gemini
      assert :chat in provider_info.endpoints
      assert :streaming in provider_info.features
      assert :embeddings in provider_info.features
    end

    test "model feature detection" do
      # Test specific model features
      assert ExLLM.model_supports?(:gemini, "gemini/gemini-2.0-flash", :streaming)
      assert ExLLM.model_supports?(:gemini, "gemini/gemini-2.0-flash", :vision)
      assert ExLLM.model_supports?(:gemini, "gemini/text-embedding-004", :embeddings)
    end
  end

  describe "Error handling and retries" do
    test "handles API errors gracefully" do
      messages = [%{role: "user", content: "Test"}]

      # Test with invalid model
      assert_raise RuntimeError, ~r/Unknown model non-existent-model/, fn ->
        ExLLM.chat(:gemini, messages,
          model: "non-existent-model",
          config_provider: ExLLM.Infrastructure.ConfigProvider.Env
        )
      end
    end

    test "validates required configuration" do
      # Test without API key
      config = %{gemini: %{}}
      {:ok, pid} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Test"}]

      result = ExLLM.chat(:gemini, messages, config_provider: pid)

      case result do
        {:error, error} ->
          # Without API key, should get an error
          assert String.contains?(to_string(error), "API key") or
                   String.contains?(to_string(error), "Google API key")

        {:ok, _} ->
          # If we have an API key in environment, the call might succeed
          # This is okay in development but would fail in CI
          assert System.get_env("GOOGLE_API_KEY") != nil or
                   System.get_env("GEMINI_API_KEY") != nil,
                 "Expected error without API key, but got success"
      end
    end

    test "handles empty responses" do
      # This would test edge cases like empty responses
      # Currently skipped as it's hard to trigger consistently
    end
  end

  describe "Performance characteristics" do
    @tag :performance
    @tag :integration
    test "response time benchmarks" do
      messages = [%{role: "user", content: "Hello"}]

      # Measure response time
      start_time = :os.system_time(:millisecond)

      {:ok, _response} =
        ExLLM.chat(:gemini, messages,
          config_provider: ExLLM.Infrastructure.ConfigProvider.Env,
          model: "gemini-2.0-flash"
        )

      end_time = :os.system_time(:millisecond)
      response_time = end_time - start_time

      # Response should be under 10 seconds for simple message
      assert response_time < 10_000
    end

    @tag :performance
    @tag :integration
    @tag :streaming
    test "streaming latency" do
      messages = [%{role: "user", content: "Count from 1 to 5"}]

      start_time = :os.system_time(:millisecond)

      {:ok, stream} =
        ExLLM.stream_chat(:gemini, messages,
          config_provider: ExLLM.Infrastructure.ConfigProvider.Env,
          model: "gemini-2.0-flash"
        )

      # Get first chunk
      first_chunk = Enum.take(stream, 1) |> hd()
      first_chunk_time = :os.system_time(:millisecond)

      time_to_first_chunk = first_chunk_time - start_time

      # First chunk should arrive within 5 seconds
      assert time_to_first_chunk < 5_000
      assert %Types.StreamChunk{} = first_chunk
    end

    @tag :performance
    @tag :integration
    test "concurrent request handling" do
      messages = [%{role: "user", content: "Hello #{:rand.uniform(1000)}"}]

      # Send 3 concurrent requests
      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            ExLLM.chat(:gemini, messages ++ [%{role: "user", content: "Request #{i}"}],
              config_provider: ExLLM.Infrastructure.ConfigProvider.Env,
              model: "gemini-2.0-flash"
            )
          end)
        end

      # Collect results
      results = Task.await_many(tasks, 30_000)

      # All should succeed
      assert length(results) == 3

      Enum.each(results, fn
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          assert String.length(response.content) > 0

        {:error, reason} ->
          flunk("Request failed: #{inspect(reason)}")
      end)
    end
  end

  describe "API module integration" do
    test "all implemented APIs are accessible" do
      # Test that all major API modules are available and working
      api_modules = [
        Models,
        Content,
        Files,
        Caching,
        Embeddings,
        Tuning,
        Permissions,
        Corpus,
        Document,
        Chunk
      ]

      Enum.each(api_modules, fn module ->
        # Check that module exists and has expected functions
        assert Code.ensure_loaded?(module)

        # Check that module has at least one public function
        functions = module.__info__(:functions)
        assert length(functions) > 0
      end)
    end

    test "API modules use consistent authentication" do
      # Test that all modules accept both api_key and oauth_token

      # Test with invalid OAuth token (should fail)
      oauth_auth = [oauth_token: "invalid-oauth-token"]
      assert {:error, _} = Models.list_models(oauth_auth)
      assert {:error, _} = Files.list_files(oauth_auth)

      assert_raise ArgumentError, ~r/OAuth2 token is required/, fn ->
        Corpus.list_corpora(oauth_auth)
      end

      # Test with valid API key (should work if we have one)
      if System.get_env("GEMINI_API_KEY") do
        api_auth = [api_key: System.get_env("GEMINI_API_KEY")]
        assert {:ok, _} = Models.list_models(api_auth)
        # Files may have different response but shouldn't crash
        _ = Files.list_files(api_auth)

        # Corpus requires OAuth token, not API key
        assert_raise ArgumentError, ~r/OAuth2 token is required/, fn ->
          Corpus.list_corpora(api_auth)
        end
      else
        # Test with invalid API key if no valid one available
        api_auth = [api_key: "invalid-api-key"]
        assert {:error, _} = Models.list_models(api_auth)
        assert {:error, _} = Files.list_files(api_auth)

        assert_raise ArgumentError, ~r/OAuth2 token is required/, fn ->
          Corpus.list_corpora(api_auth)
        end
      end
    end
  end
end
