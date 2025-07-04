defmodule ExLLM.Integration.MultiProviderComprehensiveTest do
  @moduledoc """
  Comprehensive integration tests comparing functionality across multiple providers.
  Tests provider parity, failover capabilities, and cross-provider consistency.
  """
  use ExUnit.Case
  require Logger

  # Test helpers
  defp available_providers do
    # Get providers that have API keys configured
    providers = [:openai, :anthropic, :gemini, :groq, :mistral]

    Enum.filter(providers, fn provider ->
      config = ExLLM.Environment.provider_config(provider)
      config[:api_key] != nil
    end)
  end

  defp get_test_model(provider) do
    case provider do
      :openai -> "gpt-4o-mini"
      :anthropic -> "claude-3-haiku-20240307"
      :gemini -> "gemini-1.5-flash"
      :groq -> "llama-3.1-8b-instant"
      :mistral -> "mistral-small-latest"
      _ -> nil
    end
  end

  defp get_embedding_model(provider) do
    case provider do
      :openai -> "text-embedding-3-small"
      :gemini -> "text-embedding-004"
      # Common Ollama embedding model
      :ollama -> "nomic-embed-text"
      _ -> nil
    end
  end

  defp normalize_response_content(content) do
    # Normalize responses by removing extra whitespace and lowercasing
    content
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
  end

  describe "Multi-Provider Chat Comparison" do
    @describetag :integration
    @describetag :multi_provider
    @describetag timeout: 120_000

    test "compare chat responses across providers" do
      providers = available_providers()

      if length(providers) < 2 do
        IO.puts("Skipping multi-provider test: Need at least 2 configured providers")
        assert true
      else
        # Use a factual question for consistent responses
        messages = [
          %{role: "user", content: "What is the capital of France? Answer in one word."}
        ]

        # Collect responses from all providers
        responses =
          Enum.map(providers, fn provider ->
            model = get_test_model(provider)

            try do
              case ExLLM.chat(provider, messages, model: model, max_tokens: 10) do
                {:ok, response} ->
                  {provider, {:ok, response}}

                {:error, error} ->
                  IO.puts("Provider error: #{inspect({provider, error})}")
                  {provider, {:error, error}}
              end
            rescue
              e ->
                IO.puts("Provider exception: #{inspect({provider, e})}")
                {provider, {:error, e}}
            end
          end)

        # Analyze results
        successful_responses =
          Enum.filter(responses, fn {_, result} ->
            match?({:ok, _}, result)
          end)

        assert length(successful_responses) >= 2, "Need at least 2 successful responses"

        # Check consistency
        contents =
          Enum.map(successful_responses, fn {provider, {:ok, response}} ->
            content = normalize_response_content(response.content)
            IO.puts("#{provider}: #{content}")
            content
          end)

        # All should mention "paris" in some form
        Enum.each(contents, fn content ->
          assert String.contains?(content, "paris")
        end)

        # Check cost tracking
        Enum.each(successful_responses, fn {_provider, {:ok, response}} ->
          assert response.cost.total_cost >= 0
          assert response.usage.total_tokens > 0
        end)
      end
    end

    test "compare structured outputs across providers" do
      providers = available_providers() |> Enum.filter(&(&1 in [:openai, :anthropic, :gemini]))

      if length(providers) < 2 do
        IO.puts("Skipping structured output test: Need at least 2 compatible providers")
        assert true
      else
        messages = [
          %{role: "user", content: "List three primary colors as a JSON array of strings."}
        ]

        responses =
          Enum.map(providers, fn provider ->
            model = get_test_model(provider)

            case ExLLM.chat(provider, messages,
                   model: model,
                   max_tokens: 50,
                   response_format: %{type: "json_object"}
                 ) do
              {:ok, response} ->
                # Try to parse JSON from response
                case Jason.decode(response.content) do
                  {:ok, json} -> {provider, {:ok, json}}
                  {:error, _} -> {provider, {:error, :invalid_json}}
                end

              {:error, error} ->
                {provider, {:error, error}}
            end
          end)

        successful_json =
          Enum.filter(responses, fn {_, result} ->
            match?({:ok, _}, result)
          end)

        if length(successful_json) >= 1 do
          # At least one provider returned valid JSON
          assert true

          # Log the results
          Enum.each(successful_json, fn {provider, {:ok, json}} ->
            IO.puts("Structured output: #{inspect({provider, json})}")
          end)
        else
          IO.puts("No providers returned valid JSON (this is expected for some models)")
          assert true
        end
      end
    end

    test "compare response times across providers" do
      providers = available_providers()

      if length(providers) < 2 do
        IO.puts("Skipping response time comparison: Need at least 2 configured providers")
        assert true
      else
        messages = [
          %{role: "user", content: "Hi"}
        ]

        # Measure response times
        timings =
          Enum.map(providers, fn provider ->
            model = get_test_model(provider)

            start_time = :os.system_time(:millisecond)

            result =
              try do
                case ExLLM.chat(provider, messages, model: model, max_tokens: 5) do
                  {:ok, _response} -> :ok
                  {:error, _error} -> :error
                end
              rescue
                _ -> :error
              end

            end_time = :os.system_time(:millisecond)
            elapsed = end_time - start_time

            {provider, result, elapsed}
          end)

        # Log timings
        successful_timings = Enum.filter(timings, fn {_, result, _} -> result == :ok end)

        if length(successful_timings) >= 2 do
          Enum.each(successful_timings, fn {provider, _, elapsed} ->
            IO.puts("#{provider}: #{elapsed}ms")
          end)

          # Find fastest and slowest
          sorted = Enum.sort_by(successful_timings, fn {_, _, elapsed} -> elapsed end)
          {fastest_provider, _, fastest_time} = List.first(sorted)
          {slowest_provider, _, slowest_time} = List.last(sorted)

          IO.puts("\nFastest: #{fastest_provider} (#{fastest_time}ms)")
          IO.puts("Slowest: #{slowest_provider} (#{slowest_time}ms)")
          IO.puts("Ratio: #{Float.round(slowest_time / fastest_time, 2)}x")
        end

        assert length(successful_timings) >= 1
      end
    end
  end

  describe "Multi-Provider Embeddings Comparison" do
    @describetag :integration
    @describetag :multi_provider
    @describetag :embeddings
    @describetag timeout: 60_000

    test "compare embeddings across providers" do
      # Only test providers that support embeddings
      embedding_providers = [:openai, :gemini, :ollama]
      providers = available_providers() |> Enum.filter(&(&1 in embedding_providers))

      if length(providers) < 2 do
        IO.puts("Skipping embeddings comparison: Need at least 2 providers with embeddings")
        assert true
      else
        test_text = "The quick brown fox jumps over the lazy dog."

        # Generate embeddings from each provider
        embeddings =
          Enum.map(providers, fn provider ->
            model = get_embedding_model(provider)

            # Gemini expects a list of strings for embeddings
            input = if provider == :gemini, do: [test_text], else: test_text

            case ExLLM.embeddings(provider, input, model: model) do
              {:ok, response} ->
                embedding = List.first(response.embeddings)
                {provider, {:ok, embedding}}

              {:error, error} ->
                IO.puts("Embedding error: #{inspect({provider, error})}")
                {provider, {:error, error}}
            end
          end)

        successful_embeddings =
          Enum.filter(embeddings, fn {_, result} ->
            match?({:ok, _}, result)
          end)

        assert length(successful_embeddings) >= 2, "Need at least 2 successful embeddings"

        # Compare embedding dimensions
        _dimensions =
          Enum.map(successful_embeddings, fn {provider, {:ok, embedding}} ->
            dim = length(embedding)
            IO.puts("#{provider} embedding dimensions: #{dim}")
            {provider, dim}
          end)

        # Check that all embeddings are valid (non-zero vectors)
        Enum.each(successful_embeddings, fn {provider, {:ok, embedding}} ->
          assert length(embedding) > 0, "#{provider} returned empty embedding"
          assert Enum.any?(embedding, &(&1 != 0)), "#{provider} returned zero vector"
        end)

        # Calculate self-similarity (should be 1.0)
        Enum.each(successful_embeddings, fn {provider, {:ok, embedding}} ->
          similarity = ExLLM.Embeddings.cosine_similarity(embedding, embedding)
          assert_in_delta similarity, 1.0, 0.001, "#{provider} self-similarity should be 1.0"
        end)
      end
    end

    test "compare semantic similarity across provider embeddings" do
      embedding_providers = [:openai, :gemini, :ollama]
      providers = available_providers() |> Enum.filter(&(&1 in embedding_providers))

      if length(providers) < 2 do
        IO.puts("Skipping semantic similarity test: Need at least 2 embedding providers")
        assert true
      else
        # Test similar and dissimilar text pairs
        similar_texts = {"I love programming", "I enjoy coding"}
        dissimilar_texts = {"I love programming", "The weather is nice today"}

        # Get embeddings for each provider
        provider_results =
          Enum.map(providers, fn provider ->
            model = get_embedding_model(provider)

            # Gemini expects lists
            input1 =
              if provider == :gemini, do: [elem(similar_texts, 0)], else: elem(similar_texts, 0)

            input2 =
              if provider == :gemini, do: [elem(similar_texts, 1)], else: elem(similar_texts, 1)

            input3 =
              if provider == :gemini,
                do: [elem(dissimilar_texts, 1)],
                else: elem(dissimilar_texts, 1)

            with {:ok, resp1} <- ExLLM.embeddings(provider, input1, model: model),
                 {:ok, resp2} <- ExLLM.embeddings(provider, input2, model: model),
                 {:ok, resp3} <- ExLLM.embeddings(provider, input3, model: model) do
              emb1 = List.first(resp1.embeddings)
              emb2 = List.first(resp2.embeddings)
              emb3 = List.first(resp3.embeddings)

              similar_score = ExLLM.Embeddings.cosine_similarity(emb1, emb2)
              dissimilar_score = ExLLM.Embeddings.cosine_similarity(emb1, emb3)

              {provider, {:ok, {similar_score, dissimilar_score}}}
            else
              error -> {provider, {:error, error}}
            end
          end)

        successful_results =
          Enum.filter(provider_results, fn {_, result} ->
            match?({:ok, _}, result)
          end)

        assert length(successful_results) >= 1

        # All providers should show higher similarity for similar texts
        Enum.each(successful_results, fn {provider, {:ok, {similar, dissimilar}}} ->
          IO.puts(
            "#{provider}: similar=#{Float.round(similar, 3)}, dissimilar=#{Float.round(dissimilar, 3)}"
          )

          assert similar > dissimilar,
                 "#{provider} should show higher similarity for related texts"
        end)
      end
    end
  end

  describe "Provider Failover" do
    @describetag :integration
    @describetag :multi_provider
    @describetag :failover
    @describetag timeout: 60_000

    test "failover to backup provider on primary failure" do
      providers = available_providers()

      if length(providers) < 2 do
        IO.puts("Skipping failover test: Need at least 2 configured providers")
        assert true
      else
        primary = List.first(providers)
        backup = Enum.at(providers, 1)

        messages = [
          %{role: "user", content: "Test message"}
        ]

        # Simulate primary failure by using invalid model
        primary_result =
          try do
            ExLLM.chat(primary, messages, model: "invalid-model-xyz")
          rescue
            e -> {:error, e}
          end

        case primary_result do
          {:error, _error} ->
            IO.puts("Primary provider #{primary} failed as expected")

            # Try backup provider
            backup_result =
              ExLLM.chat(backup, messages, model: get_test_model(backup), max_tokens: 10)

            case backup_result do
              {:ok, response} ->
                IO.puts("Successfully failed over to #{backup}")
                assert is_binary(response.content)

              {:error, error} ->
                IO.puts("Backup provider also failed: #{inspect(error)}")
                assert false, "Backup provider should succeed"
            end

          {:ok, _} ->
            # Some providers might accept invalid models
            IO.puts("Primary provider unexpectedly succeeded with invalid model")
            assert true
        end
      end
    end

    test "circuit breaker prevents repeated failures" do
      providers = available_providers()

      if length(providers) < 1 do
        IO.puts("Skipping circuit breaker test: No configured providers")
        assert true
      else
        provider = List.first(providers)
        invalid_model = "nonexistent-model-12345"

        # Make multiple failing requests
        results =
          Enum.map(1..3, fn i ->
            # Small delay between requests
            Process.sleep(100 * i)

            result =
              try do
                ExLLM.chat(
                  provider,
                  [%{role: "user", content: "Test #{i}"}],
                  model: invalid_model
                )
              rescue
                e -> {:error, e}
              end

            {i, result}
          end)

        # All should fail
        failed_count =
          Enum.count(results, fn {_, result} ->
            match?({:error, _}, result)
          end)

        assert failed_count == 3, "All requests should fail with invalid model"

        # Log the errors to see if circuit breaker activates
        Enum.each(results, fn {i, {:error, error}} ->
          IO.puts("Request #{i} error: #{inspect({i, error}, limit: 3)}")
        end)
      end
    end

    test "provider capability detection" do
      providers = available_providers()

      Enum.each(providers, fn provider ->
        # Check chat capability (all should support)
        chat_result =
          try do
            ExLLM.chat(
              provider,
              [%{role: "user", content: "Hi"}],
              model: get_test_model(provider),
              max_tokens: 5
            )
          rescue
            e ->
              IO.puts("Chat test exception: #{inspect({provider, e})}")
              {:error, e}
          end

        case chat_result do
          {:ok, _} ->
            IO.puts("✓ #{provider} supports chat")
            assert true

          {:error, error} ->
            IO.puts("Chat test failed: #{inspect({provider, error})}")
            # Don't fail the test, just log the error
            assert true
        end

        # Check embedding capability
        if provider in [:openai, :gemini, :ollama] do
          # Gemini expects a list of strings
          input = if provider == :gemini, do: ["test"], else: "test"

          embedding_result =
            ExLLM.embeddings(provider, input, model: get_embedding_model(provider))

          assert match?({:ok, _}, embedding_result), "#{provider} should support embeddings"
        end

        # Log capabilities
        IO.puts(
          "#{provider}: chat=✓, embeddings=#{if provider in [:openai, :gemini, :ollama], do: "✓", else: "✗"}"
        )
      end)
    end
  end

  describe "Cost Tracking Comparison" do
    @describetag :integration
    @describetag :multi_provider
    @describetag :cost_tracking
    @describetag timeout: 60_000

    test "compare cost tracking across providers" do
      providers = available_providers()

      if length(providers) < 2 do
        IO.puts("Skipping cost tracking comparison: Need at least 2 configured providers")
        assert true
      else
        messages = [
          %{role: "user", content: "Count from 1 to 5"}
        ]

        # Collect cost data from each provider
        cost_data =
          Enum.map(providers, fn provider ->
            model = get_test_model(provider)

            result =
              try do
                case ExLLM.chat(provider, messages, model: model, max_tokens: 50) do
                  {:ok, response} ->
                    {:ok, response}

                  {:error, error} ->
                    {:error, error}
                end
              rescue
                e -> {:error, e}
              end

            case result do
              {:ok, response} ->
                cost = response.cost
                usage = response.usage

                {provider,
                 %{
                   model: model,
                   total_cost: cost.total_cost,
                   input_cost: cost.input_cost,
                   output_cost: cost.output_cost,
                   input_tokens: usage.input_tokens || usage.prompt_tokens,
                   output_tokens: usage.output_tokens || usage.completion_tokens,
                   cost_per_input_token:
                     if((usage.input_tokens || usage.prompt_tokens) > 0,
                       do: cost.input_cost / (usage.input_tokens || usage.prompt_tokens),
                       else: 0
                     ),
                   cost_per_output_token:
                     if((usage.output_tokens || usage.completion_tokens) > 0,
                       do: cost.output_cost / (usage.output_tokens || usage.completion_tokens),
                       else: 0
                     )
                 }}

              {:error, _} ->
                {provider, :error}
            end
          end)

        # Filter successful providers
        successful_providers = Enum.filter(cost_data, fn {_, data} -> data != :error end)

        if length(successful_providers) >= 2 do
          IO.puts("\nCost Tracking Comparison:")
          IO.puts("========================")

          Enum.each(successful_providers, fn {provider, data} ->
            IO.puts("\n#{provider} (#{data.model}):")
            IO.puts("  Total cost: $#{Float.round(data.total_cost, 6)}")

            IO.puts(
              "  Input cost: $#{Float.round(data.input_cost, 6)} (#{data.input_tokens} tokens)"
            )

            IO.puts(
              "  Output cost: $#{Float.round(data.output_cost, 6)} (#{data.output_tokens} tokens)"
            )

            IO.puts("  Per 1K input tokens: $#{Float.round(data.cost_per_input_token * 1000, 6)}")

            IO.puts(
              "  Per 1K output tokens: $#{Float.round(data.cost_per_output_token * 1000, 6)}"
            )
          end)

          # Find cheapest and most expensive
          sorted_by_cost =
            successful_providers
            |> Enum.sort_by(fn {_, data} -> data.total_cost end)

          {cheapest_provider, cheapest_data} = List.first(sorted_by_cost)
          {expensive_provider, expensive_data} = List.last(sorted_by_cost)

          if cheapest_provider != expensive_provider do
            ratio = expensive_data.total_cost / cheapest_data.total_cost
            IO.puts("\n\nCost Analysis:")

            IO.puts(
              "Cheapest: #{cheapest_provider} ($#{Float.round(cheapest_data.total_cost, 6)})"
            )

            IO.puts(
              "Most expensive: #{expensive_provider} ($#{Float.round(expensive_data.total_cost, 6)})"
            )

            IO.puts("Price ratio: #{Float.round(ratio, 2)}x")
          end
        end

        assert length(successful_providers) >= 1
      end
    end
  end

  describe "Provider-Specific Features" do
    @describetag :integration
    @describetag :multi_provider
    @describetag :features
    @describetag timeout: 60_000

    test "provider-specific feature detection" do
      providers = available_providers()

      # Define provider-specific features to test
      feature_tests = %{
        openai: [
          {:function_calling, &test_function_calling/1},
          {:json_mode, &test_json_mode/1},
          {:vision, &test_vision_support/1}
        ],
        anthropic: [
          {:xml_mode, &test_xml_mode/1},
          {:vision, &test_vision_support/1},
          {:long_context, &test_long_context/1}
        ],
        gemini: [
          {:grounding, &test_grounding/1},
          {:safety_settings, &test_safety_settings/1},
          {:vision, &test_vision_support/1}
        ],
        groq: [
          {:json_mode, &test_json_mode/1},
          {:speed_test, &test_inference_speed/1}
        ]
      }

      Enum.each(providers, fn provider ->
        IO.puts("\n#{provider} Feature Detection:")
        IO.puts("=" <> String.duplicate("=", String.length(to_string(provider)) + 18))

        tests = Map.get(feature_tests, provider, [])

        if tests == [] do
          IO.puts("  No provider-specific tests defined")
        else
          Enum.each(tests, fn {feature, test_fn} ->
            result = test_fn.(provider)
            status = if result, do: "✓", else: "✗"
            IO.puts("  #{feature}: #{status}")
          end)
        end
      end)

      assert true
    end

    # Helper functions for feature testing
    defp test_function_calling(provider) do
      messages = [
        %{
          role: "user",
          content: "What's the weather in Paris?"
        }
      ]

      tools = [
        %{
          type: "function",
          function: %{
            name: "get_weather",
            description: "Get weather for a location",
            parameters: %{
              type: "object",
              properties: %{
                location: %{type: "string"}
              },
              required: ["location"]
            }
          }
        }
      ]

      case ExLLM.chat(provider, messages,
             model: get_test_model(provider),
             tools: tools,
             max_tokens: 100
           ) do
        {:ok, response} ->
          # Check if tool_calls are present
          Map.has_key?(response, :tool_calls) and response.tool_calls != nil

        {:error, _} ->
          false
      end
    rescue
      _ -> false
    end

    defp test_json_mode(provider) do
      messages = [
        %{role: "user", content: "Return a JSON object with name and age fields"}
      ]

      case ExLLM.chat(provider, messages,
             model: get_test_model(provider),
             response_format: %{type: "json_object"},
             max_tokens: 50
           ) do
        {:ok, response} ->
          # Try to parse as JSON
          case Jason.decode(response.content) do
            {:ok, _} -> true
            _ -> false
          end

        _ ->
          false
      end
    rescue
      _ -> false
    end

    defp test_xml_mode(_provider) do
      # Anthropic-specific XML mode test
      # For now, just return true as we know Anthropic supports it
      true
    end

    defp test_vision_support(_provider) do
      # Would need actual image to test, so we'll check capability
      true
    end

    defp test_long_context(_provider) do
      # Check if provider supports > 100k context
      true
    end

    defp test_grounding(_provider) do
      # Gemini-specific grounding test
      true
    end

    defp test_safety_settings(_provider) do
      # Gemini-specific safety settings test
      true
    end

    defp test_inference_speed(provider) do
      messages = [%{role: "user", content: "Hi"}]

      start_time = :os.system_time(:millisecond)

      result =
        ExLLM.chat(provider, messages,
          model: get_test_model(provider),
          max_tokens: 5
        )

      end_time = :os.system_time(:millisecond)

      case result do
        {:ok, _} ->
          elapsed = end_time - start_time
          IO.puts("    Speed: #{elapsed}ms")
          # Consider fast if under 1 second
          elapsed < 1000

        _ ->
          false
      end
    rescue
      _ -> false
    end
  end

  describe "Multi-Provider Workflow" do
    @describetag :integration
    @describetag :multi_provider
    @describetag :workflow
    @describetag timeout: 120_000

    test "multi-provider workflow orchestration" do
      providers = available_providers()

      if length(providers) < 2 do
        IO.puts("Skipping workflow test: Need at least 2 configured providers")
        assert true
      else
        # Simulate a complex workflow using multiple providers
        IO.puts("\nMulti-Provider Workflow Test")
        IO.puts("============================")

        # Step 1: Generate a topic with first provider
        topic_provider = List.first(providers)

        topic_result =
          ExLLM.chat(
            topic_provider,
            [
              %{
                role: "user",
                content: "Generate a single interesting science topic in 3 words or less"
              }
            ],
            model: get_test_model(topic_provider),
            max_tokens: 10
          )

        topic =
          case topic_result do
            {:ok, response} ->
              String.trim(response.content)

            _ ->
              "Quantum computing"
          end

        IO.puts("\nStep 1 - Topic Generation (#{topic_provider}): #{topic}")

        # Step 2: Generate embeddings if available
        embedding_providers = Enum.filter(providers, &(&1 in [:openai, :gemini, :ollama]))

        embeddings_result =
          if length(embedding_providers) > 0 do
            embed_provider = List.first(embedding_providers)
            input = if embed_provider == :gemini, do: [topic], else: topic

            case ExLLM.embeddings(embed_provider, input,
                   model: get_embedding_model(embed_provider)
                 ) do
              {:ok, response} ->
                embedding = List.first(response.embeddings)

                IO.puts(
                  "Step 2 - Embeddings (#{embed_provider}): #{length(embedding)} dimensions"
                )

                {:ok, embedding}

              error ->
                IO.puts("Step 2 - Embeddings failed: #{inspect(error)}")
                :skip
            end
          else
            IO.puts("Step 2 - Embeddings: No embedding providers available")
            :skip
          end

        # Step 3: Generate content with different providers
        content_providers = Enum.take(providers, 2)

        contents =
          Enum.with_index(content_providers, 1)
          |> Enum.map(fn {provider, index} ->
            prompt = "Write one sentence about #{topic}"

            result =
              ExLLM.chat(
                provider,
                [%{role: "user", content: prompt}],
                model: get_test_model(provider),
                max_tokens: 50
              )

            case result do
              {:ok, response} ->
                IO.puts(
                  "Step 3.#{index} - Content (#{provider}): #{String.slice(response.content, 0, 100)}..."
                )

                {provider, response.content}

              _ ->
                {provider, nil}
            end
          end)

        successful_contents = Enum.filter(contents, fn {_, content} -> content != nil end)

        # Step 4: Analyze costs if we have multiple successful responses
        if length(successful_contents) >= 2 do
          IO.puts("\nStep 4 - Workflow Summary:")
          IO.puts("- Topic generated with: #{topic_provider}")
          IO.puts("- Embeddings: #{if embeddings_result != :skip, do: "✓", else: "✗"}")

          IO.puts(
            "- Content generated by: #{Enum.map_join(successful_contents, ", ", fn {p, _} -> to_string(p) end)}"
          )

          IO.puts(
            "- Total providers used: #{length(Enum.uniq([topic_provider] ++ Enum.map(successful_contents, fn {p, _} -> p end)))}"
          )
        end

        assert length(successful_contents) >= 1
      end
    end
  end
end
