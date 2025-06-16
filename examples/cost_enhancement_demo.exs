#!/usr/bin/env elixir

# ExLLM Cost Enhancement Demo
# 
# This script demonstrates the new enhanced cost tracking features 
# implemented in Phase 1 of the cost enhancement specification.

IO.puts("🎯 ExLLM Cost Enhancement Features Demo")
IO.puts("=====================================")

# Demo 1: Enhanced Cost Formatting
IO.puts("\n📊 Enhanced Cost Formatting")
IO.puts("---------------------------")

costs = [0.00123, 0.0456, 0.789, 12.34, 1234.56]

for cost <- costs do
  IO.puts("Cost: #{cost}")
  IO.puts("  Auto:     #{ExLLM.Cost.format(cost, style: :auto)}")
  IO.puts("  Detailed: #{ExLLM.Cost.format(cost, style: :detailed)}")
  IO.puts("  Compact:  #{ExLLM.Cost.format(cost, style: :compact)}")
  IO.puts("  Fixed(3): #{ExLLM.Cost.format(cost, precision: 3)}")
  IO.puts("")
end

# Demo 2: Session Cost Tracking
IO.puts("\n🗂️  Session Cost Tracking")
IO.puts("-------------------------")

# Create a new session
session = ExLLM.Cost.Session.new("demo_session_#{:os.system_time(:second)}")
IO.puts("Created session: #{session.session_id}")

# Simulate some responses with cost data
mock_responses = [
  %{
    cost: %{provider: "openai", model: "gpt-4", total_cost: 0.045},
    usage: %{input_tokens: 150, output_tokens: 75}
  },
  %{
    cost: %{provider: "anthropic", model: "claude-3-5-sonnet", total_cost: 0.032},
    usage: %{input_tokens: 120, output_tokens: 80}
  },
  %{
    cost: %{provider: "openai", model: "gpt-3.5-turbo", total_cost: 0.008},
    usage: %{input_tokens: 200, output_tokens: 50}
  }
]

# Add responses to session
session = 
  Enum.reduce(mock_responses, session, fn response, acc_session ->
    ExLLM.Cost.Session.add_response(acc_session, response)
  end)

IO.puts("\nSession after adding 3 responses:")
IO.puts(ExLLM.Cost.Session.format_summary(session, format: :detailed))

# Demo 3: Different Display Formats
IO.puts("\n🎨 Display Format Options")
IO.puts("-------------------------")

IO.puts("Compact Format:")
IO.puts(ExLLM.Cost.Session.format_summary(session, format: :compact))

IO.puts("\nTable Format:")
IO.puts(ExLLM.Cost.Session.format_summary(session, format: :table))

# Demo 4: Cost Display Utilities
IO.puts("\n🖥️  Cost Display Utilities")
IO.puts("-------------------------")

# CLI Summary
summary = ExLLM.Cost.Session.get_summary(session)
IO.puts(ExLLM.Cost.Display.cli_summary(summary))

# Streaming Cost Display
IO.puts("Streaming Cost Examples:")
IO.puts("  Current: #{ExLLM.Cost.Display.streaming_cost_display(0.023, 0.045)}")
IO.puts("  Compact: #{ExLLM.Cost.Display.streaming_cost_display(0.023, 0.045, style: :compact)}")

# Cost Alerts
IO.puts("\nCost Alert Examples:")
IO.puts("  #{ExLLM.Cost.Display.cost_alert(:budget_exceeded, %{current: 1.25, budget: 1.00, session_id: "demo"})}")
IO.puts("  #{ExLLM.Cost.Display.cost_alert(:high_cost_warning, %{cost: 0.75, model: "gpt-4"})}")
IO.puts("  #{ExLLM.Cost.Display.cost_alert(:efficiency_warning, %{})}")

# Demo 5: Cost Breakdown Tables
IO.puts("\n📋 Cost Breakdown Tables")
IO.puts("------------------------")

# Provider breakdown
provider_data = ExLLM.Cost.Session.provider_breakdown(session)
IO.puts("Provider Breakdown (ASCII):")
IO.puts(ExLLM.Cost.Display.cost_breakdown_table(provider_data, format: :ascii))

IO.puts("\nProvider Breakdown (Markdown):")
IO.puts(ExLLM.Cost.Display.cost_breakdown_table(provider_data, format: :markdown))

# Model breakdown  
model_data = ExLLM.Cost.Session.model_breakdown(session)
IO.puts("\nModel Breakdown (CSV):")
IO.puts(ExLLM.Cost.Display.cost_breakdown_table(model_data, format: :csv))

# Demo 6: Provider Comparison
IO.puts("\n⚖️  Provider Comparison")
IO.puts("----------------------")

comparison_data = [
  %{provider: "openai", model: "gpt-4", cost: 0.045},
  %{provider: "anthropic", model: "claude-3-5-sonnet", cost: 0.032},
  %{provider: "openai", model: "gpt-3.5-turbo", cost: 0.008},
  %{provider: "groq", model: "llama-3.1-8b", cost: 0.002}
]

IO.puts("Cost Comparison Table:")
IO.puts(ExLLM.Cost.Display.comparison_table(comparison_data))

IO.puts("\n✅ Demo Complete!")
IO.puts("================")
IO.puts("Phase 1 cost enhancement features successfully demonstrated:")
IO.puts("  ✓ Enhanced cost formatting with multiple styles")
IO.puts("  ✓ Session-level cost aggregation and tracking")
IO.puts("  ✓ Flexible display utilities with multiple formats")
IO.puts("  ✓ Cost breakdown tables and provider comparisons")
IO.puts("  ✓ Real-time streaming cost displays")
IO.puts("  ✓ Cost alerts and notifications")
IO.puts("\nThese features provide comprehensive cost visibility and analysis")
IO.puts("capabilities for ExLLM users! 🎉")