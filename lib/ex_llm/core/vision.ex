defmodule ExLLM.Core.Vision do
  @moduledoc """
  Vision and multimodal support for ExLLM.

  Provides utilities for handling images in LLM requests, including:
  - Image format validation
  - Base64 encoding/decoding
  - URL validation
  - Provider-specific formatting

  ## Supported Image Formats

  - JPEG/JPG
  - PNG
  - GIF (static only for most providers)
  - WebP

  ## Usage

      # With image URL
      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{type: "image_url", image_url: %{url: "https://example.com/image.jpg"}}
          ]
        }
      ]
      
      # With base64 image
      image_data = File.read!("photo.jpg") |> Base.encode64()
      messages = [
        %{
          role: "user", 
          content: [
            %{type: "text", text: "Describe this photo"},
            %{type: "image", image: %{data: image_data, media_type: "image/jpeg"}}
          ]
        }
      ]
      
      {:ok, response} = ExLLM.chat(:anthropic, messages)
  """

  alias ExLLM.Types

  # @supported_formats ~w(image/jpeg image/jpg image/png image/gif image/webp)
  # 20MB default limit
  @max_image_size 20 * 1024 * 1024

  @doc """
  Check if a provider supports vision/multimodal inputs.
  """
  @spec supports_vision?(atom()) :: boolean()
  def supports_vision?(provider) do
    case provider do
      :anthropic -> true
      :openai -> true
      :gemini -> true
      # Some Bedrock models support vision
      :bedrock -> true
      _ -> false
    end
  end

  @doc """
  Validate and normalize messages containing images.

  Returns `{:ok, normalized_messages}` or `{:error, reason}`.
  """
  @spec normalize_messages(list(Types.message())) ::
          {:ok, list(Types.message())} | {:error, term()}
  def normalize_messages(messages) do
    try do
      normalized = Enum.map(messages, &normalize_message/1)
      {:ok, normalized}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Check if a message contains vision content.
  """
  @spec has_vision_content?(Types.message()) :: boolean()
  def has_vision_content?(%{content: content}) when is_list(content) do
    Enum.any?(content, fn
      %{type: "image"} -> true
      %{type: "image_url"} -> true
      %{type: :image} -> true
      %{type: :image_url} -> true
      _ -> false
    end)
  end

  def has_vision_content?(_), do: false

  @doc """
  Count images in a message.
  """
  @spec count_images(Types.message()) :: non_neg_integer()
  def count_images(%{content: content}) when is_list(content) do
    Enum.count(content, fn
      %{type: type} when type in ["image", "image_url", :image, :image_url] -> true
      _ -> false
    end)
  end

  def count_images(_), do: 0

  @doc """
  Load an image from file and encode it for API use.

  Returns a content part ready to be included in a message.
  """
  @spec load_image(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def load_image(file_path, opts \\ []) do
    # File path is provided by the developer for legitimate image loading
    # sobelow_skip ["Traversal.FileModule"]
    with {:ok, data} <- File.read(file_path),
         {:ok, media_type} <- detect_media_type(file_path, data),
         :ok <- validate_image_size(data, opts),
         encoded <- Base.encode64(data) do
      {:ok,
       %{
         type: "image",
         image: %{
           data: encoded,
           media_type: media_type
         }
       }}
    end
  end

  @doc """
  Create an image URL content part.

  ## Options
  - `:detail` - Image detail level (:auto, :low, :high)
  """
  @spec image_url(String.t(), keyword()) :: map()
  def image_url(url, opts \\ []) do
    %{
      type: "image_url",
      image_url: %{
        url: url,
        detail: Keyword.get(opts, :detail, :auto)
      }
    }
  end

  @doc """
  Create a text content part.
  """
  @spec text(String.t()) :: map()
  def text(content) do
    %{type: "text", text: content}
  end

  @doc """
  Build a vision message with text and images.

  ## Examples

      message = ExLLM.Core.Vision.build_message("user", "What's in these images?", [
        "https://example.com/image1.jpg",
        "/path/to/local/image2.png"
      ])
  """
  @spec build_message(String.t(), String.t(), list(String.t()), keyword()) ::
          {:ok, Types.message()} | {:error, term()}
  def build_message(role, text_content, image_sources, opts \\ []) do
    with {:ok, image_parts} <- process_image_sources(image_sources, opts) do
      message = %{
        role: role,
        content: [text(text_content) | image_parts]
      }

      {:ok, message}
    end
  end

  @doc """
  Create a vision message with text and images.
  
  ## Examples
  
      {:ok, message} = ExLLM.Core.Vision.create_message("What's in this image?", ["https://example.com/img.jpg"])
  """
  @spec create_message(String.t(), list(String.t()), keyword()) :: {:ok, map()} | {:error, term()}
  def create_message(text, images, opts \\ []) do
    build_message("user", text, images, opts)
  end

  @doc """
  Format messages for a specific provider.

  Some providers have specific requirements for vision content.
  """
  @spec format_for_provider(list(Types.message()), atom()) :: list(Types.message())
  def format_for_provider(messages, provider) do
    case provider do
      :anthropic -> format_for_anthropic(messages)
      :openai -> format_for_openai(messages)
      :gemini -> format_for_gemini(messages)
      _ -> messages
    end
  end

  # Private functions

  defp normalize_message(%{content: content} = message) when is_binary(content) do
    # Simple text message, no changes needed
    message
  end

  defp normalize_message(%{content: content} = message) when is_list(content) do
    # Normalize content parts
    normalized_content = Enum.map(content, &normalize_content_part/1)
    %{message | content: normalized_content}
  end

  defp normalize_content_part(%{type: type} = part) when is_atom(type) do
    %{part | type: to_string(type)}
  end

  defp normalize_content_part(part), do: part

  defp detect_media_type(file_path, data) do
    # First try by extension
    media_type =
      case Path.extname(file_path) |> String.downcase() do
        ".jpg" -> "image/jpeg"
        ".jpeg" -> "image/jpeg"
        ".png" -> "image/png"
        ".gif" -> "image/gif"
        ".webp" -> "image/webp"
        _ -> nil
      end

    if media_type do
      {:ok, media_type}
    else
      # Try to detect from magic bytes
      detect_from_bytes(data)
    end
  end

  defp detect_from_bytes(<<0xFF, 0xD8, 0xFF, _::binary>>), do: {:ok, "image/jpeg"}

  defp detect_from_bytes(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>),
    do: {:ok, "image/png"}

  defp detect_from_bytes(<<0x47, 0x49, 0x46, 0x38, _::binary>>), do: {:ok, "image/gif"}
  defp detect_from_bytes(<<"RIFF", _::32, "WEBP", _::binary>>), do: {:ok, "image/webp"}
  defp detect_from_bytes(_), do: {:error, :unknown_image_format}

  defp validate_image_size(data, opts) do
    max_size = Keyword.get(opts, :max_size, @max_image_size)
    size = byte_size(data)

    if size <= max_size do
      :ok
    else
      {:error, {:image_too_large, %{size: size, max_size: max_size}}}
    end
  end

  defp process_image_sources(sources, opts) do
    results =
      Enum.map(sources, fn source ->
        cond do
          String.starts_with?(source, "http") ->
            {:ok, image_url(source, opts)}

          File.exists?(source) ->
            load_image(source, opts)

          true ->
            {:error, {:invalid_image_source, source}}
        end
      end)

    # Check for any errors
    case Enum.find(results, &match?({:error, _}, &1)) do
      {:error, _} = error -> error
      nil -> {:ok, Enum.map(results, fn {:ok, part} -> part end)}
    end
  end

  # Provider-specific formatting

  defp format_for_anthropic(messages) do
    # Anthropic expects base64 images with media type
    Enum.map(messages, &format_anthropic_message/1)
  end

  defp format_anthropic_message(%{content: content} = message) when is_list(content) do
    formatted_content = Enum.map(content, &format_anthropic_content_part/1)
    %{message | content: formatted_content}
  end

  defp format_anthropic_message(message), do: message

  defp format_anthropic_content_part(
         %{"type" => "image_url", "image_url" => %{"url" => _url}} = part
       ) do
    # Convert URL to base64 if needed for Anthropic
    # For now, keep as-is
    part
  end

  defp format_anthropic_content_part(part), do: part

  defp format_for_openai(messages) do
    # OpenAI prefers image URLs but supports base64
    messages
  end

  defp format_for_gemini(messages) do
    # Gemini has its own format requirements
    # For now, use standard format
    messages
  end
end
