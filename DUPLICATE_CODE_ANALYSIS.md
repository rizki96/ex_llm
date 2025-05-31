# Duplicate Code Patterns in ExLLM

## 1. Similar Parsing/Transformation Functions Across Adapters

### Model Name Formatting
Multiple adapters have similar model name formatting functions:
- `format_openai_model_name/1` in OpenAI adapter
- `format_model_name/1` in Groq adapter  
- `format_model_name/1` in OpenAI Compatible module

**Duplication Pattern:**
```elixir
# Common pattern across adapters
model_id
|> String.split(["-", "_", "/"])
|> Enum.map(&String.capitalize/1)
|> Enum.join(" ")
```

### Model Description Generation
- `generate_anthropic_description/1` in Anthropic adapter
- `generate_model_description/1` in Groq adapter
- Similar patterns in OpenAI and other adapters

### Image Formatting for Multimodal
- `format_image_for_anthropic/1` in Anthropic adapter has duplicate logic for handling different map formats
- Similar image handling patterns likely exist in other multimodal adapters

### Stream Chunk Parsing
- `parse_stream_chunk/1` implemented separately in:
  - Anthropic adapter
  - OpenAI adapter
  - OpenAI Compatible module
  - Each with slightly different JSON parsing patterns

## 2. Repeated Error Handling Patterns

### API Key Validation
Every adapter has nearly identical API key validation:
```elixir
defp validate_api_key(nil), do: {:error, "API key not configured"}
defp validate_api_key(""), do: {:error, "API key not configured"}
defp validate_api_key(_), do: {:ok, :valid}
```

### HTTP Error Response Handling
While centralized in `ErrorHandler`, adapters still have duplicate patterns for:
- Parsing JSON error responses
- Extracting error messages from different formats
- Converting status codes to error types

## 3. Common Test Setup Code

### Cache Test Setup Pattern
```elixir
setup do
  case GenServer.whereis(Cache) do
    nil -> {:ok, _} = Cache.start_link()
    _ -> Cache.clear()
  end
  :ok
end
```

### Mock Adapter Setup Pattern
```elixir
setup do
  Mock.start_link()
  Mock.reset()
  :ok
end
```

### Config Restoration Pattern
Multiple test files have similar patterns for saving/restoring Application config:
```elixir
original_config = Application.get_env(:ex_llm, :key, default)
on_exit(fn ->
  Application.put_env(:ex_llm, :key, original_config)
end)
```

## 4. Similar Configuration Patterns

### Default Model Fetching
Every adapter has similar code for getting default model with error handling:
```elixir
defp get_default_model do
  case ModelConfig.get_default_model(:provider) do
    nil ->
      raise "Missing configuration: No default model found..."
    model ->
      model
  end
end
```

### Base URL Configuration
Similar patterns for getting base URL with fallbacks:
```elixir
Map.get(config, :base_url) || 
  System.get_env("PROVIDER_API_BASE") || 
  @default_base_url
```

## 5. Repeated String Manipulation & Data Transformation

### Request Body Building
Each adapter builds request bodies with similar patterns:
- Extract system messages
- Format messages for provider
- Add optional parameters (temperature, max_tokens, etc.)
- Handle function/tool formatting

### Model Capability Checking
Duplicate logic for inferring model capabilities from model ID:
```elixir
String.contains?(model_id, ["vision", "visual", "image", "multimodal"])
String.contains?(model_id, ["turbo", "gpt-4", "claude-3", "gemini"])
```

### Message Formatting
Similar message formatting across adapters:
- Converting between role formats
- Handling multimodal content
- System message extraction

## Recommendations

1. **Extract Common Model Utilities**
   - Create `ExLLM.Utils.Model` module for name formatting, description generation
   - Standardize capability detection logic

2. **Consolidate Test Helpers**
   - Create `ExLLM.TestHelpers` module with common setup patterns
   - Extract config save/restore utilities

3. **Enhance Shared Modules**
   - Move more parsing logic to `MessageFormatter`
   - Extract common request building patterns
   - Standardize stream chunk parsing

4. **Configuration Helpers**
   - Extract default model fetching to `ConfigHelper`
   - Standardize base URL resolution

5. **Validation Module**
   - Create `ExLLM.Validation` for common validation patterns
   - Include API key validation, message validation, etc.