# Gemini API Documentation vs Reality

This document tracks the differences between the official Gemini API documentation and the actual API behavior as observed during implementation and testing.

## Models API (GEMINI-API-01-MODELS.md)

### Model Resource Fields

#### `baseModelId` Field
- **Documentation**: States that `baseModelId` is a required field in the Model resource
  ```json
  {
    "name": string,
    "baseModelId": string,  // Required according to docs
    "version": string,
    ...
  }
  ```
- **Reality**: The API returns `null` for foundation models, but would contain the base model name for fine-tuned models
- **Example Response**:
  ```json
  {
    "name": "models/gemini-2.0-flash",
    "baseModelId": null,  // null for foundation models
    "version": "2.0",
    "displayName": "Gemini 2.0 Flash",
    ...
  }
  ```
- **Understanding**: 
  - Foundation models (e.g., `gemini-2.0-flash`): `baseModelId` is `null` because they ARE the base models
  - Fine-tuned models (e.g., `tunedModels/my-custom-123`): `baseModelId` would be `models/gemini-1.0-pro` or similar
- **Impact**: Tests and code expecting this field need to handle `null` values for foundation models

### Error Response Status Codes

#### Invalid API Key
- **Documentation**: Implies 401 Unauthorized for invalid API keys
- **Reality**: Returns 400 Bad Request with detailed error information
- **Example Response**:
  ```json
  {
    "error": {
      "code": 400,
      "status": "INVALID_ARGUMENT",
      "message": "API key not valid. Please pass a valid API key.",
      "details": [
        {
          "@type": "type.googleapis.com/google.rpc.ErrorInfo",
          "reason": "API_KEY_INVALID"
        }
      ]
    }
  }
  ```

## Content Generation API (GEMINI-API-02-GENERATING-CONTENT.md)

### Function Calling Response Structure

#### Function Call Fields
- **Documentation**: Not clearly specified how function calls are returned in the response
- **Reality**: Function calls are returned as plain maps (not structs) with string keys
- **Example**:
  ```elixir
  # Expected (based on typical patterns):
  function_call.name  # dot notation access
  
  # Reality:
  function_call["name"]  # string key access required
  function_call["args"]["parameter_name"]
  ```

### Grounding Metadata Structure

#### Field Names
- **Documentation**: Refers to `web_search_queries` in examples
- **Reality**: Uses camelCase: `webSearchQueries`
- **Example Response**:
  ```json
  {
    "groundingMetadata": {
      "webSearchQueries": ["query1", "query2"],  // Not web_search_queries
      "groundingChunks": [...],
      "groundingSupports": [...]
    }
  }
  ```

### Code Execution Results

#### Response Structure
- **Documentation**: Suggests structured response with `outcome` field
- **Reality**: Code execution results may be embedded in regular text responses rather than structured `code_execution_result` parts
- **Workaround**: Tests need to check for code-related content in text responses as well

### Safety and Error Responses

#### Cached Content Errors
- **Documentation**: Doesn't clearly specify error codes for invalid cached content
- **Reality**: Returns 403 Forbidden with "PERMISSION_DENIED" status
- **Example**:
  ```json
  {
    "error": {
      "code": 403,
      "status": "PERMISSION_DENIED",
      "message": "CachedContent not found (or permission denied)"
    }
  }
  ```

### Model Naming Conventions

#### Model Name Prefixes
- **Documentation**: Shows examples with `models/` prefix
- **Reality**: The API accepts multiple formats:
  - `gemini-2.0-flash` (without prefix)
  - `models/gemini-2.0-flash` (with prefix)
  - `gemini/gemini-2.0-flash` (provider prefix - needs special handling)
- **Implementation Note**: Normalize function required to handle all variants

### Default Model Changes

#### Model Availability
- **Documentation**: References models like `gemini-pro` and `gemini-1.0-pro`
- **Reality**: These models have been deprecated/removed. Current models include:
  - `gemini-2.0-flash` (recommended default)
  - `gemini-1.5-flash`
  - `gemini-1.5-pro`
  - Various specialized variants (thinking, vision, etc.)

