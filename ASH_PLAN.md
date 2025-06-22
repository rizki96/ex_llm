# ExLLM Ash Compatibility Implementation Plan

Based on comprehensive analysis of ExLLM's architecture and Ash's requirements, this document outlines a complete implementation plan to make ExLLM compatible with Ash's extension system.

## Executive Summary

**Objective**: Create an Ash-compatible wrapper layer for ExLLM that implements the Plug-like architecture pattern required by Ash, while preserving all existing ExLLM functionality.

**Approach**: Additive compatibility layer in the `ExLLM.Ash` namespace that wraps existing ExLLM functionality without breaking changes.

## Architecture Overview

```
ExLLM.Ash (New Compatibility Layer)
├── Tool Behavior (init/1, run/2 pattern)
├── Extension System (dynamic tool registration)
├── Router Integration (Ash routing compatibility)
└── Built-in Tools (ready-to-use implementations)
    │
    └── Wraps Existing ExLLM Core
        ├── Pipeline System (preserved)
        ├── Provider Abstraction (preserved)
        └── All Current APIs (unchanged)
```

## Ash Requirements Analysis

Based on the Ash author's requirements for Vancouver.Tool compatibility:

1. **Plug-like initialization**: `init(opts)` function that validates and transforms options
2. **Options-first signatures**: All functions accept initialized options as first argument
3. **Dynamic tool configuration**: Same tool with different behaviors based on opts
4. **Extension system**: Dynamic addition of tools/capabilities
5. **Router integration**: Clean integration with routing systems

**Current ExLLM vs Required Patterns**:
- Current: `function(provider, ...args, opts \\ [])`
- Required: `function(opts, ...args)` - options first

## Implementation Phases

### Phase 1: Core Tool Behavior Foundation

**Objective**: Create the foundational `ExLLM.Ash.Tool` behavior that enables Ash-compatible tool creation.

**Key Components**:

1. **Tool Behavior Definition**:
```elixir
defmodule ExLLM.Ash.Tool do
  @callback init(opts :: keyword()) :: {:ok, map()} | {:error, term()}
  @callback name(opts :: map()) :: String.t()
  @callback description(opts :: map()) :: String.t()
  @callback input_schema(opts :: map()) :: map()
  @callback run(opts :: map(), args :: term()) :: {:ok, term()} | {:error, term()}
end
```

2. **Tool Macro Implementation**:
   - Provide `use ExLLM.Ash.Tool` macro
   - Auto-generate default implementations
   - Add helper functions for common patterns

3. **Integration with ExLLM**:
   - Create adapter functions that transform Ash patterns to ExLLM calls
   - Preserve all ExLLM functionality and error handling
   - Maintain telemetry and logging integration

**Implementation Details**:
- File: `lib/ex_llm/ash/tool.ex`
- Dependencies: Core ExLLM modules (no new dependencies)
- Testing: Unit tests for behavior compliance and integration

**Success Criteria**:
- Tools can be defined using the Ash pattern
- All ExLLM providers accessible through tool interface
- Zero performance degradation from wrapper layer
- Comprehensive error handling and validation

### Phase 2: Extension System Implementation

**Objective**: Enable dynamic tool registration and discovery for Ash integration.

**Key Components**:

1. **Extension Behavior**:
```elixir
defmodule ExLLM.Ash.Extension do
  @callback add_tools(opts :: keyword()) :: [tool_spec()]
  
  @type tool_spec :: {module(), keyword()} | module()
end
```

2. **Tool Registry**:
   - Dynamic tool registration at runtime
   - Tool discovery and enumeration
   - Conflict resolution for duplicate tool names

3. **Integration Points**:
   - Hook into ExLLM's existing configuration system
   - Maintain tool metadata and capabilities
   - Support hot-reloading of tools in development

### Phase 3: Router Integration

**Objective**: Provide clean integration with Ash routing systems.

**Key Components**:

1. **Router Module**:
```elixir
defmodule ExLLM.Ash.Router do
  def forward(path, opts) do
    # Handle tool routing and request dispatch
    # Support both static tools and dynamic extensions
  end
end
```

