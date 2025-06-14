#!/usr/bin/env elixir

# StreamingCoordinator Showcase - Complete Example
# This example demonstrates all the advanced features of the StreamingCoordinator

Mix.install([
  {:ex_llm, path: "."}
])

defmodule StreamingCoordinatorShowcase do
  @moduledoc """
  Complete demonstration of StreamingCoordinator advanced features including:
  - Metrics tracking
  - Chunk transformation 
  - Chunk validation
  - Buffering
  - Stream recovery
  - Error handling
  """

  def run do
    IO.puts("\n🚀 StreamingCoordinator Advanced Features Showcase\n")
    IO.puts(String.duplicate("=", 60))
    
    # Demo 1: Basic streaming with metrics
    demo_metrics_tracking()
    
    # Demo 2: Chunk transformation
    demo_chunk_transformation()
    
    # Demo 3: Content validation
    demo_content_validation()
    
    # Demo 4: Buffering and batch processing
    demo_buffering()
    
    # Demo 5: Provider-specific features
    demo_provider_features()
    
    IO.puts("\n✅ All StreamingCoordinator features demonstrated!")
  end

  defp demo_metrics_tracking do
    IO.puts("\n📊 Demo 1: Real-time Metrics Tracking")
    IO.puts(String.duplicate("-", 40))
    
    messages = [%{role: "user", content: "Count from 1 to 5"}]
    
    # Track detailed streaming metrics
    on_metrics = fn metrics ->
      IO.puts("📈 Metrics: #{metrics.chunks_received} chunks, " <>
              "#{metrics.bytes_received} bytes, " <>
              "#{Float.round(metrics.chunks_per_second, 2)} chunks/sec, " <>
              "#{metrics.duration_ms}ms elapsed")
    end
    
    case ExLLM.stream_chat(:openai, messages,
           model: "gpt-4.1-nano",
           track_metrics: true,
           on_metrics: on_metrics
         ) do
      {:ok, stream} ->
        IO.puts("🎯 Response:")
        Enum.each(stream, fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("\n")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end

  defp demo_chunk_transformation do
    IO.puts("\n🔄 Demo 2: Chunk Transformation")
    IO.puts(String.duplicate("-", 40))
    
    messages = [%{role: "user", content: "Say 'hello world' in different languages"}]
    
    case ExLLM.stream_chat(:anthropic, messages,
           model: "claude-3-5-haiku-latest",
           annotate_reasoning: true  # Anthropic-specific transformation
         ) do
      {:ok, stream} ->
        IO.puts("🌍 Response with annotations:")
        Enum.each(stream, fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("\n")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end

  defp demo_content_validation do
    IO.puts("\n🛡️ Demo 3: Content Validation")
    IO.puts(String.duplicate("-", 40))
    
    messages = [%{role: "user", content: "Write a short poem about nature"}]
    
    case ExLLM.stream_chat(:gemini, messages,
           model: "gemini-2.0-flash",
           validate_sources: true  # Validate content quality
         ) do
      {:ok, stream} ->
        IO.puts("📝 Validated response:")
        Enum.each(stream, fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("\n")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end

  defp demo_buffering do
    IO.puts("\n📦 Demo 4: Chunk Buffering (Batch Processing)")
    IO.puts(String.duplicate("-", 40))
    
    messages = [%{role: "user", content: "List 10 programming languages"}]
    
    case ExLLM.stream_chat(:mistral, messages,
           model: "mistral/mistral-small-latest",
           buffer_chunks: 3,  # Buffer 3 chunks before processing
           format_code_blocks: true  # Mistral-specific transformation
         ) do
      {:ok, stream} ->
        IO.puts("📋 Buffered response (3 chunks per batch):")
        stream
        |> Enum.with_index()
        |> Enum.each(fn {chunk, index} ->
          if chunk.content do
            IO.puts("[Batch #{div(index, 3) + 1}] #{chunk.content}")
          end
        end)
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end

  defp demo_provider_features do
    IO.puts("\n🔧 Demo 5: Provider-Specific Features")
    IO.puts(String.duplicate("-", 40))
    
    # Perplexity with source validation
    demo_perplexity_search()
    
    # OpenAI with content moderation
    demo_openai_moderation()
    
    # LM Studio with performance monitoring
    demo_lmstudio_performance()
  end

  defp demo_perplexity_search do
    IO.puts("\n🔍 Perplexity: Search with Source Validation")
    
    messages = [%{role: "user", content: "What's the latest in AI research?"}]
    
    case ExLLM.stream_chat(:perplexity, messages,
           model: "perplexity/sonar-pro",
           search_mode: "academic",
           validate_sources: true,  # Validate search sources
           inline_citations: true,  # Transform citations
           track_metrics: true
         ) do
      {:ok, stream} ->
        IO.puts("🔬 Academic search results:")
        Enum.each(stream, fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("\n")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end

  defp demo_openai_moderation do
    IO.puts("\n🚨 OpenAI: Content Moderation")
    
    messages = [%{role: "user", content: "Write a friendly greeting"}]
    
    case ExLLM.stream_chat(:openai, messages,
           model: "gpt-4.1-nano",
           content_moderation: true,  # Enable content moderation
           highlight_function_calls: true,  # Highlight any function calls
           track_metrics: true
         ) do
      {:ok, stream} ->
        IO.puts("✅ Moderated response:")
        Enum.each(stream, fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("\n")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end

  defp demo_lmstudio_performance do
    IO.puts("\n💻 LM Studio: Performance Monitoring")
    
    messages = [%{role: "user", content: "Explain machine learning briefly"}]
    
    case ExLLM.stream_chat(:lmstudio, messages,
           model: "llama-3.2-3b-instruct",
           show_performance: true,  # Show performance annotations
           validate_local: true,    # Validate local model responses
           track_metrics: true
         ) do
      {:ok, stream} ->
        IO.puts("🖥️ Local model response:")
        Enum.each(stream, fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("\n")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end

  defp check_environment do
    required_keys = ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY"]
    missing = Enum.filter(required_keys, &is_nil(System.get_env(&1)))
    
    if missing != [] do
      IO.puts("⚠️  Missing environment variables: #{Enum.join(missing, ", ")}")
      IO.puts("Setting up mock examples instead...")
      false
    else
      true
    end
  end
end

# Run the showcase
if StreamingCoordinatorShowcase.check_environment() do
  StreamingCoordinatorShowcase.run()
else
  IO.puts("\n🔧 To run the full showcase, set the required API keys:")
  IO.puts("export OPENAI_API_KEY=your_key")
  IO.puts("export ANTHROPIC_API_KEY=your_key") 
  IO.puts("export GEMINI_API_KEY=your_key")
  IO.puts("export PERPLEXITY_API_KEY=your_key")
end