## General API Behavior

### Response Consistency

#### Nil vs Missing Fields
- **Documentation**: Suggests certain fields are required
- **Reality**: Many "required" fields can be `null` or missing entirely:
  - `baseModelId`: Always `null`
  - `temperature`, `topK`, `topP`: Can be `null` for some models
  - Various metadata fields: Present only when relevant

### Streaming Responses

#### Error Handling in Streams
- **Documentation**: Limited information on error handling during streaming
- **Reality**: Errors during streaming are thrown rather than returned, requiring special handling:
  ```elixir
  # Need to catch throws:
  catch_throw(Enum.to_list(stream))
  ```

## Recommendations

1. **Always validate API responses** against actual behavior, not just documentation
2. **Handle null/missing fields gracefully** even for "required" fields
3. **Use string keys** for accessing nested response data
4. **Test with real API** to discover undocumented behaviors
5. **Implement robust error handling** for various status codes and error formats
6. **Maintain flexible model name handling** to support multiple formats

## Token Counting API (GEMINI-API-04-TOKENS.md)

### Model Name Handling

#### Nil Model Names
- **Documentation**: Doesn't specify behavior for nil/missing model names
- **Reality**: The `normalize_model_name/1` function must handle nil values gracefully
- **Implementation**: Added explicit nil clause to prevent function clause errors

### Response Structure

#### Token Count Types
- **Documentation**: Shows `totalTokenCount` as integer in examples
- **Reality**: Token counts are always returned as integers, parsing functions must handle this correctly

## Files API (GEMINI-API-05-FILES.md)

### Resumable Upload Protocol

#### Upload URL Response
- **Documentation**: Implies upload URL is a string
- **Reality**: The `x-goog-upload-url` header can be returned as either:
  - A string: `"https://generativelanguage.googleapis.com/upload/..."`
  - An array with single element: `["https://generativelanguage.googleapis.com/upload/..."]`
- **Implementation**: Must handle both cases in `extract_upload_url/1`

### Error Responses

#### Non-existent Files
- **Documentation**: Standard REST would suggest 404 Not Found
- **Reality**: Returns 403 Forbidden for non-existent files
- **Example**:
  ```json
  {
    "error": {
      "code": 403,
      "status": "PERMISSION_DENIED",
      "message": "Permission denied on resource"
    }
  }
  ```
- **Impact**: Tests must accept both 403 and 404 as valid error responses

### HTTP Client Issues

#### Req.put Syntax
- **Documentation Examples**: May show simplified PUT requests
- **Reality**: `Req.put(url, body: data, headers: headers)` doesn't work
- **Working Solution**: Must use `Req.request(method: :put, url: url, body: data, headers: headers)`

## Context Caching API (GEMINI-API-06-CACHING.md)

### Content Size Requirements

#### Minimum Token Count
- **Documentation**: Mentions caching is for "large contexts" but doesn't specify minimum
- **Reality**: Enforces strict minimum of 4096 tokens
- **Error Response**:
  ```json
  {
    "error": {
      "code": 400,
      "status": "INVALID_ARGUMENT", 
      "message": "Cached content is too small. total_token_count=44, min_total_token_count=4096"
    }
  }
  ```
- **Impact**: Test data must be substantial (e.g., 50+ repetitions of a paragraph)

### Update Operations

#### PATCH Request Body
- **Documentation**: Shows updating cached content with PATCH
- **Reality**: Including the resource `name` in the request body causes conflicts
- **Error**:
  ```json
  {
    "error": {
      "code": 400,
      "message": "Invalid value at 'cached_content' (oneof), oneof field '_name' is already set. Cannot set 'name'"
    }
  }
  ```
- **Solution**: Only include fields being updated (ttl or expireTime) in request body

### Response Fields

#### Optional Fields in Responses
- **Documentation**: Shows complete responses with all fields
- **Reality**: Many fields are omitted from responses:
  - `systemInstruction`: Not returned even when set during creation
  - `tools`: Not returned even when set during creation
  - `contents`: May be omitted
