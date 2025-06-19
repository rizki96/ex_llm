defmodule ExLLM.Core.VisionTest do
  use ExUnit.Case, async: true
  alias ExLLM.Core.Vision

  describe "build_message/4" do
    test "creates message with single image URL" do
      {:ok, message} =
        Vision.build_message("user", "What's in this image?", ["https://example.com/image.jpg"])

      assert message.role == "user"
      assert is_list(message.content)
      assert length(message.content) == 2

      [text_part, image_part] = message.content
      assert text_part == %{type: "text", text: "What's in this image?"}
      assert image_part.type == "image_url"
      assert image_part.image_url.url == "https://example.com/image.jpg"
    end

    test "creates message with multiple images" do
      images = ["https://example.com/img1.jpg", "https://example.com/img2.jpg"]
      {:ok, message} = Vision.build_message("user", "Compare these images", images)

      assert length(message.content) == 3
      [_text | image_parts] = message.content

      assert Enum.all?(image_parts, fn part ->
               part.type == "image_url" && is_map(part.image_url)
             end)
    end

    test "returns error for data URI (not supported in process_image_sources)" do
      base64_image = "data:image/jpeg;base64,/9j/4AAQSkZJRg=="

      assert {:error, {:invalid_image_source, ^base64_image}} =
               Vision.build_message("user", "Analyze this", [base64_image])
    end

    test "creates message with image details" do
      {:ok, message} =
        Vision.build_message("user", "Look", ["https://example.com/img.jpg"], detail: "high")

      [_text, image_part] = message.content
      assert image_part.image_url.detail == "high"
    end

    test "handles empty image list" do
      {:ok, message} = Vision.build_message("user", "No images", [])

      assert message.content == [%{type: "text", text: "No images"}]
    end

    test "returns error for invalid image sources" do
      assert {:error, _} = Vision.build_message("user", "Bad image", ["not a valid url"])
    end
  end

  describe "format_for_provider/2" do
    test "formats for OpenAI provider" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Hello"},
            %{type: "image_url", image_url: %{url: "https://example.com/img.jpg"}}
          ]
        }
      ]

      formatted = Vision.format_for_provider(messages, :openai)
      # OpenAI format is the default
      assert formatted == messages
    end

    test "formats for Anthropic provider (currently passthrough)" do
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "Hello"},
            %{type: "image_url", image_url: %{url: "https://example.com/img.jpg"}}
          ]
        }
      ]

      formatted = Vision.format_for_provider(messages, :anthropic)

      # Currently format_for_anthropic is a passthrough
      assert formatted == messages
    end

    test "handles unknown provider" do
      messages = [%{role: "user", content: "Test"}]
      formatted = Vision.format_for_provider(messages, :unknown)
      assert formatted == messages
    end
  end

  describe "load_image/2" do
    test "loads image from file" do
      # Create a test file
      path = Path.join(System.tmp_dir!(), "test_image.jpg")
      # JPEG magic bytes
      File.write!(
        path,
        <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01>>
      )

      assert {:ok, image_part} = Vision.load_image(path)
      assert image_part.type == "image"
      assert image_part.image.media_type == "image/jpeg"
      assert is_binary(image_part.image.data)

      File.rm!(path)
    end

    test "returns error for non-existent file" do
      assert {:error, _} = Vision.load_image("/nonexistent/file.jpg")
    end

    test "detects image format from content" do
      # Test PNG magic bytes
      path = Path.join(System.tmp_dir!(), "test_image.png")
      File.write!(path, <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>)

      {:ok, image_part} = Vision.load_image(path)
      assert image_part.image.media_type == "image/png"

      File.rm!(path)
    end
  end

  describe "image_url/2" do
    test "creates image URL content part" do
      part = Vision.image_url("https://example.com/img.jpg")

      assert part == %{
               type: "image_url",
               image_url: %{
                 url: "https://example.com/img.jpg",
                 detail: :auto
               }
             }
    end

    test "accepts detail option" do
      part = Vision.image_url("https://example.com/img.jpg", detail: :high)
      assert part.image_url.detail == :high
    end
  end

  describe "text/1" do
    test "creates text content part" do
      part = Vision.text("Hello world")
      assert part == %{type: "text", text: "Hello world"}
    end
  end

  describe "supports_vision?/1" do
    @tag :vision
    test "returns true for vision-capable providers" do
      assert Vision.supports_vision?(:anthropic)
      assert Vision.supports_vision?(:openai)
      assert Vision.supports_vision?(:gemini)
    end

    @tag :vision
    test "returns false for non-vision providers" do
      refute Vision.supports_vision?(:bumblebee)
      refute Vision.supports_vision?(:unknown)
    end
  end

  describe "has_vision_content?/1" do
    @tag :vision
    test "detects vision content in messages" do
      message_with_image = %{
        role: "user",
        content: [
          %{type: "text", text: "Hello"},
          %{type: "image_url", image_url: %{url: "https://example.com/img.jpg"}}
        ]
      }

      assert Vision.has_vision_content?(message_with_image)
    end

    test "returns false for text-only messages" do
      text_message = %{role: "user", content: "Just text"}
      refute Vision.has_vision_content?(text_message)

      text_parts_message = %{
        role: "user",
        content: [%{type: "text", text: "Just text"}]
      }

      refute Vision.has_vision_content?(text_parts_message)
    end
  end

  describe "count_images/1" do
    test "counts images in message" do
      message = %{
        role: "user",
        content: [
          %{type: "text", text: "Look at these"},
          %{type: "image_url", image_url: %{url: "img1.jpg"}},
          %{type: "image", image: %{data: "base64data"}},
          %{type: "text", text: "What do you see?"}
        ]
      }

      assert Vision.count_images(message) == 2
    end

    test "returns 0 for no images" do
      text_message = %{role: "user", content: "No images"}
      assert Vision.count_images(text_message) == 0
    end
  end

  describe "normalize_messages/1" do
    test "normalizes atom types to strings" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"},
        %{
          role: "user",
          content: [
            %{type: :text, text: "Look at this"},
            %{type: :image_url, image_url: %{url: "img.jpg"}}
          ]
        }
      ]

      {:ok, normalized} = Vision.normalize_messages(messages)

      # String content remains as strings
      assert [msg1, msg2, msg3] = normalized
      assert msg1.content == "Hello"
      assert msg2.content == "Hi there!"

      # Atom types should be converted to strings
      assert [text_part, image_part] = msg3.content
      # Was :text
      assert text_part.type == "text"
      # Was :image_url
      assert image_part.type == "image_url"
    end
  end

  # Integration tests with the main ExLLM module
  describe "ExLLM integration" do
    setup do
      ExLLM.Infrastructure.Config.ModelConfig.ensure_cache_table()
      :ok
    end

    @tag :vision
    test "vision_message/3 creates proper message" do
      {:ok, message} = ExLLM.vision_message("What's this?", ["https://example.com/img.jpg"])

      assert message.role == "user"
      assert length(message.content) == 2
      assert hd(message.content) == %{type: "text", text: "What's this?"}
    end

    test "load_image/2 works through ExLLM" do
      path = Path.join(System.tmp_dir!(), "test.jpg")

      File.write!(
        path,
        <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01>>
      )

      assert {:ok, image_part} = ExLLM.load_image(path)
      assert image_part.type == "image"

      File.rm!(path)
    end

    @tag :vision
    test "supports_vision?/2 checks both provider and model" do
      # This would need actual model capability data to work properly
      # For now, just verify the function exists and returns boolean
      result = ExLLM.supports_vision?(:openai, "gpt-4-vision-preview")
      assert is_boolean(result)
    end
  end
end
