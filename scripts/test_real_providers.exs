#!/usr/bin/env elixir

# Real Provider Testing Script for ExLLM v1.0 Pipeline Architecture
#
# This script tests the new pipeline architecture with actual provider APIs
# to ensure everything works correctly in real-world scenarios.

defmodule RealProviderTesting do
  @moduledoc """
  Comprehensive testing of ExLLM v1.0 pipeline architecture with real providers.
  """

  require Logger

  @test_message [%{role: "user", content: "Say 'Hello' in exactly one word."}]
  @embedding_text "This is a test sentence for embedding generation."

  def run_comprehensive_tests() do
    IO.puts("🚀 ExLLM v1.0 Real Provider Testing")
    IO.puts("=====================================\n")

    # Check which providers are configured
    available_providers = check_available_providers()
    
    if Enum.empty?(available_providers) do
      IO.puts("❌ No providers configured. Please set API keys in ~/.env")
      IO.puts("Required environment variables:")
      IO.puts("  - OPENAI_API_KEY")
      IO.puts("  - ANTHROPIC_API_KEY")
      IO.puts("  - GEMINI_API_KEY")
      IO.puts("  - GROQ_API_KEY")
      System.halt(1)
    end

    IO.puts("✅ Found #{length(available_providers)} configured providers: #{inspect(available_providers)}\n")

    # Test each available provider
    results = Enum.map(available_providers, fn provider ->
      IO.puts("🧪 Testing #{provider}...")
      test_provider_comprehensive(provider)
    end)

    # Print summary
    print_test_summary(results)
    
    # Test advanced features if providers are available
    if length(available_providers) > 0 do
      test_advanced_features(List.first(available_providers))
    end

    IO.puts("\n✅ Real provider testing completed!")
  end

  defp check_available_providers() do
    providers = [
      {:openai, "OPENAI_API_KEY"},
      {:anthropic, "ANTHROPIC_API_KEY"},
      {:gemini, "GEMINI_API_KEY"},
      {:groq, "GROQ_API_KEY"}
    ]

    Enum.filter(providers, fn {provider, env_var} ->
      case System.get_env(env_var) do
        nil -> false
        "" -> false
        _key -> 
          # Just check if we can get the provider's pipeline
          try do
            ExLLM.Providers.get_pipeline(provider, :chat)
            true
          rescue
            _ -> 
              IO.puts("⚠️  #{provider} API key found but provider not configured")
              false
          end
      end
    end)
    |> Enum.map(fn {provider, _} -> provider end)
  end

  defp test_provider_comprehensive(provider) do
    tests = [
      {"Basic Chat", fn -> test_basic_chat(provider) end},
      {"Builder API", fn -> test_builder_api(provider) end},
      {"List Models", fn -> test_list_models(provider) end},
      {"Enhanced Builder", fn -> test_enhanced_builder(provider) end},
      {"Error Handling", fn -> test_error_handling(provider) end}
    ]

    # Add provider-specific tests
    provider_tests = case provider do
      :openai -> [{"Embeddings", fn -> test_embeddings(provider) end}]
      :anthropic -> []
      :gemini -> [{"Embeddings", fn -> test_embeddings(provider) end}]
      :groq -> []
      _ -> []
    end

    all_tests = tests ++ provider_tests

    results = Enum.map(all_tests, fn {test_name, test_fn} ->
      IO.write("  #{test_name}: ")
      
      try do
        {time, result} = :timer.tc(test_fn)
        case result do
          {:ok, response} ->
            IO.puts("✅ (#{format_time(time)})")
            {test_name, :success, time, response}
          {:error, reason} ->
            IO.puts("❌ #{inspect(reason)}")
            {test_name, :error, time, reason}
        end
      rescue
        error ->
          IO.puts("💥 #{Exception.message(error)}")
          {test_name, :exception, 0, error}
      end
    end)

    {provider, results}
  end

  defp test_basic_chat(provider) do
    ExLLM.chat(provider, @test_message)
  end

  defp test_builder_api(provider) do
    ExLLM.build(provider, @test_message)
    |> ExLLM.with_temperature(0.7)
    |> ExLLM.execute()
  end

  defp test_list_models(provider) do
    ExLLM.list_models(provider)
  end

  defp test_enhanced_builder(provider) do
    ExLLM.build(provider, @test_message)
    |> ExLLM.with_temperature(0.1)  # Deterministic
    |> ExLLM.with_cache(ttl: 60)    # Short cache for testing
    |> ExLLM.execute()
  end

  defp test_embeddings(provider) do
    case provider do
      :openai -> 
        ExLLM.embeddings(provider, @embedding_text, model: "text-embedding-3-small")
      :gemini ->
        ExLLM.embeddings(provider, @embedding_text)
      _ ->
        {:error, :not_supported}
    end
  end

  defp test_error_handling(provider) do
    # Test with invalid model to trigger error handling
    case ExLLM.chat(provider, @test_message, model: "invalid-model-name-12345") do
      {:error, _reason} -> {:ok, "Error handled correctly"}
      {:ok, _response} -> {:error, "Expected error but got success"}
    end
  end

  defp test_advanced_features(provider) do
    IO.puts("\n🔬 Advanced Features Testing")
    IO.puts("============================")

    # Test ChatBuilder debugging
    IO.write("Pipeline Inspection: ")
    try do
      builder = ExLLM.build(provider, @test_message)
                |> ExLLM.with_cache()
                |> ExLLM.with_temperature(0.7)

      pipeline = ExLLM.inspect_pipeline(builder)
      debug_info = ExLLM.debug_info(builder)
      
      IO.puts("✅")
      IO.puts("  Pipeline length: #{length(pipeline)}")
      IO.puts("  Provider: #{debug_info.provider}")
      IO.puts("  Pipeline modifications: #{debug_info.pipeline_modifications}")
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end

    # Test pipeline optimization
    IO.write("Pipeline Optimization: ")
    try do
      ExLLM.PipelineOptimizer.configure(enabled: true, strategies: [:reorder_plugs])
      
      messages = [%{role: "user", content: "Test optimization"}]
      pipeline = ExLLM.Providers.get_pipeline(provider, :chat)
      
      result = ExLLM.PipelineOptimizer.benchmark_optimization(
        provider, pipeline, messages, iterations: 10
      )
      
      improvement = result.improvement.time_improvement_percent
      IO.puts("✅ (#{Float.round(improvement, 1)}% improvement)")
    rescue
      error ->
        IO.puts("❌ #{Exception.message(error)}")
    end

    # Test streaming if provider supports it
    test_streaming(provider)
  end

  defp test_streaming(provider) do
    IO.write("Streaming: ")
    
    try do
      result = ExLLM.build(provider, @test_message)
                |> ExLLM.with_temperature(0.1)
                |> ExLLM.stream(fn _chunk ->
                  # Don't print during test to keep output clean
                  :ok
                end)
      
      case result do
        :ok -> 
          IO.puts("✅ (streaming successful)")
        {:error, reason} ->
          IO.puts("❌ #{inspect(reason)}")
      end
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
    end
  end

  defp print_test_summary(results) do
    IO.puts("\n📊 Test Summary")
    IO.puts("===============")

    Enum.each(results, fn {provider, test_results} ->
      successes = Enum.count(test_results, fn {_, status, _, _} -> status == :success end)
      total = length(test_results)
      success_rate = Float.round(successes / total * 100, 1)
      
      IO.puts("#{provider}: #{successes}/#{total} tests passed (#{success_rate}%)")
      
      # Show failures
      failures = Enum.filter(test_results, fn {_, status, _, _} -> status != :success end)
      if length(failures) > 0 do
        Enum.each(failures, fn {test_name, status, _, reason} ->
          IO.puts("  ❌ #{test_name}: #{status} - #{inspect(reason)}")
        end)
      end
    end)

    # Overall stats
    all_tests = Enum.flat_map(results, fn {_, test_results} -> test_results end)
    total_successes = Enum.count(all_tests, fn {_, status, _, _} -> status == :success end)
    total_tests = length(all_tests)
    overall_rate = if total_tests > 0, do: Float.round(total_successes / total_tests * 100, 1), else: 0
    
    IO.puts("\nOverall: #{total_successes}/#{total_tests} tests passed (#{overall_rate}%)")
    
    if overall_rate >= 80 do
      IO.puts("🎉 Excellent! Pipeline architecture is working well with real providers.")
    else
      IO.puts("⚠️  Some issues detected. Review failures above.")
    end
  end

  defp format_time(microseconds) do
    cond do
      microseconds < 1000 ->
        "#{microseconds}μs"
      microseconds < 1_000_000 ->
        "#{Float.round(microseconds / 1000, 1)}ms"
      true ->
        "#{Float.round(microseconds / 1_000_000, 2)}s"
    end
  end
end

# Run the tests
RealProviderTesting.run_comprehensive_tests()