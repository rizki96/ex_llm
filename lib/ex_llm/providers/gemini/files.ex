defmodule ExLLM.Providers.Gemini.Files do
  @moduledoc """
  Google Gemini Files API implementation.

  Provides functionality to upload, manage, and delete files that can be used
  with Gemini models for multimodal generation.
  """

  alias ExLLM.Providers.Shared.ConfigHelper

  defmodule Status do
    @moduledoc """
    Error status information.
    """

    @type t :: %__MODULE__{
            code: integer(),
            message: String.t() | nil,
            details: list(map())
          }

    defstruct [:code, :message, details: []]

    @doc """
    Converts API response to Status struct.
    """
    @spec from_api(map() | nil) :: t() | nil
    def from_api(nil), do: nil

    def from_api(data) when is_map(data) do
      %__MODULE__{
        code: data["code"],
        message: data["message"],
        details: data["details"] || []
      }
    end
  end

  defmodule VideoFileMetadata do
    @moduledoc """
    Metadata for video files.
    """

    @type t :: %__MODULE__{
            video_duration: float() | nil
          }

    defstruct [:video_duration]

    @doc """
    Converts API response to VideoFileMetadata struct.
    """
    @spec from_api(map() | nil) :: t() | nil
    def from_api(nil), do: nil

    def from_api(data) when is_map(data) do
      %__MODULE__{
        video_duration: parse_duration(data["videoDuration"])
      }
    end

    defp parse_duration(nil), do: nil

    defp parse_duration(duration) when is_binary(duration) do
      case Regex.run(~r/^(\d+(?:\.\d+)?)s$/, duration) do
        [_, number] -> String.to_float(number)
        nil -> nil
      end
    end
  end

  defmodule File do
    @moduledoc """
    Represents an uploaded file in the Gemini API.
    """

    @type state :: :state_unspecified | :processing | :active | :failed | atom()
    @type source :: :source_unspecified | :uploaded | :generated | atom()

    @type t :: %__MODULE__{
            name: String.t(),
            display_name: String.t() | nil,
            mime_type: String.t(),
            size_bytes: integer(),
            create_time: DateTime.t() | nil,
            update_time: DateTime.t() | nil,
            expiration_time: DateTime.t() | nil,
            sha256_hash: String.t() | nil,
            uri: String.t() | nil,
            download_uri: String.t() | nil,
            state: state(),
            source: source() | nil,
            error: Status.t() | nil,
            video_metadata: VideoFileMetadata.t() | nil
          }

    @enforce_keys [:name, :mime_type, :size_bytes, :state]
    defstruct [
      :name,
      :display_name,
      :mime_type,
      :size_bytes,
      :create_time,
      :update_time,
      :expiration_time,
      :sha256_hash,
      :uri,
      :download_uri,
      :state,
      :source,
      :error,
      :video_metadata
    ]

    @doc """
    Converts API response to File struct.
    """
    @spec from_api(map()) :: t()
    def from_api(data) when is_map(data) do
      %__MODULE__{
        name: data["name"],
        display_name: data["displayName"],
        mime_type: data["mimeType"],
        size_bytes: parse_size_bytes(data["sizeBytes"]),
        create_time: parse_timestamp(data["createTime"]),
        update_time: parse_timestamp(data["updateTime"]),
        expiration_time: parse_timestamp(data["expirationTime"]),
        sha256_hash: data["sha256Hash"],
        uri: data["uri"],
        download_uri: data["downloadUri"],
        state: parse_state(data["state"]),
        source: parse_source(data["source"]),
        error: Status.from_api(data["error"]),
        video_metadata: VideoFileMetadata.from_api(data["videoMetadata"])
      }
    end

    defp parse_size_bytes(nil), do: 0
    defp parse_size_bytes(size) when is_integer(size), do: size
    defp parse_size_bytes(size) when is_binary(size), do: String.to_integer(size)

    defp parse_timestamp(nil), do: nil

    defp parse_timestamp(timestamp) when is_binary(timestamp) do
      case DateTime.from_iso8601(timestamp) do
        {:ok, datetime, _offset} -> datetime
        {:error, _} -> nil
      end
    end

    defp parse_state(nil), do: :state_unspecified
    defp parse_state("STATE_UNSPECIFIED"), do: :state_unspecified
    defp parse_state("PROCESSING"), do: :processing
    defp parse_state("ACTIVE"), do: :active
    defp parse_state("FAILED"), do: :failed

    defp parse_state(state) when is_binary(state) do
      state |> String.downcase() |> String.to_atom()
    end

    defp parse_source(nil), do: nil
    defp parse_source("SOURCE_UNSPECIFIED"), do: :source_unspecified
    defp parse_source("UPLOADED"), do: :uploaded
    defp parse_source("GENERATED"), do: :generated

    defp parse_source(source) when is_binary(source) do
      source |> String.downcase() |> String.to_atom()
    end
  end

  @type upload_options :: [
          {:display_name, String.t()}
          | {:config_provider, pid() | atom()}
        ]

  @type list_options :: [
          {:page_size, integer()}
          | {:page_token, String.t()}
          | {:config_provider, pid() | atom()}
        ]

  @type wait_options :: [
          {:timeout, integer()}
          | {:poll_interval, integer()}
          | {:config_provider, pid() | atom()}
        ]

  @doc """
  Uploads a file to the Gemini API using resumable upload.

  ## Parameters
    * `file_path` - Path to the file to upload
    * `opts` - Upload options including `:display_name` and `:config_provider`

  ## Examples
      
      {:ok, file} = ExLLM.Providers.Gemini.Files.upload_file("/path/to/image.png", display_name: "My Image")
  """
  @spec upload_file(String.t(), upload_options()) :: {:ok, File.t()} | {:error, term()}
  def upload_file(file_path, opts \\ []) do
    with :ok <- validate_file_path(file_path),
         {:ok, file_data} <- Elixir.File.read(file_path),
         file_size <- byte_size(file_data),
         mime_type <- get_mime_type(file_path),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      # Step 1: Initiate resumable upload
      metadata = build_upload_metadata(file_path, opts)

      case initiate_upload(api_key, mime_type, file_size, metadata) do
        {:ok, upload_url} ->
          # Step 2: Upload the file content
          upload_content(upload_url, file_data, file_size)

        {:error, _} = error ->
          error
      end
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Gets metadata for a specific file.

  ## Parameters
    * `file_name` - The file name (e.g., "files/abc-123")
    * `opts` - Options including `:config_provider`

  ## Examples
      
      {:ok, file} = ExLLM.Providers.Gemini.Files.get_file("files/abc-123")
  """
  @spec get_file(String.t(), Keyword.t()) :: {:ok, File.t()} | {:error, term()}
  def get_file(file_name, opts \\ []) do
    with :ok <- validate_file_name(file_name),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      url = build_url("/v1beta/#{file_name}", api_key)
      headers = build_headers()

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, File.from_api(body)}

        {:ok, %{status: 404}} ->
          {:error, %{status: 404, message: "File not found: #{file_name}"}}

        {:ok, %{status: 403, body: body}} ->
          {:error, %{status: 403, message: "API error", body: body}}

        {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 400, message: message}}

        {:ok, %{status: status, body: body}} ->
          {:error, %{status: status, message: "API error", body: body}}

        {:error, reason} ->
          {:error, %{reason: :network_error, message: inspect(reason)}}
      end
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Lists files owned by the requesting project.

  ## Parameters
    * `opts` - Options including `:page_size`, `:page_token`, and `:config_provider`

  ## Examples
      
      {:ok, %{files: files, next_page_token: token}} = ExLLM.Providers.Gemini.Files.list_files(page_size: 10)
  """
  @spec list_files(list_options()) ::
          {:ok, %{files: [File.t()], next_page_token: String.t() | nil}} | {:error, term()}
  def list_files(opts \\ []) do
    with :ok <- validate_list_params(opts),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      query_params = build_list_query_params(opts)
      url = build_url("/v1beta/files", api_key, query_params)
      headers = build_headers()

      case Req.get(url, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          files =
            body
            |> Map.get("files", [])
            |> Enum.map(&File.from_api/1)

          {:ok,
           %{
             files: files,
             next_page_token: Map.get(body, "nextPageToken")
           }}

        {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 400, message: message}}

        {:ok, %{status: status, body: body}} ->
          {:error, %{status: status, message: "API error", body: body}}

        {:error, reason} ->
          {:error, %{reason: :network_error, message: inspect(reason)}}
      end
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Deletes a file.

  ## Parameters
    * `file_name` - The file name (e.g., "files/abc-123")
    * `opts` - Options including `:config_provider`

  ## Examples
      
      :ok = ExLLM.Providers.Gemini.Files.delete_file("files/abc-123")
  """
  @spec delete_file(String.t(), Keyword.t()) :: :ok | {:error, term()}
  def delete_file(file_name, opts \\ []) do
    with :ok <- validate_file_name(file_name),
         config_provider <- get_config_provider(opts),
         config <- ConfigHelper.get_config(:gemini, config_provider),
         api_key <- get_api_key(config),
         {:ok, _} <- validate_api_key(api_key) do
      url = build_url("/v1beta/#{file_name}", api_key)
      headers = build_headers()

      case Req.delete(url, headers: headers) do
        {:ok, %{status: status}} when status in [200, 204] ->
          :ok

        {:ok, %{status: 404}} ->
          {:error, %{status: 404, message: "File not found: #{file_name}"}}

        {:ok, %{status: 403, body: body}} ->
          {:error, %{status: 403, message: "API error", body: body}}

        {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
          {:error, %{status: 400, message: message}}

        {:ok, %{status: status, body: body}} ->
          {:error, %{status: status, message: "API error", body: body}}

        {:error, reason} ->
          {:error, %{reason: :network_error, message: inspect(reason)}}
      end
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Waits for a file to become active (processed).

  ## Parameters
    * `file_name` - The file name (e.g., "files/abc-123")
    * `opts` - Options including `:timeout`, `:poll_interval`, and `:config_provider`

  ## Examples
      
      {:ok, file} = ExLLM.Providers.Gemini.Files.wait_for_file("files/abc-123", timeout: 30_000)
  """
  @spec wait_for_file(String.t(), wait_options()) :: {:ok, File.t()} | {:error, term()}
  def wait_for_file(file_name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)
    poll_interval = Keyword.get(opts, :poll_interval, 1_000)

    wait_until = System.monotonic_time(:millisecond) + timeout

    do_wait_for_file(file_name, wait_until, poll_interval, opts)
  end

  # Public helper functions exposed for testing

  @doc false
  @spec validate_file_path(String.t() | nil) :: :ok | {:error, map()}
  def validate_file_path(nil),
    do: {:error, %{reason: :invalid_params, message: "File path is required"}}

  def validate_file_path(""),
    do: {:error, %{reason: :invalid_params, message: "File path is required"}}

  def validate_file_path(path) when is_binary(path) do
    if Elixir.File.exists?(path) do
      :ok
    else
      {:error, %{reason: :file_not_found, message: "File not found: #{path}"}}
    end
  end

  @doc false
  @spec validate_file_name(String.t() | nil) :: :ok | {:error, map()}
  def validate_file_name(nil),
    do: {:error, %{reason: :invalid_params, message: "File name is required"}}

  def validate_file_name(""),
    do: {:error, %{reason: :invalid_params, message: "File name is required"}}

  def validate_file_name(name) when is_binary(name) do
    if String.starts_with?(name, "files/") and String.length(name) > 6 do
      :ok
    else
      {:error, %{reason: :invalid_params, message: "Invalid file name format"}}
    end
  end

  @doc false
  @spec validate_page_size(term()) :: :ok | {:error, map()}
  def validate_page_size(size) when is_integer(size) and size > 0 and size <= 100, do: :ok

  def validate_page_size(_),
    do: {:error, %{reason: :invalid_params, message: "Page size must be between 1 and 100"}}

  @doc false
  @spec mime_type_from_extension(String.t()) :: String.t()
  def mime_type_from_extension(ext) do
    ext =
      ext
      |> String.downcase()
      |> String.trim_leading(".")

    case ext do
      "txt" -> "text/plain"
      "png" -> "image/png"
      "jpg" -> "image/jpeg"
      "jpeg" -> "image/jpeg"
      "gif" -> "image/gif"
      "webp" -> "image/webp"
      "mp4" -> "video/mp4"
      "mp3" -> "audio/mp3"
      "wav" -> "audio/wav"
      "pdf" -> "application/pdf"
      _ -> "application/octet-stream"
    end
  end

  @doc false
  @spec parse_state(String.t() | nil) :: atom()
  def parse_state(nil), do: nil
  def parse_state("STATE_UNSPECIFIED"), do: :state_unspecified
  def parse_state("PROCESSING"), do: :processing
  def parse_state("ACTIVE"), do: :active
  def parse_state("FAILED"), do: :failed

  def parse_state(state) when is_binary(state) do
    state |> String.downcase() |> String.to_atom()
  end

  @doc false
  @spec parse_source(String.t() | nil) :: atom()
  def parse_source(nil), do: nil
  def parse_source("SOURCE_UNSPECIFIED"), do: :source_unspecified
  def parse_source("UPLOADED"), do: :uploaded
  def parse_source("GENERATED"), do: :generated

  def parse_source(source) when is_binary(source) do
    source |> String.downcase() |> String.to_atom()
  end

  @doc false
  @spec parse_timestamp(String.t() | nil) :: DateTime.t() | nil
  def parse_timestamp(nil), do: nil
  def parse_timestamp(""), do: nil

  def parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end

  @doc false
  @spec parse_duration(String.t() | nil) :: float() | nil
  def parse_duration(nil), do: nil

  def parse_duration(duration) when is_binary(duration) do
    case Regex.run(~r/^(\d+(?:\.\d+)?)s$/, duration) do
      [_, number] ->
        if String.contains?(number, ".") do
          String.to_float(number)
        else
          String.to_float(number <> ".0")
        end

      nil ->
        nil
    end
  end

  @doc false
  @spec build_upload_metadata(String.t(), Keyword.t()) :: map()
  def build_upload_metadata(_file_path, opts) do
    file_metadata = %{}

    file_metadata =
      case Keyword.get(opts, :display_name) do
        nil -> file_metadata
        name -> Map.put(file_metadata, "displayName", name)
      end

    %{"file" => file_metadata}
  end

  @doc false
  @spec extract_upload_url(list({binary(), binary()}) | %{binary() => [binary()]}) :: {:ok, String.t()} | {:error, map()}
  def extract_upload_url(headers) when is_list(headers) or is_map(headers) do
    upload_url =
      headers
      |> Enum.find_value(fn {k, v} ->
        if String.downcase(k) == "x-goog-upload-url", do: v, else: nil
      end)

    case upload_url do
      [url | _] when is_binary(url) ->
        {:ok, url}

      url when is_binary(url) ->
        {:ok, url}

      nil ->
        {:error,
         %{reason: :upload_url_not_found, message: "Upload URL not found in response headers"}}

      _ ->
        {:error, %{reason: :invalid_upload_url, message: "Invalid upload URL format"}}
    end
  end

  # Private functions

  defp get_config_provider(opts) do
    Keyword.get(
      opts,
      :config_provider,
      Application.get_env(:ex_llm, :config_provider, ExLLM.Infrastructure.ConfigProvider.Default)
    )
  end

  defp get_api_key(config) do
    config[:api_key] || System.get_env("GOOGLE_API_KEY") || System.get_env("GEMINI_API_KEY")
  end

  defp validate_api_key(nil),
    do: {:error, %{reason: :missing_api_key, message: "API key is required"}}

  defp validate_api_key(""),
    do: {:error, %{reason: :missing_api_key, message: "API key is required"}}

  defp validate_api_key(_), do: {:ok, :valid}

  defp validate_list_params(opts) do
    case Keyword.get(opts, :page_size) do
      nil -> :ok
      size -> validate_page_size(size)
    end
  end

  defp get_mime_type(file_path) do
    ext = Path.extname(file_path)
    mime_type_from_extension(ext)
  end

  defp initiate_upload(api_key, mime_type, file_size, metadata) do
    url = build_url("/upload/v1beta/files", api_key)

    headers = [
      {"X-Goog-Upload-Protocol", "resumable"},
      {"X-Goog-Upload-Command", "start"},
      {"X-Goog-Upload-Header-Content-Length", to_string(file_size)},
      {"X-Goog-Upload-Header-Content-Type", mime_type},
      {"Content-Type", "application/json"}
    ]

    case Req.post(url, json: metadata, headers: headers) do
      {:ok, %{status: 200, headers: response_headers}} ->
        extract_upload_url(response_headers)

      {:ok, %{status: 400, body: %{"error" => %{"message" => message}}}} ->
        {:error, %{status: 400, message: message}}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, message: "Failed to initiate upload", body: body}}

      {:error, reason} ->
        {:error, %{reason: :network_error, message: inspect(reason)}}
    end
  end

  defp upload_content(upload_url, file_data, file_size) do
    headers = [
      {"Content-Length", to_string(file_size)},
      {"X-Goog-Upload-Offset", "0"},
      {"X-Goog-Upload-Command", "upload, finalize"}
    ]

    case Req.request(method: :put, url: upload_url, body: file_data, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, File.from_api(body["file"])}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, message: "Failed to upload content", body: body}}

      {:error, reason} ->
        {:error, %{reason: :network_error, message: inspect(reason)}}
    end
  end

  defp do_wait_for_file(file_name, wait_until, poll_interval, opts) do
    now = System.monotonic_time(:millisecond)

    if now > wait_until do
      {:error, :timeout}
    else
      case get_file(file_name, opts) do
        {:ok, %File{state: :active} = file} ->
          {:ok, file}

        {:ok, %File{state: :failed} = file} ->
          {:ok, file}

        {:ok, %File{state: :processing}} ->
          Process.sleep(poll_interval)
          do_wait_for_file(file_name, wait_until, poll_interval, opts)

        {:error, _} = error ->
          error
      end
    end
  end

  defp build_list_query_params(opts) do
    params = %{}

    params =
      case Keyword.get(opts, :page_size) do
        nil -> params
        size -> Map.put(params, "pageSize", size)
      end

    case Keyword.get(opts, :page_token) do
      nil -> params
      token -> Map.put(params, "pageToken", token)
    end
  end

  defp build_url(path, api_key, query_params \\ %{}) do
    base = "https://generativelanguage.googleapis.com"
    query_params = Map.put(query_params, "key", api_key)
    query_string = URI.encode_query(query_params)
    "#{base}#{path}?#{query_string}"
  end

  defp build_headers do
    [
      {"User-Agent", "ExLLM/0.4.2 (Elixir)"}
    ]
  end
end
