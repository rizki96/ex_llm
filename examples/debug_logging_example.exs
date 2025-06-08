#!/usr/bin/env elixir

# Example demonstrating ExLLM's debug logging capabilities
# Run with: elixir examples/debug_logging_example.exs

Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"}
])

defmodule DebugLoggingExample do
  @moduledoc """
  Example demonstrating ExLLM's configurable debug logging system.
  
  This shows how to:
  - Configure different log levels
  - Enable/disable specific components
  - Use structured logging with context
  - Redact sensitive information
  """

  def run do
    IO.puts("=== ExLLM Debug Logging Example ===\n")
    
    # Show current logging configuration
    show_config()
    
    # Test basic logging functions
    test_basic_logging()
    
    # Test context logging
    test_context_logging()
    
    # Test component-specific logging
    test_component_logging()
    
    # Test different log levels
    test_log_levels()
    
    IO.puts("\n=== Example Complete ===")
  end

  defp show_config do
    IO.puts("Current ExLLM logging configuration:")
    
    log_level = Application.get_env(:ex_llm, :log_level, :info)
    components = Application.get_env(:ex_llm, :log_components, %{})
    redaction = Application.get_env(:ex_llm, :log_redaction, %{})
    
    IO.puts("  Log Level: #{inspect(log_level)}")
    IO.puts("  Components: #{inspect(components)}")
    IO.puts("  Redaction: #{inspect(redaction)}")
    IO.puts("")
  end

  defp test_basic_logging do
    IO.puts("Testing basic logging functions:")
    
    ExLLM.Logger.debug("This is a debug message", component: :example)
    ExLLM.Logger.info("This is an info message", component: :example)
    ExLLM.Logger.warn("This is a warning message", component: :example)
    ExLLM.Logger.error("This is an error message", component: :example)
    
    IO.puts("")
  end

  defp test_context_logging do
    IO.puts("Testing context logging:")
    
    ExLLM.Logger.with_context([provider: :openai, operation: :chat, request_id: "req_123"], fn ->
      ExLLM.Logger.info("Starting chat request")
      ExLLM.Logger.debug("Processing message", message_count: 2)
      ExLLM.Logger.info("Chat completed", tokens: 150, cost: 0.003)
    end)
    
    IO.puts("")
  end

  defp test_component_logging do
    IO.puts("Testing component-specific logging:")
    
    # Test request/response logging
    ExLLM.Logger.log_request(:openai, "https://api.openai.com/v1/chat/completions", 
      %{messages: [%{role: "user", content: "Hello"}]}, 
      [{"Authorization", "Bearer sk-..."}])
    
    # Test retry logging
    ExLLM.Logger.log_retry(:anthropic, 2, 3, :rate_limit, 2000)
    
    # Test cache logging
    ExLLM.Logger.log_cache_event(:hit, "cache_key_abc123", %{ttl: 3600})
    
    # Test model logging
    ExLLM.Logger.log_model_event(:ollama, :loaded, %{model: "llama2", size: "7B"})
    
    # Test streaming logging
    ExLLM.Logger.log_stream_event(:anthropic, :chunk_received, %{size: 128, type: "content"})
    
    IO.puts("")
  end

  defp test_log_levels do
    IO.puts("Testing different log levels (current level: #{Application.get_env(:ex_llm, :log_level, :info)}):")
    
    # These will show/hide based on current log level configuration
    ExLLM.Logger.debug("Debug level message - only shows if log_level is :debug")
    ExLLM.Logger.info("Info level message - shows if log_level is :info or :debug")
    ExLLM.Logger.warn("Warning level message - shows unless log_level is :error")
    ExLLM.Logger.error("Error level message - always shows unless log_level is :none")
    
    IO.puts("")
  end
end

# Configure ExLLM for this example
Application.put_env(:ex_llm, :log_level, :debug)
Application.put_env(:ex_llm, :log_components, %{
  requests: true,
  responses: true,
  streaming: true,
  retries: true,
  cache: true,
  models: true
})
Application.put_env(:ex_llm, :log_redaction, %{
  api_keys: true,
  content: false
})

# Configure logger to show our metadata
Logger.configure(level: :debug)
Logger.configure_backend(:console, metadata: [:ex_llm, :provider, :operation, :component, :request_id])

DebugLoggingExample.run()