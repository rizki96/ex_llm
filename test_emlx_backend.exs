Application.ensure_all_started(:ex_llm)
Process.sleep(200)

alias ExLLM.Bumblebee.EXLAConfig

IO.puts("=== Testing EMLX Backend Configuration ===")

# Check current backend configuration
current_backend = Application.get_env(:nx, :default_backend)
IO.puts("Current Nx backend: #{inspect(current_backend)}")

# Test basic Nx operation with EMLX
if Code.ensure_loaded?(EMLX) do
  IO.puts("EMLX is available")
  
  try do
    # Simple tensor operation to test EMLX
    a = Nx.tensor([1, 2, 3, 4], backend: EMLX.Backend)
    b = Nx.tensor([5, 6, 7, 8], backend: EMLX.Backend) 
    result = Nx.add(a, b)
    
    IO.puts("✓ Basic EMLX tensor ops work: #{inspect(Nx.to_list(result))}")
    
    # Test with default backend
    a2 = Nx.tensor([1, 2, 3, 4])
    b2 = Nx.tensor([5, 6, 7, 8])
    result2 = Nx.add(a2, b2)
    
    IO.puts("✓ Default backend tensor ops work: #{inspect(Nx.to_list(result2))}")
    IO.puts("Default backend used: #{inspect(result2.data.__struct__)}")
    
  rescue
    e -> IO.puts("✗ EMLX tensor ops failed: #{inspect(e)}")
  end
else
  IO.puts("EMLX is not available")
end

# Test Bumblebee compatibility with current backend
if Code.ensure_loaded?(Bumblebee) do
  IO.puts("\n=== Testing Bumblebee with Current Backend ===")
  
  try do
    # Try to create a simple model serving without loading full model
    # This tests if Bumblebee can work with the current backend
    IO.puts("Testing if Bumblebee can initialize with current backend...")
    
    # Get serving options
    serving_opts = EXLAConfig.serving_options()
    IO.puts("Serving options: #{inspect(serving_opts)}")
    
    IO.puts("✓ Bumblebee serving options generated successfully")
    
  rescue
    e -> IO.puts("✗ Bumblebee backend test failed: #{inspect(e)}")
  end
else
  IO.puts("Bumblebee is not available")
end

# Check acceleration info
acc_info = EXLAConfig.acceleration_info()
IO.puts("\n=== Acceleration Info ===")
IO.puts("Type: #{acc_info.type}")
IO.puts("Name: #{acc_info.name}")
IO.puts("Backend: #{acc_info.backend}")
if Map.has_key?(acc_info, :memory) do
  IO.puts("Memory: #{acc_info.memory.total_gb} GB")
end