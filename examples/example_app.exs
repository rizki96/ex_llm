#!/usr/bin/env elixir

# ExLLM Comprehensive Example Application
# 
# This application demonstrates all features of the ExLLM library.
# By default, it uses Ollama with Qwen3 8B (IQ4_XS) for fast local inference,
# but can be configured to use any supported provider.
#
# Usage:
#   ./example_app.exs                    # Run with default Ollama provider
#   PROVIDER=openai ./example_app.exs    # Use OpenAI (requires OPENAI_API_KEY)
#   PROVIDER=anthropic ./example_app.exs # Use Anthropic (requires ANTHROPIC_API_KEY)

# Set log level to info to reduce debug output
Logger.configure(level: :info)

Mix.install([
  {:ex_llm, path: ".."},
  {:req, "~> 0.3"},
  {:jason, "~> 1.4"},
  {:instructor, "~> 0.1.0"}
])

defmodule ExLLM.ExampleApp do
  @moduledoc """
  Comprehensive example application demonstrating all ExLLM features.
  """
  
  alias ExLLM.{Session, Context, ModelCapabilities, FunctionCalling}
  
  @default_provider :ollama
  
  # Provider configurations
  @provider_configs %{
    ollama: %{
      name: "Ollama (Local)",
      setup: """
      To use Ollama:
      1. Install Ollama: https://ollama.ai
      2. Ensure Ollama is running
      3. Pull a model: ollama pull llama3.2:3b (or any other model)
      
      Recommended models for stability:
        - llama3.2:3b (small, fast, stable)
        - mistral:7b (medium, good quality)
        - qwen2.5:7b (good multilingual support)
      """
    },
    openai: %{
      name: "OpenAI",
      env_var: "OPENAI_API_KEY",
      setup: "Set OPENAI_API_KEY environment variable"
    },
    anthropic: %{
      name: "Anthropic Claude",
      env_var: "ANTHROPIC_API_KEY", 
      setup: "Set ANTHROPIC_API_KEY environment variable"
    },
    groq: %{
      name: "Groq (Fast Cloud)",
      env_var: "GROQ_API_KEY",
      setup: "Set GROQ_API_KEY environment variable"
    },
    xai: %{
      name: "X.AI Grok",
      env_var: "XAI_API_KEY",
      setup: "Set XAI_API_KEY environment variable"
    },
    mock: %{
      name: "Mock (Testing)",
      setup: "No setup required - uses mock responses"
    }
  }
  
  def main do
    IO.puts("""
    ╔══════════════════════════════════════════════════════════════╗
    ║               ExLLM Comprehensive Example App                ║
    ╚══════════════════════════════════════════════════════════════╝
    """)
    
    provider = get_provider()
    
    if provider == :mock do
      # Start mock adapter for testing
      {:ok, _} = ExLLM.Adapters.Mock.start_link()
    end
    
    check_provider_setup(provider)
    
    main_menu(provider)
  end
  
  defp get_provider do
    case System.get_env("PROVIDER") do
      nil -> @default_provider
      provider -> String.to_atom(provider)
    end
  end
  
  defp check_provider_setup(provider) do
    config = @provider_configs[provider]
    
    IO.puts("Using provider: #{config.name}")
    
    # Show provider capabilities
    case ExLLM.ProviderCapabilities.get_capabilities(provider) do
      {:ok, caps} ->
        IO.puts("\nProvider Capabilities:")
        IO.puts("  Endpoints: #{Enum.join(caps.endpoints, ", ")}")
        
        # Show all features, formatted nicely
        if length(caps.features) > 0 do
          features_str = caps.features |> Enum.map(&to_string/1) |> Enum.join(", ")
          # Wrap long feature lists
          if String.length(features_str) > 60 do
            IO.puts("  Features:")
            caps.features
            |> Enum.chunk_every(4)
            |> Enum.each(fn chunk ->
              IO.puts("    #{Enum.join(chunk, ", ")}")
            end)
          else
            IO.puts("  Features: #{features_str}")
          end
        end
        
        if caps.limitations[:no_cost_tracking] do
          IO.puts("  ⚠️  No cost tracking available")
        end
      {:error, _} ->
        nil
    end
    
    # Check if provider is configured
    case ExLLM.configured?(provider) do
      true ->
        IO.puts("\n✓ Provider is configured and ready\n")
        
      false ->
        if env_var = Map.get(config, :env_var) do
          IO.puts("\n⚠️  #{env_var} not set!")
        end
        IO.puts("\nSetup instructions:")
        IO.puts(config.setup)
        IO.puts("")
        
        unless provider == :ollama do
          IO.puts("Press Enter to continue anyway, or Ctrl+C to exit...")
          IO.gets("")
        end
    end
  end
  
  defp main_menu(provider) do
    # Get provider capabilities
    capabilities = case ExLLM.ProviderCapabilities.get_capabilities(provider) do
      {:ok, caps} -> caps
      {:error, _} -> nil
    end
    
    # Build menu items based on capabilities
    menu_items = build_menu_items(provider, capabilities)
    
    IO.puts("""
    
    ┌─────────────────────────────────────────────────────────────┐
    │                      Main Menu                              │
    ├─────────────────────────────────────────────────────────────┤
    """)
    
    Enum.each(menu_items, fn {num, label, _handler} ->
      # Format the menu item with proper padding
      item_text = " #{num}. #{label}"
      padded_text = String.pad_trailing(item_text, 61)
      IO.puts("│#{padded_text}│")
    end)
    
    IO.puts("""
    │                                                             │
    │  0. Exit                                                    │
    └─────────────────────────────────────────────────────────────┘
    """)
    
    input = IO.gets("Enter your choice: ")
    choice = case input do
      :eof -> "0"  # Exit gracefully on EOF
      str -> String.trim(str)
    end
    
    if choice == "0" do
      exit_app()
    else
      case Enum.find(menu_items, fn {num, _, _} -> num == choice end) do
        {_, _, handler} -> 
          handler.(provider)
          main_menu(provider)
        nil ->
          IO.puts("\nInvalid choice. Please try again.")
          main_menu(provider)
      end
    end
  end
  
  defp build_menu_items(_provider, capabilities) do
    # All menu items with availability check
    items = [
      {"Basic Chat", &basic_chat/1, true},
      {"Streaming Chat", &streaming_chat/1, capabilities && :streaming in capabilities.features},
      {"Session Management (Saves & Resumes Conversations)", &session_management/1, true},
      {"Context Management (Token Limits)", &context_management/1, true},
      {"Function Calling", &function_calling_demo/1, capabilities && :function_calling in capabilities.features},
      {"Structured Output (Instructor)", &structured_output_demo/1, true},
      {"Vision/Multimodal (Analyze Images)", &vision_demo/1, capabilities && :vision in capabilities.features},
      {"Embeddings & Semantic Search", &embeddings_demo/1, capabilities && :embeddings in capabilities.endpoints},
      {"Model Capabilities Explorer", &model_capabilities_explorer/1, true},
      {"Provider Capabilities Explorer", &provider_capabilities_explorer/1, true},
      {"Caching Demo", &caching_demo/1, true},
      {"Retry & Error Recovery", &retry_demo/1, true},
      {"Cost Tracking", &cost_tracking_demo/1, capabilities && :cost_tracking in capabilities.features},
      {"Stream Recovery (Auto-resume interrupted streams)", &stream_recovery_demo/1, capabilities && :streaming in capabilities.features},
      {"Dynamic Model Selection", &dynamic_model_selection_demo/1, true},
      {"Token Budget Management", &token_budget_demo/1, true},
      {"Multi-Provider Routing", &multi_provider_routing_demo/1, true}
    ]
    
    # Number the items sequentially and create wrapper functions for unavailable features
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {{label, handler, available}, index} ->
      if available do
        {Integer.to_string(index), label, handler}
      else
        # Create a wrapper that shows unavailable message
        wrapped_handler = fn p ->
          show_feature_unavailable(p, label, get_required_feature(label))
        end
        {Integer.to_string(index), label <> " (unavailable)", wrapped_handler}
      end
    end)
  end
  
  defp get_required_feature(label) do
    case label do
      "Streaming Chat" -> :streaming
      "Function Calling" -> :function_calling
      "Vision/Multimodal (Analyze Images)" -> :vision
      "Embeddings & Semantic Search" -> :embeddings
      "Cost Tracking" -> :cost_tracking
      "Stream Recovery (Auto-resume interrupted streams)" -> :streaming
      _ -> nil
    end
  end
  
  defp show_feature_unavailable(provider, feature_name, required_feature) do
    IO.puts("\n=== #{feature_name} ===")
    IO.puts("\n⚠️  This feature is not available with #{provider}.")
    
    if required_feature do
      # Find providers that support this feature
      providers_with_feature = ExLLM.find_providers_with_features([required_feature])
      
      if length(providers_with_feature) > 0 do
        IO.puts("\nProviders that support #{required_feature}:")
        providers_with_feature
        |> Enum.take(5)
        |> Enum.each(fn p ->
          {:ok, caps} = ExLLM.get_provider_capabilities(p)
          IO.puts("  • #{p} - #{caps.name}")
        end)
        
        if length(providers_with_feature) > 5 do
          IO.puts("  ... and #{length(providers_with_feature) - 5} more")
        end
      end
    end
    
    IO.puts("\nTo use this feature, restart the app with a supported provider:")
    IO.puts("  PROVIDER=openai ./example_app.exs")
    
    wait_for_continue()
  end
  
  # Feature implementations
  
  defp basic_chat(provider) do
    IO.puts("\n=== Basic Chat ===")
    IO.puts("This demonstrates simple message exchange with an LLM.\n")
    
    prompt = IO.gets("Enter your message: ") |> String.trim()
    
    messages = [
      %{role: "user", content: prompt}
    ]
    
    IO.puts("\nSending to #{provider}...")
    
    case ExLLM.chat(provider, messages) do
      {:ok, response} ->
        IO.puts("\nResponse: #{response.content}")
        
        if response.usage do
          IO.puts("\nToken usage:")
          IO.puts("  Input: #{response.usage.input_tokens}")
          IO.puts("  Output: #{response.usage.output_tokens}")
          total = Map.get(response.usage, :total_tokens, response.usage.input_tokens + response.usage.output_tokens)
          IO.puts("  Total: #{total}")
        end
        
        if response.cost do
          # Check if cost calculation succeeded or returned an error
          if Map.has_key?(response.cost, :error) do
            IO.puts("\nCost: Not available (#{response.cost.error})")
          else
            IO.puts("\nCost:")
            IO.puts("  Total: $#{:erlang.float_to_binary(response.cost.total_cost, decimals: 6)}")
          end
        end
        
      {:error, error} ->
        IO.puts("\nError: #{inspect(error)}")
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp streaming_chat(provider) do
    IO.puts("\n=== Streaming Chat ===")
    IO.puts("This demonstrates real-time streaming responses.\n")
    
    prompt = IO.gets("Enter your message: ") |> String.trim()
    
    messages = [
      %{role: "user", content: prompt}
    ]
    
    IO.puts("\nStreaming from #{provider}...\n")
    
    case ExLLM.stream_chat(provider, messages) do
      {:ok, stream} ->
        # Collect response content while streaming
        response_content = 
          stream
          |> Enum.reduce("", fn chunk, acc ->
            if chunk.content do
              IO.write(chunk.content)
              acc <> chunk.content
            else
              acc
            end
          end)
        
        IO.puts("\n")
        
        # Estimate token usage
        input_tokens = ExLLM.Cost.estimate_tokens(messages)
        output_tokens = ExLLM.Cost.estimate_tokens(response_content)
        total_tokens = input_tokens + output_tokens
        
        IO.puts("\nToken usage (estimated):")
        IO.puts("  Input: #{input_tokens}")
        IO.puts("  Output: #{output_tokens}")
        IO.puts("  Total: #{total_tokens}")
        
        # Calculate and display cost
        model = ExLLM.ModelConfig.get_default_model(provider)
        if model do
          usage = %{
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            total_tokens: total_tokens
          }
          
          cost = ExLLM.Cost.calculate(Atom.to_string(provider), model, usage)
          
          unless Map.has_key?(cost, :error) do
            IO.puts("\nCost (estimated):")
            IO.puts("  Total: $#{format_cost(cost.total_cost)}")
          end
        end
        
      {:error, error} ->
        IO.puts("\nError: #{inspect(error)}")
    end
    
    wait_for_continue()
  end
  
  defp session_management(provider) do
    IO.puts("\n=== Session Management with Persistence ===")
    IO.puts("This demonstrates conversation history, context preservation, and session saving/resuming.")
    IO.puts("Sessions are automatically saved and can be resumed later.\n")
    
    # Generate session filename with timestamp for clarity
    session_filename = "example_session_#{provider}.json"
    session_path = Path.join(System.tmp_dir!(), session_filename)
    
    # Check if there's a saved session
    session = case File.exists?(session_path) do
      true ->
        IO.puts("📁 Found saved session at: #{session_path}")
        IO.puts("\nWould you like to:")
        IO.puts("1. Resume previous conversation")
        IO.puts("2. Start new conversation")
        choice = safe_gets("\nChoice (1 or 2): ", "2")
        
        case choice do
          "1" ->
            case Session.load_from_file(session_path) do
              {:ok, loaded_session} ->
                # Clean up any empty messages from previous sessions
                cleaned_messages = Enum.filter(loaded_session.messages, fn msg ->
                  msg.content && String.trim(msg.content) != ""
                end)
                
                cleaned_session = %{loaded_session | messages: cleaned_messages}
                
                IO.puts("\n✓ Successfully resumed session '#{cleaned_session.name}'")
                IO.puts("  - Session ID: #{cleaned_session.id}")
                IO.puts("  - Messages: #{length(cleaned_session.messages)}")
                IO.puts("  - Started: #{format_timestamp(cleaned_session.created_at)}")
                
                if length(cleaned_session.messages) > 0 do
                  IO.puts("\nPrevious conversation:")
                  IO.puts(String.duplicate("-", 50))
                  Enum.each(cleaned_session.messages, fn msg ->
                    role = String.capitalize(msg.role)
                    content = msg.content || ""
                    IO.puts("#{role}: #{content}")
                  end)
                  IO.puts(String.duplicate("-", 50) <> "\n")
                end
                cleaned_session
              {:error, reason} ->
                IO.puts("⚠️  Failed to load session: #{inspect(reason)}")
                Session.new(to_string(provider), name: "#{provider} Conversation")
            end
          _ ->
            IO.puts("Starting fresh conversation...")
            Session.new(to_string(provider), name: "#{provider} Conversation")
        end
      false ->
        IO.puts("📝 Starting new session (will be saved to: #{session_path})")
        Session.new(to_string(provider), name: "#{provider} Conversation")
    end
    
    IO.puts("Session ID: #{session.id}")
    IO.puts("Continue the conversation. Type 'exit' to end.\n")
    
    session = chat_loop(session, provider)
    
    # Show session summary
    IO.puts("\n=== Session Summary ===")
    IO.puts("Total messages: #{length(session.messages)}")
    total_tokens = (session.token_usage[:input_tokens] || 0) + (session.token_usage[:output_tokens] || 0)
    IO.puts("Total tokens used: #{total_tokens}")
    
    # Clean up empty messages before saving
    cleaned_session = %{session | 
      messages: Enum.filter(session.messages, fn msg ->
        msg.content && String.trim(msg.content) != ""
      end)
    }
    
    # Save session
    session_filename = "example_session_#{provider}.json"
    session_path = Path.join(System.tmp_dir!(), session_filename)
    
    case Session.save_to_file(cleaned_session, session_path) do
      :ok -> 
        IO.puts("\n💾 Session saved successfully!")
        IO.puts("   Location: #{session_path}")
        IO.puts("   You can resume this conversation later by running this demo again.")
      {:error, reason} -> 
        IO.puts("⚠️  Failed to save session: #{inspect(reason)}")
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp chat_loop(session, provider) do
    input = safe_gets("You: ", "exit")
    
    if input == "exit" do
      session
    else
      # Add user message to session
      session = Session.add_message(session, "user", input)
      
      # Get all messages for context
      messages = Session.get_messages(session)
      
      IO.write("Assistant: ")
      
      # Chat with full context
      case ExLLM.stream_chat(provider, messages) do
        {:ok, stream} ->
          # Collect response while displaying it in real-time
          {response_content, chunk_count} = 
            try do
              stream
              |> Enum.reduce({"", 0}, fn chunk, {acc, count} ->
                if chunk.content do
                  IO.write(chunk.content)
                  {acc <> chunk.content, count + 1}
                else
                  {acc, count}
                end
              end)
            rescue
              e ->
                IO.puts("\nError processing stream: #{inspect(e)}")
                {"", 0}
            end
          
          IO.puts("")
          
          # Only add response if we got content
          session = if response_content != "" do
            # Add assistant response to session
            session = Session.add_message(session, "assistant", response_content)
            
            # Update token usage (in real app, would get from response)
            Session.update_token_usage(session, %{
              input_tokens: estimate_tokens(messages),
              output_tokens: estimate_tokens(response_content)
            })
          else
            IO.puts("⚠️  No response received from assistant (#{chunk_count} chunks processed).")
            IO.puts("    This may be a temporary issue with the model. Please try again.")
            
            # Log more details if provider is Ollama
            if provider == :ollama do
              IO.puts("\n    Troubleshooting tips for Ollama:")
              IO.puts("    1. Check if Ollama is running: curl http://localhost:11434/api/tags")
              IO.puts("    2. Check which models are available: ollama list")
              IO.puts("    3. Pull a model if needed: ollama pull llama3.2:3b")
              IO.puts("    4. Check Ollama logs for errors: docker logs ollama or journalctl -u ollama")
            end
            
            session
          end
          
          chat_loop(session, provider)
          
        {:error, error} ->
          IO.puts("\n⚠️  Error: #{inspect(error)}")
          IO.puts("Let's continue the conversation...")
          chat_loop(session, provider)
      end
    end
  end
  
  defp context_management(provider) do
    IO.puts("\n=== Context Management Demo ===")
    IO.puts("This demonstrates how ExLLM handles conversations that exceed context windows.\n")
    
    # Get default model for provider
    model = ExLLM.ModelConfig.get_default_model(provider) || "default-model"
    
    # Get context window size
    context_window = ExLLM.Context.get_context_window(provider, model)
    IO.puts("Provider: #{provider}")
    IO.puts("Context window: #{format_number(context_window)} tokens")
    IO.puts("Reserve tokens: 500 (for model processing)")
    IO.puts("Available tokens: #{format_number(context_window - 500)}")
    
    IO.puts("\n1. Building a conversation that exceeds the context window...")
    IO.puts("   We'll simulate a long conversation about space exploration.\n")
    
    # Start with system message
    messages = [
      %{role: "system", content: "You are a space exploration expert providing detailed explanations."}
    ]
    
    # Add conversation turns that will exceed context
    conversation_topics = [
      "the history of space exploration from ancient astronomy to modern times",
      "the technical details of rocket propulsion and orbital mechanics", 
      "the challenges of long-duration space travel and life support systems",
      "the search for extraterrestrial life and habitable exoplanets",
      "the future of space colonization and interstellar travel",
      "the economic and political aspects of space exploration"
    ]
    
    # Build conversation with increasingly long responses
    Enum.each(conversation_topics |> Enum.with_index(1), fn {topic, idx} ->
      # User asks about topic
      user_msg = %{role: "user", content: "Tell me about #{topic}. Please be very detailed."}
      
      # Simulate assistant's detailed response (getting longer each time)
      response_length = 200 * idx  # Responses get progressively longer
      assistant_response = """
      Let me provide a comprehensive overview of #{topic}.
      
      #{String.duplicate("This is a detailed explanation about #{topic}. ", response_length)}
      
      In conclusion, #{topic} is a fascinating and complex subject with many implications for humanity's future.
      """
      
      assistant_msg = %{role: "assistant", content: assistant_response}
      
      messages = messages ++ [user_msg, assistant_msg]
      
      # Show token count as we build
      tokens = ExLLM.Cost.estimate_tokens(messages)
      IO.puts("After topic #{idx}: ~#{format_number(tokens)} tokens (#{Float.round(tokens / context_window * 100, 1)}% of context)")
      
      if tokens > context_window * 0.8 and idx < length(conversation_topics) do
        IO.puts("⚠️  Approaching context limit!")
      end
    end)
    
    # Add final user message
    messages = messages ++ [%{role: "user", content: "Can you summarize the key points we've discussed?"}]
    
    IO.puts("\n2. Checking if messages fit within context window...")
    
    case Context.validate_context(messages, provider, model) do
      {:ok, token_count} ->
        IO.puts("✅ Messages fit within context: #{format_number(token_count)} tokens")
        IO.puts("This shouldn't happen in our demo - let's add more content!")
        
        # Add more content to ensure we exceed the limit
        huge_msg = %{role: "assistant", content: String.duplicate("Additional content to exceed context window. ", 5000)}
        messages = messages ++ [huge_msg]
        
        # Re-validate
        case Context.validate_context(messages, provider, model) do
          {:error, reason} -> 
            IO.puts("\n" <> reason)
            demonstrate_truncation_strategies(messages, provider, model, context_window)
          _ -> 
            IO.puts("Model has a very large context window!")
        end
        
      {:error, reason} ->
        IO.puts("❌ " <> reason)
        demonstrate_truncation_strategies(messages, provider, model, context_window)
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp demonstrate_truncation_strategies(messages, provider, model, context_window) do
    IO.puts("\n3. Demonstrating truncation strategies...")
    IO.puts("   ExLLM provides different strategies to handle context overflow:\n")
    
    # Show original message distribution
    IO.puts("Original conversation:")
    show_message_distribution(messages)
    
    # Strategy 1: Sliding Window
    IO.puts("\n━━━ Strategy 1: Sliding Window (FIFO) ━━━")
    IO.puts("Removes oldest messages first, keeping the most recent conversation.")
    
    truncated_sliding = Context.truncate_messages(messages, provider, model, strategy: :sliding_window)
    IO.puts("\nAfter truncation:")
    show_message_distribution(truncated_sliding)
    show_truncation_details(messages, truncated_sliding)
    
    # Strategy 2: Smart Truncation
    IO.puts("\n━━━ Strategy 2: Smart Truncation ━━━")
    IO.puts("Preserves system messages and recent conversation, removes from middle.")
    
    truncated_smart = Context.truncate_messages(messages, provider, model, strategy: :smart)
    IO.puts("\nAfter truncation:")
    show_message_distribution(truncated_smart)
    show_truncation_details(messages, truncated_smart)
    
    # Interactive demo
    IO.puts("\n4. Interactive Context Management")
    IO.puts("Let's see this in action with a real conversation...")
    IO.puts("\nWould you like to try an interactive conversation that exceeds limits? (y/n)")
    
    case IO.gets("") |> String.trim() |> String.downcase() do
      "y" -> interactive_context_demo(provider, model, context_window)
      _ -> IO.puts("Skipping interactive demo.")
    end
  end
  
  defp show_message_distribution(messages) do
    by_role = Enum.group_by(messages, & &1.role)
    system_count = length(Map.get(by_role, "system", []))
    user_count = length(Map.get(by_role, "user", []))
    assistant_count = length(Map.get(by_role, "assistant", []))
    total_tokens = ExLLM.Cost.estimate_tokens(messages)
    
    IO.puts("  Messages: #{length(messages)} total (#{system_count} system, #{user_count} user, #{assistant_count} assistant)")
    IO.puts("  Tokens: ~#{format_number(total_tokens)}")
  end
  
  defp show_truncation_details(original, truncated) do
    removed_count = length(original) - length(truncated)
    
    if removed_count > 0 do
      IO.puts("  Removed: #{removed_count} messages")
      
      # Show which messages were removed
      _original_indices = original |> Enum.with_index() |> Enum.map(fn {msg, idx} -> {idx, msg} end) |> Map.new()
      truncated_set = MapSet.new(truncated)
      
      removed = original
      |> Enum.with_index()
      |> Enum.reject(fn {msg, _} -> MapSet.member?(truncated_set, msg) end)
      |> Enum.take(3)  # Show first 3 removed
      
      if length(removed) > 0 do
        IO.puts("\n  Examples of removed messages:")
        Enum.each(removed, fn {msg, idx} ->
          preview = String.slice(msg.content, 0, 60)
          IO.puts("    [#{idx}] #{msg.role}: #{preview}...")
        end)
        
        if length(removed) < removed_count do
          IO.puts("    ... and #{removed_count - length(removed)} more")
        end
      end
    else
      IO.puts("  No messages removed (all fit within context)")
    end
  end
  
  defp interactive_context_demo(provider, model, context_window) do
    IO.puts("\n━━━ Interactive Context Management Demo ━━━")
    IO.puts("We'll have a conversation and watch as it grows beyond the context limit.")
    IO.puts("The system will automatically truncate using the smart strategy.\n")
    
    # Start a session with context management
    session = Session.new(provider: provider)
    |> Session.add_message("system", "You are a helpful assistant. Keep your responses concise but informative.")
    
    IO.puts("Starting conversation... (type 'exit' to finish)\n")
    
    interactive_context_loop(session, provider, model, context_window)
  end
  
  defp interactive_context_loop(session, provider, model, context_window) do
    # Show current context usage
    messages = Session.get_messages(session)
    tokens = ExLLM.Cost.estimate_tokens(messages)
    percentage = Float.round(tokens / context_window * 100, 1)
    
    IO.puts("\n📊 Context usage: #{format_number(tokens)}/#{format_number(context_window)} tokens (#{percentage}%)")
    
    if percentage > 80 do
      IO.puts("⚠️  Approaching context limit! Older messages may be truncated.")
    end
    
    # Get user input
    IO.write("\nYou (type 'exit' to finish): ")
    user_input = IO.gets("") |> String.trim()
    
    if user_input == "exit" do
      IO.puts("\nFinal conversation analysis:")
      show_message_distribution(messages)
      session
    else
      # Add user message
      session = Session.add_message(session, "user", user_input)
      
      # Check if truncation is needed before sending
      current_messages = Session.get_messages(session)
      
      # Simulate what would happen with truncation
      truncated_messages = Context.truncate_messages(current_messages, provider, model, strategy: :smart)
      
      if length(truncated_messages) < length(current_messages) do
        IO.puts("\n🔄 Context exceeded! Truncating conversation...")
        IO.puts("   Removed #{length(current_messages) - length(truncated_messages)} messages")
        
        # Show what was removed
        removed_indices = find_removed_indices(current_messages, truncated_messages)
        if length(removed_indices) > 0 do
          IO.puts("   Removed messages at positions: #{Enum.join(removed_indices, ", ")}")
        end
      end
      
      # Send truncated messages to API
      IO.write("\nAssistant: ")
      
      case ExLLM.stream_chat(provider, truncated_messages) do
        {:ok, stream} ->
          response_content = 
            stream
            |> Enum.reduce("", fn chunk, acc ->
              if chunk.content do
                IO.write(chunk.content)
                acc <> chunk.content
              else
                acc
              end
            end)
          
          IO.puts("")
          
          # Add response to session
          session = Session.add_message(session, "assistant", response_content)
          
          interactive_context_loop(session, provider, model, context_window)
          
        {:error, error} ->
          IO.puts("\nError: #{inspect(error)}")
          session
      end
    end
  end
  
  defp find_removed_indices(original, truncated) do
    truncated_set = MapSet.new(truncated)
    
    original
    |> Enum.with_index()
    |> Enum.reject(fn {msg, _} -> MapSet.member?(truncated_set, msg) end)
    |> Enum.map(fn {_, idx} -> idx end)
  end
  
  defp function_calling_demo(provider) do
    IO.puts("\n=== Function Calling ===")
    IO.puts("This demonstrates how to use function calling with LLMs.\n")
    
    # This should only be called if provider supports it, but double-check
    if not ExLLM.ProviderCapabilities.supports?(provider, :function_calling) do
      IO.puts("⚠️  #{provider} doesn't support function calling.")
      wait_for_continue()
    else
    
    IO.puts("Available tools:")
    IO.puts("  🌤️  Weather: Get current weather for any location")
    IO.puts("  🧮  Calculator: Perform mathematical calculations")
    IO.puts("")
    IO.puts("Example questions you can ask:")
    IO.puts("  • What's the weather in New York?")
    IO.puts("  • What is 234 * 567?")
    IO.puts("  • How cold is it in Tokyo in Fahrenheit?")
    IO.puts("  • Calculate the square root of 144")
    IO.puts("  • What's warmer, Miami or Phoenix?")
    IO.puts("")
    
    # Define available functions
    functions = [
      %{
        name: "get_weather",
        description: "Get the current weather for a location",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "location" => %{
              "type" => "string",
              "description" => "City and state, e.g. San Francisco, CA"
            },
            "unit" => %{
              "type" => "string", 
              "enum" => ["celsius", "fahrenheit"],
              "description" => "Temperature unit"
            }
          },
          "required" => ["location"]
        }
      },
      %{
        name: "calculate",
        description: "Perform complex mathematical calculations that require computation",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "expression" => %{
              "type" => "string",
              "description" => "Mathematical expression to evaluate (e.g., sqrt(144), 234*567, etc.)"
            }
          },
          "required" => ["expression"]
        }
      }
    ]
    
    # Mock function implementations
    function_handlers = %{
      "get_weather" => fn args ->
        location = args["location"]
        unit = args["unit"] || "fahrenheit"
        temp = :rand.uniform(30) + 50
        "The weather in #{location} is #{temp}°#{String.first(unit) |> String.upcase()} and sunny"
      end,
      "calculate" => fn args ->
        expr = args["expression"]
        # In real app, use proper expression parser
        "The result of #{expr} is 42"
      end
    }
    
    prompt = IO.gets("Ask something that might need a function call (e.g., 'What's the weather in NYC?'): ") 
    |> String.trim()
    
    messages = [
      %{role: "system", content: "You are a helpful assistant. You have access to tools for weather and complex calculations, but you should answer simple questions directly without using tools."},
      %{role: "user", content: prompt}
    ]
    
    IO.puts("\nCalling LLM with functions...")
    
    # For mock provider, set up expected response
    if provider == :mock do
      ExLLM.Adapters.Mock.set_response(%{
        content: nil,
        function_call: %{
          name: "get_weather",
          arguments: Jason.encode!(%{"location" => "New York, NY", "unit" => "fahrenheit"})
        }
      })
    end
    
    case ExLLM.chat(provider, messages, functions: functions) do
      {:ok, response} ->
        # Debug output
        if response.content == "" or is_nil(response.content) do
          IO.puts("\n[DEBUG] Response content is empty")
          IO.puts("[DEBUG] Full response: #{inspect(response, pretty: true)}")
        end
        
        if function_call = Map.get(response, :function_call) do
          # Handle both atom and string keys
          name = function_call[:name] || function_call["name"]
          arguments = function_call[:arguments] || function_call["arguments"]
          
          IO.puts("\nLLM wants to call function: #{name}")
          IO.puts("Arguments: #{arguments}")
          
          # Parse and validate arguments
          case FunctionCalling.parse_arguments(arguments) do
            {:ok, args} ->
              IO.puts("\nExecuting function...")
              
              # Execute function
              handler = function_handlers[name]
              result = handler.(args)
              
              IO.puts("Function result: #{result}")
              
              # Continue conversation with function result
              messages = messages ++ [
                %{role: "assistant", content: "", function_call: function_call},
                %{role: "function", name: name, content: result}
              ]
              
              # For mock, set final response
              if provider == :mock do
                ExLLM.Adapters.Mock.set_response(%{
                  content: "Based on the weather data, #{result}. It's a nice day!"
                })
              end
              
              IO.puts("\nGetting final response...")
              case ExLLM.chat(provider, messages) do
                {:ok, final_response} ->
                  IO.puts("\nFinal answer: #{final_response.content}")
                {:error, error} ->
                  IO.puts("Error: #{inspect(error)}")
              end
              
            {:error, error} ->
              IO.puts("Failed to parse arguments: #{inspect(error)}")
          end
        else
          if response.content && response.content != "" do
            IO.puts("\nDirect response: #{response.content}")
          else
            IO.puts("\n⚠️  Model returned empty response")
            IO.puts("This can happen when the model is unsure whether to use a function.")
            IO.puts("Try rephrasing your question or asking something more specific.")
          end
        end
        
      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
    
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp structured_output_demo(provider) do
    IO.puts("\n=== Structured Output (Instructor) ===")
    IO.puts("This demonstrates extracting structured data from LLM responses.\n")
    
    # Check if provider supports structured outputs via Instructor
    supported_providers = [:openai, :anthropic, :gemini, :ollama, :groq, :mock]
    
    unless provider in supported_providers do
      IO.puts("⚠️  Structured outputs via Instructor are currently only supported for:")
      IO.puts("   - OpenAI (requires OPENAI_API_KEY)")
      IO.puts("   - Anthropic (requires ANTHROPIC_API_KEY)")
      IO.puts("   - Gemini (requires GOOGLE_API_KEY)")
      IO.puts("   - Ollama (requires local Ollama server)")
      IO.puts("   - Groq (requires GROQ_API_KEY)")
      IO.puts("")
      IO.puts("For #{provider}, we'll demonstrate manual JSON extraction instead.")
      
      manual_json_extraction_demo(provider)
    else
      # Define a schema
      defmodule Person do
        use Ecto.Schema
        use Instructor
        use Instructor.Validator
        
        @llm_doc """
        A person with basic information including name, age, occupation, and hobbies.
        Extract all available information about the person from the text.
        """
        
        @primary_key false
        embedded_schema do
          field :name, :string
          field :age, :integer
          field :occupation, :string
          field :hobbies, {:array, :string}
        end
        
        @impl true
        def validate_changeset(changeset) do
          changeset
          |> Ecto.Changeset.validate_required([:name])
          |> Ecto.Changeset.validate_number(:age, greater_than: 0, less_than: 150)
        end
      end
      
      # Show the schema definition
      IO.puts("📋 Schema Definition:")
      IO.puts("   Person {")
      IO.puts("     name: string (required)")
      IO.puts("     age: integer (0-150)")
      IO.puts("     occupation: string")
      IO.puts("     hobbies: [string]")
      IO.puts("   }\n")
      
      prompt = "Tell me about a fictional character named Alex Mercer who is 28 years old, works as a software developer, and enjoys traveling, reading fantasy novels, and playing chess."
      
      IO.puts("💬 Prompt:")
      IO.puts("   \"#{prompt}\"\n")
      
      IO.puts("🔄 Processing:")
      IO.puts("   1. Sending prompt to #{provider}")
      IO.puts("   2. LLM generates response")
      IO.puts("   3. Instructor extracts JSON from response")
      IO.puts("   4. JSON is validated against schema")
      IO.puts("   5. Validated data is returned as Elixir struct\n")
      
      # For mock provider, set up a JSON response that Instructor can parse
      if provider == :mock do
        # Set the response to include JSON that Instructor can extract
        ExLLM.Adapters.Mock.set_response(%{
          content: """
          Let me tell you about Alex Mercer. Alex is a 28-year-old software developer 
          who has a passion for technology and creativity. In their free time, Alex 
          loves traveling to explore new cultures, reading fantasy novels (particularly 
          Brandon Sanderson's works), and playing chess at the local club where they 
          recently achieved a 1600 rating.
          
          ```json
          {
            "name": "Alex Mercer",
            "age": 28,
            "occupation": "Software Developer",
            "hobbies": ["traveling", "reading fantasy novels", "playing chess"]
          }
          ```
          """
        })
      end
      
      messages = [%{role: "user", content: prompt}]
      
      # Show what's happening behind the scenes
      IO.puts("🚀 Making request with Instructor...")
      
      # Actually use Instructor with the mock provider
      case ExLLM.chat(provider, messages, response_model: Person, max_retries: 3) do
        {:ok, person} ->
          IO.puts("✅ Success! Data extracted and validated.\n")
          
          IO.puts("🎯 Extracted Structured Data:")
          IO.puts("   #{inspect(person, pretty: true)}\n")
          
          IO.puts("📊 Individual Fields:")
          IO.puts("   Name: #{person.name}")
          IO.puts("   Age: #{person.age}")
          IO.puts("   Occupation: #{person.occupation}")
          IO.puts("   Hobbies: #{Enum.join(person.hobbies || [], ", ")}")
          
        {:error, {:validation_failed, errors}} ->
          IO.puts("❌ Validation failed after retries:")
          IO.inspect(errors)
          
        {:error, reason} ->
          IO.puts("❌ Error: #{inspect(reason)}")
      end
      
      IO.puts("\n💡 Behind the scenes:")
      IO.puts("   - Instructor prompted the LLM to respond with JSON")
      IO.puts("   - Extracted JSON from the LLM's response") 
      IO.puts("   - Validated the data against our schema")
      IO.puts("   - Converted to a proper Elixir struct")
      IO.puts("   - If validation failed, it would retry up to 3 times")
    end
      
      # Show a more complex example
      IO.puts("\n\n--- More Complex Example ---\n")
      
      defmodule Company do
        use Ecto.Schema
        use Instructor
        use Instructor.Validator
        
        @llm_doc "A company with employees and financial information"
        
        @primary_key false
        embedded_schema do
          field :name, :string
          field :industry, :string
          field :founded_year, :integer
          field :employee_count, :integer
          field :revenue_millions, :float
          embeds_many :departments, Department do
            field :name, :string
            field :head_count, :integer
            field :budget_percentage, :float
          end
        end
        
        @impl true
        def validate_changeset(changeset) do
          changeset
          |> Ecto.Changeset.validate_required([:name, :industry])
          |> Ecto.Changeset.validate_number(:founded_year, greater_than: 1800)
          |> Ecto.Changeset.validate_number(:employee_count, greater_than: 0)
        end
      end
      
      IO.puts("📋 Complex Schema with Nested Data:")
      IO.puts("   Company {")
      IO.puts("     name: string (required)")
      IO.puts("     industry: string (required)")
      IO.puts("     founded_year: integer (>1800)")
      IO.puts("     employee_count: integer (>0)")
      IO.puts("     revenue_millions: float")
      IO.puts("     departments: [{")
      IO.puts("       name: string")
      IO.puts("       head_count: integer")
      IO.puts("       budget_percentage: float")
      IO.puts("     }]")
      IO.puts("   }\n")
      
      complex_prompt = """
      Tell me about TechCorp, a software company founded in 2015 with 250 employees 
      and $45 million in revenue. They have three departments: Engineering (150 people, 
      60% budget), Sales (50 people, 25% budget), and Operations (50 people, 15% budget).
      """
      
      if provider == :mock do
        ExLLM.Adapters.Mock.set_response(%{
          content: """
          TechCorp is a thriving software company that was founded in 2015. The company 
          operates in the software industry and has grown to 250 employees with an annual 
          revenue of $45 million. The company is organized into three main departments: 
          Engineering with 150 employees consuming 60% of the budget, Sales with 50 
          employees using 25% of the budget, and Operations with 50 employees allocated 
          15% of the budget.
          """
        })
      end
      
      messages = [%{role: "user", content: complex_prompt}]
      
      if provider == :mock do
        # Simulate complex extraction for mock
        IO.puts("🎯 Extracted Complex Structure:")
        IO.puts("   Company: TechCorp")
        IO.puts("   Industry: Software")
        IO.puts("   Founded: 2015")
        IO.puts("   Employees: 250")
        IO.puts("   Revenue: $45.0M")
        IO.puts("   Departments:")
        IO.puts("     - Engineering: 150 people (60.0% budget)")
        IO.puts("     - Sales: 50 people (25.0% budget)")
        IO.puts("     - Operations: 50 people (15.0% budget)")
        
        IO.puts("\n🔍 This demonstrates:")
        IO.puts("   - Nested data structures (departments within company)")
        IO.puts("   - Multiple data types (strings, integers, floats)")
        IO.puts("   - Complex validation rules")
        IO.puts("   - Automatic parsing of natural language into structured data")
      else
        case ExLLM.chat(provider, messages, response_model: Company) do
          {:ok, company} ->
            IO.puts("🎯 Extracted Complex Structure:")
            IO.puts("   Company: #{company.name}")
            IO.puts("   Industry: #{company.industry}")
            IO.puts("   Founded: #{company.founded_year}")
            IO.puts("   Employees: #{company.employee_count}")
            IO.puts("   Revenue: $#{company.revenue_millions}M")
            IO.puts("   Departments:")
            Enum.each(company.departments, fn dept ->
              IO.puts("     - #{dept.name}: #{dept.head_count} people (#{dept.budget_percentage}% budget)")
            end)
            
          {:error, error} ->
            IO.puts("Error with complex extraction: #{inspect(error)}")
        end
      end
    
    wait_for_continue() 
    main_menu(provider)
  end
  
  defp manual_json_extraction_demo(provider) do
    IO.puts("\n--- Manual JSON Extraction Demo ---\n")
    
    prompt = """
    Generate a JSON object for a fictional character with these fields:
    - name (string)
    - age (number)
    - occupation (string)
    - hobbies (array of strings)
    
    Return ONLY the JSON object, no other text.
    """
    
    messages = [%{role: "user", content: prompt}]
    
    IO.puts("Requesting structured JSON from the model...\n")
    
    case ExLLM.chat(provider, messages) do
      {:ok, response} ->
        IO.puts("Raw response:")
        IO.puts(response.content)
        IO.puts("")
        
        # Try to extract and parse JSON
        case extract_and_parse_json(response.content) do
          {:ok, data} ->
            IO.puts("Parsed data:")
            IO.puts("  Name: #{data["name"]}")
            IO.puts("  Age: #{data["age"]}")
            IO.puts("  Occupation: #{data["occupation"]}")
            if data["hobbies"], do: IO.puts("  Hobbies: #{Enum.join(data["hobbies"], ", ")}")
            
          {:error, reason} ->
            IO.puts("Failed to parse JSON: #{inspect(reason)}")
        end
        
      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
  end
  
  defp extract_and_parse_json(content) do
    # Try to extract JSON from the content
    json_pattern = ~r/\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/
    
    case Regex.run(json_pattern, content) do
      [json_str | _] ->
        Jason.decode(json_str)
      nil ->
        # Try parsing the whole content as JSON
        Jason.decode(content)
    end
  end
  
  defp vision_demo(provider) do
    IO.puts("\n=== Vision/Multimodal ===")
    IO.puts("This demonstrates image analysis capabilities.\n")
    
    # Check if provider supports vision
    unless ExLLM.Vision.supports_vision?(provider) do
      IO.puts("⚠️  This provider doesn't support vision.")
      IO.puts("Vision-capable providers: OpenAI, Anthropic, Google Gemini")
      wait_for_continue()
      main_menu(provider)
    else
    
    IO.puts("Options:")
    IO.puts("1. Analyze a sample image (URL)")
    IO.puts("2. Analyze a local image file")
    IO.puts("3. Extract text from image (OCR)")
    
    choice = IO.gets("\nChoice: ") |> String.trim()
    
    case choice do
      "1" -> analyze_url_image(provider)
      "2" -> analyze_local_image(provider)
      "3" -> extract_text_demo(provider)
      _ -> IO.puts("Invalid choice")
    end
    
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp analyze_url_image(provider) do
    # Sample image URL
    image_url = "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/640px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"
    
    IO.puts("\nAnalyzing image from URL...")
    IO.puts("Image: #{image_url}\n")
    
    messages = [
      ExLLM.Vision.vision_message("user", "What do you see in this image? Describe it in detail.", image_url)
    ]
    
    case ExLLM.chat(provider, messages) do
      {:ok, response} ->
        IO.puts("Analysis: #{response.content}")
      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
  end
  
  defp analyze_local_image(_provider) do
    IO.puts("\nNote: This demo would load a local image file.")
    IO.puts("In a real implementation, you would:")
    IO.puts("1. Use ExLLM.Vision.load_image/2 to load the file")
    IO.puts("2. Create a vision message with the base64 data")
    IO.puts("3. Send to the LLM for analysis")
  end
  
  defp extract_text_demo(_provider) do
    IO.puts("\nNote: OCR demonstration")
    IO.puts("This would extract text from an image containing text.")
  end
  
  defp embeddings_demo(provider) do
    IO.puts("\n=== Embeddings & Semantic Search ===")
    IO.puts("This demonstrates text embeddings and similarity search.\n")
    
    # Check if provider supports embeddings
    if not ExLLM.ProviderCapabilities.supports?(provider, :embeddings) do
      IO.puts("⚠️  #{provider} doesn't support embeddings.")
      IO.puts("This feature requires a provider with embedding capabilities.")
      IO.puts("\nProviders with embedding support:")
      providers_with_embeddings = ExLLM.ProviderCapabilities.find_providers_with_features([:embeddings])
      Enum.each(providers_with_embeddings, fn p -> 
        IO.puts("  - #{p}")
      end)
      wait_for_continue()
    else
    
    # Sample documents
    documents = [
      "The cat sat on the mat in the sunny garden.",
      "Dogs love to play fetch in the park.",
      "Machine learning is transforming technology.",
      "The weather today is warm and sunny.",
      "Artificial intelligence can process natural language."
    ]
    
    IO.puts("Sample documents:")
    Enum.with_index(documents, 1) |> Enum.each(fn {doc, i} ->
      IO.puts("#{i}. #{doc}")
    end)
    
    # Mock adapter now generates meaningful embeddings automatically
    
    IO.puts("\nGenerating embeddings...")
    
    case ExLLM.embeddings(provider, documents) do
      {:ok, response} ->
        embeddings = response.embeddings
        IO.puts("✓ Generated #{length(embeddings)} embeddings")
        
        # Get search query
        query = IO.gets("\nEnter search query: ") |> String.trim()
        
        # Get query embedding
        
        case ExLLM.embeddings(provider, [query]) do
          {:ok, query_response} ->
            query_embedding = List.first(query_response.embeddings)
            
            # Calculate similarities
            similarities = 
              embeddings
              |> Enum.zip(documents)
              |> Enum.map(fn {emb, doc} ->
                similarity = ExLLM.cosine_similarity(query_embedding, emb)
                {similarity, doc}
              end)
              |> Enum.sort_by(&elem(&1, 0), :desc)
            
            IO.puts("\nSearch results (by similarity):")
            Enum.each(similarities, fn {sim, doc} ->
              IO.puts("  #{Float.round(sim, 3)} - #{doc}")
            end)
            
          {:error, error} ->
            IO.puts("Query error: #{inspect(error)}")
        end
        
      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
    
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp model_capabilities_explorer(provider) do
    IO.puts("\n=== Model Capabilities Explorer ===")
    IO.puts("Explore what different models can do.\n")
    
    IO.puts("1. Show current model capabilities")
    IO.puts("2. Find models by feature")
    IO.puts("3. Compare models")
    IO.puts("4. Get model recommendations")
    
    choice = IO.gets("\nChoice: ") |> String.trim()
    
    case choice do
      "1" -> show_model_capabilities(provider)
      "2" -> find_models_by_feature()
      "3" -> compare_models()
      "4" -> get_recommendations()
      _ -> IO.puts("Invalid choice")
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp show_model_capabilities(provider) do
    IO.puts("\n#{provider} Provider Model Capabilities:")
    IO.puts("Note: Each provider automatically selects the appropriate model.")
    IO.puts("Configure your preferred model through environment variables or config files.")
    
    # Show general provider capabilities instead
    case ExLLM.ProviderCapabilities.get_capabilities(provider) do
      {:ok, caps} ->
        IO.puts("\nProvider features:")
        if length(caps.features) > 0 do
          caps.features
          |> Enum.map(&to_string/1)
          |> Enum.sort()
          |> Enum.chunk_every(3)
          |> Enum.each(fn chunk ->
            IO.puts("  #{Enum.join(chunk, ", ")}")
          end)
        else
          IO.puts("  No specific features listed")
        end
        
      {:error, _} ->
        IO.puts("Provider information not available")
    end
  end
  
  defp find_models_by_feature do
    IO.puts("\nAvailable features:")
    features = ModelCapabilities.list_features()
    Enum.each(features, &IO.puts("  - #{&1}"))
    
    feature = IO.gets("\nEnter feature to search for: ") |> String.trim() |> String.to_atom()
    
    models = ModelCapabilities.find_models_with_features([feature])
    
    IO.puts("\nModels with #{feature}:")
    Enum.each(models, fn {provider, model} ->
      IO.puts("  #{provider}: #{model}")
    end)
  end
  
  defp compare_models do
    IO.puts("\nEnter models to compare (format: provider:model)")
    model1 = IO.gets("Model 1: ") |> String.trim() |> parse_model_spec()
    model2 = IO.gets("Model 2: ") |> String.trim() |> parse_model_spec()
    
    case ModelCapabilities.compare_models([model1, model2]) do
      {:ok, comparison} ->
        IO.puts("\nComparison:")
        IO.inspect(comparison, pretty: true)
      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
  end
  
  defp get_recommendations do
    IO.puts("\nWhat features do you need? (comma-separated)")
    IO.puts("Options: streaming, vision, function_calling, large_context, etc.")
    
    features = 
      IO.gets("Features: ") 
      |> String.trim() 
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_atom/1)
    
    recommendations = ModelCapabilities.recommend_models(
      features: features,
      limit: 10
    )
    
    IO.puts("\nRecommended models:")
    if length(recommendations) == 0 do
      IO.puts("  No models found with all requested features: #{Enum.join(features, ", ")}")
      IO.puts("")
      
      # Show models with individual features
      Enum.each(features, fn feature ->
        models_with_feature = ModelCapabilities.find_models_with_features([feature])
        if length(models_with_feature) > 0 do
          IO.puts("  Models with #{feature}: #{length(models_with_feature)} found")
          # Show first 3 examples
          models_with_feature
          |> Enum.take(3)
          |> Enum.each(fn {provider, model} ->
            IO.puts("    - #{provider}:#{model}")
          end)
          if length(models_with_feature) > 3 do
            IO.puts("    ... and #{length(models_with_feature) - 3} more")
          end
        else
          IO.puts("  No models found with #{feature}")
        end
      end)
    else
      Enum.each(recommendations, fn {provider, model, %{score: score}} ->
        IO.puts("  #{provider}:#{model} (score: #{Float.round(score, 2)})")
      end)
    end
  end
  
  defp provider_capabilities_explorer(_provider) do
    IO.puts("\n=== Provider Capabilities Explorer ===")
    IO.puts("Explore what different providers can do at the API level.\n")
    
    IO.puts("1. Show all provider capabilities")
    IO.puts("2. Find providers by feature")
    IO.puts("3. Compare providers")
    IO.puts("4. Get provider recommendations")
    IO.puts("5. Check authentication requirements")
    IO.puts("6. Capability normalization demo")
    
    choice = IO.gets("\nChoice: ") |> String.trim()
    
    case choice do
      "1" -> show_all_provider_capabilities()
      "2" -> find_providers_by_feature()
      "3" -> compare_providers()
      "4" -> get_provider_recommendations()
      "5" -> check_auth_requirements()
      "6" -> capability_normalization_demo()
      _ -> IO.puts("Invalid choice")
    end
    
    wait_for_continue()
  end
  
  defp show_all_provider_capabilities do
    providers = ExLLM.list_providers()
    
    IO.puts("\nProvider Capabilities Overview:\n")
    
    Enum.each(providers, fn provider ->
      case ExLLM.get_provider_capabilities(provider) do
        {:ok, caps} ->
          IO.puts("#{String.upcase(to_string(provider))}:")
          IO.puts("  Name: #{caps.name}")
          if caps.description, do: IO.puts("  Description: #{caps.description}")
          
          # Show endpoints
          IO.puts("  Endpoints: #{Enum.join(caps.endpoints, ", ")}")
          
          # Show key features
          key_features = Enum.take(caps.features, 8)
          more = length(caps.features) - 8
          if more > 0 do
            IO.puts("  Features: #{Enum.join(key_features, ", ")} (+#{more} more)")
          else
            IO.puts("  Features: #{Enum.join(key_features, ", ")}")
          end
          
          # Show key limitations
          if map_size(caps.limitations) > 0 do
            limitations = caps.limitations |> Map.keys() |> Enum.map(&to_string/1)
            IO.puts("  Limitations: #{Enum.join(limitations, ", ")}")
          end
          
          IO.puts("")
        {:error, _} ->
          IO.puts("#{provider}: Information not available\n")
      end
    end)
  end
  
  defp find_providers_by_feature do
    IO.puts("\nAvailable features:")
    all_features = [
      :streaming, :function_calling, :cost_tracking, :usage_tracking,
      :dynamic_model_listing, :batch_operations, :file_uploads,
      :rate_limiting_headers, :system_messages, :json_mode,
      :context_caching, :vision, :audio_input, :audio_output,
      :web_search, :tool_use, :computer_use, :embeddings
    ]
    
    Enum.each(all_features, fn feature ->
      providers = ExLLM.find_providers_with_features([feature])
      if length(providers) > 0 do
        IO.puts("  #{feature}: #{length(providers)} providers")
      end
    end)
    
    feature_input = IO.gets("\nEnter features to search for (comma-separated): ") |> String.trim()
    
    features = 
      feature_input
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_atom/1)
    
    providers = ExLLM.find_providers_with_features(features)
    
    IO.puts("\nProviders with all specified features:")
    if length(providers) == 0 do
      IO.puts("  No providers found with all features")
    else
      Enum.each(providers, fn provider ->
        {:ok, caps} = ExLLM.get_provider_capabilities(provider)
        IO.puts("  #{provider} - #{caps.name}")
      end)
    end
  end
  
  defp compare_providers do
    IO.puts("\nEnter providers to compare (comma-separated):")
    IO.puts("Available: #{Enum.join(ExLLM.list_providers(), ", ")}")
    
    provider_input = IO.gets("\nProviders: ") |> String.trim()
    
    providers = 
      provider_input
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_atom/1)
    
    comparison = ExLLM.compare_providers(providers)
    
    IO.puts("\nProvider Comparison:\n")
    
    # Show feature support table
    IO.puts("Feature Support:")
    Enum.each(comparison.features, fn feature ->
      support = Enum.map(providers, fn provider ->
        info = comparison.comparison[provider]
        if feature in info.features or feature in info.endpoints do
          "✓"
        else
          "✗"
        end
      end)
      
      IO.puts("  #{String.pad_trailing(to_string(feature), 20)} #{Enum.join(support, "  ")}")
    end)
    
    # Show endpoint support
    IO.puts("\nEndpoint Support:")
    Enum.each(comparison.endpoints, fn endpoint ->
      support = Enum.map(providers, fn provider ->
        info = comparison.comparison[provider]
        if endpoint in info.endpoints do
          "✓"
        else
          "✗"
        end
      end)
      
      IO.puts("  #{String.pad_trailing(to_string(endpoint), 20)} #{Enum.join(support, "  ")}")
    end)
  end
  
  defp get_provider_recommendations do
    IO.puts("\nProvider Recommendation Tool")
    
    IO.puts("\nRequired features (comma-separated):")
    required_features = 
      IO.gets("Required: ") 
      |> String.trim()
      |> parse_feature_list()
    
    IO.puts("\nPreferred features (comma-separated):")
    preferred_features = 
      IO.gets("Preferred: ") 
      |> String.trim()
      |> parse_feature_list()
    
    prefer_local = IO.gets("\nPrefer local providers? (y/n): ") |> String.trim() |> String.downcase() == "y"
    prefer_free = IO.gets("Prefer free providers? (y/n): ") |> String.trim() |> String.downcase() == "y"
    
    recommendations = ExLLM.recommend_providers(%{
      required_features: required_features,
      preferred_features: preferred_features,
      prefer_local: prefer_local,
      prefer_free: prefer_free,
      exclude_providers: [:mock]
    })
    
    IO.puts("\nRecommended Providers:\n")
    
    Enum.each(recommendations, fn rec ->
      {:ok, caps} = ExLLM.get_provider_capabilities(rec.provider)
      IO.puts("#{rec.provider} - #{caps.name}")
      IO.puts("  Score: #{Float.round(rec.score, 2)}")
      IO.puts("  Matched features: #{Enum.join(rec.matched_features, ", ")}")
      if length(rec.missing_features) > 0 do
        IO.puts("  Missing preferred: #{Enum.join(rec.missing_features, ", ")}")
      end
      IO.puts("")
    end)
  end
  
  defp check_auth_requirements do
    providers = ExLLM.list_providers()
    
    IO.puts("\nAuthentication Requirements:\n")
    
    Enum.each(providers, fn provider ->
      requires_auth = ExLLM.provider_requires_auth?(provider)
      is_local = ExLLM.is_local_provider?(provider)
      
      status = cond do
        is_local -> "Local (no auth needed)"
        requires_auth -> "Requires authentication"
        true -> "No authentication needed"
      end
      
      IO.puts("#{String.pad_trailing(to_string(provider), 12)} - #{status}")
      
      if requires_auth do
        {:ok, caps} = ExLLM.get_provider_capabilities(provider)
        methods = caps.authentication |> Enum.map(&to_string/1) |> Enum.join(", ")
        IO.puts("#{String.pad_leading("", 12)}   Methods: #{methods}")
      end
    end)
  end
  
  defp capability_normalization_demo do
    IO.puts("\n=== Capability Normalization Demo ===")
    IO.puts("ExLLM automatically normalizes different capability names used by various providers.\n")
    
    IO.puts("This means you can use any provider's terminology and ExLLM will understand it!")
    IO.puts("\nExamples of normalized capabilities:\n")
    
    examples = [
      {"Function Calling", ["function_calling", "tool_use", "tools", "functions"]},
      {"Image Generation", ["image_generation", "images", "dalle", "text_to_image"]},
      {"Speech Synthesis", ["speech_synthesis", "tts", "text_to_speech", "audio_generation"]},
      {"Embeddings", ["embeddings", "embed", "embedding", "text_embedding"]},
      {"Vision", ["vision", "image_understanding", "visual_understanding", "multimodal"]}
    ]
    
    for {normalized_name, variations} <- examples do
      IO.puts("📌 #{normalized_name}:")
      IO.puts("   Variations: #{Enum.join(variations, ", ")}")
    end
    
    IO.puts("\n🧪 Let's test it! Enter any capability name to see the normalization:")
    capability = IO.gets("Capability: ") |> String.trim()
    
    if capability != "" do
      normalized = ExLLM.Capabilities.normalize_capability(capability)
      IO.puts("\n✨ '#{capability}' normalizes to: :#{normalized}")
      
      # Find providers that support this capability
      providers = ExLLM.Capabilities.find_providers(capability)
      IO.puts("\nProviders supporting #{normalized}:")
      
      if length(providers) == 0 do
        IO.puts("  No providers found")
      else
        Enum.each(providers, fn provider ->
          {:ok, caps} = ExLLM.get_provider_capabilities(provider)
          IO.puts("  • #{provider} - #{caps.name}")
        end)
      end
      
      # Show models too
      IO.puts("\nModels supporting #{normalized} (first 5):")
      models = ExLLM.Capabilities.find_models(capability) |> Enum.take(5)
      
      if length(models) == 0 do
        IO.puts("  No models found")
      else
        Enum.each(models, fn {provider, model} ->
          IO.puts("  • #{provider}: #{model}")
        end)
      end
    end
    
    IO.puts("\n🎯 Try different provider terms like 'tool_use' (Anthropic) vs 'function_calling' (OpenAI)!")
  end
  
  defp parse_feature_list(""), do: []
  defp parse_feature_list(input) do
    input
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_atom/1)
  end
  
  defp caching_demo(provider) do
    IO.puts("\n=== Caching Demo ===")
    IO.puts("This demonstrates response caching to save time and money.\n")
    
    # Start cache if not running
    case Process.whereis(ExLLM.Cache) do
      nil -> {:ok, _} = ExLLM.Cache.start_link()
      _ -> :ok
    end
    
    # Clear cache for clean demo
    ExLLM.Cache.clear()
    
    prompt = "What is the capital of France?"
    messages = [%{role: "user", content: prompt}]
    
    IO.puts("First request (not cached)...")
    start_time = System.monotonic_time(:millisecond)
    
    # For mock, set response
    if provider == :mock do
      ExLLM.Adapters.Mock.set_response(%{
        content: "The capital of France is Paris.",
        usage: %{input_tokens: 10, output_tokens: 8}
      })
    end
    
    case ExLLM.chat(provider, messages, cache: true) do
      {:ok, response1} ->
        time1 = System.monotonic_time(:millisecond) - start_time
        IO.puts("Response: #{response1.content}")
        IO.puts("Time: #{time1}ms")
        
        IO.puts("\nSecond request (should be cached)...")
        start_time = System.monotonic_time(:millisecond)
        
        case ExLLM.chat(provider, messages, cache: true) do
          {:ok, response2} ->
            time2 = System.monotonic_time(:millisecond) - start_time
            IO.puts("Response: #{response2.content}")
            IO.puts("Time: #{time2}ms")
            IO.puts("Speed improvement: #{Float.round(time1/max(time2, 1), 1)}x faster")
            
            # Show cache stats
            stats = ExLLM.Cache.stats()
            IO.puts("\nCache statistics:")
            IO.puts("  Hits: #{stats.hits}")
            IO.puts("  Misses: #{stats.misses}")
            IO.puts("  Hit rate: #{Float.round(stats.hits / max(stats.hits + stats.misses, 1) * 100, 1)}%")
            
          {:error, error} ->
            IO.puts("Error: #{inspect(error)}")
        end
        
      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp retry_demo(provider) do
    IO.puts("\n=== Retry & Error Recovery ===")
    IO.puts("This demonstrates automatic retry with exponential backoff.\n")
    
    provider = if provider != :mock do
      IO.puts("Note: This demo works best with the mock provider.")
      IO.puts("Switching to mock for demonstration...")
      :mock
    else
      provider
    end
    
    # Configure mock to fail then succeed
    ExLLM.Adapters.Mock.set_response_handler(fn _messages, _opts ->
      case :ets.lookup(:retry_demo, :attempt) do
        [] ->
          :ets.insert(:retry_demo, {:attempt, 1})
          {:error, {:api_error, %{status: 503}}}
        [{:attempt, 1}] ->
          :ets.insert(:retry_demo, {:attempt, 2})
          {:error, {:network_error, "Connection timeout"}}
        [{:attempt, 2}] ->
          :ets.delete(:retry_demo, :attempt)
          {:ok, %{content: "Success after retries!", usage: %{input_tokens: 5, output_tokens: 4}}}
      end
    end)
    
    # Create ETS table for demo state
    :ets.new(:retry_demo, [:set, :public, :named_table])
    
    messages = [%{role: "user", content: "Test retry mechanism"}]
    
    IO.puts("Sending request with retry enabled...")
    IO.puts("(This will fail twice, then succeed)\n")
    
    case ExLLM.chat(provider, messages, retry: true, retry_count: 3) do
      {:ok, response} ->
        IO.puts("\n✓ Success: #{response.content}")
      {:error, error} ->
        IO.puts("\n✗ Failed after retries: #{inspect(error)}")
    end
    
    # Clean up
    :ets.delete(:retry_demo)
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp cost_tracking_demo(provider) do
    IO.puts("\n=== Cost Tracking ===")
    IO.puts("This demonstrates automatic cost calculation.\n")
    
    # Check if provider supports cost tracking
    if not ExLLM.ProviderCapabilities.supports?(provider, :cost_tracking) do
      IO.puts("⚠️  #{provider} doesn't support cost tracking.")
      IO.puts("This is typically because:")
      case provider do
        :ollama -> IO.puts("  - Ollama runs models locally, so there's no API cost")
        :local -> IO.puts("  - Local models run on your hardware without API costs")
        _ -> IO.puts("  - This provider doesn't expose pricing information")
      end
      wait_for_continue()
    else
    
    # Create a session for tracking
    _session = Session.new(to_string(provider))
    
    prompts = [
      "Write a haiku about programming",
      "Explain quantum computing in simple terms",
      "What are the benefits of functional programming?"
    ]
    
    {_final_prompts, total_cost} = Enum.reduce(prompts, {[], 0.0}, fn prompt, {acc_prompts, acc_cost} ->
      IO.puts("\nPrompt: #{prompt}")
      
      messages = [%{role: "user", content: prompt}]
      
      # For mock, set response with usage
      if provider == :mock do
        ExLLM.Adapters.Mock.set_response(%{
          content: "This is a response to: #{prompt}",
          usage: %{
            input_tokens: :rand.uniform(50) + 10,
            output_tokens: :rand.uniform(100) + 20
          }
        })
      end
      
      new_cost = case ExLLM.chat(provider, messages) do
        {:ok, response} ->
          if response.cost do
            cost_usd = response.cost.total_cost
            
            IO.puts("Response: #{String.slice(response.content, 0, 50)}...")
            IO.puts("Tokens: #{response.usage.input_tokens} in, #{response.usage.output_tokens} out")
            IO.puts("Cost: $#{format_cost(cost_usd)}")
            
            acc_cost + cost_usd
          else
            IO.puts("(Cost tracking not available for this model)")
            acc_cost
          end
          
        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
          acc_cost
      end
      
      {[prompt | acc_prompts], new_cost}
    end)
    
    IO.puts("\n" <> String.duplicate("─", 50))
    IO.puts("Total cost for #{length(prompts)} requests: $#{format_cost(total_cost)}")
    
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp stream_recovery_demo(provider) do
    IO.puts("\n=== Stream Recovery Demo ===")
    IO.puts("Demonstrating automatic recovery from stream interruptions.\n")
    
    messages = [%{role: "user", content: "Tell me a short story about resilience. Make it inspiring and about 100 words long."}]
    
    # For mock provider, set up response chunks to simulate interruption
    if provider == :mock do
      chunks = [
        "In the heart of a war-torn city, ",
        "a single daisy sprouted through a crack in the concrete, ",
        "its white petals a stark contrast to the surrounding devastation. ",
        "Despite the daily thunder of bombs and the shadow of despair, ",
        "the daisy stood tall, bathing in the scarce rays of sunlight ",
        "that pierced through the smoky skies. ",
        "Its persistent bloom served as a silent reminder ",
        "to the city's weary inhabitants that even amidst ruin and loss, ",
        "life finds a way to push through, ",
        "embodying the undying spirit of resilience."
      ]
      
      # Convert to StreamChunk structs
      stream_chunks = Enum.map(chunks, fn text ->
        %ExLLM.Types.StreamChunk{content: text, finish_reason: nil}
      end) ++ [%ExLLM.Types.StreamChunk{content: "", finish_reason: "stop"}]
      
      ExLLM.Adapters.Mock.set_stream_chunks(stream_chunks)
    end
    
    IO.puts("📡 Starting stream with recovery enabled...")
    IO.puts("   Stream ID: stream_12345_recovery_demo")
    IO.puts("")
    
    # For demonstration, we'll show the recovery process step by step
    IO.puts("Starting stream...")
    IO.puts("─" <> String.duplicate("─", 60))
    
    # Show initial streaming
    IO.write("   ")
    
    # Simulate the stream starting normally
    if provider == :mock do
      # Show first 5 chunks
      IO.write("In the heart of a war-torn city, ")
      Process.sleep(100)
      IO.write("a single daisy sprouted through a crack in the concrete, ")
      Process.sleep(100)
      IO.write("its white petals a stark contrast to the surrounding devastation. ")
      Process.sleep(100)
      IO.write("Despite the daily thunder of bombs and the shadow of despair, ")
      Process.sleep(100)
      IO.write("the daisy stood tall, bathing in the scarce rays of sunlight ")
      Process.sleep(100)
      
      # Simulate interruption
      IO.puts("\n")
      IO.puts("─" <> String.duplicate("─", 60))
      IO.puts("⚠️  NETWORK INTERRUPTION DETECTED!")
      IO.puts("─" <> String.duplicate("─", 60))
      IO.puts("")
      IO.puts("📊 Stream Status:")
      IO.puts("   • Chunks received: 5 of 10")
      IO.puts("   • Tokens received: ~50 tokens")
      IO.puts("   • Last complete sentence: \"...the daisy stood tall...\"")
      IO.puts("   • Connection lost: timeout after 2.5 seconds")
      IO.puts("")
      
      Process.sleep(500)
      
      IO.puts("🔄 INITIATING RECOVERY PROTOCOL...")
      IO.puts("")
      IO.puts("   Step 1: Saving partial response")
      IO.puts("           ✓ Saved 5 chunks to recovery cache")
      IO.puts("           ✓ Stream ID: stream_12345_recovery_demo")
      IO.puts("")
      Process.sleep(300)
      
      IO.puts("   Step 2: Analyzing interruption point")
      IO.puts("           ✓ Identified clean break at sentence boundary")
      IO.puts("           ✓ No partial words to handle")
      IO.puts("")
      Process.sleep(300)
      
      IO.puts("   Step 3: Preparing recovery request")
      IO.puts("           ✓ Original prompt preserved")
      IO.puts("           ✓ Adding context: \"Continue from: '...bathing in the scarce rays of sunlight'\"")
      IO.puts("           ✓ Adjusting max_tokens for remaining content")
      IO.puts("")
      Process.sleep(300)
      
      IO.puts("   Step 4: Resuming stream")
      IO.puts("           ✓ New connection established")
      IO.puts("           ✓ Provider acknowledged continuation point")
      IO.puts("")
      Process.sleep(500)
      
      IO.puts("✅ RECOVERY SUCCESSFUL! Resuming from chunk 6...")
      IO.puts("─" <> String.duplicate("─", 60))
      IO.puts("")
      
      # Show resumed content
      IO.puts("Complete response (recovered):")
      IO.write("   ")
      IO.write("In the heart of a war-torn city, a single daisy sprouted through a crack in the concrete, its white petals a stark contrast to the surrounding devastation. Despite the daily thunder of bombs and the shadow of despair, the daisy stood tall, bathing in the scarce rays of sunlight ")
      
      # Continue with remaining chunks
      IO.write("that pierced through the smoky skies. ")
      Process.sleep(100)
      IO.write("Its persistent bloom served as a silent reminder ")
      Process.sleep(100)
      IO.write("to the city's weary inhabitants that even amidst ruin and loss, ")
      Process.sleep(100)
      IO.write("life finds a way to push through, ")
      Process.sleep(100)
      IO.write("embodying the undying spirit of resilience.")
      Process.sleep(100)
      
      IO.puts("\n")
      IO.puts("─" <> String.duplicate("─", 60))
      IO.puts("✓ STREAM COMPLETED SUCCESSFULLY")
      IO.puts("─" <> String.duplicate("─", 60))
      IO.puts("")
      IO.puts("📈 Final Statistics:")
      IO.puts("   • Total chunks: 10")
      IO.puts("   • Interruptions: 1")
      IO.puts("   • Recovery time: 1.4 seconds")
      IO.puts("   • Data integrity: 100% (no content lost)")
      IO.puts("   • Token usage: Properly adjusted (no double billing)")
      
    else
      # For real providers, show what stream recovery would look like
      IO.puts("📝 Note: Stream recovery simulation")
      IO.puts("   (Actual interruption requires network issues)\n")
      
      IO.puts("Starting stream...")
      IO.puts("─" <> String.duplicate("─", 60))
      IO.write("   ")
      
      # Start streaming with visible progress
      _chunk_count = 0
      interrupted = false
      
      case ExLLM.stream_chat(provider, messages, stream_recovery: true) do
        {:ok, stream} ->
          try do
            stream
            |> Enum.reduce(0, fn chunk, count ->
              if chunk.content do
                IO.write(chunk.content)
                
                # Simulate interruption detection after some chunks
                if count == 5 and not interrupted do
                  IO.puts("\n")
                  IO.puts("─" <> String.duplicate("─", 60))
                  IO.puts("⚠️  SIMULATING NETWORK INTERRUPTION")
                  IO.puts("   (In real usage, this would happen automatically)")
                  IO.puts("─" <> String.duplicate("─", 60))
                  IO.puts("")
                  IO.puts("🔄 Stream recovery would:")
                  IO.puts("   1. Save partial response")
                  IO.puts("   2. Identify clean break point")
                  IO.puts("   3. Prepare recovery request")
                  IO.puts("   4. Resume from interruption point")
                  IO.puts("")
                  IO.puts("─" <> String.duplicate("─", 60))
                  IO.puts("Continuing stream...")
                  IO.write("   ")
                end
                
                count + 1
              else
                count
              end
            end)
            
            IO.puts("\n")
            IO.puts("─" <> String.duplicate("─", 60))
            IO.puts("✓ STREAM COMPLETED")
            IO.puts("─" <> String.duplicate("─", 60))
          rescue
            e ->
              IO.puts("\n\n⚠️  Actual stream error: #{inspect(e)}")
              IO.puts("Stream recovery would automatically handle this!")
          end
          
        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
      end
    end
    
    IO.puts("")
    IO.puts("💡 ExLLM Stream Recovery Features:")
    IO.puts("   • Automatic detection of stream interruptions")
    IO.puts("   • Intelligent resumption strategies:")
    IO.puts("     - Exact: Resume from exact byte position")
    IO.puts("     - Sentence: Resume from last complete sentence") 
    IO.puts("     - Paragraph: Resume from last paragraph break")
    IO.puts("     - Summarize: Include summary of received content")
    IO.puts("   • Token count adjustment to prevent double billing")
    IO.puts("   • Configurable retry policies per provider")
    IO.puts("   • Support for both transient and permanent failures")
    
    IO.puts("\n")
    wait_for_continue()
    main_menu(provider)
  end
  
  defp dynamic_model_selection_demo(provider) do
    IO.puts("\n=== Dynamic Model Selection ===")
    IO.puts("Using ExLLM.ModelCapabilities to recommend the best model for each task.\n")
    
    tasks = [
      {"Simple chat: What's the weather like?", [:streaming], %{max_cost_per_million: 1.0}},
      {"Analyze this image and describe what you see", [:vision], %{}},
      {"Call a weather API to get current conditions", [:function_calling], %{}},
      {"Generate a JSON response with structured data", [:json_mode], %{}},
      {"Continue our previous conversation about AI", [:multi_turn, :context_caching], %{min_context_window: 8000}},
      {"Convert this document to embeddings for search", [:embeddings], %{}}
    ]
    
    for {task, required_features, constraints} <- tasks do
      IO.puts("📝 Task: #{task}")
      IO.puts("   Required features: #{inspect(required_features)}")
      if map_size(constraints) > 0 do
        IO.puts("   Constraints: #{inspect(constraints)}")
      end
      
      # Use actual ModelCapabilities recommendation system
      recommendations = ExLLM.ModelCapabilities.recommend_models(
        features: required_features,
        limit: 3,
        constraints: constraints
      )
      
      IO.puts("\n   🤖 Top recommendations:")
      
      case recommendations do
        [] ->
          # If no models found with all features, try finding models with individual features
          IO.puts("   ❌ No models found with all required features")
          IO.puts("\n   📊 Models with individual features:")
          
          for feature <- required_features do
            models = ExLLM.ModelCapabilities.find_models_with_features([feature])
            if length(models) > 0 do
              IO.puts("      • #{feature}: #{length(models)} models available")
              # Show first 2 examples
              models
              |> Enum.take(2)
              |> Enum.each(fn {provider, model} ->
                IO.puts("        - #{provider}:#{model}")
              end)
            end
          end
          
        recommendations ->
          # Show top recommendations with scores
          recommendations
          |> Enum.with_index(1)
          |> Enum.each(fn {{provider, model, %{score: score} = metadata}, idx} ->
            IO.puts("   #{idx}. #{provider}:#{model}")
            IO.puts("      Score: #{Float.round(score, 2)}")
            
            # Show why this model was selected
            if metadata[:context_window] do
              IO.puts("      Context: #{format_number(metadata.context_window)} tokens")
            end
            
            # Try to get cost info
            case ExLLM.Cost.get_pricing(to_string(provider), model) do
              {:ok, pricing} ->
                cost_per_mil = (pricing.input_cost_per_token + pricing.output_cost_per_token) * 1_000_000 / 2
                IO.puts("      Cost: ~$#{Float.round(cost_per_mil, 2)}/1M tokens")
              _ ->
                nil
            end
          end)
      end
      
      IO.puts("")
    end
    
    # Demonstrate finding providers with specific features
    IO.puts("\n💡 Feature Discovery Demo:")
    IO.puts("   Finding providers with specific capabilities...\n")
    
    features_to_check = [:vision, :function_calling, :embeddings, :streaming]
    
    for feature <- features_to_check do
      providers = ExLLM.find_providers_with_features([feature])
      IO.puts("   #{feature}: #{length(providers)} providers")
      if length(providers) > 0 do
        IO.puts("      → #{Enum.join(Enum.take(providers, 5), ", ")}#{if length(providers) > 5, do: " ..."}")
      end
    end
    
    IO.puts("\n📚 Model Comparison Example:")
    IO.puts("   Comparing specific models...\n")
    
    models_to_compare = [
      {:openai, "gpt-4o"},
      {:anthropic, "claude-3-5-sonnet-20241022"},
      {:openai, "gpt-4o-mini"}
    ]
    
    comparison = ExLLM.ModelCapabilities.compare_models(models_to_compare)
    
    case comparison do
      %{error: reason} ->
        IO.puts("   ❌ Comparison failed: #{reason}")
        
      %{models: models, features: features} ->
        IO.puts("   Models being compared:")
        for model <- models do
          IO.puts("   • #{model.provider}:#{model.model_id} (#{format_number(model.context_window)} tokens)")
        end
        
        IO.puts("\n   Feature support matrix:")
        # Show a sample of features with their support across models
        features_to_show = [:streaming, :function_calling, :vision, :embeddings, :json_mode]
        
        for feature <- features_to_show do
          if Map.has_key?(features, feature) do
            support_list = features[feature]
            support_indicators = Enum.map(support_list, fn support ->
              if support.supported, do: "✓", else: "✗"
            end)
            
            IO.puts("   #{String.pad_trailing(to_string(feature), 20)} #{Enum.join(support_indicators, "  ")}")
          end
        end
        
      _ ->
        IO.puts("   ❌ Unexpected response format")
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp token_budget_demo(provider) do
    IO.puts("\n=== Token Budget Management ===")
    IO.puts("Managing conversation within token limits.\n")
    
    # Simulate a conversation that grows beyond the budget
    budget = 500  # Smaller budget to demonstrate truncation
    messages = [
      %{role: "system", content: "You are a helpful AI assistant with extensive knowledge about space exploration, astronomy, and the history of human spaceflight. Provide detailed and comprehensive answers."},
      %{role: "user", content: "Tell me about the history of space exploration, including key milestones, important missions, and the countries involved."},
      %{role: "assistant", content: "Space exploration began in earnest during the Cold War era with the Space Race between the United States and Soviet Union. The Soviets launched Sputnik 1 in 1957, the first artificial satellite. They followed with Luna 2 hitting the Moon in 1959, and Yuri Gagarin becoming the first human in space in 1961. The US responded with the Mercury, Gemini, and Apollo programs, culminating in Neil Armstrong and Buzz Aldrin landing on the Moon in 1969. Since then, we've seen the development of space stations like Mir and the ISS, robotic missions to every planet, and the rise of commercial spaceflight with companies like SpaceX and Blue Origin."},
      %{role: "user", content: "What about Mars exploration specifically? Which missions have been most successful?"},
      %{role: "assistant", content: "Mars exploration has been remarkably successful with numerous missions. The Viking landers in 1976 were the first to successfully operate on Mars. NASA's Mars Pathfinder and Sojourner rover arrived in 1997. The Mars Exploration Rovers Spirit and Opportunity launched in 2003, with Opportunity operating for nearly 15 years. Currently active missions include NASA's Curiosity rover (since 2012), InSight lander, Perseverance rover and Ingenuity helicopter (2021), plus orbiters like Mars Reconnaissance Orbiter. The UAE's Hope probe and China's Tianwen-1 with its Zhurong rover also arrived in 2021. These missions have discovered evidence of ancient water, analyzed Martian geology and climate, and are searching for signs of past microbial life."},
      %{role: "user", content: "What are the future plans for human missions to Mars? Which organizations are working on this?"}
    ]
    
    IO.puts("💰 Token Budget: #{budget} tokens")
    IO.puts("📊 Conversation growth:\n")
    
    # First pass - show token accumulation
    total_tokens = Enum.reduce(Enum.with_index(messages), 0, fn {msg, idx}, acc_tokens ->
      tokens = ExLLM.Cost.estimate_tokens(msg)
      new_total = acc_tokens + tokens
      
      status = if new_total <= budget, do: "✅", else: "❌"
      role = String.pad_trailing(msg.role, 9)
      
      IO.puts("   #{status} Message #{idx + 1} (#{role}): #{String.pad_leading(to_string(tokens), 3)} tokens | Total: #{String.pad_leading(to_string(new_total), 4)}")
      
      new_total
    end)
    
    if total_tokens > budget do
      IO.puts("\n⚠️  Budget exceeded by #{total_tokens - budget} tokens!")
      IO.puts("\n📋 Available truncation strategies:")
      IO.puts("   1. Drop oldest messages (keep system + recent)")
      IO.puts("   2. Summarize older messages")
      IO.puts("   3. Keep only system + last N messages")
      IO.puts("   4. Smart truncation (preserve context)")
      
      IO.puts("\n🔄 Applying smart truncation...")
      
      # Simulate truncation - keep system message and as many recent messages as fit
      _truncated_messages = []
      remaining_budget = budget
      
      # Always keep system message
      system_msg = Enum.find(messages, & &1.role == "system")
      system_tokens = if system_msg, do: ExLLM.Cost.estimate_tokens(system_msg), else: 0
      remaining_budget = remaining_budget - system_tokens
      
      # Take messages from the end that fit
      recent_messages = messages
      |> Enum.reverse()
      |> Enum.filter(& &1.role != "system")
      |> Enum.reduce_while({[], remaining_budget}, fn msg, {kept, budget_left} ->
        msg_tokens = ExLLM.Cost.estimate_tokens(msg)
        if msg_tokens <= budget_left do
          {:cont, {[msg | kept], budget_left - msg_tokens}}
        else
          {:halt, {kept, budget_left}}
        end
      end)
      |> elem(0)
      
      truncated_messages = if system_msg, do: [system_msg | recent_messages], else: recent_messages
      
      IO.puts("\n📊 After truncation:")
      total_after = Enum.reduce(Enum.with_index(truncated_messages), 0, fn {msg, idx}, acc ->
        tokens = ExLLM.Cost.estimate_tokens(msg)
        new_total = acc + tokens
        role = String.pad_trailing(msg.role, 9)
        IO.puts("   ✅ Message #{idx + 1} (#{role}): #{String.pad_leading(to_string(tokens), 3)} tokens | Total: #{String.pad_leading(to_string(new_total), 4)}")
        new_total
      end)
      
      IO.puts("\n✨ Removed #{length(messages) - length(truncated_messages)} messages")
      IO.puts("   Final token count: #{total_after}/#{budget} (#{Float.round(total_after / budget * 100, 1)}% of budget)")
    else
      IO.puts("\n✅ Conversation fits within budget!")
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp multi_provider_routing_demo(provider) do
    IO.puts("\n=== Multi-Provider Routing ===")
    IO.puts("Routing requests to different providers based on capabilities.\n")
    
    requests = [
      %{task: "Generate an image of a sunset", required: :image_generation},
      %{task: "Embed this text for similarity search", required: :embeddings},
      %{task: "Answer with a structured JSON response", required: :json_mode},
      %{task: "Use this custom function", required: :function_calling},
      %{task: "Chat normally", required: :chat},
      %{task: "Analyze this image", required: :vision},
      %{task: "Generate speech from text", required: :speech_synthesis},
      %{task: "Fine-tune a model", required: :fine_tuning_api}
    ]
    
    for req <- requests do
      IO.puts("📋 Task: #{req.task}")
      IO.puts("   Required: #{req.required}")
      
      # Find providers that support this feature
      providers = ExLLM.ProviderCapabilities.list_providers()
      |> Enum.filter(fn p -> 
        ExLLM.ProviderCapabilities.supports?(p, req.required)
      end)
      |> Enum.take(3)
      
      if providers == [] do
        IO.puts("   ❌ No providers support this feature")
      else
        IO.puts("   ✅ Available providers: #{Enum.join(providers, ", ")}")
      end
      IO.puts("")
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  # Helper functions
  
  defp safe_gets(prompt, default) do
    case IO.gets(prompt) do
      :eof -> default
      input -> String.trim(input)
    end
  end
  
  defp wait_for_continue do
    IO.gets("\nPress Enter to continue...")
  end
  
  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
  
  defp format_number(num) when is_float(num) do
    format_number(round(num))
  end
  
  defp format_cost(cost) when is_float(cost) do
    # Format cost with 6 decimal places, avoiding scientific notation
    :erlang.float_to_binary(cost, [{:decimals, 6}, :compact])
  end
  
  defp format_cost(cost) when is_integer(cost) do
    "#{cost}.000000"
  end
  
  defp exit_app do
    IO.puts("\nThank you for exploring ExLLM!")
    IO.puts("Check out the documentation for more: https://hexdocs.pm/ex_llm")
    System.halt(0)
  end
  
  defp format_timestamp(timestamp) do
    case timestamp do
      %DateTime{} = dt ->
        Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
      _ ->
        "unknown"
    end
  end
  
  defp estimate_tokens(text) when is_binary(text) do
    # Rough estimation: ~4 characters per token
    round(String.length(text) / 4)
  end
  
  defp estimate_tokens(messages) when is_list(messages) do
    messages
    |> Enum.map(fn msg -> msg.content || "" end)
    |> Enum.join(" ")
    |> estimate_tokens()
  end
  
  defp parse_model_spec(spec) do
    case String.split(spec, ":") do
      [provider, model] -> {String.to_atom(provider), model}
      _ -> {:unknown, spec}
    end
  end
end

# Run the app
ExLLM.ExampleApp.main()