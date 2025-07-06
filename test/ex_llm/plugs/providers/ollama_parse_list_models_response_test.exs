defmodule ExLLM.Plugs.Providers.OllamaParseListModelsResponseTest do
  use ExUnit.Case, async: true

  alias ExLLM.Pipeline.Request
  alias ExLLM.Plugs.Providers.OllamaParseListModelsResponse
  alias ExLLM.Types.Model

  describe "parse list models response" do
    test "uses model config for known models" do
      # Create a mock response with a model that exists in ollama.yml
      response = %Tesla.Env{
        status: 200,
        body: %{
          "models" => [
            %{
              "size" => 3_826_793_344,
              "modified_at" => "2024-01-15T10:30:00Z",
              "name" => "llama2:latest"
            }
          ]
        }
      }

      request = %Request{
        id: "test-request-1",
        provider: :ollama,
        messages: [],
        response: response,
        state: :pending
      }

      result = OllamaParseListModelsResponse.call(request, [])

      assert result.state == :completed
      assert [model] = result.result
      assert %Model{} = model
      assert model.id == "llama2:latest"
      assert model.name == "llama2:latest"
      # From ollama.yml config
      assert model.context_window == 4096
      assert model.capabilities == ["chat", "streaming"]
    end

    test "falls back to defaults for unknown models" do
      # Create a mock response with an unknown model
      response = %Tesla.Env{
        status: 200,
        body: %{
          "models" => [
            %{
              "size" => 1_000_000_000,
              "modified_at" => "2024-01-15T10:30:00Z",
              "name" => "unknown-model:v1"
            }
          ]
        }
      }

      request = %Request{
        id: "test-request-1",
        provider: :ollama,
        messages: [],
        response: response,
        state: :pending
      }

      result = OllamaParseListModelsResponse.call(request, [])

      assert result.state == :completed
      assert [model] = result.result
      assert %Model{} = model
      assert model.id == "unknown-model:v1"
      # Default values
      assert model.context_window == 4_096
      assert model.max_output_tokens == 2_048
      assert model.capabilities == ["chat"]
    end

    test "handles models with different name formats" do
      # Test a model that might have the ollama/ prefix in config
      response = %Tesla.Env{
        status: 200,
        body: %{
          "models" => [
            %{
              "size" => 5_000_000_000,
              "modified_at" => "2024-01-15T10:30:00Z",
              "name" => "codegemma"
            }
          ]
        }
      }

      request = %Request{
        id: "test-request-1",
        provider: :ollama,
        messages: [],
        response: response,
        state: :pending
      }

      result = OllamaParseListModelsResponse.call(request, [])

      assert result.state == :completed
      assert [model] = result.result
      assert %Model{} = model
      assert model.id == "codegemma"
      # Should find ollama/codegemma in config
      assert model.context_window == 8192
      assert model.max_output_tokens == 8192
    end

    test "handles embedding models correctly" do
      # Test an embedding model
      response = %Tesla.Env{
        status: 200,
        body: %{
          "models" => [
            %{
              "size" => 274_000_000,
              "modified_at" => "2024-01-15T10:30:00Z",
              "name" => "nomic-embed-text:latest"
            }
          ]
        }
      }

      request = %Request{
        id: "test-request-1",
        provider: :ollama,
        messages: [],
        response: response,
        state: :pending
      }

      result = OllamaParseListModelsResponse.call(request, [])

      assert result.state == :completed
      assert [model] = result.result
      assert %Model{} = model
      assert model.id == "nomic-embed-text:latest"
      # Should not add "chat" capability for embedding models
      assert model.capabilities == ["embeddings", "streaming"]
    end

    test "handles 404 response when Ollama is not running" do
      response = %Tesla.Env{
        status: 404,
        body: "Not Found"
      }

      request = %Request{
        id: "test-request-1",
        provider: :ollama,
        messages: [],
        response: response,
        state: :pending
      }

      result = OllamaParseListModelsResponse.call(request, [])

      assert result.state == :error
      assert [error] = result.errors
      assert error.type == :service_unavailable
      assert error.message =~ "Ollama service not running"
    end
  end
end
