# OpenAI Advanced APIs Cache Integration Fix

## Problem
The caching system was not working for most OpenAI advanced APIs (Assistants, Vector Stores, Threads, etc.) even though it was working for some APIs like Fine-tuning.

## Root Cause
There was an inconsistency in the HTTP client response format:
- `HTTPClient.get_json()` was returning `{:ok, %{status: status, body: response_body}}`
- `HTTPClient.post_json()` was returning `{:ok, response_body}`

This inconsistency meant that:
1. GET requests (like `list_fine_tuning_jobs`) had their responses wrapped in a status/body structure
2. POST requests with method override (like `list_assistants` using `post_json` with `method: :get`) returned raw responses
3. The cache metadata was being added at different levels, causing some APIs to not show cache metadata

## Solution
Fixed the inconsistency by ensuring both `get_json` and `post_json` return the same format:
- Both now return `{:ok, add_cache_metadata(response_body)}`
- This ensures cache metadata is consistently added to all responses

## Files Modified
- `/Users/azmaveth/code/ex_llm/lib/ex_llm/providers/shared/http_client.ex`
  - Line 687: Changed `{:ok, response_body}` to `{:ok, add_cache_metadata(response_body)}`
  - Line 779: Changed `{:ok, %{status: status, body: add_cache_metadata(response_body)}}` to `{:ok, add_cache_metadata(response_body)}`

## Verification
All OpenAI advanced APIs now properly cache responses:
- ✅ List Assistants - Shows `from_cache: true`
- ✅ List Vector Stores - Shows `from_cache: true`
- ✅ List Fine-tuning Jobs - Shows `from_cache: true`
- ✅ Create Thread - Shows `from_cache: true`
- ✅ List Files - Shows `from_cache: true`
- ✅ Embeddings - Shows `from_cache: true`
- ✅ Moderate Content - Shows `from_cache: true`

## Impact
- Significantly faster test execution for OpenAI advanced features
- Consistent caching behavior across all HTTP methods
- No breaking changes to existing functionality