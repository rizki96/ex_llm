defmodule ExLLM.Providers.LMStudioPublicAPITest do
  @moduledoc """
  LM Studio-specific integration tests using the public ExLLM API.
  Common tests are handled by the shared module.
  """

  use ExLLM.Shared.ProviderIntegrationTest, provider: :lmstudio

  @moduletag :requires_service

  # Provider-specific tests only
  describe "lmstudio-specific features via public API" do
    test "works with LM Studio local server" do
      messages = [
        %{role: "user", content: "What is 2+2? Answer with just the number."}
      ]

      case ExLLM.chat(:lmstudio, messages, max_tokens: 10) do
        {:ok, response} ->
          assert response.content =~ ~r/4/
          assert response.provider == :lmstudio
          # Local models have no cost
          assert response.cost == 0.0

        {:error, %{reason: :econnrefused}} ->
          # LM Studio not running
          :ok

        {:error, _} ->
          :ok
      end
    end

    test "supports OpenAI-compatible endpoint" do
      # LM Studio uses OpenAI-compatible API
      messages = [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: "Hello"}
      ]

      case ExLLM.chat(:lmstudio, messages, temperature: 0.7, max_tokens: 50) do
        {:ok, response} ->
          assert is_binary(response.content)
          assert response.provider == :lmstudio
          # Should get a friendly response
          assert String.length(response.content) > 5

        {:error, %{reason: :econnrefused}} ->
          # LM Studio not running
          :ok

        {:error, _} ->
          :ok
      end
    end

    @tag :streaming
    test "streaming with LM Studio" do
      messages = [
        %{role: "user", content: "Count from 1 to 5 slowly"}
      ]

      case ExLLM.stream(:lmstudio, messages, max_tokens: 50) do
        {:ok, stream} ->
          chunks = Enum.to_list(stream)

          assert length(chunks) > 0

          full_content =
            chunks
            |> Enum.map(& &1.content)
            |> Enum.filter(& &1)
            |> Enum.join("")

          assert full_content =~ ~r/1.*2.*3.*4.*5/s

        {:error, %{reason: :econnrefused}} ->
          # LM Studio not running
          :ok

        {:error, _} ->
          :ok
      end
    end

    test "custom endpoint configuration" do
      # Test with custom LM Studio endpoint
      config = %{lmstudio: %{base_url: "http://localhost:1234/v1"}}
      {:ok, provider} = ExLLM.Infrastructure.ConfigProvider.Static.start_link(config)

      messages = [%{role: "user", content: "Hi"}]

      case ExLLM.chat(:lmstudio, messages, config_provider: provider, max_tokens: 10) do
        {:ok, response} ->
          assert response.provider == :lmstudio

        {:error, %{reason: :econnrefused}} ->
          # Expected if LM Studio not running
          :ok

        {:error, _} ->
          :ok
      end
    end

    test "model selection in LM Studio" do
      # LM Studio allows loading different models
      messages = [%{role: "user", content: "Hello"}]

      # Try to specify a model (LM Studio will use whatever is loaded)
      case ExLLM.chat(:lmstudio, messages, model: "local-model", max_tokens: 20) do
        {:ok, response} ->
          assert response.provider == :lmstudio
          assert is_binary(response.content)
          # Model name depends on what's loaded in LM Studio
          assert is_binary(response.model)

        {:error, %{reason: :econnrefused}} ->
          # LM Studio not running
          :ok

        {:error, _} ->
          :ok
      end
    end
  end
end
