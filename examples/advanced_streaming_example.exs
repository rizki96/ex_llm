#!/usr/bin/env elixir

# Advanced Streaming Example with StreamingCoordinator features

Mix.install([
  {:ex_llm, path: "."}
])

defmodule AdvancedStreamingExample do
  alias ExLLM.Providers.Shared.StreamingCoordinator
  
  @doc """
  Example of using StreamingCoordinator with advanced features
  """
  def run do
    IO.puts("Advanced Streaming Example")
    IO.puts("=" <> String.duplicate("=", 50) <> "\n")
    
    # Example 1: Streaming with metrics tracking
    streaming_with_metrics()
    IO.puts("\n" <> String.duplicate("-", 50) <> "\n")
    
    # Example 2: Streaming with chunk transformation
    streaming_with_transformation()
    IO.puts("\n" <> String.duplicate("-", 50) <> "\n")
    
    # Example 3: Streaming with buffering
    streaming_with_buffering()
    IO.puts("\n" <> String.duplicate("-", 50) <> "\n")
    
    # Example 4: Streaming with validation
    streaming_with_validation()
  end
  
  defp streaming_with_metrics do
    IO.puts("1. Streaming with Metrics Tracking")
    IO.puts("Watch real-time streaming metrics...")
    
    messages = [%{role: "user", content: "Count from 1 to 10 slowly"}]
    
    # Metrics callback
    on_metrics = fn metrics ->
      IO.puts("\rMetrics: #{metrics.chunks_received} chunks, " <>
              "#{metrics.bytes_received} bytes, " <>
              "#{metrics.chunks_per_second} chunks/sec")
    end
    
    case ExLLM.stream_chat(:openai, messages,
           model: "gpt-4.1-nano",
           track_metrics: true,
           on_metrics: on_metrics
         ) do
      {:ok, stream} ->
        stream
        |> Enum.each(fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        IO.puts("\n✅ Streaming completed!")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  defp streaming_with_transformation do
    IO.puts("2. Streaming with Chunk Transformation")
    IO.puts("Transforming chunks to uppercase...")
    
    messages = [%{role: "user", content: "Say hello world"}]
    
    # Transform function to uppercase content
    transform_chunk = fn chunk ->
      if chunk.content do
        {:ok, %{chunk | content: String.upcase(chunk.content)}}
      else
        {:ok, chunk}
      end
    end
    
    # Direct use of StreamingCoordinator for demonstration
    url = "https://api.openai.com/v1/chat/completions"
    headers = [
      {"Authorization", "Bearer #{System.get_env("OPENAI_API_KEY")}"},
      {"Content-Type", "application/json"}
    ]
    
    request = %{
      "model" => "gpt-4.1-nano",
      "messages" => [%{"role" => "user", "content" => "Say hello world"}],
      "stream" => true
    }
    
    callback = fn chunk ->
      if chunk.content, do: IO.write(chunk.content)
    end
    
    case StreamingCoordinator.simple_stream(
           url: url,
           request: request,
           headers: headers,
           callback: callback,
           parse_chunk: &parse_openai_chunk/1,
           options: [
             transform_chunk: transform_chunk,
             provider: :openai
           ]
         ) do
      {:ok, _stream_id} ->
        Process.sleep(2000)  # Wait for streaming to complete
        IO.puts("\n✅ Transformation completed!")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  defp streaming_with_buffering do
    IO.puts("3. Streaming with Chunk Buffering")
    IO.puts("Buffering chunks in groups of 3...")
    
    messages = [%{role: "user", content: "List 5 colors"}]
    
    # This would buffer chunks before sending them
    case ExLLM.stream_chat(:anthropic, messages,
           model: "claude-3-5-haiku-latest",
           buffer_chunks: 3
         ) do
      {:ok, stream} ->
        stream
        |> Enum.with_index()
        |> Enum.each(fn {chunk, index} ->
          if chunk.content do
            IO.puts("[Chunk #{index}] #{chunk.content}")
          end
        end)
        IO.puts("✅ Buffered streaming completed!")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  defp streaming_with_validation do
    IO.puts("4. Streaming with Chunk Validation")
    IO.puts("Validating chunks contain no profanity...")
    
    messages = [%{role: "user", content: "Tell me a joke"}]
    
    # Simple validation function
    validate_chunk = fn chunk ->
      if chunk.content && String.contains?(String.downcase(chunk.content), ["bad", "evil"]) do
        {:error, "Content contains prohibited words"}
      else
        :ok
      end
    end
    
    # Note: This would require adapter support for validate_chunk option
    case ExLLM.stream_chat(:gemini, messages,
           model: "gemini-2.0-flash",
           validate_chunk: validate_chunk
         ) do
      {:ok, stream} ->
        valid_chunks = 
          stream
          |> Enum.filter(& &1.content)
          |> Enum.to_list()
          
        IO.puts("Received #{length(valid_chunks)} valid chunks")
        Enum.each(valid_chunks, fn chunk ->
          IO.write(chunk.content)
        end)
        IO.puts("\n✅ Validated streaming completed!")
        
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
    end
  end
  
  # Helper function to parse OpenAI chunks
  defp parse_openai_chunk(data) do
    case Jason.decode(data) do
      {:ok, %{"choices" => [%{"delta" => delta} | _]}} ->
        chunk = %ExLLM.Types.StreamChunk{
          content: delta["content"],
          finish_reason: delta["finish_reason"]
        }
        {:ok, chunk}
        
      _ ->
        {:error, :invalid_chunk}
    end
  end
end

# Check if we have API keys
if System.get_env("OPENAI_API_KEY") do
  AdvancedStreamingExample.run()
else
  IO.puts("Please set OPENAI_API_KEY environment variable to run this example")
end