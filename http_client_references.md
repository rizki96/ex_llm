# Legacy HTTPClient Reference Report

Generated on: 2025-06-26 06:14:32.620275Z

## Summary
- **Total files with references**: 26
- **Total references found**: 96

### Breakdown by category:
- **Other**: 0 files, 0 references
- **Configuration**: 0 files, 0 references
- **Documentation**: 8 files, 42 references
- **Production**: 13 files, 24 references
- **Tests**: 5 files, 30 references


## Dependency Tree
```
HTTPClient
├── Direct Usage (imports/calls)
│   └── (none)
├── Alias Only
│   └── (none)
└── Other References
    ├── CHANGELOG.md
    ├── CLAUDE.md
    ├── HTTPCLIENT_REMOVAL_PLAN.md
    ├── TASKS.md
    ├── docs/ARCHITECTURE.md
    ├── docs/LOGGER.md
    ├── docs/telemetry_migration_example.md
    ├── guides/internal_modules.md
    ├── lib/ex_llm/infrastructure/circuit_breaker/bulkhead.ex
    ├── lib/ex_llm/plugs/execute_stream_request.ex
    ├── lib/ex_llm/providers/anthropic.ex
    ├── lib/ex_llm/providers/gemini/base.ex
    ├── lib/ex_llm/providers/gemini/chunk.ex
    ├── lib/ex_llm/providers/gemini/content.ex
    ├── lib/ex_llm/providers/gemini/corpus.ex
    ├── lib/ex_llm/providers/gemini/document.ex
    ├── lib/ex_llm/providers/gemini/qa.ex
    ├── lib/ex_llm/providers/openai.ex
    ├── lib/ex_llm/providers/openai_compatible.ex
    ├── lib/ex_llm/providers/shared/http_client.ex
    ├── lib/ex_llm/testing/interceptor.ex
    ├── test/ex_llm/core/streaming_pipeline_test.exs
    ├── test/ex_llm/providers/shared/http_client_test.exs
    ├── test/ex_llm/providers/shared/http_core_streaming_test.exs
    ├── test/ex_llm/providers/shared/streaming_migration_test.exs
    └── test/ex_llm/providers/shared/streaming_performance_test.exs

```

## Production Code (`lib/`)
### `lib/ex_llm/infrastructure/circuit_breaker/bulkhead.ex`

  - **Line 35** (Text Match): `HTTPClient.get("/api/data")`

### `lib/ex_llm/plugs/execute_stream_request.ex`

  - **Line 7** (Text Match): `from HTTPClient to use the modern HTTP.Core streaming infrastructure.`

### `lib/ex_llm/providers/anthropic.ex`

  - **Line 858** (Text Match): `# HTTP client helper functions to migrate from HTTPClient to Core`

### `lib/ex_llm/providers/gemini/base.ex`

  - **Line 42** (Text Match): `# Use shared HTTPClient for caching support`
  - **Line 74** (Text Match): `# Use shared HTTPClient for caching support`

### `lib/ex_llm/providers/gemini/chunk.ex`

  - **Line 887** (Text Match): `# Handle different response formats from HTTPClient`
  - **Line 894** (Text Match): `# Wrapped HTTP response format (from cache or HTTPClient)`
  - **Line 959** (Text Match): `# Handle different response formats from HTTPClient`
  - **Line 966** (Text Match): `# Wrapped HTTP response format (from cache or HTTPClient)`

### `lib/ex_llm/providers/gemini/content.ex`

  - **Line 605** (Text Match): `# Use HTTPClient directly for streaming`

### `lib/ex_llm/providers/gemini/corpus.ex`

  - **Line 588** (Text Match): `# Handle different response formats from HTTPClient`
  - **Line 595** (Text Match): `# Wrapped HTTP response format (from cache or HTTPClient)`

### `lib/ex_llm/providers/gemini/document.ex`

  - **Line 717** (Text Match): `# Handle different response formats from HTTPClient`
  - **Line 724** (Text Match): `# Wrapped HTTP response format (from cache or HTTPClient)`

### `lib/ex_llm/providers/gemini/qa.ex`

  - **Line 249** (Text Match): `# Handle different response formats from HTTPClient`
  - **Line 256** (Text Match): `# Wrapped HTTP response format (from cache or HTTPClient)`

### `lib/ex_llm/providers/openai.ex`

  - **Line 141** (Text Match): `# Create a stream using HTTPClient's streaming capabilities`
  - **Line 3537** (Text Match): `# HTTP client helper functions to migrate from HTTPClient to Core`

### `lib/ex_llm/providers/openai_compatible.ex`

  - **Line 105** (Text Match): `# Store provider name for HTTPClient`

