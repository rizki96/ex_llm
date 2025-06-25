defmodule ExLLM.Providers.Shared.HTTP.Multipart do
  @moduledoc """
  Multipart form data handling for file uploads and complex form submissions.

  This module provides utilities for creating and managing multipart/form-data
  requests, commonly used for file uploads in LLM providers like OpenAI's
  fine-tuning API, Anthropic's document upload, etc.

  ## Features

  - File upload handling with proper content-type detection
  - Support for mixed content types in single request
  - Memory-efficient streaming for large files
  - Base64 encoding support for binary data
  - Content-Disposition header management

  ## Usage

      # Simple file upload
      multipart = HTTP.Multipart.new()
      |> HTTP.Multipart.add_field("purpose", "fine-tune")
      |> HTTP.Multipart.add_file("file", file_path)
      
      {:ok, response} = Tesla.post(client, "/files", multipart)
      
      # Binary data upload
      multipart = HTTP.Multipart.new()
      |> HTTP.Multipart.add_binary("image", image_data, "image.png", "image/png")
  """

  alias ExLLM.Infrastructure.Logger

  # Maximum file size for in-memory reading (25MB)
  # Files larger than this must use stream_file/4 to prevent memory exhaustion
  @max_file_size_for_in_memory_read 25 * 1_000_000

  @type part :: %{
          name: String.t(),
          content: binary() | String.t(),
          headers: [{String.t(), String.t()}],
          filename: String.t() | nil
        }

  @type multipart :: %{
          boundary: String.t(),
          parts: [part()]
        }

  @doc """
  Create a new multipart form with a random boundary.
  """
  @spec new() :: multipart()
  def new do
    boundary = generate_boundary()
    %{boundary: boundary, parts: []}
  end

  @doc """
  Add a simple text field to the multipart form.

  ## Examples

      multipart
      |> HTTP.Multipart.add_field("purpose", "fine-tune")
      |> HTTP.Multipart.add_field("model", "gpt-3.5-turbo")
  """
  @spec add_field(multipart(), String.t(), String.t()) :: multipart()
  def add_field(multipart, name, value) do
    part = %{
      name: name,
      content: to_string(value),
      headers: [{"content-type", "text/plain"}],
      filename: nil
    }

    %{multipart | parts: [part | multipart.parts]}
  end

  @doc """
  Add a file from the filesystem to the multipart form.

  ## Examples

      multipart
      |> HTTP.Multipart.add_file("file", "/path/to/data.jsonl")
      |> HTTP.Multipart.add_file("image", "/path/to/image.png", "custom-name.png")
  """
  @spec add_file(multipart(), String.t(), String.t(), String.t() | nil) :: multipart()
  def add_file(multipart, name, file_path, custom_filename \\ nil) do
    with {:ok, %File.Stat{size: size}} <- File.stat(file_path),
         :ok <- check_file_size(size, file_path),
         {:ok, content} <- File.read(file_path) do
      filename = custom_filename || Path.basename(file_path)
      content_type = detect_content_type(file_path)

      add_binary(multipart, name, content, filename, content_type)
    else
      {:error, reason} ->
        Logger.error("Failed to add file #{file_path}: #{inspect(reason)}")
        multipart
    end
  end

  @doc """
  Add binary data to the multipart form.

  ## Examples

      multipart
      |> HTTP.Multipart.add_binary("file", file_content, "data.jsonl", "application/json")
      |> HTTP.Multipart.add_binary("image", image_bytes, "photo.jpg", "image/jpeg")
  """
  @spec add_binary(multipart(), String.t(), binary(), String.t(), String.t()) :: multipart()
  def add_binary(multipart, name, content, filename, content_type) do
    part = %{
      name: name,
      content: content,
      headers: [{"content-type", content_type}],
      filename: filename
    }

    %{multipart | parts: [part | multipart.parts]}
  end

  @doc """
  Add JSON data to the multipart form.

  ## Examples

      config = %{model: "gpt-3.5-turbo", temperature: 0.7}
      multipart
      |> HTTP.Multipart.add_json("config", config)
  """
  @spec add_json(multipart(), String.t(), term()) :: multipart()
  def add_json(multipart, name, data) do
    case Jason.encode(data) do
      {:ok, json} ->
        part = %{
          name: name,
          content: json,
          headers: [{"content-type", "application/json"}],
          filename: nil
        }

        %{multipart | parts: [part | multipart.parts]}

      {:error, reason} ->
        Logger.error("Failed to encode JSON for field #{name}: #{reason}")
        multipart
    end
  end

  @doc """
  Convert multipart form to Tesla-compatible format.

  This function generates the complete multipart body with proper boundaries
  and headers that can be used directly with Tesla HTTP client.
  """
  @spec to_tesla_multipart(multipart()) :: {:multipart, [map()]}
  def to_tesla_multipart(%{parts: parts}) do
    tesla_parts = Enum.map(parts, &convert_part_to_tesla/1)
    {:multipart, tesla_parts}
  end

  @doc """
  Convert multipart form to raw binary format.

  This generates the complete HTTP body with boundaries and headers as a binary,
  useful for low-level HTTP libraries or debugging.
  """
  @spec to_binary(multipart()) :: {binary(), String.t()}
  def to_binary(%{boundary: boundary, parts: parts}) do
    content_type = "multipart/form-data; boundary=#{boundary}"

    body_parts =
      parts
      # Restore original order
      |> Enum.reverse()
      |> Enum.map(&format_part(&1, boundary))

    body =
      [body_parts, "--#{boundary}--\r\n"]
      |> List.flatten()
      |> Enum.join()

    {body, content_type}
  end

  @doc """
  Calculate the total size of the multipart form.

  WARNING: This function loads the entire content of all parts into memory.
  It should NOT be used for requests containing large files. Doing so can
  lead to significant memory usage and application instability. It is
  incompatible with streamed uploads.

  Useful for setting Content-Length header for small requests or for debugging.
  """
  @spec calculate_size(multipart()) :: non_neg_integer()
  def calculate_size(multipart) do
    {body, _content_type} = to_binary(multipart)
    byte_size(body)
  end

  @doc """
  Validate multipart form for common issues.

  Returns `:ok` if valid, or `{:error, reason}` if issues are found.
  """
  @spec validate(multipart()) :: :ok | {:error, String.t()}
  def validate(%{parts: []}) do
    {:error, "Multipart form cannot be empty"}
  end

  def validate(%{parts: parts}) do
    case find_invalid_part(parts) do
      nil -> :ok
      error -> {:error, error}
    end
  end

  # Private functions

  defp generate_boundary do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> then(&"----ExLLMBoundary#{&1}")
  end

  # Content type mapping for file extensions
  @content_types %{
    ".json" => "application/json",
    ".jsonl" => "application/x-ndjson",
    ".txt" => "text/plain",
    ".csv" => "text/csv",
    ".pdf" => "application/pdf",
    ".png" => "image/png",
    ".jpg" => "image/jpeg",
    ".jpeg" => "image/jpeg",
    ".gif" => "image/gif",
    ".webp" => "image/webp",
    ".mp3" => "audio/mpeg",
    ".wav" => "audio/wav",
    ".mp4" => "video/mp4",
    ".avi" => "video/x-msvideo"
  }

  @default_content_type "application/octet-stream"

  defp detect_content_type(file_path) do
    extension =
      file_path
      |> Path.extname()
      |> String.downcase()

    Map.get(@content_types, extension, @default_content_type)
  end

  defp check_file_size(size, file_path) when size > @max_file_size_for_in_memory_read do
    error_msg =
      "File #{file_path} with size #{size} bytes exceeds the in-memory limit of #{@max_file_size_for_in_memory_read} bytes. " <>
        "Please use `stream_file/4` for large files to prevent memory exhaustion."

    Logger.error(error_msg)
    {:error, :file_too_large}
  end

  defp check_file_size(_size, _file_path), do: :ok

  defp convert_part_to_tesla(part) do
    headers = format_tesla_headers(part)

    case part.filename do
      nil ->
        # Simple field
        {part.name, part.content}

      filename ->
        # File field
        {part.name, part.content, [{"filename", filename} | headers]}
    end
  end

  defp format_tesla_headers(%{headers: headers}) do
    Enum.map(headers, fn {name, value} -> {name, value} end)
  end

  defp format_part(part, boundary) do
    disposition = format_content_disposition(part)
    content_type = format_content_type(part)

    [
      "--#{boundary}\r\n",
      "Content-Disposition: #{disposition}\r\n",
      content_type,
      "\r\n",
      part.content,
      "\r\n"
    ]
  end

  defp format_content_disposition(%{name: name, filename: nil}) do
    "form-data; name=\"#{name}\""
  end

  defp format_content_disposition(%{name: name, filename: filename}) do
    "form-data; name=\"#{name}\"; filename=\"#{filename}\""
  end

  defp format_content_type(%{headers: headers}) do
    case List.keyfind(headers, "content-type", 0) do
      {"content-type", content_type} ->
        "Content-Type: #{content_type}\r\n"

      nil ->
        "Content-Type: application/octet-stream\r\n"
    end
  end

  defp find_invalid_part(parts) do
    Enum.find_value(parts, fn part ->
      cond do
        is_nil(part.name) or part.name == "" ->
          "Part name cannot be empty"

        is_nil(part.content) ->
          "Part content cannot be nil"

        not is_binary(part.content) and not is_bitstring(part.content) ->
          "Part content must be binary"

        # 100MB limit
        byte_size(part.content) > 100_000_000 ->
          "Part content exceeds 100MB limit"

        true ->
          nil
      end
    end)
  end

  @doc """
  Stream a large file as multipart data to avoid loading entire file into memory.

  This is useful for very large files that shouldn't be loaded entirely into memory.
  Returns a stream that yields chunks of the multipart body.
  """
  @spec stream_file(String.t(), String.t()) :: Enumerable.t()
  @spec stream_file(String.t(), String.t(), String.t() | nil) :: Enumerable.t()
  @spec stream_file(String.t(), String.t(), String.t() | nil, keyword()) :: Enumerable.t()
  def stream_file(name, file_path, filename \\ nil, opts \\ []) do
    filename = filename || Path.basename(file_path)
    content_type = Keyword.get(opts, :content_type) || detect_content_type(file_path)
    boundary = Keyword.get(opts, :boundary) || generate_boundary()
    chunk_size = Keyword.get(opts, :chunk_size, 8192)

    Stream.resource(
      fn ->
        # Open file and create headers
        {:ok, file} = File.open(file_path, [:read, :binary])

        disposition = "form-data; name=\"#{name}\"; filename=\"#{filename}\""

        headers = [
          "--#{boundary}\r\n",
          "Content-Disposition: #{disposition}\r\n",
          "Content-Type: #{content_type}\r\n",
          "\r\n"
        ]

        {file, boundary, headers, :headers}
      end,
      fn
        {file, boundary, headers, :headers} ->
          # Yield headers first
          {headers, {file, boundary, :content}}

        {file, boundary, :content} ->
          # Yield file content in chunks
          case IO.binread(file, chunk_size) do
            :eof ->
              {:halt, {file, boundary, :done}}

            data ->
              {[data], {file, boundary, :content}}
          end

        {file, boundary, :done} ->
          # Yield final boundary
          {["\r\n--#{boundary}--\r\n"], {file, boundary, :closed}}

        {file, _boundary, :closed} ->
          {:halt, file}
      end,
      fn file ->
        if is_pid(file) do
          File.close(file)
        end
      end
    )
  end
end
