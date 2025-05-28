# Model Capability Discovery Example
#
# This example demonstrates how to discover and compare model capabilities

defmodule ModelCapabilityDemo do
  def run do
    IO.puts("\n=== Model Capability Discovery Demo ===\n")
    
    # 1. Check specific model capabilities
    check_model_capabilities()
    
    # 2. Find models with specific features
    find_models_by_features()
    
    # 3. Compare models
    compare_multiple_models()
    
    # 4. Get recommendations
    get_model_recommendations()
    
    # 5. Group by capability
    show_capability_groups()
  end
  
  defp check_model_capabilities do
    IO.puts("1. Checking Model Capabilities")
    IO.puts("=" |> String.duplicate(40))
    
    models = [
      {:openai, "gpt-4-turbo"},
      {:anthropic, "claude-3-5-sonnet-20241022"},
      {:gemini, "gemini-pro-vision"},
      {:local, "microsoft/phi-2"}
    ]
    
    Enum.each(models, fn {provider, model} ->
      case ExLLM.get_model_info(provider, model) do
        {:ok, info} ->
          IO.puts("\n#{info.display_name} (#{provider}:#{model})")
          IO.puts("  Context Window: #{format_number(info.context_window)} tokens")
          IO.puts("  Max Output: #{info.max_output_tokens || "N/A"} tokens")
          
          # Check key features
          features = [:vision, :function_calling, :streaming, :context_caching]
          IO.puts("  Capabilities:")
          Enum.each(features, fn feature ->
            supported = ExLLM.model_supports?(provider, model, feature)
            status = if supported, do: "✓", else: "✗"
            IO.puts("    #{status} #{feature}")
          end)
          
        {:error, :not_found} ->
          IO.puts("\n#{provider}:#{model} - Not found in capability database")
      end
    end)
  end
  
  defp find_models_by_features do
    IO.puts("\n\n2. Finding Models by Features")
    IO.puts("=" |> String.duplicate(40))
    
    # Find models with vision capabilities
    IO.puts("\nModels with vision support:")
    vision_models = ExLLM.find_models_with_features([:vision])
    Enum.each(vision_models, fn {provider, model} ->
      IO.puts("  - #{provider}:#{model}")
    end)
    
    # Find models with both vision and function calling
    IO.puts("\nModels with vision AND function calling:")
    advanced_models = ExLLM.find_models_with_features([:vision, :function_calling])
    Enum.each(advanced_models, fn {provider, model} ->
      {:ok, info} = ExLLM.get_model_info(provider, model)
      IO.puts("  - #{info.display_name} (#{provider}:#{model})")
    end)
    
    # Find models with large context windows
    IO.puts("\nModels with 100k+ context window:")
    large_context = ExLLM.find_models_with_features([:streaming])
    |> Enum.filter(fn {provider, model} ->
      {:ok, info} = ExLLM.get_model_info(provider, model)
      info.context_window >= 100_000
    end)
    |> Enum.each(fn {provider, model} ->
      {:ok, info} = ExLLM.get_model_info(provider, model)
      IO.puts("  - #{info.display_name}: #{format_number(info.context_window)} tokens")
    end)
  end
  
  defp compare_multiple_models do
    IO.puts("\n\n3. Comparing Models")
    IO.puts("=" |> String.duplicate(40))
    
    models_to_compare = [
      {:openai, "gpt-4-turbo"},
      {:anthropic, "claude-3-5-sonnet-20241022"},
      {:gemini, "gemini-pro"}
    ]
    
    comparison = ExLLM.compare_models(models_to_compare)
    
    IO.puts("\nModel Comparison:")
    IO.puts("─" |> String.duplicate(80))
    
    # Print model names
    IO.write(String.pad_trailing("Feature", 20))
    Enum.each(comparison.models, fn model ->
      name = String.slice(model.display_name, 0, 15)
      IO.write(" | " <> String.pad_trailing(name, 15))
    end)
    IO.puts("")
    IO.puts("─" |> String.duplicate(80))
    
    # Print feature support
    features = [:vision, :function_calling, :streaming, :json_mode, :context_caching]
    Enum.each(features, fn feature ->
      IO.write(String.pad_trailing(to_string(feature), 20))
      
      support_list = Map.get(comparison.features, feature, [])
      Enum.each(support_list, fn support ->
        status = if support.supported, do: "✓", else: "✗"
        IO.write(" | " <> String.pad_trailing(status, 15))
      end)
      IO.puts("")
    end)
    
    # Print context windows
    IO.puts("─" |> String.duplicate(80))
    IO.write(String.pad_trailing("Context Window", 20))
    Enum.each(comparison.models, fn model ->
      ctx = format_number(model.context_window)
      IO.write(" | " <> String.pad_trailing(ctx, 15))
    end)
    IO.puts("")
  end
  
  defp get_model_recommendations do
    IO.puts("\n\n4. Model Recommendations")
    IO.puts("=" |> String.duplicate(40))
    
    # Recommend for vision tasks
    IO.puts("\nBest models for vision tasks:")
    vision_recs = ExLLM.recommend_models(
      features: [:vision, :streaming],
      min_context_window: 10_000,
      limit: 3
    )
    
    Enum.with_index(vision_recs, 1)
    |> Enum.each(fn {{provider, model, %{score: score}}, idx} ->
      {:ok, info} = ExLLM.get_model_info(provider, model)
      IO.puts("  #{idx}. #{info.display_name} (score: #{Float.round(score, 1)})")
      IO.puts("     Context: #{format_number(info.context_window)}, Provider: #{provider}")
    end)
    
    # Recommend for budget-conscious users
    IO.puts("\nBest models for basic chat (low cost):")
    budget_recs = ExLLM.recommend_models(
      features: [:multi_turn, :system_messages],
      prefer_local: true,
      limit: 3
    )
    
    Enum.with_index(budget_recs, 1)
    |> Enum.each(fn {{provider, model, %{score: score}}, idx} ->
      {:ok, info} = ExLLM.get_model_info(provider, model)
      local_tag = if provider == :local, do: " [LOCAL]", else: ""
      IO.puts("  #{idx}. #{info.display_name}#{local_tag} (score: #{Float.round(score, 1)})")
    end)
  end
  
  defp show_capability_groups do
    IO.puts("\n\n5. Models by Capability")
    IO.puts("=" |> String.duplicate(40))
    
    # Show vision capability grouping
    vision_groups = ExLLM.models_by_capability(:vision)
    
    IO.puts("\nVision Support:")
    IO.puts("  Supported (#{length(vision_groups.supported)}):")
    vision_groups.supported
    |> Enum.take(5)
    |> Enum.each(fn {provider, model} ->
      IO.puts("    - #{provider}:#{model}")
    end)
    if length(vision_groups.supported) > 5 do
      IO.puts("    ... and #{length(vision_groups.supported) - 5} more")
    end
    
    IO.puts("  Not Supported (#{length(vision_groups.not_supported)}):")
    vision_groups.not_supported
    |> Enum.take(3)
    |> Enum.each(fn {provider, model} ->
      IO.puts("    - #{provider}:#{model}")
    end)
    
    # List all features
    IO.puts("\n\nAll tracked features:")
    features = ExLLM.list_model_features()
    features
    |> Enum.chunk_every(3)
    |> Enum.each(fn chunk ->
      formatted = chunk
      |> Enum.map(&String.pad_trailing(to_string(&1), 20))
      |> Enum.join(" ")
      IO.puts("  #{formatted}")
    end)
  end
  
  defp format_number(num) when num >= 1_000_000 do
    "#{div(num, 1_000_000)}M"
  end
  defp format_number(num) when num >= 1_000 do
    "#{div(num, 1_000)}k"
  end
  defp format_number(num), do: to_string(num)
end

# Run the demo
IO.puts("""
Model Capability Discovery
==========================

This example demonstrates ExLLM's model capability discovery features:

1. Query individual model capabilities
2. Find models by required features
3. Compare multiple models side-by-side
4. Get recommendations based on requirements
5. Group models by capability

This helps you:
- Choose the right model for your use case
- Understand feature availability across providers
- Make cost-effective decisions
- Plan for feature requirements
""")

ModelCapabilityDemo.run()

IO.puts("\n\nTip: Use these APIs in your application to dynamically select models based on requirements!")