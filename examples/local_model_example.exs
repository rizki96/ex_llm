# Example: Using Local Models with ExLLM
# 
# This example demonstrates how to use local models with ExLLM.
# Make sure you have the optional dependencies installed:
# {:bumblebee, "~> 0.5"}, {:nx, "~> 0.7"}, {:exla, "~> 0.7"}

# Check if local models are available
if ExLLM.configured?(:local) do
  IO.puts("Local models are available!")
  
  # Get acceleration info
  info = ExLLM.Local.EXLAConfig.acceleration_info()
  IO.puts("Running on: #{info.name} (#{info.backend})")
  
  # List available models
  {:ok, models} = ExLLM.list_models(:local)
  IO.puts("\nAvailable models:")
  Enum.each(models, fn model ->
    status = model.metadata[:status] || "available"
    IO.puts("  - #{model.name} (#{model.id}) - #{status}")
    IO.puts("    Context: #{model.context_window} tokens, Max output: #{model.max_output_tokens}")
  end)
  
  # Simple chat example
  IO.puts("\n--- Chat Example ---")
  messages = [
    %{role: "user", content: "Write a haiku about Elixir programming"}
  ]
  
  case ExLLM.chat(:local, messages, model: "microsoft/phi-2") do
    {:ok, response} ->
      IO.puts("Response: #{response.content}")
      
    {:error, reason} ->
      IO.puts("Error: #{inspect(reason)}")
  end
  
  # Streaming example
  IO.puts("\n--- Streaming Example ---")
  messages = [
    %{role: "user", content: "Count from 1 to 5 slowly"}
  ]
  
  case ExLLM.stream_chat(:local, messages, model: "microsoft/phi-2") do
    {:ok, stream} ->
      IO.write("Response: ")
      Enum.each(stream, fn chunk ->
        if chunk.content, do: IO.write(chunk.content)
      end)
      IO.puts("")
      
    {:error, reason} ->
      IO.puts("Error: #{inspect(reason)}")
  end
  
else
  IO.puts("Local models are not available.")
  IO.puts("Please install the optional dependencies:")
  IO.puts("  {:bumblebee, \"~> 0.5\"}")
  IO.puts("  {:nx, \"~> 0.7\"}")
  IO.puts("  {:exla, \"~> 0.7\"}")
  IO.puts("\nOr for Apple Silicon:")
  IO.puts("  {:emlx, \"~> 0.1\"}")
end