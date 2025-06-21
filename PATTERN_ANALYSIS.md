# ExLLM Function Pattern Analysis

## Overview

Analysis of the 37 repetitive function groups in the main ExLLM module to design the delegation architecture.

**Generated**: June 21, 2025
**Scope**: All provider delegation functions in lib/ex_llm.ex

---

## Pattern Categories

### Category 1: Direct Delegation (Simple)
Functions that directly call provider modules without argument transformation.

**Examples**:
- `create_cached_context/3` - Only Gemini, direct call
- `list_files/2` - Gemini and OpenAI, both direct calls
- `get_batch/3` - Only Anthropic, direct call

**Pattern**:
```elixir
def function_name(provider, args, opts \\ [])
def function_name(:provider, args, opts), do: Provider.Module.function(args, opts)
def function_name(provider, _args, _opts), do: {:error, "not supported for #{provider}"}
```

### Category 2: Argument Transformation (Medium)
Functions that need to transform arguments before calling provider modules.

**Examples**:
- `upload_file/3` - OpenAI needs `:purpose` extracted and passed separately
- `create_fine_tune/3` - Complex transformation needed for Gemini vs OpenAI

**Pattern**:
```elixir
def function_name(provider, args, opts \\ [])
def function_name(:provider1, args, opts), do: Provider1.function(args, opts)
def function_name(:provider2, args, opts) do
  transformed = transform_args(args, opts)
  Provider2.function(transformed)
end
def function_name(provider, _args, _opts), do: {:error, "not supported for #{provider}"}
```

### Category 3: Complex Logic (High)
Functions with significant preprocessing logic before provider calls.

**Examples**:
- `create_fine_tune/3` - Has `build_gemini_tuning_request/2` and `build_openai_tuning_params/2`
- Some functions may have validation, format conversion, etc.

---

## Function Inventory

### File Management (4 functions)
1. `upload_file/3` - **Category 2** - OpenAI needs `:purpose` extraction
   - Gemini: `ExLLM.Providers.Gemini.Files.upload_file(file_path, opts)` [direct]
   - OpenAI: Extract purpose, `ExLLM.Providers.OpenAI.upload_file(file_path, purpose, config_opts)` [transform]

2. `list_files/2` - **Category 1** - Direct calls
   - Gemini: `ExLLM.Providers.Gemini.Files.list_files(opts)` [direct]
   - OpenAI: `ExLLM.Providers.OpenAI.list_files(opts)` [direct]

3. `get_file/3` - **Category 1** - Direct calls
   - Gemini: `ExLLM.Providers.Gemini.Files.get_file(file_id, opts)` [direct]
   - OpenAI: `ExLLM.Providers.OpenAI.get_file(file_id, opts)` [direct]

4. `delete_file/3` - **Category 1** - Direct calls
   - Gemini: `ExLLM.Providers.Gemini.Files.delete_file(file_id, opts)` [direct]
   - OpenAI: `ExLLM.Providers.OpenAI.delete_file(file_id, opts)` [direct]

### Context Caching (5 functions)
5. `create_cached_context/3` - **Category 1** - Gemini only
   - Gemini: `ExLLM.Providers.Gemini.Caching.create_cached_content(content, opts)` [direct]

6. `get_cached_context/3` - **Category 1** - Gemini only
   - Gemini: `ExLLM.Providers.Gemini.Caching.get_cached_content(name, opts)` [direct]

7. `update_cached_context/4` - **Category 1** - Gemini only
   - Gemini: `ExLLM.Providers.Gemini.Caching.update_cached_content(name, updates, opts)` [direct]

8. `delete_cached_context/3` - **Category 1** - Gemini only
   - Gemini: `ExLLM.Providers.Gemini.Caching.delete_cached_content(name, opts)` [direct]

9. `list_cached_contexts/2` - **Category 1** - Gemini only
   - Gemini: `ExLLM.Providers.Gemini.Caching.list_cached_contents(opts)` [direct]

### Knowledge Bases (9 functions)
10. `create_knowledge_base/3` - **Category 1** - Gemini only
    - Gemini: `ExLLM.Providers.Gemini.Corpus.create_corpus(name, opts)` [direct]