2. **Request Handling**:
   - Transform router requests to ExLLM format
   - Handle tool execution and response formatting
   - Maintain compatibility with Ash's expected patterns

**Integration Pattern**:
```elixir
# In Ash application
forward "/llm", ExLLM.Ash.Router, 
  tools: [
    {MyApp.ChatTool, provider: :openai, model: "gpt-4"},
    {MyApp.EmbeddingTool, provider: :openai}
  ],
  extensions: [
    {MyApp.CustomExtension, custom_opts: true}
  ]
```

### Phase 4: Built-in Tools Implementation

**Objective**: Provide comprehensive, ready-to-use tools that demonstrate the Ash compatibility layer.

**Core Tools to Implement**:
1. **ChatTool**: Basic chat completion with configurable providers
2. **StreamingChatTool**: Real-time streaming chat responses  
3. **EmbeddingTool**: Text embeddings with different models
4. **FileUploadTool**: File management across providers
5. **BatchProcessingTool**: Batch operations for high-volume use cases

**Tool Configuration Examples**:
```elixir
# Multiple configurations of the same tool
tools: [
  {ExLLM.Ash.Tools.ChatTool, provider: :openai, model: "gpt-4", name: "gpt4_chat"},
  {ExLLM.Ash.Tools.ChatTool, provider: :anthropic, model: "claude-3", name: "claude_chat"},
  {ExLLM.Ash.Tools.EmbeddingTool, provider: :openai, model: "text-embedding-3-large"}
]
```

### Phase 5: Production Readiness

**Objective**: Ensure the Ash compatibility layer is production-ready with comprehensive testing and documentation.

**Key Deliverables**:

1. **Comprehensive Documentation**:
   - Getting started guide for Ash integration
   - Tool development tutorial
   - Extension system guide
   - Performance considerations

2. **Testing Strategy**:
   - Unit tests for all behaviors and tools
   - Integration tests with mock Ash scenarios
   - Performance benchmarks vs direct ExLLM usage
   - Error handling and edge case coverage

3. **Examples and Templates**:
   - Complete Ash application example
   - Custom tool templates
   - Extension development patterns
   - Router configuration examples

## Implementation Dependencies

```
Phase 1 (Foundation)
    |
    v
Phase 2 (Extensions) --> Phase 3 (Router)
    |                        |
    v                        v
Phase 4 (Built-in Tools) --> Phase 5 (Production)
```

**Critical Path**: Phase 1 must be complete before Phase 2, and Phase 2 must be complete before Phase 3. Phase 4 can begin after Phase 3, and Phase 5 runs in parallel with Phase 4.

## Success Metrics

- **Compatibility**: Zero breaking changes to existing ExLLM APIs
- **Performance**: <1ms overhead for wrapper layer
- **Integration**: Complete Ash integration working as expected
- **Quality**: Comprehensive documentation and examples
- **Adoption**: Easy for Ash developers to integrate and extend

## Immediate Next Steps

1. **Research Phase**: Study Ash extension patterns and Vancouver.Tool interface
2. **Prototype Development**: Create minimal working example
3. **Validation**: Test prototype with Ash-style integration
4. **Iterate**: Refine based on initial feedback

## Example Tool Implementation

Here's what a complete Ash-compatible tool would look like:

```elixir
defmodule MyApp.Tools.ChatTool do
  use ExLLM.Ash.Tool

  @impl true
  def init(opts) do
    provider = opts[:provider] || :openai
    model = opts[:model] || "gpt-4"
    
    # Validate provider is supported
    unless provider in ExLLM.Providers.supported_providers() do
      {:error, "Unsupported provider: #{provider}"}
    else
      {:ok, %{provider: provider, model: model, name: opts[:name]}}
    end
  end

  @impl true
  def name(%{name: name}) when is_binary(name), do: name
  def name(%{provider: provider}), do: "chat_#{provider}"

  @impl true
  def description(%{provider: provider, model: model}) do
    "Chat completion using #{provider} with #{model}"
  end

  @impl true
  def input_schema(_opts) do
    %{
      "type" => "object",
      "properties" => %{
        "messages" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "role" => %{"type" => "string"},
              "content" => %{"type" => "string"}
            }
          }
        }
      },
      "required" => ["messages"]
    }
  end

  @impl true
  def run(%{provider: provider, model: model}, %{"messages" => messages}) do
    # Transform to ExLLM format and call
    ExLLM.chat(provider, messages, model: model)
  end
end
```

