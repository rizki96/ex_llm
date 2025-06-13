# OAuth2 API Test Setup Guide

This guide explains how to set up test data and accounts for comprehensive OAuth2 API testing.

## Overview

The OAuth2-protected APIs in Gemini include:
1. **Corpus Management API** - Document collections for semantic retrieval
2. **Document Management API** - Documents within corpora
3. **Chunk Management API** - Text chunks within documents
4. **Question Answering API** - Semantic Q&A using corpora
5. **Permissions API** - Access control for tuned models

## Test Data Requirements

### 1. Basic OAuth2 Setup (Required)

```bash
# Set up OAuth2 credentials
elixir scripts/setup_oauth2.exs

# This creates .gemini_tokens with access to:
# - https://www.googleapis.com/auth/cloud-platform
# - https://www.googleapis.com/auth/generative-language.tuning
# - https://www.googleapis.com/auth/generative-language.retriever
```

### 2. Corpus/Document/Chunk APIs (Automatic)

The test suite automatically creates and cleans up:
- Test corpora with unique names
- Documents with metadata
- Chunks with searchable content

No manual setup required - tests are self-contained.

### 3. Question Answering API (Automatic)

Tests automatically create:
- A corpus with Elixir documentation
- Multiple chunks about Elixir features
- Queries are run against this test data

### 4. Permissions API (Manual Setup Required)

To fully test the Permissions API, you need a tuned model:

#### Option A: Use Gemini AI Studio (Easiest)
1. Go to [Google AI Studio](https://aistudio.google.com/)
2. Click "Tune a model" in the left sidebar
3. Select a base model (e.g., Gemini 1.5 Flash)
4. Upload training data (even a small dataset works)
5. Start tuning (takes 1-2 hours)
6. Note the model name (e.g., `tunedModels/my-test-model-123`)

#### Option B: Use the API (Advanced)
```elixir
# Create a tuning job via API
{:ok, operation} = ExLLM.Gemini.Tuning.create_tuning_job(
  "models/gemini-1.5-flash-001-tuning",
  %{
    display_name: "Test Model for Permissions",
    training_examples: [
      %{
        text_input: "What is ExLLM?",
        output: "ExLLM is a unified Elixir client for Large Language Models."
      },
      # Add more examples...
    ]
  },
  oauth_token: token
)
```

#### Setting the Test Model
```bash
# Set environment variable with your tuned model
export TEST_TUNED_MODEL="tunedModels/your-actual-model-name"

# Run permission tests
mix test test/ex_llm/adapters/gemini/oauth2_apis_test.exs --only requires_tuned_model
```

## Running OAuth2 Tests

### Run All OAuth2 Tests
```bash
# Ensure you have valid tokens
mix test --only oauth2
```

### Run Specific OAuth2 API Tests
```bash
# Corpus Management
mix test test/ex_llm/adapters/gemini/oauth2_apis_test.exs:"Corpus Management API"

# Document Management
mix test test/ex_llm/adapters/gemini/oauth2_apis_test.exs:"Document Management API"

# Chunk Management
mix test test/ex_llm/adapters/gemini/oauth2_apis_test.exs:"Chunk Management API"

# Question Answering
mix test test/ex_llm/adapters/gemini/oauth2_apis_test.exs:"Question Answering API"

# Permissions (requires tuned model)
mix test test/ex_llm/adapters/gemini/oauth2_apis_test.exs:"Permissions API"
```

### Token Management

```bash
# Refresh expired token
elixir scripts/refresh_oauth2_token.exs

# Check token validity
iex -S mix
iex> {:ok, tokens} = File.read!(".gemini_tokens") |> Jason.decode!()
iex> tokens["expires_at"]  # Check expiration time
```

## Test Data Cleanup

The test suite automatically cleans up all created resources:
- Corpora are deleted after each test
- Documents and chunks are deleted with their parent corpus
- Uses `on_exit` callbacks to ensure cleanup even on test failure

## Quotas and Limits

Be aware of API quotas:
- **Corpora**: Up to 5 per project
- **Documents**: Up to 10,000 per corpus
- **Chunks**: Up to 1,000,000 per corpus
- **Request rate**: Check your project's quota in Google Cloud Console

## Troubleshooting

### "Request had insufficient authentication scopes"
- Re-run `elixir scripts/setup_oauth2.exs` with updated scopes
- Ensure all required scopes are included

### "Quota exceeded"
- Delete old test corpora manually:
```elixir
{:ok, list} = Corpus.list_corpora([], oauth_token: token)
Enum.each(list.corpora, fn corpus ->
  if String.contains?(corpus.display_name, "test") do
    Corpus.delete_corpus(corpus.name, oauth_token: token, force: true)
  end
end)
```

### "Invalid corpus/document name"
- Names must follow the pattern: `corpora/[a-z0-9-]+`
- No uppercase letters or special characters except hyphens

## Best Practices

1. **Use unique names**: Include timestamps or random IDs in test data names
2. **Clean up resources**: Always use `on_exit` callbacks
3. **Test incrementally**: Build corpus → add documents → add chunks → query
4. **Mock when possible**: For unit tests, mock OAuth2 responses
5. **Monitor quotas**: Check Google Cloud Console for usage

## Example Test Data Structure

```
corpus: "test-corpus-12345"
├── document: "elixir-guide"
│   ├── chunk: "Elixir is a dynamic, functional language..."
│   ├── chunk: "Pattern matching is powerful..."
│   └── chunk: "GenServer implements client-server..."
└── document: "phoenix-guide"
    ├── chunk: "Phoenix is a web framework..."
    └── chunk: "LiveView enables real-time features..."
```

This structure allows testing:
- Corpus queries across all documents
- Document-specific queries
- Metadata filtering
- Semantic retrieval
- Question answering