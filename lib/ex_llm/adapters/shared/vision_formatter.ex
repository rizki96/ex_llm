defmodule ExLLM.Adapters.Shared.VisionFormatter do
  @moduledoc """
  Unified vision/multimodal content formatting for LLM providers.

  This module standardizes the handling of images and other multimodal
  content across different providers, reducing code duplication.

  Features:
  - Image format validation and detection
  - Base64 encoding/decoding
  - Provider-specific formatting
  - URL and file handling
  - Content type detection
  """

  @supported_formats ~w(image/jpeg image/jpg image/png image/gif image/webp)
  # 20MB default
  @max_image_size 20 * 1024 * 1024

  @doc """
  Callback for provider-specific vision content formatting.
  """
  @callback format_vision_content(content :: map()) :: map()

  @doc """
  Callback to check if a model supports vision.
  """
  @callback model_supports_vision?(model :: String.t()) :: boolean()

  # Optional callbacks
  @optional_callbacks [format_vision_content: 1, model_supports_vision?: 1]

  @doc """
  Check if messages contain vision content.
  """
  @spec has_vision_content?(list(map())) :: boolean()
  def has_vision_content?(messages) do
    Enum.any?(messages, &message_has_vision_content?/1)
  end

  @doc """
  Check if a single message has vision content.
  """
  @spec message_has_vision_content?(map()) :: boolean()
  def message_has_vision_content?(%{content: content}) when is_list(content) do
    Enum.any?(content, fn
      %{"type" => type} when type in ["image", "image_url"] -> true
      %{type: type} when type in [:image, :image_url, "image", "image_url"] -> true
      _ -> false
    end)
  end

  def message_has_vision_content?(_), do: false

  @doc """
  Format messages containing vision content for a specific provider.

  ## Examples

      messages = [
        %{
          role: "user",
          content: [
            %{type: "text", text: "What's in this image?"},
            %{type: "image_url", image_url: %{url: "https://example.com/cat.jpg"}}
          ]
        }
      ]
      
      formatted = VisionFormatter.format_messages(messages, :anthropic)
  """
  @spec format_messages(list(map()), atom()) :: list(map())
  def format_messages(messages, provider) do
    formatter = get_formatter(provider)
    Enum.map(messages, &format_message(&1, formatter))
  end

  @doc """
  Load an image from a file path and encode it.

  Returns a content part ready for inclusion in a message.

  ## Options
  - `:format` - Force output format (:base64 or :url)
  - `:max_size` - Maximum file size in bytes
  - `:detail` - Image detail level ("low", "high", "auto")
  """
  @spec load_image_file(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def load_image_file(path, options \\ []) do
    # File path is provided by the developer for legitimate image loading
    # sobelow_skip ["Traversal.FileModule"]
    with {:ok, data} <- File.read(path),
         :ok <- validate_image_size(data, options),
         {:ok, media_type} <- detect_media_type(path, data) do
      format = Keyword.get(options, :format, :base64)

      case format do
        :base64 ->
          {:ok, format_base64_image(data, media_type, options)}

        :url ->
          # For local files, we typically need to convert to base64
          # unless the provider supports file uploads
          {:ok, format_base64_image(data, media_type, options)}

        _ ->
          {:error, {:invalid_format, format}}
      end
    end
  end

  @doc """
  Create an image URL content part.
  """
  @spec image_url(String.t(), keyword()) :: map()
  def image_url(url, options \\ []) do
    base = %{
      "type" => "image_url",
      "image_url" => %{
        "url" => url
      }
    }

    # Add optional detail level
    case Keyword.get(options, :detail) do
      nil -> base
      detail -> put_in(base, ["image_url", "detail"], detail)
    end
  end

  @doc """
  Create a base64 image content part.
  """
  @spec base64_image(binary(), String.t(), keyword()) :: map()
  def base64_image(data, media_type, options \\ []) do
    format_base64_image(data, media_type, options)
  end

  @doc """
  Validate that an image format is supported.
  """
  @spec validate_media_type(String.t()) :: :ok | {:error, :unsupported_format}
  def validate_media_type(media_type) do
    if media_type in @supported_formats do
      :ok
    else
      {:error, :unsupported_format}
    end
  end

  @doc """
  Detect media type from file extension or magic bytes.
  """
  @spec detect_media_type(String.t(), binary()) :: {:ok, String.t()} | {:error, :unknown_format}
  def detect_media_type(path, data) do
    # Try extension first
    case path |> Path.extname() |> String.downcase() do
      ".jpg" -> {:ok, "image/jpeg"}
      ".jpeg" -> {:ok, "image/jpeg"}
      ".png" -> {:ok, "image/png"}
      ".gif" -> {:ok, "image/gif"}
      ".webp" -> {:ok, "image/webp"}
      _ -> detect_from_magic_bytes(data)
    end
  end

  # Provider-specific formatters

  defp get_formatter(:anthropic), do: &format_for_anthropic/1
  defp get_formatter(:openai), do: &format_for_openai/1
  defp get_formatter(:gemini), do: &format_for_gemini/1
  defp get_formatter(:bedrock), do: &format_for_bedrock/1
  defp get_formatter(_), do: &identity/1

  defp identity(x), do: x

  defp format_message(%{content: content} = message, formatter) when is_list(content) do
    formatted_content = Enum.map(content, formatter)
    %{message | content: formatted_content}
  end

  defp format_message(message, _formatter), do: message

  # Anthropic formatting
  defp format_for_anthropic(%{"type" => "image_url", "image_url" => %{"url" => url}} = part) do
    if String.starts_with?(url, "data:") do
      # Already base64 data URL
      parse_data_url_to_anthropic(url)
    else
      # Keep URL as-is, Anthropic may support it
      part
    end
  end

  defp format_for_anthropic(%{"type" => "image", "source" => source} = _part) do
    # Already in Anthropic format
    %{
      "type" => "image",
      "source" => source
    }
  end

  defp format_for_anthropic(part), do: part

  # OpenAI formatting
  defp format_for_openai(%{
         "type" => "image",
         "source" => %{"data" => data, "media_type" => media_type}
       }) do
    # Convert Anthropic format to OpenAI
    %{
      "type" => "image_url",
      "image_url" => %{
        "url" => "data:#{media_type};base64,#{data}"
      }
    }
  end

  defp format_for_openai(part), do: part

  # Gemini formatting
  defp format_for_gemini(%{"type" => "image_url", "image_url" => %{"url" => url}}) do
    if String.starts_with?(url, "data:") do
      # Parse data URL for Gemini
      parse_data_url_to_gemini(url)
    else
      # Gemini prefers inline data
      %{
        "type" => "image",
        "inlineData" => %{
          # Default, should be detected
          "mimeType" => "image/jpeg",
          # This should be fetched and encoded
          "data" => url
        }
      }
    end
  end

  defp format_for_gemini(part), do: part

  # Bedrock formatting (varies by model)
  defp format_for_bedrock(part), do: part

  # Helper functions

  defp format_base64_image(data, media_type, options) do
    provider_format = Keyword.get(options, :provider_format, :openai)
    encoded = Base.encode64(data)

    case provider_format do
      :anthropic ->
        %{
          "type" => "image",
          "source" => %{
            "type" => "base64",
            "media_type" => media_type,
            "data" => encoded
          }
        }

      :gemini ->
        %{
          "type" => "image",
          "inlineData" => %{
            "mimeType" => media_type,
            "data" => encoded
          }
        }

      # OpenAI and default
      _ ->
        %{
          "type" => "image_url",
          "image_url" => %{
            "url" => "data:#{media_type};base64,#{encoded}"
          }
        }
    end
  end

  defp validate_image_size(data, options) do
    max_size = Keyword.get(options, :max_size, @max_image_size)
    size = byte_size(data)

    if size <= max_size do
      :ok
    else
      {:error, {:image_too_large, size, max_size}}
    end
  end

  defp detect_from_magic_bytes(<<0xFF, 0xD8, 0xFF, _::binary>>), do: {:ok, "image/jpeg"}

  defp detect_from_magic_bytes(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>),
    do: {:ok, "image/png"}

  defp detect_from_magic_bytes(<<0x47, 0x49, 0x46, 0x38, _::binary>>), do: {:ok, "image/gif"}
  defp detect_from_magic_bytes(<<"RIFF", _::32, "WEBP", _::binary>>), do: {:ok, "image/webp"}
  defp detect_from_magic_bytes(_), do: {:error, :unknown_format}

  defp parse_data_url_to_anthropic(url) do
    case Regex.run(~r/^data:([^;]+);base64,(.+)$/, url) do
      [_, media_type, data] ->
        %{
          "type" => "image",
          "source" => %{
            "type" => "base64",
            "media_type" => media_type,
            "data" => data
          }
        }

      _ ->
        # Invalid data URL, keep as-is
        %{"type" => "image_url", "image_url" => %{"url" => url}}
    end
  end

  defp parse_data_url_to_gemini(url) do
    case Regex.run(~r/^data:([^;]+);base64,(.+)$/, url) do
      [_, media_type, data] ->
        %{
          "type" => "image",
          "inlineData" => %{
            "mimeType" => media_type,
            "data" => data
          }
        }

      _ ->
        # Invalid data URL
        %{"type" => "image_url", "image_url" => %{"url" => url}}
    end
  end
end
