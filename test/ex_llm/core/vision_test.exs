defmodule ExLLM.Core.VisionTest do
  use ExUnit.Case, async: true

  @moduletag capability: :vision
  alias ExLLM.Core.Vision

  @moduledoc """
  Tests for vision and multimodal functionality in ExLLM.

  These tests ensure that image handling works correctly across
  different providers and formats.
  """

  describe "has_vision_content?/1" do
    test "detects messages with image content" do
      message_with_images = %{
        role: "user",
        content: [
          %{type: "text", text: "Look at this"},
          %{type: "image_url", image_url: %{url: "https://example.com/img.jpg"}}
        ]
      }

      assert Vision.has_vision_content?(message_with_images) == true
    end

    test "detects messages with base64 images" do
      message = %{
        role: "user",
        content: [
          %{type: "text", text: "Check this"},
          %{type: "image", image: %{data: "base64data", media_type: "image/png"}}
        ]
      }

      assert Vision.has_vision_content?(message) == true
    end

    test "returns false for text-only messages" do
      text_only = %{role: "user", content: "Just text"}
      assert Vision.has_vision_content?(text_only) == false
    end

    test "returns false for empty content list" do
      assert Vision.has_vision_content?(%{role: "user", content: []}) == false
    end

    test "handles string content correctly" do
      message = %{role: "user", content: "Simple string content"}

      assert Vision.has_vision_content?(message) == false
    end

    test "handles atom types" do
      message = %{
        role: "user",
        content: [
          %{type: :text, text: "Text"},
          %{type: :image_url, image_url: %{url: "https://example.com/img.jpg"}}
        ]
      }

      assert Vision.has_vision_content?(message) == true
    end
  end

  describe "count_images/1" do
    test "counts images in message content" do
      message = %{
        role: "user",
        content: [
          %{type: "text", text: "Two images:"},
          %{type: "image_url", image_url: %{url: "https://example.com/1.jpg"}},
          %{type: "image_url", image_url: %{url: "https://example.com/2.jpg"}}
        ]
      }

      assert Vision.count_images(message) == 2
    end

    test "counts mixed image types" do
      message = %{
        role: "user",
        content: [
          %{type: "image_url", image_url: %{url: "https://example.com/1.jpg"}},
          %{type: "image", image: %{data: "base64", media_type: "image/png"}},
          %{type: :image, image: %{data: "more", media_type: "image/gif"}}
        ]
      }

      assert Vision.count_images(message) == 3
    end

    test "returns 0 for text-only messages" do
      message = %{role: "user", content: "Just text"}
      assert Vision.count_images(message) == 0
    end

    test "returns 0 for empty content" do
      message = %{role: "user", content: []}
      assert Vision.count_images(message) == 0
    end
  end

  describe "normalize_messages/1" do
    test "normalizes atom types to strings" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: :text, text: "Hello"},
            %{type: :image_url, image_url: %{url: "https://example.com/img.jpg"}}
          ]
        }
      ]

      {:ok, normalized} = Vision.normalize_messages(messages)

      assert [%{content: [text_part, image_part]}] = normalized
      assert text_part.type == "text"
      assert image_part.type == "image_url"
    end

    test "preserves already normalized content arrays" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Already normalized"}
          ]
        }
      ]

      {:ok, normalized} = Vision.normalize_messages(messages)
      assert normalized == messages
    end

    test "handles string content" do
      messages = [
        %{role: "user", content: "Simple string"}
      ]

      {:ok, normalized} = Vision.normalize_messages(messages)
      assert normalized == messages
    end

    test "handles mixed content types" do
      messages = [
        %{role: "system", content: "You are helpful"},
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's this?"},
            %{type: "image", image: %{data: "..."}}
          ]
        },
        %{role: "assistant", content: "I see an image"}
      ]

      {:ok, normalized} = Vision.normalize_messages(messages)
      assert length(normalized) == 3
    end

    test "handles errors gracefully" do
      # This would cause an error in normalize_content_part
      invalid_messages = [
        %{
          role: "user",
          content: [
            %{invalid: "structure"}
          ]
        }
      ]

      {:ok, _normalized} = Vision.normalize_messages(invalid_messages)
    end
  end

  describe "format_for_provider/2" do
    test "formats messages for OpenAI provider" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{type: "image_url", image_url: %{url: "https://example.com/image.jpg"}}
          ]
        }
      ]

      # OpenAI format should pass through mostly unchanged
      formatted = Vision.format_for_provider(messages, :openai)
      assert is_list(formatted)
    end

    test "formats messages for Anthropic provider" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Describe this"},
            %{type: "image_url", image_url: %{url: "https://example.com/img.jpg"}}
          ]
        }
      ]

      formatted = Vision.format_for_provider(messages, :anthropic)

      # Anthropic has specific formatting requirements
      assert is_list(formatted)
    end

    test "formats messages for Gemini provider" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What do you see?"},
            %{type: "image", image: %{data: "base64data", media_type: "image/png"}}
          ]
        }
      ]

      formatted = Vision.format_for_provider(messages, :gemini)

      # Gemini has specific formatting requirements
      assert is_list(formatted)
    end

    test "handles providers without special formatting" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Test"},
            %{type: "image_url", image_url: %{url: "https://example.com/test.jpg"}}
          ]
        }
      ]

      # Unknown provider should return messages unchanged
      formatted = Vision.format_for_provider(messages, :unknown_provider)
      assert formatted == messages
    end
  end

  describe "supports_vision?/1" do
    test "returns true for supported providers" do
      assert Vision.supports_vision?(:anthropic) == true
      assert Vision.supports_vision?(:openai) == true
      assert Vision.supports_vision?(:gemini) == true
      assert Vision.supports_vision?(:bedrock) == true
    end

    test "returns false for unsupported providers" do
      assert Vision.supports_vision?(:ollama) == false
      assert Vision.supports_vision?(:groq) == false
      assert Vision.supports_vision?(:unknown) == false
    end
  end

  describe "load_image/2" do
    @tag :tmp_dir
    test "loads and encodes image from file", %{tmp_dir: tmp_dir} do
      # Create a simple test image file
      image_path = Path.join(tmp_dir, "test.png")
      png_data = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82>>
      File.write!(image_path, png_data)

      result = Vision.load_image(image_path)

      assert {:ok, content_part} = result
      assert content_part.type == "image"
      assert content_part.image.media_type == "image/png"
      assert is_binary(content_part.image.data)
    end

    test "handles missing files" do
      result = Vision.load_image("/nonexistent/file.jpg")
      assert {:error, :enoent} = result
    end
  end

  describe "image_url/2" do
    test "creates image URL content part" do
      url = "https://example.com/image.jpg"
      content_part = Vision.image_url(url)

      assert content_part.type == "image_url"
      assert content_part.image_url.url == url
      assert content_part.image_url.detail == :auto
    end

    test "accepts detail option" do
      url = "https://example.com/image.jpg"
      content_part = Vision.image_url(url, detail: :high)

      assert content_part.image_url.detail == :high
    end
  end

  describe "text/1" do
    test "creates text content part" do
      content = "Hello, world!"
      content_part = Vision.text(content)

      assert content_part.type == "text"
      assert content_part.text == content
    end
  end

  describe "build_message/4" do
    test "builds message with text and image URLs" do
      result =
        Vision.build_message("user", "Look at these", [
          "https://example.com/1.jpg",
          "https://example.com/2.jpg"
        ])

      assert {:ok, message} = result
      assert message.role == "user"
      # 1 text + 2 images
      assert length(message.content) == 3
      assert List.first(message.content).type == "text"
    end

    @tag :tmp_dir
    test "builds message with local images", %{tmp_dir: tmp_dir} do
      # Create test image
      image_path = Path.join(tmp_dir, "test.jpg")
      jpeg_data = <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70>>
      File.write!(image_path, jpeg_data)

      result = Vision.build_message("user", "Check this", [image_path])

      assert {:ok, message} = result
      # 1 text + 1 image
      assert length(message.content) == 2
    end

    test "handles multiple image URLs" do
      result =
        Vision.build_message("user", "Multiple images", [
          "https://example.com/web1.jpg",
          "https://example.com/web2.jpg"
        ])

      assert {:ok, message} = result
      # 1 text + 2 images
      assert length(message.content) == 3
    end
  end

  describe "create_message/3" do
    test "creates user message with default role" do
      result = Vision.create_message("What's this?", ["https://example.com/img.jpg"])

      assert {:ok, message} = result
      assert message.role == "user"
    end
  end

  describe "integration scenarios" do
    test "handles complex multimodal conversation" do
      messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{type: "image_url", image_url: %{url: "https://example.com/cat.jpg"}}
          ]
        },
        %{role: "assistant", content: "I see a cat in the image."},
        %{
          role: "user",
          content: [
            %{type: "text", text: "And this one?"},
            %{type: "image", image: %{data: "base64data", media_type: "image/png"}}
          ]
        }
      ]

      # Count vision content
      vision_messages = Enum.filter(messages, &Vision.has_vision_content?/1)
      assert length(vision_messages) == 2

      # Count total images
      total_images =
        Enum.reduce(messages, 0, fn msg, acc ->
          acc + Vision.count_images(msg)
        end)

      assert total_images == 2

      # Test normalization
      assert {:ok, normalized} = Vision.normalize_messages(messages)
      assert length(normalized) == 4

      # Test provider formatting doesn't break the structure
      for provider <- [:openai, :anthropic, :gemini] do
        formatted = Vision.format_for_provider(normalized, provider)
        assert is_list(formatted)
        assert length(formatted) > 0
      end
    end
  end
end
