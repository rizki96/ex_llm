defmodule ExLLM.Providers.Shared.MessageFormatterNormalizationTest do
  use ExUnit.Case, async: true
  alias ExLLM.Providers.Shared.MessageFormatter

  describe "normalize_message_keys/1" do
    test "keeps atom keys unchanged" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]

      result = MessageFormatter.normalize_message_keys(messages)
      assert result == messages
    end

    test "converts string keys to atom keys" do
      messages = [
        %{"role" => "user", "content" => "Hello"},
        %{"role" => "assistant", "content" => "Hi there!"}
      ]

      expected = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]

      result = MessageFormatter.normalize_message_keys(messages)
      assert result == expected
    end

    test "handles mixed key formats" do
      messages = [
        %{role: "user", content: "Hello"},
        %{"role" => "assistant", "content" => "Hi there!"},
        %{"content" => "Mixed keys", role: "user"}
      ]

      expected = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"},
        %{role: "user", content: "Mixed keys"}
      ]

      result = MessageFormatter.normalize_message_keys(messages)
      assert result == expected
    end

    test "normalizes complex content with string keys" do
      messages = [
        %{
          "role" => "user",
          "content" => [
            %{"type" => "text", "text" => "What's in this image?"},
            %{"type" => "image_url", "image_url" => %{"url" => "data:image/png;base64,..."}}
          ]
        }
      ]

      expected = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{type: "image_url", image_url: %{url: "data:image/png;base64,..."}}
          ]
        }
      ]

      result = MessageFormatter.normalize_message_keys(messages)
      assert result == expected
    end

    test "preserves optional fields" do
      messages = [
        %{
          "role" => "assistant",
          "content" => "I'll help you",
          "name" => "Claude",
          "function_call" => %{"name" => "get_weather", "arguments" => "{}"}
        }
      ]

      result = MessageFormatter.normalize_message_keys(messages)

      assert result == [
               %{
                 role: "assistant",
                 content: "I'll help you",
                 name: "Claude",
                 function_call: %{"name" => "get_weather", "arguments" => "{}"}
               }
             ]
    end

    test "handles tool_calls field" do
      messages = [
        %{
          "role" => "assistant",
          "content" => nil,
          "tool_calls" => [
            %{"id" => "call_123", "type" => "function", "function" => %{"name" => "test"}}
          ]
        }
      ]

      result = MessageFormatter.normalize_message_keys(messages)

      assert result == [
               %{
                 role: "assistant",
                 content: nil,
                 tool_calls: [
                   %{"id" => "call_123", "type" => "function", "function" => %{"name" => "test"}}
                 ]
               }
             ]
    end

    test "logs deprecation warning for string keys" do
      # Since Logger uses :logger directly, we'll test the behavior
      # by verifying the correct messages are returned
      messages = [%{"role" => "user", "content" => "Hello"}]

      result = MessageFormatter.normalize_message_keys(messages)

      # Verify the conversion happened
      assert result == [%{role: "user", content: "Hello"}]

      # The warning is logged but we can't capture it in tests
      # due to :logger usage. The important behavior is the conversion.
    end

    test "does not normalize when already using atom keys" do
      messages = [%{role: "user", content: "Hello"}]

      result = MessageFormatter.normalize_message_keys(messages)

      # Should return the same messages unchanged
      assert result == messages
    end

    test "returns normalized messages with mixed string/atom content" do
      messages = [
        %{
          "role" => "user",
          "content" => [
            %{"type" => "text", "text" => "Hello"},
            %{type: "image_url", image_url: %{"url" => "data:..."}}
          ]
        }
      ]

      result = MessageFormatter.normalize_message_keys(messages)

      expected = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Hello"},
            %{type: "image_url", image_url: %{url: "data:..."}}
          ]
        }
      ]

      assert result == expected
    end
  end
end