11. `list_knowledge_bases/2` - **Category 1** - Gemini only
    - Gemini: `ExLLM.Providers.Gemini.Corpus.list_corpora(opts)` [direct]

12. `get_knowledge_base/3` - **Category 1** - Gemini only
    - Gemini: `ExLLM.Providers.Gemini.Corpus.get_corpus(name, opts)` [direct]

13. `delete_knowledge_base/3` - **Category 1** - Gemini only
    - Gemini: `ExLLM.Providers.Gemini.Corpus.delete_corpus(name, opts)` [direct]

14. `add_document/4` - **Category 1** - Gemini only
    - Gemini: `ExLLM.Providers.Gemini.Document.create_document(knowledge_base, document, opts)` [direct]

15. `list_documents/3` - **Category 1** - Gemini only
    - Gemini: `ExLLM.Providers.Gemini.Document.list_documents(knowledge_base, opts)` [direct]

16. `get_document/4` - **Category 1** - Gemini only
    - Gemini: `ExLLM.Providers.Gemini.Document.get_document(knowledge_base, document_id, opts)` [direct]

17. `delete_document/4` - **Category 1** - Gemini only
    - Gemini: `ExLLM.Providers.Gemini.Document.delete_document(knowledge_base, document_id, opts)` [direct]

18. `semantic_search/4` - **Category 1** - Gemini only
    - Gemini: `ExLLM.Providers.Gemini.QA.query_corpus(knowledge_base, query, opts)` [direct]

### Fine-tuning (4 functions)
19. `create_fine_tune/3` - **Category 3** - Complex preprocessing
    - Gemini: `build_gemini_tuning_request(dataset, opts)` → `ExLLM.Providers.Gemini.Tuning.create_tuned_model(request, opts)` [complex]
    - OpenAI: `build_openai_tuning_params(training_file, opts)` → `ExLLM.Providers.OpenAI.create_fine_tuning_job(params, opts)` [complex]

20. `list_fine_tunes/2` - **Category 1** - Direct calls
    - Gemini: `ExLLM.Providers.Gemini.Tuning.list_tuned_models(opts)` [direct]
    - OpenAI: `ExLLM.Providers.OpenAI.list_fine_tuning_jobs(opts)` [direct]

21. `get_fine_tune/3` - **Category 1** - Direct calls
    - Gemini: `ExLLM.Providers.Gemini.Tuning.get_tuned_model(id, opts)` [direct]
    - OpenAI: `ExLLM.Providers.OpenAI.get_fine_tuning_job(id, opts)` [direct]

22. `cancel_fine_tune/3` - **Category 1** - Direct calls
    - Gemini: `ExLLM.Providers.Gemini.Tuning.cancel_tuned_model(id, opts)` [direct]
    - OpenAI: `ExLLM.Providers.OpenAI.cancel_fine_tuning_job(id, opts)` [direct]

### Assistants (8 functions)
23. `create_assistant/2` - **Category 1** - OpenAI only
    - OpenAI: `ExLLM.Providers.OpenAI.create_assistant(opts)` [direct]

24. `list_assistants/2` - **Category 1** - OpenAI only
    - OpenAI: `ExLLM.Providers.OpenAI.list_assistants(opts)` [direct]

25. `get_assistant/3` - **Category 1** - OpenAI only
    - OpenAI: `ExLLM.Providers.OpenAI.get_assistant(assistant_id, opts)` [direct]

26. `update_assistant/4` - **Category 1** - OpenAI only
    - OpenAI: `ExLLM.Providers.OpenAI.update_assistant(assistant_id, updates, opts)` [direct]

27. `delete_assistant/3` - **Category 1** - OpenAI only
    - OpenAI: `ExLLM.Providers.OpenAI.delete_assistant(assistant_id, opts)` [direct]

28. `create_thread/2` - **Category 1** - OpenAI only
    - OpenAI: `ExLLM.Providers.OpenAI.create_thread(opts)` [direct]

29. `create_message/4` - **Category 1** - OpenAI only
    - OpenAI: `ExLLM.Providers.OpenAI.create_message(thread_id, content, opts)` [direct]

