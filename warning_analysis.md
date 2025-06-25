# Dialyzer Warning Analysis

Total warnings: 59

## Warnings by Type

### call (6 warnings)

#### build_request (1)
- Line 51: lib/ex_llm/providers/bedrock/build_request.ex

#### engine (2)
- Line 305: lib/ex_llm/providers/shared/streaming/engine.ex
- Line 336: lib/ex_llm/providers/shared/streaming/engine.ex

#### http_client (1)
- Line 75: lib/ex_llm/providers/shared/http_client.ex

#### multipart (1)
- Line 349: lib/ex_llm/providers/shared/http/multipart.ex

#### parse_response (1)
- Line 45: lib/ex_llm/providers/gemini/parse_response.ex

### guard_fail (6 warnings)

#### build_request (6)
- Line 8: lib/ex_llm/providers/lmstudio/build_request.ex
- Line 8: lib/ex_llm/providers/mistral/build_request.ex
- Line 8: lib/ex_llm/providers/ollama/build_request.ex
- Line 8: lib/ex_llm/providers/openrouter/build_request.ex
- Line 8: lib/ex_llm/providers/perplexity/build_request.ex
- Line 8: lib/ex_llm/providers/xai/build_request.ex

### no_return (3 warnings)

#### http_client (1)
- Line 74: lib/ex_llm/providers/shared/http_client.ex

#### multipart (1)
- Line 349: lib/ex_llm/providers/shared/http/multipart.ex

#### stream_parse_response (1)
- Line 32: lib/ex_llm/providers/bedrock/stream_parse_response.ex

### pattern_match (32 warnings)

#### anthropic (8)
- Line 209: lib/ex_llm/providers/anthropic.ex
- Line 592: lib/ex_llm/providers/anthropic.ex
- Line 614: lib/ex_llm/providers/anthropic.ex
- Line 636: lib/ex_llm/providers/anthropic.ex
- Line 639: lib/ex_llm/providers/anthropic.ex
- Line 715: lib/ex_llm/providers/anthropic.ex
- Line 737: lib/ex_llm/providers/anthropic.ex
- Line 759: lib/ex_llm/providers/anthropic.ex

#### compatibility (1)
- Line 128: lib/ex_llm/providers/shared/streaming/compatibility.ex

#### engine (1)
- Line 221: lib/ex_llm/providers/shared/streaming/engine.ex

#### execute_request (1)
- Line 93: lib/ex_llm/plugs/execute_request.ex

#### http_client (1)
- Line 367: lib/ex_llm/providers/shared/http_client.ex

#### lmstudio (3)
- Line 309: lib/ex_llm/providers/lmstudio.ex
- Line 321: lib/ex_llm/providers/lmstudio.ex
- Line 352: lib/ex_llm/providers/lmstudio.ex

#### ollama (3)
- Line 294: lib/ex_llm/providers/ollama.ex
- Line 301: lib/ex_llm/providers/ollama.ex
- Line 1573: lib/ex_llm/providers/ollama.ex

#### openai (4)
- Line 3393: lib/ex_llm/providers/openai.ex
- Line 3431: lib/ex_llm/providers/openai.ex
- Line 3512: lib/ex_llm/providers/openai.ex
- Line 3557: lib/ex_llm/providers/openai.ex

#### stream_parse_response (9)
- Line 7: lib/ex_llm/providers/groq/stream_parse_response.ex
- Line 7: lib/ex_llm/providers/lmstudio/stream_parse_response.ex
- Line 7: lib/ex_llm/providers/mistral/stream_parse_response.ex
- Line 7: lib/ex_llm/providers/openrouter/stream_parse_response.ex
- Line 7: lib/ex_llm/providers/perplexity/stream_parse_response.ex
- Line 7: lib/ex_llm/providers/xai/stream_parse_response.ex
- Line 54: lib/ex_llm/providers/ollama/stream_parse_response.ex
- Line 55: lib/ex_llm/providers/gemini/stream_parse_response.ex
- Line 55: lib/ex_llm/providers/openai/stream_parse_response.ex

#### xai (1)
- Line 60: lib/ex_llm/providers/xai.ex

### unknown_type (1 warnings)

#### multipart (1)
- Line 159: lib/ex_llm/providers/shared/http/multipart.ex

### unused_fun (11 warnings)

#### compatibility (1)
- Line 226: lib/ex_llm/providers/shared/streaming/compatibility.ex

#### engine (1)
- Line 355: lib/ex_llm/providers/shared/streaming/engine.ex

#### ollama (7)
- Line 1794: lib/ex_llm/providers/ollama.ex
- Line 1816: lib/ex_llm/providers/ollama.ex
- Line 1882: lib/ex_llm/providers/ollama.ex
- Line 1893: lib/ex_llm/providers/ollama.ex
- Line 1916: lib/ex_llm/providers/ollama.ex
- Line 1929: lib/ex_llm/providers/ollama.ex
- Line 1961: lib/ex_llm/providers/ollama.ex

#### parse_response (2)
- Line 93: lib/ex_llm/providers/gemini/parse_response.ex
- Line 115: lib/ex_llm/providers/gemini/parse_response.ex

## Pattern Match Analysis

Error handling patterns: 21
Stream-related patterns: 11
Other patterns: 0

## Warnings by Provider

### anthropic.ex (8 warnings)
Types: pattern_match: 8

### bedrock (2 warnings)
Types: call: 1, no_return: 1

### gemini (4 warnings)
Types: call: 1, pattern_match: 1, unused_fun: 2

### groq (1 warnings)
Types: pattern_match: 1

### lmstudio (2 warnings)
Types: guard_fail: 1, pattern_match: 1

### lmstudio.ex (3 warnings)
Types: pattern_match: 3

### mistral (2 warnings)
Types: guard_fail: 1, pattern_match: 1

### ollama (2 warnings)
Types: guard_fail: 1, pattern_match: 1

### ollama.ex (10 warnings)
Types: pattern_match: 3, unused_fun: 7

### openai (1 warnings)
Types: pattern_match: 1

### openai.ex (4 warnings)
Types: pattern_match: 4

### openrouter (2 warnings)
Types: guard_fail: 1, pattern_match: 1

### perplexity (2 warnings)
Types: guard_fail: 1, pattern_match: 1

### shared (12 warnings)
Types: call: 4, no_return: 2, pattern_match: 3, unknown_type: 1, unused_fun: 2

### xai (2 warnings)
Types: guard_fail: 1, pattern_match: 1

### xai.ex (1 warnings)
Types: pattern_match: 1