### `lib/ex_llm/providers/shared/http_client.ex`

  - **Line 1** (Text Match): `defmodule ExLLM.Providers.Shared.HTTPClient do`
  - **Line 122** (Text Match): `HTTPClient.post_stream(url, body,`
  - **Line 249** (Text Match): `Logger.debug("HTTPClient.post error: #{inspect(error)}")`

### `lib/ex_llm/testing/interceptor.ex`

  - **Line 5** (Text Match): `This module hooks into the HTTPClient request/response cycle to provide`
  - **Line 355** (Text Match): `# Use string key for HTTPClient replay compatibility`

## Test Code (`test/`)
### `test/ex_llm/core/streaming_pipeline_test.exs`

  - **Line 12** (Text Match): `# Mock the HTTPClient to return controlled chunks`
  - **Line 36** (Text Match): `# Mock the HTTPClient to return Anthropic-style chunks`

### `test/ex_llm/providers/shared/http_client_test.exs`

  - **Line 1** (Text Match): `defmodule ExLLM.Providers.Shared.HTTPClientTest do`
  - **Line 5** (Text Match): `alias ExLLM.Providers.Shared.HTTPClient`
  - **Line 64** (Text Match): `{:ok, response} = HTTPClient.post(url, body, headers: headers)`
  - **Line 87** (Text Match): `{:ok, response} = HTTPClient.get(url, headers)`
  - **Line 132** (Text Match): `{:ok, _response} = HTTPClient.post_stream(url, body, headers: headers, into: collector)`
  - **Line 151** (Text Match): `{:error, error} = HTTPClient.post_stream(url, body, headers: headers, into: collector)`
  - **Line 167** (Text Match): `{:error, error} = HTTPClient.post(url, body, headers: headers)`
  - **Line 184** (Text Match): `{:error, error} = HTTPClient.post(url, body, headers: headers)`
  - **Line 200** (Text Match): `{:error, error} = HTTPClient.post(url, body, headers: headers)`
  - **Line 211** (Text Match): `{:error, error} = HTTPClient.post(url, body, headers: headers)`
  - **Line 241** (Text Match): `HTTPClient.post(url, body, headers: headers, cache_key: cache_key, cache_ttl: 60_000)`
  - **Line 247** (Text Match): `HTTPClient.post(url, body, headers: headers, cache_key: cache_key, cache_ttl: 60_000)`
  - **Line 282** (Text Match): `{:ok, response} = HTTPClient.post(url, body, headers: headers, retry: true, max_retries: 2)`
  - **Line 317** (Text Match): `HTTPClient.post_multipart(url, multipart,`

### `test/ex_llm/providers/shared/http_core_streaming_test.exs`

  - **Line 6** (Text Match): `compatibility and behavior with the legacy HTTPClient.post_stream.`
  - **Line 10** (Text Match): `alias ExLLM.Providers.Shared.{HTTP.Core, HTTPClient, StreamingCoordinator}`
  - **Line 197** (Text Match): `describe "HTTPClient.post_stream compatibility" do`
  - **Line 198** (Text Match): `test "HTTPClient.post_stream still works as compatibility layer", %{`
  - **Line 251** (Text Match): `assert {:ok, _} = HTTPClient.post_stream(url, body, opts)`

### `test/ex_llm/providers/shared/streaming_migration_test.exs`

  - **Line 3** (Text Match): `Test suite to verify that the streaming migration from HTTPClient to HTTP.Core`
  - **Line 17** (Text Match): `HTTPClient,`
  - **Line 34** (Text Match): `test "HTTPClient.post_stream and HTTP.Core.stream produce identical results", %{`
  - **Line 47** (Text Match): `# Test HTTPClient.post_stream (legacy)`
  - **Line 299** (Text Match): `{:ok, _} = HTTPClient.post_stream(url, body, opts)`
  - **Line 365** (Text Match): `case HTTPClient.post_stream(url, body, opts) do`

### `test/ex_llm/providers/shared/streaming_performance_test.exs`

  - **Line 6** (Text Match): `1. Legacy HTTPClient.post_stream`
  - **Line 102** (Text Match): `IO.puts("Legacy HTTPClient: #{legacy_mem} KB")`
  - **Line 148** (Text Match): `IO.puts("Legacy HTTPClient: #{legacy_latency}ms")`

## Configuration (`config/`)
_None found._


## Documentation
### `CHANGELOG.md`

  - **Line 411** (Text Match): `- Enhanced `HTTPClient` with unified streaming support via `post_stream/3``
  - **Line 543** (Text Match): `- JSON double-encoding issue in HTTPClient`

