defmodule ExLLM.Adapters.Gemini.IntegrationTest do
  use ExUnit.Case, async: false

  alias ExLLM
  alias ExLLM.Adapters.Gemini

  alias ExLLM.Gemini.{
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
      assert Gemini.configured?(config_provider: ExLLM.ConfigProvider.Env)

      # Test default model
      default_model = Gemini.default_model()
      assert is_binary(default_model)
      assert String.contains?(default_model, "gemini")
    end

    test "model listing integration" do
      # Test that list_models returns proper ExLLM.Types.Model structs
      {:ok, models} = Gemini.list_models(config_provider: ExLLM.ConfigProvider.Env)

      assert is_list(models)
      assert length(models) > 0

      # Verify model structure
      model = hd(models)
      assert %ExLLM.Types.Model{} = model
      assert model.id
      assert model.name
      assert is_map(model.capabilities)
      assert is_boolean(model.capabilities.supports_streaming)
      assert is_boolean(model.capabilities.supports_functions)
      assert is_boolean(model.capabilities.supports_vision)
    end

    test "basic chat functionality through ExLLM interface" do
      messages = [
        %{
          role: "user",
          content: "Hello! Please respond with exactly: 'Integration test successful'"
        }
      ]

      # Test via ExLLM main interface
      {:ok, response} =
        ExLLM.chat(messages,
          provider: :gemini,
          config_provider: ExLLM.ConfigProvider.Env,
          model: "gemini-2.0-flash"
        )

      assert %ExLLM.Types.LLMResponse{} = response
      assert is_binary(response.content)
      assert String.length(response.content) > 0
      assert is_map(response.usage)
      assert response.usage.total_tokens > 0
      assert response.model
    end

    test "streaming chat through ExLLM interface" do
      messages = [
        %{role: "user", content: "Count from 1 to 3, one number per line"}
      ]

      # Test via ExLLM streaming interface
      {:ok, stream} =
        ExLLM.stream_chat(messages,
          provider: :gemini,
          config_provider: ExLLM.ConfigProvider.Env,
          model: "gemini-2.0-flash"
        )

      chunks = Enum.take(stream, 10)
      assert length(chunks) > 0

      # Verify chunk structure
      chunk = hd(chunks)
      assert %ExLLM.Types.StreamChunk{} = chunk
      assert is_binary(chunk.content) or is_nil(chunk.content)
    end

    @tag :skip
    test "error handling integration" do
      # Test invalid API key
      messages = [%{role: "user", content: "Test"}]

      config = %{gemini: %{api_key: "invalid-key"}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

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

      # Test Models API structure
      assert {:error, _} = Models.list_models(api_key: "invalid")
      assert {:error, _} = Models.get_model("models/gemini-pro", api_key: "invalid")

      # Test Content API structure
      request = %ExLLM.Gemini.Content.GenerateContentRequest{
        contents: [
          %ExLLM.Gemini.Content.Content{
            role: "user",
            parts: [%ExLLM.Gemini.Content.Part{text: "Hello"}]
          }
        ]
      }

      assert {:error, _} =
               Content.generate_content("models/gemini-pro", request, api_key: "invalid")

      # Test Files API structure
      assert {:error, _} = Files.list_files(api_key: "invalid")

      # Test Embeddings API structure  
      request = %Embeddings.EmbedContentRequest{
        content: %ExLLM.Gemini.Content.Content{
          role: "user",
          parts: [%ExLLM.Gemini.Content.Part{text: "test"}]
        }
      }

      assert {:error, _} =
               Embeddings.embed_content("text-embedding-004", request, api_key: "invalid")

      # Test Semantic Retrieval APIs structure
      assert {:error, _} = Corpus.list_corpora(api_key: "invalid")
      assert {:error, _} = Document.list_documents("corpora/test", api_key: "invalid")
      assert {:error, _} = Chunk.list_chunks("corpora/test/documents/test", api_key: "invalid")

      # Test Permissions API structure
      assert {:error, _} = Permissions.list_permissions("corpora/test", api_key: "invalid")
    end

    @tag :integration
    test "embeddings integration with similarity search" do
      content_1 = "The weather is sunny today"
      content_2 = "It's a bright and clear day"
      content_3 = "Programming languages are diverse"

      # Generate embeddings using ExLLM interface
      {:ok, embedding_1} =
        ExLLM.embeddings(:gemini, [content_1],
          config_provider: ExLLM.ConfigProvider.Env,
          model: "text-embedding-004"
        )

      {:ok, embedding_2} =
        ExLLM.embeddings(:gemini, [content_2],
          config_provider: ExLLM.ConfigProvider.Env,
          model: "text-embedding-004"
        )

      {:ok, embedding_3} =
        ExLLM.embeddings(:gemini, [content_3],
          config_provider: ExLLM.ConfigProvider.Env,
          model: "text-embedding-004"
        )

      # Check response structure
      assert %ExLLM.Types.EmbeddingResponse{} = embedding_1
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
    test "model capabilities detection" do
      {:ok, models} = Gemini.list_models(config_provider: ExLLM.ConfigProvider.Env)

      # Find a Gemini model
      gemini_model = Enum.find(models, &String.contains?(&1.id, "gemini"))
      assert gemini_model

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

      assert %ExLLM.ProviderCapabilities.ProviderInfo{} = provider_info
      assert provider_info.id == :gemini
      assert :chat in provider_info.endpoints
      assert :streaming in provider_info.features
      assert :embeddings in provider_info.features
    end

    test "model feature detection" do
      # Test specific model features
      assert ExLLM.model_supports?(:gemini, "gemini-2.0-flash", :streaming)
      assert ExLLM.model_supports?(:gemini, "gemini-2.0-flash", :vision)
      assert ExLLM.model_supports?(:gemini, "text-embedding-004", :embeddings)
    end
  end

  describe "Error handling and retries" do
    test "handles API errors gracefully" do
      messages = [%{role: "user", content: "Test"}]

      # Test with invalid model
      {:error, error} =
        ExLLM.chat(:gemini, messages,
          model: "non-existent-model",
          config_provider: ExLLM.ConfigProvider.Env
        )

      assert is_binary(error) or is_map(error)
    end

    test "validates required configuration" do
      # Test without API key
      config = %{gemini: %{}}
      {:ok, provider} = ExLLM.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Test"}]

      {:error, error} = ExLLM.chat(:gemini, messages, config_provider: provider)

      assert String.contains?(to_string(error), "API key")
    end

    test "handles empty responses" do
      # This would test edge cases like empty responses
      # Currently skipped as it's hard to trigger consistently
    end
  end

  describe "Performance characteristics" do
    @tag :performance
    test "response time benchmarks" do
      messages = [%{role: "user", content: "Hello"}]

      # Measure response time
      start_time = :os.system_time(:millisecond)

      {:ok, _response} =
        ExLLM.chat(messages,
          provider: :gemini,
          config_provider: ExLLM.ConfigProvider.Env,
          model: "gemini-2.0-flash"
        )

      end_time = :os.system_time(:millisecond)
      response_time = end_time - start_time

      # Response should be under 10 seconds for simple message
      assert response_time < 10_000
    end

    @tag :performance
    test "streaming latency" do
      messages = [%{role: "user", content: "Count from 1 to 5"}]

      start_time = :os.system_time(:millisecond)

      {:ok, stream} =
        ExLLM.stream_chat(messages,
          provider: :gemini,
          config_provider: ExLLM.ConfigProvider.Env,
          model: "gemini-2.0-flash"
        )

      # Get first chunk
      first_chunk = Enum.take(stream, 1) |> hd()
      first_chunk_time = :os.system_time(:millisecond)

      time_to_first_chunk = first_chunk_time - start_time

      # First chunk should arrive within 5 seconds
      assert time_to_first_chunk < 5_000
      assert %ExLLM.Types.StreamChunk{} = first_chunk
    end

    @tag :performance
    test "concurrent request handling" do
      messages = [%{role: "user", content: "Hello #{:rand.uniform(1000)}"}]

      # Send 3 concurrent requests
      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            ExLLM.chat(messages ++ [%{role: "user", content: "Request #{i}"}],
              provider: :gemini,
              config_provider: ExLLM.ConfigProvider.Env,
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
          assert %ExLLM.Types.LLMResponse{} = response
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
      auth_methods = [
        %{api_key: @api_key},
        %{oauth_token: "test-token"}
      ]

      Enum.each(auth_methods, fn auth_opts ->
        # These should at least validate without throwing exceptions
        assert {:error, _} = Models.list_models(auth_opts)
        assert {:error, _} = Files.list_files(auth_opts)
        assert {:error, _} = Corpus.list_corpora(auth_opts)
      end)
    end
  end
end
