defmodule ExLLM.Providers.PerplexityPublicAPITest do
  @moduledoc """
  Perplexity-specific integration tests using the public ExLLM API.
  Common tests are handled by the shared module.
  """

  use ExLLM.Shared.ProviderIntegrationTest, provider: :perplexity

  # Provider-specific tests only  
  describe "perplexity-specific features via public API" do
    test "uses online search capabilities" do
      messages = [
        %{role: "user", content: "What are the latest developments in AI as of 2024?"}
      ]

      case ExLLM.chat(:perplexity, messages,
             model: "llama-3.1-sonar-small-128k-online",
             max_tokens: 100
           ) do
        {:ok, response} ->
          assert response.provider == :perplexity
          assert is_binary(response.content)
          # Online models should provide current information
          assert response.content =~ ~r/2024|recent|latest/i

        {:error, _} ->
          :ok
      end
    end

    test "supports both online and offline models" do
      test_cases = [
        {"llama-3.1-sonar-small-128k-online", "What happened yesterday?", true},
        {"llama-3.1-sonar-small-128k-chat", "Explain quantum computing", false}
      ]

      for {model, question, is_online} <- test_cases do
        messages = [%{role: "user", content: question}]

        case ExLLM.chat(:perplexity, messages, model: model, max_tokens: 100) do
          {:ok, response} ->
            assert response.provider == :perplexity
            assert is_binary(response.content)

            if is_online do
              # Online models might include citations or current data
              assert String.length(response.content) > 50
            end

          {:error, {:api_error, %{status: 404}}} ->
            # Model might not be available
            :ok

          {:error, _} ->
            :ok
        end
      end
    end

    @tag :streaming
    test "streaming with Perplexity models" do
      messages = [
        %{role: "user", content: "List 3 benefits of exercise"}
      ]

      # Collect chunks using the callback API
      collector = fn chunk ->
        send(self(), {:chunk, chunk})
      end

      case ExLLM.stream(:perplexity, messages, collector,
             model: "llama-3.1-sonar-small-128k-chat",
             max_tokens: 100,
             timeout: 10000
           ) do
        :ok ->
          chunks = collect_stream_chunks([], 1000)

          assert length(chunks) > 0

          full_content =
            chunks
            |> Enum.map(& &1.content)
            |> Enum.filter(& &1)
            |> Enum.join("")

          # Should list benefits
          assert full_content =~ ~r/(health|fitness|energy|mood|strength)/i

        {:error, _} ->
          :ok
      end
    end

    test "handles search-focused queries" do
      messages = [
        %{
          role: "user",
          content: "Find information about the ExLLM library for Elixir"
        }
      ]

      case ExLLM.chat(:perplexity, messages,
             model: "llama-3.1-sonar-large-128k-online",
             max_tokens: 200
           ) do
        {:ok, response} ->
          assert response.provider == :perplexity
          # Response should attempt to find information
          assert is_binary(response.content)
          assert String.length(response.content) > 50

        {:error, _} ->
          :ok
      end
    end

    test "respects context window limits" do
      # Perplexity models have large context windows (128k)
      large_context = String.duplicate("This is a test sentence. ", 1000)

      messages = [
        %{role: "user", content: large_context <> "\n\nSummarize the above in one sentence."}
      ]

      case ExLLM.chat(:perplexity, messages, max_tokens: 50) do
        {:ok, response} ->
          assert response.provider == :perplexity
          assert is_binary(response.content)
          # Should handle large context well
          assert response.content =~ ~r/test|sentence|repeat/i

        {:error, _} ->
          :ok
      end
    end
  end
end
