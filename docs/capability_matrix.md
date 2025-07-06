# Provider Capability Matrix

The Provider Capability Matrix is a comprehensive view of which features are supported by each LLM provider in ExLLM. It combines static capability configuration with runtime checks and test results to provide accurate information about feature availability.

## Overview

The capability matrix tracks the following core capabilities across all providers:

- **Chat**: Basic chat completion functionality
- **Streaming**: Real-time response streaming
- **Models**: Dynamic model listing (`list_models` API)
- **Functions**: Function calling / tool use
- **Vision**: Image understanding capabilities
- **Tools**: Advanced tool use (beyond basic function calling)

## Status Indicators

The matrix uses four status indicators:

- ✅ **Pass** - Feature is supported and working (tests pass or configuration confirms support)
- ❌ **Fail** - Feature is not supported or tests are failing
- ⏭️ **Skip** - Feature cannot be tested (usually due to missing API key)
- ❓ **Unknown** - No data available about this feature

## Usage

### Command Line

Generate and display the capability matrix using the Mix task:

```bash
# Display in console
mix ex_llm.capability_matrix

# Export to Markdown
mix ex_llm.capability_matrix --format markdown

# Export to HTML
mix ex_llm.capability_matrix --format html

# Show extended capabilities
mix ex_llm.capability_matrix --extended

# Include test results (if available)
mix ex_llm.capability_matrix --with-tests
```

### Programmatic Access

Use the capability matrix in your code:

```elixir
# Generate the full matrix
{:ok, matrix} = ExLLM.CapabilityMatrix.generate()

# Check specific provider capabilities
openai_caps = matrix.matrix[:openai]
IO.inspect(openai_caps[:vision])
# => %{indicator: "✅", reason: "Supported and configured"}

# Find providers supporting specific features
vision_providers = for {provider, caps} <- matrix.matrix,
                      caps[:vision].indicator == "✅",
                      do: provider

# Display the matrix
ExLLM.CapabilityMatrix.display()

# Export to file
{:ok, "capability_matrix.md"} = ExLLM.CapabilityMatrix.export(:markdown)
{:ok, "capability_matrix.html"} = ExLLM.CapabilityMatrix.export(:html)
```

### Integration with Tests

The capability matrix can aggregate test results to show real-world status:

```elixir
# Get test status for a specific provider/capability
status = ExLLM.TestResultAggregator.get_test_status(:openai, :streaming)
# => :passed | :failed | :skipped | :not_tested

# Generate test summary
summary = ExLLM.TestResultAggregator.generate_summary()
```

## Architecture

The capability matrix system consists of three main components:

1. **ExLLM.CapabilityMatrix** - Main module for generating and displaying the matrix
2. **ExLLM.TestResultAggregator** - Aggregates test results by provider and capability
3. **Mix.Tasks.ExLlm.CapabilityMatrix** - Mix task for command-line usage

### Data Sources

The matrix combines data from multiple sources:

1. **Static Configuration** (`ExLLM.Capabilities`)
   - Hardcoded capability definitions
   - Provider feature lists
   
2. **Provider Capabilities** (`ExLLM.Infrastructure.Config.ProviderCapabilities`)
   - Detailed provider information
   - Endpoint availability
   - Authentication methods
   
3. **Model Capabilities** (`ExLLM.Infrastructure.Config.ModelCapabilities`)
   - Model-specific features
   - Context windows and limits
   
4. **Test Results** (when available)
   - Actual test execution status
   - Runtime verification

### Status Determination Logic

The system determines capability status using this priority:

1. **Test Results** (if available)
   - ✅ Passed tests
   - ❌ Failed tests
   - ⏭️ Skipped tests
   
2. **Configuration Status**
   - ⏭️ If provider not configured (no API key)
   - ❌ If capability not supported in configuration
   
3. **Static Capabilities**
   - ✅ If listed as supported
   - ❓ If no information available

## Example Output

```
Provider Capability Matrix
========================

| Provider   | Chat     | Streaming | Models    | Functions | Vision    | Tools     |
|------------|----------|-----------|-----------|-----------|-----------|-----------|
| Openai     | ✅       | ✅        | ✅        | ✅        | ✅        | ✅        |
| Anthropic  | ✅       | ✅        | ✅        | ✅        | ✅        | ✅        |
| Gemini     | ✅       | ✅        | ✅        | ✅        | ✅        | ✅        |
| Groq       | ✅       | ✅        | ✅        | ✅        | ❌        | ✅        |
| Ollama     | ✅       | ✅        | ✅        | ❌        | ❌        | ❌        |
| Mistral    | ✅       | ✅        | ✅        | ✅        | ❌        | ❌        |
| Xai        | ✅       | ✅        | ✅        | ✅        | ❌        | ❌        |
| Perplexity | ✅       | ✅        | ✅        | ❌        | ❌        | ❌        |

Legend:
✅ Pass - Feature supported and working
❌ Fail - Feature not supported or failing
⏭️ Skip - Feature not tested (no API key)
❓ Unknown - No data available
```

## Extending the Matrix

To add new capabilities:

1. Add the capability to `@core_capabilities` in `ExLLM.CapabilityMatrix`
2. Update the `map_capability/1` function if needed
3. Add the capability to provider configurations in `ExLLM.Capabilities`
4. Update tests to include the new capability

To add new providers:

1. Add the provider to `get_providers/0` in `ExLLM.CapabilityMatrix`
2. Configure capabilities in `ExLLM.Capabilities`
3. Add provider configuration in `ExLLM.Infrastructure.Config.ProviderCapabilities`

## Best Practices

1. **Use for Provider Selection**
   ```elixir
   # Find providers that support required features
   providers = ExLLM.Capabilities.providers_with_capability(:vision)
   configured = Enum.filter(providers, &ExLLM.configured?/1)
   ```

2. **Graceful Feature Degradation**
   ```elixir
   if ExLLM.Capabilities.supports?(provider, :vision) do
     # Use vision features
   else
     # Fall back to text-only
   end
   ```

3. **Test Integration**
   - Tag tests with provider and capability information
   - Use `skip_unless_configured_and_supports/2` in tests
   - Run capability matrix after test suite for verification

4. **CI/CD Integration**
   - Generate matrix as part of test reports
   - Track capability changes over time
   - Alert on capability regressions