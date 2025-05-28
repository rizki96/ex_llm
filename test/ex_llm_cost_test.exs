defmodule ExLLMCostTest do
  use ExUnit.Case

  describe "cost calculation" do
    test "calculates cost for OpenAI GPT-4o" do
      usage = %{input_tokens: 1000, output_tokens: 500}
      result = ExLLM.calculate_cost(:openai, "gpt-4o", usage)

      assert result.provider == "openai"
      assert result.model == "gpt-4o"
      assert result.input_tokens == 1000
      assert result.output_tokens == 500
      assert result.total_tokens == 1500
      # 1000/1M * 2.50
      assert result.input_cost == 0.0025
      # 500/1M * 10.00
      assert result.output_cost == 0.005
      assert result.total_cost == 0.0075
      assert result.currency == "USD"
    end

    test "calculates cost for Anthropic Claude" do
      usage = %{input_tokens: 2000, output_tokens: 1000}
      result = ExLLM.calculate_cost(:anthropic, "claude-3-5-sonnet-20241022", usage)

      assert result.provider == "anthropic"
      assert result.model == "claude-3-5-sonnet-20241022"
      assert_in_delta result.input_cost, 0.006, 0.0001
      assert_in_delta result.output_cost, 0.015, 0.0001
      assert_in_delta result.total_cost, 0.021, 0.0001
    end

    test "handles unknown provider/model" do
      usage = %{input_tokens: 1000, output_tokens: 500}
      result = ExLLM.calculate_cost(:unknown, "model", usage)

      assert Map.has_key?(result, :error)
      assert result.error == "No pricing data available for unknown/model"
    end
  end

  describe "token estimation" do
    test "estimates tokens for simple text" do
      tokens = ExLLM.estimate_tokens("Hello world")
      assert tokens == 3
    end

    test "estimates tokens for text with punctuation" do
      tokens = ExLLM.estimate_tokens("Hello, world!")
      assert tokens == 4
    end

    test "estimates tokens for empty text" do
      tokens = ExLLM.estimate_tokens("")
      assert tokens == 0
    end

    test "estimates tokens for message map" do
      message = %{content: "Hello world"}
      tokens = ExLLM.estimate_tokens(message)
      assert tokens == 3
    end

    test "estimates tokens for message list" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there"}
      ]

      tokens = ExLLM.estimate_tokens(messages)
      assert tokens == 10
    end
  end

  describe "cost formatting" do
    test "formats small costs correctly" do
      assert ExLLM.format_cost(0.005) == "$0.500¢"
      assert ExLLM.format_cost(0.0035) == "$0.350¢"
    end

    test "formats medium costs correctly" do
      assert ExLLM.format_cost(0.0235) == "$0.0235"
      assert ExLLM.format_cost(0.5) == "$0.5000"
    end

    test "formats large costs correctly" do
      assert ExLLM.format_cost(1.50) == "$1.50"
      assert ExLLM.format_cost(25.99) == "$25.99"
    end
  end
end
