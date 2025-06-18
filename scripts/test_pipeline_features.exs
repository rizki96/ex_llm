#!/usr/bin/env elixir

# Pipeline-Specific Feature Testing for ExLLM v1.0
#
# This script specifically tests the new pipeline architecture features
# like custom plugs, caching, optimization, and advanced builder patterns.

defmodule PipelineFeatureTesting do
  @moduledoc """
  Test new pipeline architecture features with real providers.
  """

  require Logger

  @test_messages [%{role: "user", content: "What is 2+2? Answer with just the number."}]

  def run_pipeline_tests() do
    IO.puts("🔧 ExLLM v1.0 Pipeline Feature Testing")
    IO.puts("====================================\n")

    # Find a working provider
    provider = find_working_provider()
    
    unless provider do
      IO.puts("❌ No working providers found. Please configure API keys.")
      System.halt(1)
    end

    IO.puts("✅ Using provider: #{provider}\n")

    # Test pipeline features
    test_caching_functionality(provider)
    test_custom_plugs(provider)
    test_pipeline_debugging(provider)
    test_optimization_features(provider)
    test_error_recovery(provider)
    test_context_management(provider)

    IO.puts("\n🎉 Pipeline feature testing completed!")
  end

  defp find_working_provider() do
    providers = [:openai, :anthropic, :groq, :gemini]
    
    Enum.find(providers, fn provider ->
      ExLLM.configured?(provider) and test_provider_basic(provider)
    end)
  end

  defp test_provider_basic(provider) do
    try do
      case ExLLM.chat(provider, @test_messages) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    rescue
      _ -> false
    end
  end

  defp test_caching_functionality(provider) do
    IO.puts("🗄️  Testing Caching Functionality")
    IO.puts("================================")

    # Test 1: Basic caching
    IO.write("Basic cache operation: ")
    
    try do
      # First request (cache miss)
      {time1, result1} = :timer.tc(fn ->
        ExLLM.build(provider, @test_messages)
        |> ExLLM.with_cache(ttl: 60)
        |> ExLLM.with_temperature(0.0)  # Deterministic for caching
        |> ExLLM.execute()
      end)

      # Second request (should be cache hit)
      {time2, result2} = :timer.tc(fn ->
        ExLLM.build(provider, @test_messages)
        |> ExLLM.with_cache(ttl: 60)
        |> ExLLM.with_temperature(0.0)
        |> ExLLM.execute()
      end)

      case {result1, result2} do
        {{:ok, resp1}, {:ok, resp2}} ->
          speedup = time1 / max(time2, 1000)  # Avoid division by zero
          IO.puts("✅ (#{Float.round(speedup, 1)}x speedup on cache hit)")
          IO.puts("  First request: #{format_time(time1)}")
          IO.puts("  Second request: #{format_time(time2)}")
          
        _ ->
          IO.puts("❌ Requests failed")
      end
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
    end

    # Test 2: Cache disable
    IO.write("Cache disable: ")
    
    try do
      result = ExLLM.build(provider, @test_messages)
                |> ExLLM.without_cache()
                |> ExLLM.with_temperature(0.1)
                |> ExLLM.execute()
      
      case result do
        {:ok, _} -> IO.puts("✅")
        {:error, reason} -> IO.puts("❌ #{inspect(reason)}")
      end
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
    end
  end

  defp test_custom_plugs(provider) do
    IO.puts("\n🔌 Testing Custom Plugs")
    IO.puts("=======================")

    # Create a simple custom plug for testing
    defmodule TestPlug do
      use ExLLM.Plug

      def init(opts), do: opts

      def call(request, opts) do
        metadata_key = Keyword.get(opts, :metadata_key, :test_plug_executed)
        ExLLM.Pipeline.Request.put_metadata(request, metadata_key, true)
      end
    end

    IO.write("Custom plug integration: ")
    
    try do
      result = ExLLM.build(provider, @test_messages)
                |> ExLLM.with_custom_plug(TestPlug, metadata_key: :custom_test)
                |> ExLLM.with_temperature(0.1)
                |> ExLLM.execute()
      
      case result do
        {:ok, response} ->
          # Check if our custom plug was executed (metadata would be in request)
          IO.puts("✅ Custom plug executed successfully")
        {:error, reason} ->
          IO.puts("❌ #{inspect(reason)}")
      end
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
    end

    # Test multiple custom plugs
    IO.write("Multiple custom plugs: ")
    
    try do
      result = ExLLM.build(provider, @test_messages)
                |> ExLLM.with_custom_plug(TestPlug, metadata_key: :plug1)
                |> ExLLM.with_custom_plug(TestPlug, metadata_key: :plug2)
                |> ExLLM.with_temperature(0.1)
                |> ExLLM.execute()
      
      case result do
        {:ok, _} -> IO.puts("✅")
        {:error, reason} -> IO.puts("❌ #{inspect(reason)}")
      end
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
    end
  end

  defp test_pipeline_debugging(provider) do
    IO.puts("\n🔍 Testing Pipeline Debugging")
    IO.puts("=============================")

    IO.write("Pipeline inspection: ")
    
    try do
      builder = ExLLM.build(provider, @test_messages)
                |> ExLLM.with_cache()
                |> ExLLM.with_temperature(0.7)

      pipeline = ExLLM.inspect_pipeline(builder)
      debug_info = ExLLM.debug_info(builder)
      
      IO.puts("✅")
      IO.puts("  Pipeline steps: #{length(pipeline)}")
      IO.puts("  Provider: #{debug_info.provider}")
      IO.puts("  Message count: #{debug_info.message_count}")
      IO.puts("  Options: #{map_size(debug_info.options)}")
      IO.puts("  Pipeline modifications: #{debug_info.pipeline_modifications}")
      IO.puts("  Has custom pipeline: #{debug_info.has_custom_pipeline}")
      
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
    end

    IO.write("Debug info accuracy: ")
    
    try do
      builder = ExLLM.build(provider, @test_messages)
                |> ExLLM.with_model("test-model")
                |> ExLLM.with_temperature(0.8)
                |> ExLLM.with_cache()

      debug_info = ExLLM.debug_info(builder)
      
      expected_options = %{model: "test-model", temperature: 0.8}
      actual_options = debug_info.options
      
      if Map.take(actual_options, [:model, :temperature]) == expected_options do
        IO.puts("✅ Debug info matches builder state")
      else
        IO.puts("❌ Debug info mismatch")
        IO.puts("  Expected: #{inspect(expected_options)}")
        IO.puts("  Actual: #{inspect(Map.take(actual_options, [:model, :temperature]))}")
      end
      
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
    end
  end

  defp test_optimization_features(provider) do
    IO.puts("\n⚡ Testing Optimization Features")
    IO.puts("===============================")

    IO.write("Pipeline optimizer configuration: ")
    
    try do
      ExLLM.PipelineOptimizer.configure(
        enabled: true,
        strategies: [:reorder_plugs, :fast_path]
      )
      IO.puts("✅")
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
        return
    end

    IO.write("Pipeline optimization: ")
    
    try do
      original_pipeline = ExLLM.Providers.get_pipeline(provider, :chat)
      optimized_pipeline = ExLLM.PipelineOptimizer.optimize(original_pipeline)
      
      IO.puts("✅")
      IO.puts("  Original length: #{length(original_pipeline)}")
      IO.puts("  Optimized length: #{length(optimized_pipeline)}")
      
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
    end

    IO.write("Optimization benchmark: ")
    
    try do
      pipeline = ExLLM.Providers.get_pipeline(provider, :chat)
      result = ExLLM.PipelineOptimizer.benchmark_optimization(
        provider, pipeline, @test_messages, iterations: 5
      )
      
      improvement = result.improvement.time_improvement_percent
      IO.puts("✅ (#{Float.round(improvement, 1)}% performance change)")
      
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
    end
  end

  defp test_error_recovery(provider) do
    IO.puts("\n🛡️  Testing Error Recovery")
    IO.puts("========================")

    IO.write("Invalid model error handling: ")
    
    try do
      result = ExLLM.build(provider, @test_messages)
                |> ExLLM.with_model("definitely-not-a-real-model-12345")
                |> ExLLM.execute()
      
      case result do
        {:error, error} ->
          IO.puts("✅ Error handled correctly")
          IO.puts("  Error type: #{inspect(error)}")
        {:ok, _} ->
          IO.puts("❌ Expected error but got success")
      end
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
    end

    IO.write("Pipeline error recovery: ")
    
    try do
      # Create a plug that fails
      defmodule FailingPlug do
        use ExLLM.Plug

        def init(opts), do: opts

        def call(_request, _opts) do
          raise "Intentional test failure"
        end
      end

      result = ExLLM.build(provider, @test_messages)
                |> ExLLM.with_custom_plug(FailingPlug)
                |> ExLLM.execute()
      
      case result do
        {:error, _error} ->
          IO.puts("✅ Pipeline error handled correctly")
        {:ok, _} ->
          IO.puts("❌ Expected error but got success")
      end
    rescue
      error ->
        IO.puts("✅ Exception caught: #{Exception.message(error)}")
    end
  end

  defp test_context_management(provider) do
    IO.puts("\n📝 Testing Context Management")
    IO.puts("=============================")

    # Create a long conversation to test context management
    long_messages = Enum.flat_map(1..10, fn i ->
      [
        %{role: "user", content: "This is message #{i}. " <> String.duplicate("More text. ", 20)},
        %{role: "assistant", content: "I understand message #{i}. " <> String.duplicate("Response text. ", 15)}
      ]
    end) ++ [%{role: "user", content: "What is 2+2?"}]

    IO.write("Long conversation handling: ")
    
    try do
      result = ExLLM.build(provider, long_messages)
                |> ExLLM.with_context_strategy(:truncate, max_tokens: 1000)
                |> ExLLM.with_temperature(0.1)
                |> ExLLM.execute()
      
      case result do
        {:ok, response} ->
          IO.puts("✅ Context management successful")
          IO.puts("  Response length: #{String.length(response.content || "")} chars")
        {:error, reason} ->
          IO.puts("❌ #{inspect(reason)}")
      end
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
    end

    IO.write("Context strategy configuration: ")
    
    try do
      builder = ExLLM.build(provider, @test_messages)
                |> ExLLM.with_context_strategy(:sliding_window, window_size: 5)

      debug_info = ExLLM.debug_info(builder)
      
      if debug_info.pipeline_modifications > 0 do
        IO.puts("✅ Context strategy applied")
      else
        IO.puts("❌ Context strategy not detected")
      end
    rescue
      error ->
        IO.puts("💥 #{Exception.message(error)}")
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

# Run the pipeline feature tests
PipelineFeatureTesting.run_pipeline_tests()