defmodule ExLLM.PerplexityIntegrationTest do
  use ExUnit.Case
  alias ExLLM.Adapters.Perplexity
  alias ExLLM.Types

  @moduletag :integration
  @moduletag :perplexity

  # These tests require a Perplexity API key
  # Run with: mix test --only perplexity

  setup_all do
    case check_perplexity_api() do
      :ok ->
        :ok

      {:error, reason} ->
        IO.puts("\nSkipping Perplexity integration tests: #{reason}")
        :ok
    end
  end

  describe "chat/2 with real API" do
    @tag :skip
    test "generates response with sonar model" do
      messages = [%{role: "user", content: "What is the capital of France?"}]

      result = Perplexity.chat(messages, model: "perplexity/sonar")

      case result do
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          assert is_binary(response.content)
          assert response.content != ""
          assert String.contains?(String.downcase(response.content), "paris")
          assert response.usage.input_tokens > 0
          assert response.usage.output_tokens > 0
          assert response.model == "perplexity/sonar"

        {:error, reason} ->
          IO.puts("Perplexity API error: #{inspect(reason)}")
      end
    end

    @tag :skip
    test "handles web search with sonar-pro model" do
      messages = [%{role: "user", content: "What's the latest news in AI today?"}]

      result =
        Perplexity.chat(messages,
          model: "perplexity/sonar-pro",
          search_mode: "news"
        )

      case result do
        {:ok, response} ->
          assert %Types.LLMResponse{} = response
          # Should include recent information
          assert String.length(response.content) > 50
          # May include citations
          assert response.content =~ ~r/\w+/

        {:error, _reason} ->
          :ok
      end
    end

    @tag :skip
    test "handles academic search mode" do
      messages = [%{role: "user", content: "What are the latest findings on quantum computing?"}]

      result =
        Perplexity.chat(messages,
          model: "perplexity/sonar-pro",
          search_mode: "academic",
          web_search_options: %{search_context_size: "large"}
        )

      case result do
        {:ok, response} ->
          assert response.content != ""
          # Academic responses often include citations
          assert String.contains?(response.content, "[") or String.length(response.content) > 100

        {:error, _reason} ->
          :ok
      end
    end

    @tag :skip
    test "handles reasoning effort for deep research" do
      messages = [
        %{role: "user", content: "Analyze the pros and cons of renewable energy adoption"}
      ]

      result =
        Perplexity.chat(messages,
          model: "perplexity/sonar-deep-research",
          reasoning_effort: "high"
        )

      case result do
        {:ok, response} ->
          # Deep research should provide comprehensive analysis
          assert String.length(response.content) > 200
          assert response.usage.output_tokens > 100

        {:error, _reason} ->
          :ok
      end
    end

    @tag :skip
    test "handles standard LLM model without search" do
      messages = [%{role: "user", content: "Write a haiku about programming"}]

      result =
        Perplexity.chat(messages,
          model: "perplexity/llama-3.1-8b-instruct",
          temperature: 0.7
        )

      case result do
        {:ok, response} ->
          assert response.content != ""
          # Should be a short poem
          lines = String.split(response.content, "\n") |> Enum.filter(&(&1 != ""))
          assert length(lines) >= 1

        {:error, _reason} ->
          :ok
      end
    end

    @tag :skip
    test "respects max_tokens limit" do
      messages = [%{role: "user", content: "Explain machine learning in detail"}]

      result =
        Perplexity.chat(messages,
          model: "perplexity/sonar",
          max_tokens: 50
        )

      case result do
        {:ok, response} ->
          # Response should be relatively short due to token limit
          # Some buffer for stop tokens
          assert response.usage.output_tokens <= 60

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "stream_chat/2 with real API" do
    @tag :skip
    test "streams response chunks" do
      messages = [%{role: "user", content: "Count from 1 to 5 slowly"}]

      case Perplexity.stream_chat(messages, model: "perplexity/sonar") do
        {:ok, stream} ->
          chunks = stream |> Enum.take(10) |> Enum.to_list()

          assert length(chunks) > 0

          # Each chunk should be a StreamChunk
          assert Enum.all?(chunks, fn chunk ->
                   %Types.StreamChunk{} = chunk
                   is_binary(chunk.content) or is_nil(chunk.content)
                 end)

          # At least one chunk should have content
          assert Enum.any?(chunks, fn chunk ->
                   chunk.content != nil and chunk.content != ""
                 end)

        {:error, _reason} ->
          :ok
      end
    end

    @tag :skip
    test "streams with web search enabled" do
      messages = [%{role: "user", content: "What happened in tech news today?"}]

      case Perplexity.stream_chat(messages,
             model: "perplexity/sonar-pro",
             search_mode: "news"
           ) do
        {:ok, stream} ->
          chunks = Enum.to_list(stream)

          # Concatenate all content
          full_content =
            chunks
            |> Enum.map(&(&1.content || ""))
            |> Enum.join("")

          assert String.length(full_content) > 50

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "list_models/1 with API" do
    @tag :skip
    test "returns available Perplexity models" do
      case Perplexity.list_models() do
        {:ok, models} ->
          assert is_list(models)
          assert length(models) > 0

          # Check model structure
          assert Enum.all?(models, fn model ->
                   assert %Types.Model{} = model
                   assert is_binary(model.id)
                   assert is_binary(model.name)
                   assert is_integer(model.context_window)
                   assert model.context_window > 0
                 end)

          # Should include key models
          model_ids = Enum.map(models, & &1.id)
          assert Enum.any?(model_ids, &String.contains?(&1, "sonar"))

        {:error, _reason} ->
          # API might be down or key invalid
          :ok
      end
    end
  end

  describe "error handling with real API" do
    @tag :skip
    test "handles rate limiting gracefully" do
      messages = [%{role: "user", content: "Test"}]

      # Make multiple rapid requests
      results =
        for _ <- 1..5 do
          Task.async(fn ->
            Perplexity.chat(messages, model: "perplexity/sonar")
          end)
        end
        |> Enum.map(&Task.await/1)

      # Should handle rate limits without crashing
      assert Enum.all?(results, fn
               {:ok, _} -> true
               {:error, _} -> true
             end)
    end

    @tag :skip
    test "handles invalid model gracefully" do
      messages = [%{role: "user", content: "Test"}]

      result = Perplexity.chat(messages, model: "perplexity/invalid-model")

      assert {:error, reason} = result
      assert is_binary(reason)
    end
  end

  describe "Perplexity-specific features" do
    @tag :skip
    test "returns images when requested" do
      messages = [%{role: "user", content: "Show me pictures of the Eiffel Tower"}]

      result =
        Perplexity.chat(messages,
          model: "perplexity/sonar",
          return_images: true,
          image_domain_filter: ["wikipedia.org", "wikimedia.org"]
        )

      case result do
        {:ok, response} ->
          # Response should mention images or indicate search was performed
          assert response.content != ""

        {:error, _reason} ->
          :ok
      end
    end

    @tag :skip
    test "applies recency filter for recent information" do
      messages = [%{role: "user", content: "What happened in the last 24 hours?"}]

      result =
        Perplexity.chat(messages,
          model: "perplexity/sonar-pro",
          search_mode: "news",
          recency_filter: "day"
        )

      case result do
        {:ok, response} ->
          # Should return recent information
          assert String.length(response.content) > 50

        {:error, _reason} ->
          :ok
      end
    end
  end

  # Helper functions

  defp check_perplexity_api do
    config = %{perplexity: %{api_key: System.get_env("PERPLEXITY_API_KEY") || ""}}

    if config.perplexity.api_key == "" do
      {:error, "PERPLEXITY_API_KEY environment variable not set"}
    else
      :ok
    end
  end
end
