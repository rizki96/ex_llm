# Revised Integration Strategy for ExLLM

## Current Status
- ExLLM is a comprehensive LLM library with cloud providers, cost tracking, context management, and sessions
- MCP implementation: ~3,600 lines of code (substantial protocol implementation)
- Local model support: ~800 lines of code (moderate complexity)

## Recommended Approach

### 1. Local Model Support → Add to ExLLM ✅
**Rationale:**
- Natural fit as another LLM provider/adapter
- Completes the provider story (cloud + local)
- Manageable size (~800 lines)
- Clear value proposition for ExLLM users

**Implementation:**
- Add as `ExLLM.Adapters.Local`
- Include ModelLoader and EXLAConfig as submodules
- Make Bumblebee/Nx/EXLA optional dependencies
- Users only pay for what they use

### 2. MCP Support → Keep Separate ❌
**Rationale:**
- MCP is a large, complex protocol (~3,600 lines)
- Has value beyond just LLM applications
- Could be used by non-LLM tools and applications
- Deserves to be its own focused library

**Future Integration:**
- Create `ex_mcp` as a separate library
- ExLLM could optionally depend on ex_mcp
- Or users could combine them in their applications

## Immediate Action Plan

### Phase 1: Add Local Model Support to ExLLM
1. Create `ExLLM.Adapters.Local`
2. Copy and adapt the local model implementation
3. Add optional dependencies:
   ```elixir
   # In mix.exs deps
   {:bumblebee, "~> 0.5", optional: true},
   {:exla, "~> 0.7", optional: true},
   {:nx, "~> 0.7", optional: true}
   ```
4. Document how to enable local support
5. Add tests with mocks (don't require Bumblebee for tests)

### Phase 2: Extract MCP as Separate Library (Future)
1. Create new `ex_mcp` project
2. Extract MCP implementation from mcp_chat
3. Design clean, focused API for MCP protocol
4. Publish as standalone library
5. Document integration patterns with ExLLM

## Benefits of This Approach

1. **ExLLM stays focused** - LLM functionality only
2. **Clean separation of concerns** - MCP protocol separate from LLM client
3. **Optional dependencies** - Users don't need Bumblebee if not using local models
4. **Composable** - Users can combine ex_llm + ex_mcp as needed
5. **Manageable scope** - Adding local models is achievable, MCP extraction can wait

## Example Usage After Integration

```elixir
# First, add optional deps to your project
{:ex_llm, "~> 0.2.0"},
{:bumblebee, "~> 0.5"},  # Only if using local models
{:exla, "~> 0.7"},       # Only if using local models

# Use local models
{:ok, response} = ExLLM.chat(:local, messages,
  model: "microsoft/phi-2",
  max_tokens: 1000
)

# With session tracking
session = ExLLM.new_session(:local, name: "Local Chat")
{:ok, {response, session}} = ExLLM.chat_with_session(session, "Hello!")

# Model management
{:ok, _} = ExLLM.Local.load_model("microsoft/phi-2")
models = ExLLM.Local.list_loaded_models()
{:ok, _} = ExLLM.Local.unload_model("microsoft/phi-2")
```