- **Impact**: Tests should not assert on presence of these fields

### TTL Format

#### Duration Parsing
- **Documentation**: Shows TTL as string like "3600s"
- **Reality**: Must be parsed to float internally for proper handling
- **Implementation**: TTL parsing returns float values (e.g., `{:ok, 3600.0}` not `{:ok, 3600}`)

## Fine-tuning API (GEMINI-API-08-TUNING_TUNING.md)

### API Authentication

#### Error Codes
- **Documentation**: Standard REST would suggest 401 for authentication failures
- **Reality**: Returns 400 Bad Request for invalid API keys (consistent with other Gemini APIs)
- **Example**:
  ```json
  {
    "error": {
      "code": 400,
      "status": "INVALID_ARGUMENT",
      "message": "API key not valid. Please pass a valid API key."
    }
  }
  ```

### Error Responses for Non-existent Resources

#### Tuned Model Operations
- **Documentation**: Standard REST would suggest 404 Not Found
- **Reality**: Returns 400 or 403 for non-existent tuned models (consistent with Files API)
- **Impact**: Tests must accept 400, 403, and 404 as valid error responses

### Operation Tracking

#### Long-running Operations
- **Documentation**: Create operations return Operation objects for tracking
- **Reality**: Operation format follows Google's longrunning operations pattern
- **Example Response**:
  ```json
  {
    "name": "operations/abc-123-def",
    "metadata": {
      "@type": "type.googleapis.com/google.ai.generativelanguage.v1beta.CreateTunedModelMetadata"
    }
  }
  ```

## Permissions API (GEMINI-API-09-TUNING_PERMISSIONS.md)

### Authentication Requirements

#### OAuth2 vs API Key
- **Documentation**: Not explicitly clear about authentication requirements
- **Reality**: Permissions API requires OAuth2 authentication, NOT API keys
- **Error Response**:
  ```json
  {
    "error": {
      "code": 401,
      "status": "UNAUTHENTICATED", 
      "message": "API keys are not supported by this API. Expected OAuth2 access token or other authentication credentials that assert a principal.",
      "details": [
        {
          "@type": "type.googleapis.com/google.rpc.ErrorInfo",
          "reason": "CREDENTIALS_MISSING"
        }
      ]
    }
  }
  ```
- **Impact**: All permissions operations require OAuth2 access tokens
- **Implication**: This API is designed for managing access control where user identity matters

### API Design

#### Permission Model
- **Documentation**: Shows three roles (READER, WRITER, OWNER) and three grantee types (USER, GROUP, EVERYONE)
- **Reality**: Follows standard Google Cloud IAM patterns
- **Key Points**:
  - OWNER can delete resources and transfer ownership
  - WRITER has READER permissions plus can edit and share
  - READER can only use resources for inference
  - EVERYONE grantee type doesn't require email_address

## General Patterns Observed

### API Consistency
1. **Error Codes**: 403 often used where 404 might be expected
2. **Field Presence**: Many "optional" fields are completely omitted rather than null
3. **Type Flexibility**: Headers and other fields may be strings or arrays
4. **Minimum Requirements**: Undocumented minimums (like 4096 tokens for caching)

### Testing Considerations
1. **API Key Validation**: Most operations return 400 (not 401) for invalid keys
2. **Field Assertions**: Avoid asserting on optional field presence
3. **Error Handling**: Accept multiple valid error codes (403/404)
4. **Data Size**: Ensure test data meets minimum requirements

## Version Information

- **Documentation Version**: v1beta (as of December 2024)
- **Tested Models**: Gemini 2.0, 1.5 family
- **APIs Implemented**: Models, Content Generation, Token Counting, Files, Context Caching, Embeddings, Fine-tuning, Permissions
- **Last Updated**: June 2025

---

**Note**: This document reflects observations from actual API usage and may change as Google updates their API. Always test against the live API to verify current behavior.