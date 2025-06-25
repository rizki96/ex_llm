defmodule ExLLM.Pipeline.RequestTest do
  use ExUnit.Case, async: true
  alias ExLLM.Pipeline.Request

  describe "new/3" do
    test "accepts map as options" do
      messages = [%{role: "user", content: "Hello"}]
      options = %{temperature: 0.5, model: "gpt-4"}

      request = Request.new(:openai, messages, options)

      assert request.provider == :openai
      assert request.messages == messages
      assert request.options == options
      assert request.state == :pending
    end

    test "accepts keyword list as options" do
      messages = [%{role: "user", content: "Hello"}]
      options = [temperature: 0.5, model: "gpt-4"]

      request = Request.new(:openai, messages, options)

      assert request.provider == :openai
      assert request.messages == messages
      # Options should be normalized to a map
      assert request.options == %{temperature: 0.5, model: "gpt-4"}
      assert request.state == :pending
    end

    test "handles empty options" do
      messages = [%{role: "user", content: "Hello"}]

      request = Request.new(:openai, messages)

      assert request.options == %{}
    end

    test "handles nil options" do
      messages = [%{role: "user", content: "Hello"}]

      request = Request.new(:openai, messages, nil)

      assert request.options == %{}
    end

    test "generates unique IDs" do
      messages = [%{role: "user", content: "Hello"}]

      request1 = Request.new(:openai, messages)
      request2 = Request.new(:openai, messages)

      assert request1.id != request2.id
    end
  end

  describe "normalize_options/1" do
    test "preserves map options" do
      options = %{temperature: 0.5, model: "gpt-4"}
      request = Request.new(:openai, [], options)
      assert request.options == options
    end

    test "converts keyword list to map" do
      options = [temperature: 0.5, model: "gpt-4"]
      request = Request.new(:openai, [], options)
      assert request.options == %{temperature: 0.5, model: "gpt-4"}
    end

    test "handles mixed keyword list with duplicate keys" do
      # Last value wins when converting keyword list to map
      options = [temperature: 0.5, model: "gpt-4", temperature: 0.7]
      request = Request.new(:openai, [], options)
      assert request.options == %{temperature: 0.7, model: "gpt-4"}
    end

    test "handles invalid input gracefully" do
      request = Request.new(:openai, [], "invalid")
      assert request.options == %{}

      request = Request.new(:openai, [], 123)
      assert request.options == %{}

      request = Request.new(:openai, [], [:not, :a, :keyword, :list])
      assert request.options == %{}
    end
  end

  describe "backwards compatibility" do
    test "existing code using keyword lists continues to work" do
      # This simulates how chat.ex uses Request.new
      messages = [%{role: "user", content: "Test"}]
      options = [temperature: 0.5, stream: true]
      options = Keyword.put(options, :model, "gpt-4")

      request = Request.new(:openai, messages, options)

      assert request.options.temperature == 0.5
      assert request.options.stream == true
      assert request.options.model == "gpt-4"
    end

    test "options can be accessed as a map after normalization" do
      options = [temperature: 0.5, model: "gpt-4"]
      request = Request.new(:openai, [], options)

      # All map operations should work
      assert Map.get(request.options, :temperature) == 0.5
      assert Map.keys(request.options) == [:model, :temperature]
      assert map_size(request.options) == 2
    end
  end
end