## Usage Examples

### Basic Tool Usage

```elixir
# Define a tool with specific configuration
defmodule MyApp.FastChatTool do
  use ExLLM.Ash.Tool

  def init(opts) do
    {:ok, %{provider: :groq, model: "llama-3-70b", speed: :fast}}
  end

  def name(%{speed: :fast}), do: "fast_chat"
  def description(_), do: "Ultra-fast chat using Groq"

  def run(opts, %{"messages" => messages}) do
    ExLLM.chat(opts.provider, messages, model: opts.model)
  end
end

# Use in router
forward "/mcp", ExLLM.Ash.Router, tools: [
  {MyApp.FastChatTool, []},
  {MyApp.ChatTool, provider: :openai, model: "gpt-4"}
]
```

### Extension System Usage

```elixir
defmodule MyApp.CustomExtension do
  use ExLLM.Ash.Extension

  def add_tools(opts) do
    otp_app = opts[:otp_app]
    
    [
      {MyApp.Tools.CustomChatTool, provider: :anthropic},
      {MyApp.Tools.SpecializedTool, config: get_config(otp_app)}
    ]
  end
end

# Use with extensions
forward "/mcp", ExLLM.Ash.Router,
  tools: [
    {ExLLM.Ash.Tools.ChatTool, provider: :openai}
  ],
  extensions: [
    {MyApp.CustomExtension, otp_app: :my_app}
  ]
```

## Technical Considerations

### Performance

- **Wrapper Overhead**: Target <1ms additional latency
- **Memory Usage**: Minimal additional memory footprint
- **Caching**: Leverage ExLLM's existing caching mechanisms

### Error Handling

- **Validation**: Comprehensive option validation in `init/1`
- **Error Propagation**: Preserve ExLLM's error handling patterns
- **Graceful Degradation**: Handle provider failures gracefully

### Testing Strategy

- **Unit Tests**: Test each behavior and tool independently
- **Integration Tests**: Test with mock Ash routing scenarios
- **Performance Tests**: Benchmark against direct ExLLM usage
- **Compatibility Tests**: Ensure no breaking changes to existing APIs

## File Structure

```
lib/ex_llm/ash/
├── tool.ex              # Core tool behavior
├── extension.ex         # Extension system
├── router.ex           # Router integration
├── registry.ex         # Tool registry
└── tools/
    ├── chat_tool.ex     # Basic chat tool
    ├── streaming_tool.ex # Streaming chat tool
    ├── embedding_tool.ex # Embedding tool
    ├── file_tool.ex     # File management tool
    └── batch_tool.ex    # Batch processing tool

test/ex_llm/ash/
├── tool_test.exs
├── extension_test.exs
├── router_test.exs
└── integration/
    └── ash_compatibility_test.exs

docs/ash/
├── getting_started.md
├── tool_development.md
├── extension_guide.md
└── examples/
    └── complete_ash_app/
```

## Migration Path

1. **Phase 1**: Implement core behavior, no impact on existing code
2. **Phase 2**: Add extension system, still no impact
3. **Phase 3**: Add router integration, ready for Ash usage
4. **Phase 4**: Add built-in tools, provide examples
5. **Phase 5**: Production polish, comprehensive documentation

This approach ensures that existing ExLLM users are unaffected while providing a clear path for Ash integration.

## Conclusion

This implementation plan provides a comprehensive approach to making ExLLM compatible with Ash's extension system while preserving all existing functionality. The additive wrapper layer approach minimizes risk and ensures backward compatibility while providing the exact interface patterns that Ash requires.

The plan is structured to deliver value incrementally, with each phase building upon the previous one and providing clear milestones for validation and feedback.
