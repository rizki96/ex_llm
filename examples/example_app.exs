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

Mix.install([
  {:ex_llm, path: ".."},
  {:req, "~> 0.3"},
  {:jason, "~> 1.4"}
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
      model: "hf.co/unsloth/Qwen3-8B-GGUF:IQ4_XS",
      name: "Ollama (Local) - Qwen3 8B",
      setup: """
      To use Ollama:
      1. Install Ollama: https://ollama.ai
      2. Ensure Ollama is running
      3. Model already available: hf.co/unsloth/Qwen3-8B-GGUF:IQ4_XS (4.6 GB)
      """
    },
    openai: %{
      model: "gpt-4o-mini",
      name: "OpenAI",
      env_var: "OPENAI_API_KEY",
      setup: "Set OPENAI_API_KEY environment variable"
    },
    anthropic: %{
      model: "claude-3-5-sonnet-20241022",
      name: "Anthropic Claude",
      env_var: "ANTHROPIC_API_KEY", 
      setup: "Set ANTHROPIC_API_KEY environment variable"
    },
    groq: %{
      model: "llama-3.3-70b-versatile",
      name: "Groq (Fast Cloud)",
      env_var: "GROQ_API_KEY",
      setup: "Set GROQ_API_KEY environment variable"
    },
    mock: %{
      model: "mock-model",
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
    IO.puts("Model: #{config.model}")
    
    # Show provider capabilities
    case ExLLM.ProviderCapabilities.get_capabilities(provider) do
      {:ok, caps} ->
        IO.puts("\nProvider Capabilities:")
        IO.puts("  Endpoints: #{Enum.join(caps.endpoints, ", ")}")
        features = Enum.take(caps.features, 5)
        more = length(caps.features) - 5
        if more > 0 do
          IO.puts("  Features: #{Enum.join(features, ", ")} (+#{more} more)")
        else
          IO.puts("  Features: #{Enum.join(features, ", ")}")
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
      IO.puts("│ #{String.pad_trailing(" #{num}. #{label}", 60)}│")
    end)
    
    IO.puts("""
    │                                                            │
    │  0. Exit                                                   │
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
    # Always available features
    items = [
      {"1", "Basic Chat", &basic_chat/1},
      {"3", "Session Management (Conversation History)", &session_management/1},
      {"4", "Context Management (Token Limits)", &context_management/1},
      {"9", "Model Capabilities Explorer", &model_capabilities_explorer/1},
      {"10", "Caching Demo", &caching_demo/1},
      {"11", "Retry & Error Recovery", &retry_demo/1}
    ]
    
    # Conditionally add features based on capabilities
    items = if capabilities && :streaming in capabilities.features do
      items ++ [{"2", "Streaming Chat", &streaming_chat/1}]
    else
      items
    end
    
    items = if capabilities && :function_calling in capabilities.features do
      items ++ [{"5", "Function Calling", &function_calling_demo/1}]
    else
      items
    end
    
    items = if capabilities do
      items ++ [{"6", "Structured Output (Instructor)", &structured_output_demo/1}]
    else
      items
    end
    
    items = if capabilities && :vision in capabilities.features do
      items ++ [{"7", "Vision/Multimodal (Analyze Images)", &vision_demo/1}]
    else
      items
    end
    
    items = if capabilities && :embeddings in capabilities.endpoints do
      items ++ [{"8", "Embeddings & Semantic Search", &embeddings_demo/1}]
    else
      items
    end
    
    items = if capabilities && :cost_tracking in capabilities.features do
      items ++ [{"12", "Cost Tracking", &cost_tracking_demo/1}]
    else
      items
    end
    
    items = items ++ [{"13", "Advanced Features Demo", &advanced_features_demo/1}]
    
    # Sort by number
    Enum.sort_by(items, fn {num, _, _} -> 
      {n, _} = Integer.parse(num)
      n
    end)
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
        for chunk <- stream do
          if chunk.content do
            IO.write(chunk.content)
          end
        end
        IO.puts("\n")
        
      {:error, error} ->
        IO.puts("\nError: #{inspect(error)}")
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp session_management(provider) do
    IO.puts("\n=== Session Management ===")
    IO.puts("This demonstrates conversation history and context preservation.\n")
    
    # Create a new session
    session = Session.new(to_string(provider), name: "Example Conversation")
    
    IO.puts("Created session: #{session.id}")
    IO.puts("Let's have a multi-turn conversation. Type 'exit' to end.\n")
    
    session = chat_loop(session, provider)
    
    # Show session summary
    IO.puts("\n=== Session Summary ===")
    IO.puts("Total messages: #{length(session.messages)}")
    IO.puts("Total tokens used: #{session.token_usage.input_tokens + session.token_usage.output_tokens}")
    
    # Save session
    case Session.save_to_file(session, "example_session.json") do
      :ok -> IO.puts("Session saved to example_session.json")
      {:error, reason} -> IO.puts("Failed to save session: #{inspect(reason)}")
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp chat_loop(session, provider) do
    input = IO.gets("You: ") |> String.trim()
    
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
          response_content = 
            stream
            |> Enum.map(fn chunk -> chunk.content || "" end)
            |> Enum.join("")
          
          IO.puts("")
          
          # Add assistant response to session
          session = Session.add_message(session, "assistant", response_content)
          
          # Update token usage (in real app, would get from response)
          session = Session.update_token_usage(session, %{
            input_tokens: estimate_tokens(messages),
            output_tokens: estimate_tokens(response_content)
          })
          
          chat_loop(session, provider)
          
        {:error, error} ->
          IO.puts("\nError: #{inspect(error)}")
          session
      end
    end
  end
  
  defp context_management(provider) do
    IO.puts("\n=== Context Management ===")
    IO.puts("This demonstrates handling of context windows and message truncation.\n")
    
    model = @provider_configs[provider].model
    
    # Get context window size
    context_window = Context.get_context_window(provider, model)
    IO.puts("Model #{model} has a context window of #{context_window} tokens")
    
    # Create a long conversation
    messages = [
      %{role: "system", content: "You are a helpful assistant."},
      %{role: "user", content: "Tell me a very long story about space exploration."},
      %{role: "assistant", content: String.duplicate("Once upon a time in space... ", 100)},
      %{role: "user", content: "Continue the story with more details."},
      %{role: "assistant", content: String.duplicate("The astronauts discovered... ", 100)},
      %{role: "user", content: "What happened next?"}
    ]
    
    # Check if messages fit
    case Context.validate_context(messages, provider, model) do
      {:ok, token_count} ->
        IO.puts("Messages fit within context: #{token_count} tokens")
        
      {:error, reason} ->
        IO.puts("Messages exceed context: #{reason}")
        
        # Truncate messages
        IO.puts("\nTruncating messages using sliding window strategy...")
        truncated = Context.truncate_messages(messages, provider, model, strategy: :sliding_window)
        
        IO.puts("Truncated to #{length(truncated)} messages")
        
        # Show what was kept
        IO.puts("\nKept messages:")
        Enum.each(truncated, fn msg ->
          preview = String.slice(msg.content, 0, 50)
          IO.puts("  #{msg.role}: #{preview}...")
        end)
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp function_calling_demo(provider) do
    IO.puts("\n=== Function Calling ===")
    IO.puts("This demonstrates how to use function calling with LLMs.\n")
    
    # This should only be called if provider supports it, but double-check
    if not ExLLM.ProviderCapabilities.supports?(provider, :function_calling) do
      IO.puts("⚠️  #{provider} doesn't support function calling.")
      wait_for_continue()
    else
    
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
        description: "Perform a mathematical calculation",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "expression" => %{
              "type" => "string",
              "description" => "Mathematical expression to evaluate"
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
        if function_call = Map.get(response, :function_call) do
          IO.puts("\nLLM wants to call function: #{function_call.name}")
          IO.puts("Arguments: #{function_call.arguments}")
          
          # Parse and validate arguments
          case FunctionCalling.parse_arguments(function_call.arguments) do
            {:ok, args} ->
              IO.puts("\nExecuting function...")
              
              # Execute function
              handler = function_handlers[function_call.name]
              result = handler.(args)
              
              IO.puts("Function result: #{result}")
              
              # Continue conversation with function result
              messages = messages ++ [
                %{role: "assistant", content: nil, function_call: function_call},
                %{role: "function", name: function_call.name, content: result}
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
          IO.puts("\nDirect response: #{response.content}")
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
    
    # Check if Instructor is available
    if ExLLM.Instructor.available?() do
      # Define a schema
      defmodule Person do
        use Ecto.Schema
        import Ecto.Changeset
        
        embedded_schema do
          field :name, :string
          field :age, :integer
          field :occupation, :string
          field :hobbies, {:array, :string}
        end
        
        def changeset(person, attrs) do
          person
          |> cast(attrs, [:name, :age, :occupation, :hobbies])
          |> validate_required([:name])
          |> validate_number(:age, greater_than: 0, less_than: 150)
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
      
      case ExLLM.Instructor.chat(provider, prompt, Person) do
        {:ok, person} ->
          IO.puts("Extracted Person:")
          IO.puts("  Name: #{person.name}")
          IO.puts("  Age: #{person.age}")
          IO.puts("  Occupation: #{person.occupation}")
          IO.puts("  Hobbies: #{Enum.join(person.hobbies, ", ")}")
          
        {:error, error} ->
          IO.puts("Error: #{inspect(error)}")
      end
    else
      IO.puts("⚠️  Instructor is not available. Add {:instructor, \"~> 0.0.5\"} to your dependencies.")
    end
    
    wait_for_continue() 
    main_menu(provider)
  end
  
  defp vision_demo(provider) do
    IO.puts("\n=== Vision/Multimodal ===")
    IO.puts("This demonstrates image analysis capabilities.\n")
    
    # Check if provider supports vision
    model = @provider_configs[provider].model
    
    unless ExLLM.Vision.supports_vision?(provider, model) do
      IO.puts("⚠️  Model #{model} doesn't support vision.")
      IO.puts("Vision-capable models: gpt-4o, claude-3-5-sonnet, gemini-pro-vision")
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
        model: "text-embedding-ada-002",
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
            model: "text-embedding-ada-002", 
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
    model = @provider_configs[provider].model
    
    case ModelCapabilities.get_model_info(provider, model) do
      {:ok, info} ->
        IO.puts("\nCapabilities for #{model}:")
        IO.puts("  Context window: #{info.context_window} tokens")
        IO.puts("  Max output: #{info.max_tokens} tokens")
        IO.puts("  Features: #{Enum.join(info.features, ", ")}")
        
        if info.released do
          IO.puts("  Released: #{info.released}")
        end
        
      {:error, _} ->
        IO.puts("Model information not available")
    end
  end
  
  defp find_models_by_feature do
    IO.puts("\nAvailable features:")
    features = ModelCapabilities.list_model_features()
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
      max_results: 5
    )
    
    IO.puts("\nRecommended models:")
    Enum.each(recommendations, fn {{provider, model}, score} ->
      IO.puts("  #{provider}:#{model} (score: #{score})")
    end)
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
          },
          model: "mock-model"
        })
      end
      
      new_cost = case ExLLM.chat(provider, messages) do
        {:ok, response} ->
          if response.cost do
            cost_usd = response.cost.total_usd
            
            IO.puts("Response: #{String.slice(response.content, 0, 50)}...")
            IO.puts("Tokens: #{response.usage.input_tokens} in, #{response.usage.output_tokens} out")
            IO.puts("Cost: $#{Float.round(cost_usd, 6)}")
            
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
    IO.puts("Total cost for #{length(prompts)} requests: $#{Float.round(total_cost, 6)}")
    
    end
    
    wait_for_continue()
    main_menu(provider)
  end
  
  defp advanced_features_demo(provider) do
    IO.puts("\n=== Advanced Features ===")
    IO.puts("This demonstrates multiple advanced features working together.\n")
    
    IO.puts("Features to demonstrate:")
    IO.puts("1. Stream recovery (resume interrupted streams)")
    IO.puts("2. Dynamic model selection")
    IO.puts("3. Token budget management")
    IO.puts("4. Multi-provider routing")
    
    IO.puts("\nNote: These are advanced features that would be implemented")
    IO.puts("in a production application. This demo shows the concepts.")
    
    wait_for_continue()
    main_menu(provider)
  end
  
  # Helper functions
  
  defp wait_for_continue do
    IO.gets("\nPress Enter to continue...")
  end
  
  defp exit_app do
    IO.puts("\nThank you for exploring ExLLM!")
    IO.puts("Check out the documentation for more: https://hexdocs.pm/ex_llm")
    System.halt(0)
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