### `CLAUDE.md`

  - **Line 279** (Text Match): `ExLLM has successfully migrated from a legacy HTTPClient facade to a modern Tesla middleware-based HTTP architecture:`
  - **Line 307** (Text Match): `- **HTTP.Core Adoption**: All streaming components now use HTTP.Core.stream directly instead of HTTPClient.stream_request`
  - **Line 309** (Text Match): `- **Zero Legacy Dependencies**: No remaining references to HTTPClient.stream_request in the codebase`
  - **Line 312** (Text Match): `- **HTTPClient.post_stream** is now deprecated and serves as a compatibility shim`
  - **Line 417** (Text Match): `During the HTTP client migration from HTTPClient to HTTP.Core, we encountered and resolved several critical callback signature mismatches:`

### `HTTPCLIENT_REMOVAL_PLAN.md`

  - **Line 1** (Text Match): `# Legacy HTTPClient Removal Plan`
  - **Line 4** (Text Match): `This plan provides a systematic approach to completely remove the legacy HTTPClient compatibility layer from the ExLLM codebase, ensuring no functionality is lost while modernizing the HTTP infrastructure.`
  - **Line 13** (Text Match): `**Objective:** Map all HTTPClient dependencies and usage patterns`
  - **Line 18** (Text Match): `git grep -n "HTTPClient" > httpclient_references.txt`
  - **Line 28** (Text Match): `- Search for aliases: `alias.*HTTPClient``
  - **Line 30** (Text Match): `- Module attributes referencing HTTPClient`
  - **Line 34** (Text Match): `HTTPClient`
  - **Line 63** (Text Match): `# Verify no direct HTTPClient usage in providers`
  - **Line 64** (Text Match): `git grep "HTTPClient" lib/ex_llm/providers/ --include="*.ex"`
  - **Line 76** (Text Match): `- Remove HTTPClient vs HTTP.Core comparison tests`
  - **Line 84** (Text Match): `- Update to remove HTTPClient references`
  - **Line 114** (Text Match): `- Remove if only used by HTTPClient`
  - **Line 132** (Text Match): `- [ ] `git grep HTTPClient` returns no results`
  - **Line 140** (Text Match): `- Remove HTTPClient references from CLAUDE.md`
  - **Line 172** (Text Match): `git grep -n "HTTPClient" | tee httpclient_references.txt`
  - **Line 197** (Text Match): `## Remove Legacy HTTPClient Compatibility Layer`
  - **Line 200** (Text Match): `Completes the HTTP client migration by removing the deprecated HTTPClient`
  - **Line 204** (Text Match): `- Removed `HTTPClient` module and all references`
  - **Line 216** (Text Match): `All functionality previously provided by HTTPClient is now handled by`
  - **Line 239** (Text Match): `- All HTTPClient references are removed from the codebase`
  - **Line 240** (Text Match): `- All tests pass without any HTTPClient dependencies`
  - **Line 247** (Text Match): `This plan ensures safe, systematic removal of the legacy HTTPClient layer while maintaining all functionality through the modern HTTP.Core implementation.`

### `TASKS.md`

  - **Line 709** (Text Match): `- [ ] Add provider-specific headers to HTTPClient`
  - **Line 1118** (Text Match): `- Hook into HTTPClient request/response cycle`
  - **Line 1123** (Text Match): `- `ExLLM.Adapters.Shared.HTTPClient``
  - **Line 1127** (Text Match): `#### Task 2.2: Enhance HTTPClient with Timestamp-Based Test Caching`

### `docs/ARCHITECTURE.md`

  - **Line 113** (Text Match): `ExLLM.Providers.Shared.HTTPClient           # HTTP communication`
  - **Line 172** (Text Match): `alias ExLLM.Providers.Shared.{HTTPClient, MessageFormatter}`

### `docs/LOGGER.md`

  - **Line 398** (Text Match): `case HTTPClient.post(url, body, headers) do`

### `docs/telemetry_migration_example.md`

  - **Line 83** (Text Match): `defmodule ExLLM.Adapters.Shared.HTTPClient do`
  - **Line 111** (Text Match): `defmodule ExLLM.Adapters.Shared.HTTPClient do`
  - **Line 152** (Text Match): `case HTTPClient.post_json(@api_url, request_body, headers) do`
  - **Line 175** (Text Match): `case HTTPClient.post_json(@api_url, request_body, headers) do`

### `guides/internal_modules.md`

  - **Line 23** (Text Match): `- `ExLLM.Providers.Shared.HTTPClient` - HTTP implementation`
  - **Line 88** (Text Match): `ExLLM.Providers.Shared.HTTPClient.post_json(url, body, headers)`

## Other Files
_None found._


## Next Steps

Based on this analysis:
1. Review all production code references to ensure they have HTTP.Core equivalents
2. Check if StreamingCoordinator and EnhancedStreamingCoordinator have been fully migrated
3. Plan test file updates for Phase 3
4. Identify any orphaned modules that can be removed
