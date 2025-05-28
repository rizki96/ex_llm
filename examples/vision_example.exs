# Vision/Multimodal Example with ExLLM
#
# This example demonstrates how to use ExLLM's vision capabilities:
# - Analyzing images with text prompts
# - Using both URLs and local files
# - Comparing multiple images
# - Extracting text from images (OCR)
# - Different detail levels for analysis
#
# Run with: mix run examples/vision_example.exs

defmodule VisionExample do
  def run do
    IO.puts("\n🚀 ExLLM Vision/Multimodal Example\n")
    
    # Note: This example uses mock responses. In real usage with actual providers,
    # remove the mock_response options and ensure you have vision-capable models.
    
    # Example 1: Basic Image Analysis
    IO.puts("1️⃣ Basic Image Analysis Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Using image URL
    {:ok, message} = ExLLM.vision_message("What's in this image?", [
      "https://example.com/sample-image.jpg"
    ])
    
    # Mock response for demonstration
    {:ok, response} = ExLLM.chat(:mock, [message],
      mock_response: """
      I can see a beautiful landscape photo showing:
      - A mountain range in the background with snow-capped peaks
      - A crystal-clear lake in the foreground reflecting the mountains
      - Pine trees along the shoreline
      - Clear blue sky with a few white clouds
      The photo appears to be taken during golden hour, giving it warm lighting.
      """
    )
    
    IO.puts("Analysis: #{response.content}")
    
    # Example 2: Local Image File
    IO.puts("\n\n2️⃣ Local Image File Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Create a mock local image for demo
    mock_image_path = "example_chart.png"
    
    # In real usage, this would load an actual file
    {:ok, message} = ExLLM.vision_message(
      "Analyze this chart and extract the key data points",
      [mock_image_path],
      detail: :high  # Use high detail for charts and detailed images
    )
    
    {:ok, response} = ExLLM.chat(:mock, [message],
      mock_response: """
      This bar chart shows quarterly sales data for 2024:
      - Q1: $2.5M (25% growth YoY)
      - Q2: $3.1M (35% growth YoY)
      - Q3: $2.8M (20% growth YoY)
      - Q4: $3.6M (projected, 30% growth YoY)
      
      Total annual revenue: $12M (projected)
      Average quarterly growth: 27.5%
      """
    )
    
    IO.puts("Chart Analysis: #{response.content}")
    
    # Example 3: Multiple Images Comparison
    IO.puts("\n\n3️⃣ Multiple Images Comparison:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    {:ok, message} = ExLLM.vision_message(
      "Compare these two product images and identify the differences",
      ["product_v1.jpg", "product_v2.jpg"]
    )
    
    {:ok, response} = ExLLM.chat(:mock, [message],
      mock_response: """
      Comparing the two product images:
      
      Product V1:
      - Blue color scheme
      - Rounded corners
      - Single button interface
      - Matte finish
      
      Product V2:
      - Gray color scheme  
      - Square corners with chamfered edges
      - Touch screen interface
      - Glossy finish
      - Added LED status indicator
      - 20% smaller form factor
      """
    )
    
    IO.puts("Comparison: #{response.content}")
    
    # Example 4: Text Extraction (OCR)
    IO.puts("\n\n4️⃣ Text Extraction (OCR) Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    {:ok, extracted_text} = ExLLM.extract_text_from_image(:mock, "document.png",
      mock_response: """
      INVOICE #12345
      Date: January 15, 2025
      
      Bill To:
      Acme Corporation
      123 Business Ave
      San Francisco, CA 94105
      
      Items:
      - Widget Pro (10 units) - $500.00
      - Service Fee - $150.00
      
      Subtotal: $650.00
      Tax (8.5%): $55.25
      Total: $705.25
      
      Payment Due: February 15, 2025
      """
    )
    
    IO.puts("Extracted Text:\n#{extracted_text}")
    
    # Example 5: Complex Multimodal Message
    IO.puts("\n\n5️⃣ Complex Multimodal Message:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Build a message with multiple text and image parts
    complex_message = %{
      role: "user",
      content: [
        ExLLM.Vision.text("I'm planning a vacation. Based on these images:"),
        ExLLM.Vision.image_url("https://example.com/beach.jpg", detail: :low),
        ExLLM.Vision.text("versus"),
        ExLLM.Vision.image_url("https://example.com/mountains.jpg", detail: :low),
        ExLLM.Vision.text("Which destination would you recommend for a relaxing week in July?")
      ]
    }
    
    {:ok, response} = ExLLM.chat(:mock, [complex_message],
      mock_response: """
      Based on the images, I'd recommend the beach destination for a relaxing July vacation:
      
      Beach (Image 1):
      ✓ Perfect for July - warm weather, swimming, and sunbathing
      ✓ More relaxing activities - lounging, reading, gentle walks
      ✓ Easier accessibility and less physical demands
      ✓ Beautiful sunsets over the ocean
      
      Mountains (Image 2):
      - Can be hot in July at lower elevations
      - More active vacation - hiking, climbing
      - Requires more physical fitness
      - Better for adventure seekers
      
      For pure relaxation in July, the beach offers the ideal combination of warm weather,
      soothing ocean sounds, and low-key activities.
      """
    )
    
    IO.puts("Recommendation: #{response.content}")
    
    # Example 6: Vision Model Capabilities
    IO.puts("\n\n6️⃣ Vision Model Capabilities Check:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    providers = [:anthropic, :openai, :gemini]
    
    IO.puts("Vision-capable models:")
    Enum.each(providers, fn provider ->
      IO.puts("\n#{provider}:")
      
      # In real usage, this would check actual models
      vision_models = [
        %{name: "claude-3-opus-20240229", vision: true},
        %{name: "gpt-4-turbo", vision: true},
        %{name: "gemini-pro-vision", vision: true}
      ]
      
      Enum.each(vision_models, fn model ->
        if model.vision do
          IO.puts("  ✓ #{model.name}")
        end
      end)
    end)
    
    # Example 7: Image Analysis with Specific Instructions
    IO.puts("\n\n7️⃣ Structured Image Analysis:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    analysis_prompt = """
    Analyze this image and provide:
    1. Main subject
    2. Colors present
    3. Mood/atmosphere
    4. Technical quality
    5. Suggested improvements
    """
    
    {:ok, analysis} = ExLLM.analyze_images(:mock, 
      ["artistic_photo.jpg"],
      analysis_prompt,
      mock_response: """
      1. Main subject: A lone tree silhouetted against a sunset sky
      
      2. Colors present:
         - Deep oranges and reds in the sky
         - Purple and pink clouds
         - Black silhouette of the tree
         - Dark blue transitioning to night at the top
      
      3. Mood/atmosphere: 
         - Serene and contemplative
         - Slightly melancholic
         - End-of-day tranquility
      
      4. Technical quality:
         - Sharp focus on the tree
         - Good exposure balance between sky and foreground
         - Nice composition with rule of thirds
         - High dynamic range captured well
      
      5. Suggested improvements:
         - Could benefit from slight increase in contrast
         - A graduated filter might enhance the sky colors
         - Consider a slightly lower angle to show more foreground detail
      """
    )
    
    IO.puts("Structured Analysis:\n#{analysis}")
    
    # Example 8: Error Handling
    IO.puts("\n\n8️⃣ Error Handling Example:")
    IO.puts("=" <> String.duplicate("=", 50))
    
    # Unsupported format
    result = ExLLM.Vision.load_image("document.pdf")
    case result do
      {:error, :unknown_image_format} ->
        IO.puts("✓ Correctly rejected unsupported format")
      _ ->
        IO.puts("Unexpected result")
    end
    
    # Model without vision support
    if not ExLLM.supports_vision?(:openai, "gpt-3.5-turbo") do
      IO.puts("✓ Correctly identified model without vision support")
    end
    
    IO.puts("\n\n✅ Vision examples completed!")
    IO.puts("\nKey takeaways:")
    IO.puts("- Vision support varies by provider and model")
    IO.puts("- Both URLs and local files are supported")
    IO.puts("- Different detail levels optimize for performance vs accuracy")
    IO.puts("- Multiple images can be analyzed together")
    IO.puts("- OCR and structured analysis are powerful use cases")
  end
end

# Run the examples
VisionExample.run()