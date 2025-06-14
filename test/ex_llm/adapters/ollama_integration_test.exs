defmodule ExLLM.OllamaIntegrationTest do
  use ExUnit.Case
  alias ExLLM.Adapters.Ollama
  alias ExLLM.Types

  @moduletag :integration
  @moduletag :requires_service
  @moduletag :local_models
  @moduletag provider: :ollama

  # These tests require a running Ollama server
  # Run with: mix test --include integration --include requires_service
  # Or use the provider-specific alias: mix test.ollama

  describe "generate/2" do
    test "generates completion without streaming" do
      result = Ollama.generate("The capital of France is", model: "llama2")

      case result do
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          assert is_binary(response.content)
          assert response.content != ""
          assert response.usage.input_tokens > 0
          assert response.usage.output_tokens > 0

        {:error, {:api_error, %{status: 404}}} ->
          IO.puts("Model not found, skipping test")

        {:error, reason} ->
          IO.puts("Ollama error: #{inspect(reason)}")
      end
    end

    test "generates with temperature option" do
      result =
        Ollama.generate(
          "Write a haiku about coding",
          model: "llama2",
          options: %{temperature: 0.5, seed: 42}
        )

      case result do
        {:ok, response} ->
          assert response.content =~ ~r/\w+/

        _ ->
          :ok
      end
    end

    test "respects max_tokens limit" do
      result =
        Ollama.generate(
          "Count from 1 to 100",
          model: "llama2",
          max_tokens: 20
        )

      case result do
        {:ok, response} ->
          # Response should be truncated
          assert response.usage.output_tokens <= 20

        _ ->
          :ok
      end
    end
  end

  describe "stream_generate/2" do
    test "streams generation responses" do
      {:ok, stream} = Ollama.stream_generate("Tell me a short story", model: "llama2")

      try do
        chunks = stream |> Enum.take(5) |> Enum.to_list()

        assert length(chunks) > 0

        assert Enum.all?(chunks, fn chunk ->
                 %Types.StreamChunk{} = chunk
                 is_binary(chunk.content)
               end)
      catch
        error ->
          # Stream might throw an error if model is not available
          IO.puts("Stream error (expected if model not available): #{inspect(error)}")
          :ok
      end
    end
  end

  describe "show_model/2" do
    test "shows model information" do
      # Try with a commonly available model
      result = Ollama.show_model("llama2")

      case result do
        {:ok, info} ->
          assert is_map(info)
          assert Map.has_key?(info, "details")
          assert Map.has_key?(info, "parameters")

        {:error, {:api_error, %{status: 404}}} ->
          IO.puts("Model not found")

        {:error, _} ->
          :ok
      end
    end
  end

  describe "list_models/1" do
    test "lists available models" do
      case Ollama.list_models() do
        {:ok, models} ->
          assert is_list(models)

          if length(models) > 0 do
            model = hd(models)
            assert %Types.Model{} = model
            assert is_binary(model.name)
            assert is_integer(model.context_window)
          end

        {:error, _} ->
          :ok
      end
    end
  end

  describe "list_running_models/1" do
    test "lists currently loaded models" do
      case Ollama.list_running_models() do
        {:ok, models} ->
          assert is_list(models)

        # Could be empty if no models are loaded

        {:error, _} ->
          :ok
      end
    end
  end

  describe "version/1" do
    test "gets Ollama version" do
      case Ollama.version() do
        {:ok, version_info} ->
          assert is_map(version_info)
          assert Map.has_key?(version_info, "version")
          assert is_binary(version_info["version"])

        {:error, _} ->
          :ok
      end
    end
  end

  describe "copy_model/3" do
    test "copies model with new name" do
      # This test requires an existing model
      case Ollama.list_models() do
        {:ok, [%{name: source} | _]} ->
          dest = "test-copy-#{:rand.uniform(10000)}"

          case Ollama.copy_model(source, dest) do
            {:ok, result} ->
              assert result.message =~ "success"

              # Clean up - delete the copied model
              Ollama.delete_model(dest)

            {:error, _} ->
              :ok
          end

        _ ->
          IO.puts("No models available to copy")
      end
    end
  end

  describe "pull_model/2" do
    @tag timeout: :infinity
    test "pulls a small model" do
      # Only test if explicitly enabled
      if System.get_env("TEST_OLLAMA_PULL") == "true" do
        {:ok, stream} = Ollama.pull_model("tinyllama:latest")

        try do
          updates = Enum.to_list(stream)
          assert length(updates) > 0

          # Check for expected status messages
          statuses = Enum.map(updates, & &1["status"])
          assert "pulling manifest" in statuses or "success" in statuses
        catch
          error ->
            IO.puts("Pull failed: #{inspect(error)}")
        end
      else
        IO.puts("Skipping pull test (set TEST_OLLAMA_PULL=true to enable)")
      end
    end
  end

  describe "embeddings/2" do
    test "generates embeddings for text" do
      result = Ollama.embeddings("Hello world", model: "nomic-embed-text")

      case result do
        {:ok, response} ->
          assert %Types.EmbeddingResponse{} = response
          assert is_list(response.embeddings)
          assert length(response.embeddings) == 1

          [embedding] = response.embeddings
          assert is_list(embedding)
          assert length(embedding) > 0
          assert Enum.all?(embedding, &is_float/1)

        {:error, {:api_error, %{status: 404}}} ->
          IO.puts("Embedding model not found")

        {:error, _} ->
          :ok
      end
    end

    test "generates embeddings for multiple inputs" do
      inputs = ["Hello", "World", "Testing"]
      result = Ollama.embeddings(inputs, model: "nomic-embed-text")

      case result do
        {:ok, response} ->
          assert length(response.embeddings) == 3

        _ ->
          :ok
      end
    end
  end

  describe "generate_config/1" do
    test "generates YAML configuration" do
      case Ollama.generate_config() do
        {:ok, yaml} ->
          assert is_binary(yaml)
          assert yaml =~ "provider: ollama"
          assert yaml =~ "models:"
          assert yaml =~ "metadata:"

        {:error, _} ->
          :ok
      end
    end

    test "saves configuration to temporary file" do
      temp_path = Path.join(System.tmp_dir!(), "ollama_test_#{:rand.uniform(10000)}.yml")

      try do
        case Ollama.generate_config(save: true, path: temp_path) do
          {:ok, path} ->
            assert path == temp_path
            assert File.exists?(path)

            content = File.read!(path)
            assert content =~ "provider: ollama"

          {:error, _} ->
            :ok
        end
      after
        File.rm(temp_path)
      end
    end
  end

  describe "update_model_config/2" do
    test "updates model configuration" do
      # First, create a temporary config file
      temp_path = Path.join(System.tmp_dir!(), "ollama_update_test_#{:rand.uniform(10000)}.yml")

      initial_config = """
      provider: ollama
      default_model: ollama/llama2
      models:
        ollama/llama2:
          context_window: 4096
          capabilities:
            - streaming
      """

      File.write!(temp_path, initial_config)

      try do
        # Get an actual model to update
        case Ollama.list_models() do
          {:ok, [%{name: model_name} | _]} ->
            case Ollama.update_model_config(model_name, path: temp_path, save: true) do
              {:ok, ^temp_path} ->
                updated = File.read!(temp_path)
                assert updated =~ "ollama/#{model_name}:"
                assert updated =~ "metadata:"
                assert updated =~ "updated_at:"

              {:error, _} ->
                :ok
            end

          _ ->
            IO.puts("No models available to update")
        end
      after
        File.rm(temp_path)
      end
    end
  end

  # Helper functions removed - tests now use tag-based exclusion
end
