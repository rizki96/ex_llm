# Installing Local Model Support

This guide covers installing the optional dependencies needed for local model support in ExLLM.

## Basic Installation

Add these dependencies to your `mix.exs`:

```elixir
def deps do
  [
    {:ex_llm, "~> 0.1.0"},
    
    # For local model support
    {:bumblebee, "~> 0.5"},
    {:nx, "~> 0.7"},
    {:exla, "~> 0.7"}
  ]
end
```

Then run:

```bash
mix deps.get
mix compile
```

## Platform-Specific Instructions

### macOS (Apple Silicon)

For M1/M2/M3 Macs, you can use either EXLA or EMLX (recommended for better Metal support):

```elixir
# Option 1: EXLA (works well)
{:exla, "~> 0.7"}

# Option 2: EMLX (optimized for Apple Silicon) - when available
{:emlx, "~> 0.1"}
```

If using EXLA on Apple Silicon:

```bash
# Install with precompiled binaries
EXLA_TARGET=darwin-arm64 mix deps.compile exla
```

### Linux with NVIDIA GPU

For CUDA support:

```bash
# Ensure CUDA is installed (11.8 or 12.x)
nvidia-smi  # Should show your GPU

# Install with CUDA support
EXLA_TARGET=cuda120 mix deps.compile exla  # For CUDA 12.x
# or
EXLA_TARGET=cuda118 mix deps.compile exla  # For CUDA 11.8
```

### Linux/Windows CPU Only

```bash
# No special configuration needed
mix deps.get
mix compile
```

## Verifying Installation

Run this to verify everything is working:

```elixir
# In iex
iex> ExLLM.configured?(:local)
true

iex> ExLLM.Local.EXLAConfig.acceleration_info()
%{
  type: :metal,  # or :cuda, :cpu
  name: "Apple Metal",
  backend: "EXLA"
}
```

## Troubleshooting

### "Bumblebee is not available"

Make sure Bumblebee is in your dependencies and compiled:

```bash
mix deps.get bumblebee
mix deps.compile bumblebee
```

### EXLA Compilation Issues

If EXLA fails to compile:

1. **macOS**: Install Xcode command line tools
   ```bash
   xcode-select --install
   ```

2. **Linux**: Install build essentials
   ```bash
   sudo apt-get install build-essential  # Ubuntu/Debian
   sudo yum groupinstall "Development Tools"  # RHEL/CentOS
   ```

3. **Use precompiled binaries** (recommended):
   ```elixir
   # In mix.exs
   {:exla, "~> 0.7", system_env: %{"EXLA_TARGET" => "host"}}
   ```

### Out of Memory Errors

Large models require significant RAM/VRAM:

- Phi-2 (2.7B): ~6GB
- Llama 2 (7B): ~14GB  
- Mistral (7B): ~14GB

Consider using smaller models or upgrading your hardware.

### Slow First Load

Models are downloaded from HuggingFace on first use. This is normal and only happens once. Models are cached in `~/.ex_llm/models/`.

## Performance Tips

1. **Enable mixed precision** (automatic by default):
   ```elixir
   ExLLM.Local.EXLAConfig.enable_mixed_precision()
   ```

2. **Pre-load models** you'll use frequently:
   ```elixir
   {:ok, _} = ExLLM.Local.ModelLoader.load_model("microsoft/phi-2")
   ```

3. **Monitor memory usage**:
   ```elixir
   ExLLM.Local.ModelLoader.list_loaded_models()
   # Unload unused models
   ExLLM.Local.ModelLoader.unload_model("model-name")
   ```

## Example Usage

```elixir
# After installation, you can use local models
{:ok, response} = ExLLM.chat(:local, [
  %{role: "user", content: "Hello, world!"}
], model: "microsoft/phi-2")

IO.puts(response.content)
```

For more examples, see `examples/local_model_example.exs`.