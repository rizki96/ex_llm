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
      {"Advanced Features Demo", &advanced_features_demo/1, true}
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
          IO.puts("  Total: #{response.usage.total_tokens}")
        end
        
        if response.cost do
          IO.puts("\nCost:")
          IO.puts("  Total: $#{:erlang.float_to_binary(response.cost.total_cost, decimals: 6)}")
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
    supported_providers = [:openai, :anthropic, :gemini]
    
    unless provider in supported_providers do
      IO.puts("⚠️  Structured outputs via Instructor are currently only supported for:")
      IO.puts("   - OpenAI (requires OPENAI_API_KEY)")
      IO.puts("   - Anthropic (requires ANTHROPIC_API_KEY)")
      IO.puts("   - Gemini (requires GOOGLE_API_KEY)")
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
      
      prompt = "Tell me about a fictional character with a name, age, occupation, and hobbies."
      
      IO.puts("Extracting structured data about a person...\n")
      
      # For mock provider, set up response
      if provider == :mock do
        ExLLM.Adapters.Mock.set_response(%{
          content: """
          Meet Sarah Chen, a 32-year-old software engineer who loves hiking, 
          photography, and playing the violin in her spare time.
          """
        })
      end
      
      messages = [%{role: "user", content: prompt}]
      
      # Use the main ExLLM.chat function with response_model option
      case ExLLM.chat(provider, messages, response_model: Person) do
        {:ok, person} ->
          IO.puts("Extracted Person:")
          IO.puts("  Name: #{person.name}")
          IO.puts("  Age: #{person.age}")
          IO.puts("  Occupation: #{person.occupation}")
          IO.puts("  Hobbies: #{Enum.join(person.hobbies, ", ")}")
          
        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
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
    
    # For mock, create fake embeddings
    if provider == :mock do
      # Create somewhat meaningful fake embeddings
      embeddings = Enum.map(documents, fn doc ->
        base = :erlang.phash2(doc) / 1000000
        for _ <- 1..10, do: base + (:rand.uniform() - 0.5) * 0.1
      end)
      
      ExLLM.Adapters.Mock.set_response(%{
        embeddings: embeddings,
        usage: %{input_tokens: 50}
      })
    end
    
    IO.puts("\nGenerating embeddings...")
    
    case ExLLM.embeddings(provider, documents) do
      {:ok, response} ->
        embeddings = response.embeddings
        IO.puts("✓ Generated #{length(embeddings)} embeddings")
        
        # Get search query
        query = IO.gets("\nEnter search query: ") |> String.trim()
        
        # Get query embedding
        if provider == :mock do
          query_emb = for _ <- 1..10, do: :rand.uniform()
          ExLLM.Adapters.Mock.set_response(%{
            embeddings: [query_emb],
            usage: %{input_tokens: 10}
          })
        end
        
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
    
    choice = IO.gets("\nChoice: ") |> String.trim()
    
    case choice do
      "1" -> show_all_provider_capabilities()
      "2" -> find_providers_by_feature()
      "3" -> compare_providers()
      "4" -> get_provider_recommendations()
      "5" -> check_auth_requirements()
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
  
  defp advanced_features_demo(provider) do
    IO.puts("\n=== Advanced Features ===")
    IO.puts("This demonstrates multiple advanced features working together.\n")
    
    # 1. Stream Recovery Demo
    IO.puts("1️⃣  Stream Recovery Demo")
    IO.puts("   Simulating an interrupted stream that recovers...\n")
    
    messages = [%{role: "user", content: "Tell me a short story about resilience in 3 sentences."}]
    
    # For mock provider, set up response
    if provider == :mock do
      ExLLM.Adapters.Mock.set_stream_chunks([
        "Once there was a tiny seed buried deep in concrete. ",
        "Despite the darkness and weight above, it pushed through the smallest crack. ",
        "Years later, a mighty tree stood where once was only stone."
      ])
    end
    
    case ExLLM.stream_chat(provider, messages) do
      {:ok, stream} ->
        IO.puts("Streaming response:")
        IO.write("   ")
        
        # Demonstrate the stream recovery capability
        stream
        |> Stream.each(fn chunk ->
          if chunk.content, do: IO.write(chunk.content)
        end)
        |> Stream.run()
        
        IO.puts("\n\n   ✓ Stream completed successfully")
        IO.puts("   (ExLLM includes automatic recovery for transient errors)")
        
      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
    end
    
    IO.puts("\n")
    wait_for_continue()
    
    # 2. Dynamic Model Selection
    IO.puts("\n2️⃣  Dynamic Model Selection")
    IO.puts("   Automatically choosing the best model for the task...\n")
    
    tasks = [
      {"What's 2+2?", "Fast, simple task → Using smallest/fastest model"},
      {"Write a haiku about coding", "Creative task → Using creative model"},
      {"Analyze this code: def fib(n), do: if n<2, do: n, else: fib(n-1)+fib(n-2)", "Code task → Using code-optimized model"}
    ]
    
    for {task, reasoning} <- tasks do
      IO.puts("📝 Task: #{task}")
      IO.puts("🤖 #{reasoning}")
      
      # Simulate model selection based on task
      selected_model = cond do
        String.contains?(task, "code") -> "codellama"
        String.contains?(task, "haiku") || String.contains?(task, "creative") -> "claude-3-sonnet"
        true -> "gpt-3.5-turbo"
      end
      
      IO.puts("✅ Selected: #{selected_model}\n")
    end
    
    wait_for_continue()
    
    # 3. Token Budget Management
    IO.puts("\n3️⃣  Token Budget Management")
    IO.puts("   Managing conversation within token limits...\n")
    
    # Simulate a conversation that grows
    budget = 1000
    messages = [
      %{role: "system", content: "You are a helpful assistant."},
      %{role: "user", content: "Tell me about space exploration."},
      %{role: "assistant", content: "Space exploration began in the 1950s with the Space Race..."},
      %{role: "user", content: "What about Mars missions?"},
      %{role: "assistant", content: "Mars has been a target for exploration since the 1960s..."},
      %{role: "user", content: "And future plans?"}
    ]
    
    IO.puts("💰 Token Budget: #{budget} tokens")
    IO.puts("📊 Conversation growth:\n")
    
    {_total_tokens, _exceeded_budget} = Enum.reduce_while(Enum.with_index(messages), {0, false}, fn {msg, idx}, {acc_tokens, _exceeded} ->
      tokens = ExLLM.Cost.estimate_tokens(msg)
      new_total = acc_tokens + tokens
      
      status = if new_total <= budget, do: "✅", else: "❌"
      role = String.pad_trailing(msg.role, 9)
      
      IO.puts("   #{status} Message #{idx + 1} (#{role}): #{tokens} tokens | Total: #{new_total}")
      
      if new_total > budget do
        IO.puts("\n⚠️  Exceeded budget! Applying truncation strategy...")
        IO.puts("   → Removing oldest messages to fit within budget")
        {:halt, {new_total, true}}
      else
        {:cont, {new_total, false}}
      end
    end)
    
    wait_for_continue()
    
    # 4. Multi-Provider Routing
    IO.puts("\n4️⃣  Multi-Provider Routing")
    IO.puts("   Routing requests to different providers based on capabilities...\n")
    
    requests = [
      %{task: "Generate an image of a sunset", required: :image_generation},
      %{task: "Embed this text for similarity search", required: :embeddings},
      %{task: "Answer with a structured JSON response", required: :json_mode},
      %{task: "Use this custom function", required: :function_calling},
      %{task: "Chat normally", required: :chat}
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
  
  defp safe_gets(prompt, default \\ "") do
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