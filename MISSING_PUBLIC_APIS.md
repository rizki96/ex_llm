# Missing Public APIs in ExLLM

**✅ STATUS: ALL APIS IMPLEMENTED**

This document lists provider-specific APIs that need to be exposed through the main ExLLM module. As of today, all APIs listed below have been successfully implemented.

## Gemini-Specific APIs ✅

### 1. Context Caching ✅
```elixir
# Current (internal)
Gemini.Caching.create_cached_content(content, opts)
Gemini.Caching.get_cached_content(name)
Gemini.Caching.update_cached_content(name, updates)
Gemini.Caching.delete_cached_content(name)
Gemini.Caching.list_cached_contents(opts)

# Should be (public)
ExLLM.create_cached_context(:gemini, content, opts)
ExLLM.get_cached_context(:gemini, name)
ExLLM.update_cached_context(:gemini, name, updates)
ExLLM.delete_cached_context(:gemini, name)
ExLLM.list_cached_contexts(:gemini, opts)
```

### 2. Semantic Retrieval (Corpus/Chunk/Document) ✅
```elixir
# Current (internal)
Gemini.Corpus.create(name, opts)
Gemini.Corpus.list(opts)
Gemini.Corpus.get(name)
Gemini.Corpus.update(name, updates)
Gemini.Corpus.delete(name)

Gemini.Document.create(corpus_name, document, opts)
Gemini.Document.list(corpus_name, opts)
Gemini.Document.get(corpus_name, document_name)
Gemini.Document.update(corpus_name, document_name, updates)
Gemini.Document.delete(corpus_name, document_name)

Gemini.Chunk.create(corpus_name, document_name, chunk, opts)
Gemini.Chunk.list(corpus_name, document_name, opts)
Gemini.Chunk.get(corpus_name, document_name, chunk_name)
Gemini.Chunk.update(corpus_name, document_name, chunk_name, updates)
Gemini.Chunk.delete(corpus_name, document_name, chunk_name)

# Should be (public)
ExLLM.create_knowledge_base(:gemini, name, opts)
ExLLM.list_knowledge_bases(:gemini, opts)
ExLLM.get_knowledge_base(:gemini, name)
ExLLM.update_knowledge_base(:gemini, name, updates)
ExLLM.delete_knowledge_base(:gemini, name)

ExLLM.add_document(:gemini, knowledge_base, document, opts)
ExLLM.list_documents(:gemini, knowledge_base, opts)
ExLLM.get_document(:gemini, knowledge_base, document_id)
ExLLM.update_document(:gemini, knowledge_base, document_id, updates)
ExLLM.delete_document(:gemini, knowledge_base, document_id)

ExLLM.semantic_search(:gemini, knowledge_base, query, opts)
```

### 3. File Management ✅
```elixir
# Current (internal)
Gemini.Files.upload(file_path, opts)
Gemini.Files.list(opts)
Gemini.Files.get(file_name)
Gemini.Files.delete(file_name)

# Should be (public)
ExLLM.upload_file(:gemini, file_path, opts)
ExLLM.list_files(:gemini, opts)
ExLLM.get_file(:gemini, file_id)
ExLLM.delete_file(:gemini, file_id)
```

### 4. Fine-tuning ✅
```elixir
# Current (internal)
Gemini.Tuning.create_tuned_model(dataset, opts)
Gemini.Tuning.list_tuned_models(opts)
Gemini.Tuning.get_tuned_model(name)
Gemini.Tuning.delete_tuned_model(name)

# Should be (public)
ExLLM.create_fine_tune(:gemini, dataset, opts)
ExLLM.list_fine_tunes(:gemini, opts)
ExLLM.get_fine_tune(:gemini, model_id)
ExLLM.delete_fine_tune(:gemini, model_id)
```

### 5. Token Counting ✅
```elixir
# Current (internal)
Gemini.Tokens.count_tokens(model, content)

# Should be (public)
ExLLM.count_tokens(:gemini, model, content)
```

## OpenAI-Specific APIs ✅

### 1. Files and Uploads ✅
```elixir
# Current (internal)
OpenAI.Files.upload(file_path, purpose)
OpenAI.Files.list(opts)
OpenAI.Files.retrieve(file_id)
OpenAI.Files.delete(file_id)

# Should be (public)
ExLLM.upload_file(:openai, file_path, purpose: purpose)
ExLLM.list_files(:openai, opts)
ExLLM.get_file(:openai, file_id)
ExLLM.delete_file(:openai, file_id)
```

### 2. Fine-tuning ✅
```elixir
# Current (internal)
OpenAI.FineTunes.create(training_file, opts)
OpenAI.FineTunes.list(opts)
OpenAI.FineTunes.retrieve(fine_tune_id)
OpenAI.FineTunes.cancel(fine_tune_id)

# Should be (public)
ExLLM.create_fine_tune(:openai, training_file, opts)
ExLLM.list_fine_tunes(:openai, opts)
ExLLM.get_fine_tune(:openai, fine_tune_id)
ExLLM.cancel_fine_tune(:openai, fine_tune_id)
```

### 3. Assistants API ✅
```elixir
# Should be (public)
ExLLM.create_assistant(:openai, opts)
ExLLM.list_assistants(:openai, opts)
ExLLM.get_assistant(:openai, assistant_id)
ExLLM.update_assistant(:openai, assistant_id, updates)
ExLLM.delete_assistant(:openai, assistant_id)

ExLLM.create_thread(:openai, opts)
ExLLM.create_message(:openai, thread_id, content, opts)
ExLLM.run_assistant(:openai, thread_id, assistant_id, opts)
```

## Anthropic-Specific APIs ✅

### 1. Message Batches ✅
```elixir
# Should be (public)
ExLLM.create_batch(:anthropic, messages_list, opts)
ExLLM.get_batch(:anthropic, batch_id)
ExLLM.cancel_batch(:anthropic, batch_id)
```

## General Pattern

All provider-specific functionality should be exposed through ExLLM with:
1. Provider as first argument
2. Consistent naming across providers
3. Provider-agnostic return types where possible
4. Clear documentation of provider-specific features

## Implementation Priority

1. **High Priority**: APIs used in existing tests ✅
   - Gemini semantic retrieval (Corpus/Document/Chunk) ✅
   - File management (OpenAI, Gemini) ✅
   - Token counting ✅

2. **Medium Priority**: Commonly needed features ✅
   - Fine-tuning APIs ✅
   - Context caching ✅
   - Batch processing ✅

3. **Low Priority**: Advanced features ✅
   - Assistants API ✅
   - Message Batches API ✅
   
## Implementation Summary

All provider-specific APIs have been successfully implemented:

- **Gemini**: 30+ functions across 5 categories (token counting, file management, knowledge bases, context caching, fine-tuning)
- **OpenAI**: 12+ functions across 3 categories (file management, fine-tuning, assistants)
- **Anthropic**: 3 functions for message batches

Total: 45+ new public API functions added to the ExLLM module, providing a unified interface for all provider-specific features.

## Benefits

1. **Single API Surface**: Users only need to learn one API
2. **Provider Switching**: Easy to switch providers for similar features
3. **Discoverability**: All features available through ExLLM module
4. **Type Safety**: Consistent types across providers
5. **Documentation**: Single place for all API documentation