30. `run_assistant/4` - **Category 1** - OpenAI only
    - OpenAI: `ExLLM.Providers.OpenAI.run_assistant(thread_id, assistant_id, opts)` [direct]

### Batch Processing (3 functions)
31. `create_batch/3` - **Category 1** - Anthropic only
    - Anthropic: `ExLLM.Providers.Anthropic.create_batch(messages_list, opts)` [direct]

32. `get_batch/3` - **Category 1** - Anthropic only
    - Anthropic: `ExLLM.Providers.Anthropic.get_batch(batch_id, opts)` [direct]

33. `cancel_batch/3` - **Category 1** - Anthropic only
    - Anthropic: `ExLLM.Providers.Anthropic.cancel_batch(batch_id, opts)` [direct]

### Core Operations (6 functions)
34. `chat/3` - **Category 1** - All providers (handled by existing pipeline)
35. `stream/4` - **Category 1** - All providers (handled by existing pipeline)
36. `embeddings/3` - **Category 1** - Multiple providers
37. `new_session/2` - **Category 1** - All providers

### Additional Functions
38. `count_tokens/3` - **Category 1** - Gemini only
39. `create_embedding_index/3` - **Category 1** - Gemini only

---

## Transformation Requirements

### Simple Argument Extraction (Category 2)
- **`upload_file` for OpenAI**: Extract `:purpose` from opts, pass as separate parameter

### Complex Preprocessing (Category 3)
- **`create_fine_tune`**: 
  - Gemini: `build_gemini_tuning_request(dataset, opts)` function needed
  - OpenAI: `build_openai_tuning_params(training_file, opts)` function needed

---

## Provider Capability Matrix

| Function | Gemini | OpenAI | Anthropic | Notes |
|----------|---------|---------|-----------|-------|
| upload_file | ✅ Direct | ✅ Transform | ❌ | OpenAI needs purpose extraction |
| list_files | ✅ Direct | ✅ Direct | ❌ | |
| create_cached_context | ✅ Direct | ❌ | ❌ | Gemini exclusive |
| create_fine_tune | ✅ Complex | ✅ Complex | ❌ | Different preprocessing needed |
| create_assistant | ❌ | ✅ Direct | ❌ | OpenAI exclusive |
| create_batch | ❌ | ❌ | ✅ Direct | Anthropic exclusive |

---

## Recommended Delegation Architecture

```elixir
defmodule ExLLM.API.Delegator do
  @capabilities %{
    # Category 1: Direct delegation
    list_files: %{
      gemini: {ExLLM.Providers.Gemini.Files, :list_files, :direct},
      openai: {ExLLM.Providers.OpenAI, :list_files, :direct}
    },
    
    # Category 2: Argument transformation
    upload_file: %{
      gemini: {ExLLM.Providers.Gemini.Files, :upload_file, :direct},
      openai: {ExLLM.Providers.OpenAI, :upload_file, :transform_upload_args}
    },
    
    # Category 3: Complex preprocessing
    create_fine_tune: %{
      gemini: {ExLLM.Providers.Gemini.Tuning, :create_tuned_model, :preprocess_gemini_tuning},
      openai: {ExLLM.Providers.OpenAI, :create_fine_tuning_job, :preprocess_openai_tuning}
    }
  }

  def delegate(operation, provider, args) do
    case @capabilities[operation][provider] do
      {module, function, :direct} -> apply(module, function, args)
      {module, function, transformer} -> 
        transformed_args = apply(ExLLM.API.Transformers, transformer, [args])
        apply(module, function, transformed_args)
      nil -> {:error, "#{operation} not supported for provider: #{provider}"}
    end
  end
end
```

---

## Summary

- **37 total functions** analyzed
- **28 functions (76%)** are Category 1 (direct delegation) - simple to migrate
- **2 functions (5%)** are Category 2 (argument transformation) - medium complexity
- **1 function (3%)** is Category 3 (complex preprocessing) - highest complexity
- **6 functions (16%)** are core operations already handled by existing pipeline

**Migration Priority**: Start with Category 1 (direct delegation) for maximum impact with minimal risk.