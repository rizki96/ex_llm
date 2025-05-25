# ExLLM Integration Plan

## Overview

Plan to integrate MCP (Model Context Protocol) and local model support into ExLLM, making it a comprehensive LLM solution for Elixir.

## Phase 1: Local Model Support Integration

### Components to Integrate
1. **Local LLM Adapter** (`MCPChat.LLM.Local` → `ExLLM.Adapters.Local`)
   - Bumblebee integration for on-device inference
   - Support for Phi, Llama, Mistral, and other GGUF models
   - Streaming response generation

2. **Model Loader** (`MCPChat.LLM.ModelLoader` → `ExLLM.Local.ModelLoader`)
   - GenServer for model lifecycle management
   - Model loading/unloading
   - Memory management
   - Multiple model support

3. **EXLA Configuration** (`MCPChat.LLM.EXLAConfig` → `ExLLM.Local.EXLAConfig`)
   - Hardware acceleration detection (CPU, CUDA, Metal)
   - Optimal settings for different hardware
   - Backend configuration

### Dependencies to Add
```elixir
# In mix.exs
{:bumblebee, "~> 0.5"},
{:exla, "~> 0.7"},
{:nx, "~> 0.7"}
```

### API Design
```elixir
# Use local models just like any other provider
{:ok, response} = ExLLM.chat(:local, messages, 
  model: "microsoft/phi-2",
  max_tokens: 1000
)

# Model management
ExLLM.Local.load_model("microsoft/phi-2")
ExLLM.Local.unload_model("microsoft/phi-2")
models = ExLLM.Local.list_loaded_models()
info = ExLLM.Local.acceleration_info()
```

## Phase 2: MCP Integration (Optional Feature)

### Components to Integrate
1. **MCP Client** (`MCPChat.MCP.Client` → `ExLLM.MCP.Client`)
   - WebSocket and stdio transport support
   - Tool discovery and execution
   - Resource access

2. **MCP Protocol** (`MCPChat.MCP.Protocol` → `ExLLM.MCP.Protocol`)
   - JSON-RPC message encoding/decoding
   - Protocol compliance

3. **Server Manager** (`MCPChat.MCP.ServerManager` → `ExLLM.MCP.ServerManager`)
   - Multiple server connections
   - Server lifecycle management

### API Design
```elixir
# Configure MCP servers
ExLLM.MCP.add_server("filesystem", 
  command: ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
)

# Use tools in chat
{:ok, response} = ExLLM.chat(:anthropic, messages,
  mcp_enabled: true,
  tools: ["read_file", "write_file"]
)

# Direct tool access
{:ok, result} = ExLLM.MCP.call_tool("filesystem", "read_file", 
  %{path: "/tmp/data.txt"}
)
```

## Benefits of Integration

1. **Complete LLM Solution**
   - Cloud providers (Anthropic, OpenAI, etc.)
   - Local models (Phi, Llama, Mistral)
   - Tool integration via MCP
   - All with unified API

2. **Better Developer Experience**
   - Single dependency for all LLM needs
   - Consistent interface across all providers
   - Integrated features (cost tracking, context, sessions)

3. **Performance**
   - Local models for offline/private use
   - No API costs for local inference
   - Hardware acceleration support

## Implementation Strategy

### Step 1: Create Local Adapter (Priority: High)
1. Copy `MCPChat.LLM.Local` to `ExLLM.Adapters.Local`
2. Copy model loader and EXLA config modules
3. Update module references and dependencies
4. Add tests
5. Update documentation

### Step 2: Add MCP Support (Priority: Medium)
1. Create `ExLLM.MCP` namespace
2. Copy core MCP modules (Client, Protocol)
3. Simplify API for LLM use cases
4. Make it optional (don't require WebSockex if not using MCP)
5. Add integration examples

### Step 3: Integration Testing
1. Test local models with cost tracking
2. Test local models with context management
3. Test MCP tools with different providers
4. Performance benchmarks

## Considerations

1. **Dependencies**
   - Bumblebee/Nx/EXLA are heavy dependencies
   - Consider making local support optional via config
   - MCP requires WebSockex

2. **API Compatibility**
   - Maintain consistent API across all adapters
   - Local models may have different capabilities
   - Handle feature gaps gracefully

3. **Performance**
   - Model loading can be slow
   - Memory usage can be high
   - Need proper resource management

## Questions to Resolve

1. Should local model support be in core ex_llm or a separate package (ex_llm_local)?
2. Should MCP be integrated or remain separate for broader use?
3. How to handle optional dependencies (Bumblebee, WebSockex)?
4. Resource management strategy for loaded models?