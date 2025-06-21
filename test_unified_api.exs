#!/usr/bin/env elixir

# Simple test runner for unified API tests
# This script tests the error handling patterns without requiring live API calls

defmodule UnifiedAPITestRunner do
  def run do
    IO.puts("Testing ExLLM Unified API Error Handling...")
    
    # Test basic error patterns
    test_error_patterns()
    
    # Test function existence
    test_function_existence()
    
    IO.puts("\n✅ All unified API tests passed!")
  end
  
  defp test_error_patterns do
    IO.puts("\n🔍 Testing error patterns...")
    
    # Test file management errors
    assert_error_pattern(
      ExLLM.upload_file(:anthropic, "test.txt"),
      "File upload not supported for provider: anthropic"
    )
    
    # Test context caching errors
    assert_error_pattern(
      ExLLM.create_cached_context(:openai, %{}),
      "Context caching not supported for provider: openai"
    )
    
    # Test knowledge base errors
    assert_error_pattern(
      ExLLM.create_knowledge_base(:anthropic, "kb"),
      "Knowledge base creation not supported for provider: anthropic"
    )
    
    # Test fine-tuning errors
    assert_error_pattern(
      ExLLM.create_fine_tune(:anthropic, %{}),
      "Fine-tuning not supported for provider: anthropic"
    )
    
    # Test assistants errors
    assert_error_pattern(
      ExLLM.create_assistant(:gemini, %{}),
      "Assistants API not supported for provider: gemini"
    )
    
    # Test batch processing errors
    assert_error_pattern(
      ExLLM.create_batch(:openai, []),
      "Message batches not supported for provider: openai"
    )
    
    # Test token counting errors
    assert_error_pattern(
      ExLLM.count_tokens(:openai, "model", "text"),
      "Token counting not supported for provider: openai"
    )
    
    IO.puts("   ✅ Error patterns are consistent")
  end
  
  defp test_function_existence do
    IO.puts("\n🔍 Testing function existence...")
    
    unified_functions = [
      {:upload_file, 3}, {:list_files, 2}, {:get_file, 3}, {:delete_file, 3},
      {:create_cached_context, 3}, {:get_cached_context, 3}, 
      {:update_cached_context, 4}, {:delete_cached_context, 3}, {:list_cached_contexts, 2},
      {:create_knowledge_base, 3}, {:list_knowledge_bases, 2}, {:get_knowledge_base, 3},
      {:delete_knowledge_base, 3}, {:add_document, 4}, {:list_documents, 3},
      {:get_document, 4}, {:delete_document, 4}, {:semantic_search, 4},
      {:create_fine_tune, 3}, {:list_fine_tunes, 2}, {:get_fine_tune, 3}, {:cancel_fine_tune, 3},
      {:create_assistant, 2}, {:list_assistants, 2}, {:get_assistant, 3},
      {:update_assistant, 4}, {:delete_assistant, 3},
      {:create_thread, 2}, {:create_message, 4}, {:run_assistant, 4},
      {:create_batch, 3}, {:get_batch, 3}, {:cancel_batch, 3},
      {:count_tokens, 3}
    ]
    
    for {function, arity} <- unified_functions do
      unless function_exported?(ExLLM, function, arity) do
        raise "Function #{function}/#{arity} not exported from ExLLM module"
      end
    end
    
    IO.puts("   ✅ All #{length(unified_functions)} unified API functions are exported")
  end
  
  defp assert_error_pattern(result, expected_error) do
    case result do
      {:error, ^expected_error} -> 
        :ok
      {:error, other_error} -> 
        raise "Expected error '#{expected_error}', got '#{other_error}'"
      {:ok, _} -> 
        raise "Expected error '#{expected_error}', got success"
      other -> 
        raise "Expected error tuple, got #{inspect(other)}"
    end
  end
end

# Add the lib directory to the code path
Code.prepend_path("lib")

# Compile and load ExLLM
Code.compile_file("lib/ex_llm.ex")

# Run the tests
UnifiedAPITestRunner.run()
