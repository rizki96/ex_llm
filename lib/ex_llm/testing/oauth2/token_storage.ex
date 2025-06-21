defmodule ExLLM.Testing.OAuth2.TokenStorage do
  @moduledoc """
  Token storage abstraction for OAuth2 providers.

  Handles reading, writing, and validating OAuth2 tokens from various storage backends.
  Currently supports file-based storage with JSON format.
  """

  require Logger

  @doc """
  Loads tokens from the specified file.

  Returns {:ok, tokens} if successful, or {:error, reason} otherwise.
  """
  @spec load_tokens(String.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def load_tokens(token_file) do
    token_path = Path.join(File.cwd!(), token_file)

    case File.read(token_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, tokens} ->
            if valid_token_structure?(tokens) do
              Logger.debug("✓ Loaded tokens from #{token_file}")
              check_token_expiry(tokens)
              {:ok, tokens}
            else
              {:error, "Invalid token structure in #{token_file}"}
            end

          {:error, _} ->
            {:error, "Invalid JSON in #{token_file}"}
        end

      {:error, :enoent} ->
        {:error, "Token file not found: #{token_file}"}

      {:error, reason} ->
        {:error, "Failed to read #{token_file}: #{reason}"}
    end
  end

  @doc """
  Saves tokens to the specified file.

  Returns :ok if successful, or {:error, reason} otherwise.
  """
  @spec save_tokens(map(), String.t()) :: :ok | {:error, atom() | String.t()}
  def save_tokens(tokens, token_file) do
    token_path = Path.join(File.cwd!(), token_file)

    # Add timestamp for tracking
    tokens_with_metadata =
      tokens
      |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())
      |> Map.put("expires_at", calculate_expiry(tokens))

    case Jason.encode(tokens_with_metadata, pretty: true) do
      {:ok, json} ->
        case File.write(token_path, json) do
          :ok ->
            Logger.info("✅ Saved tokens to #{token_file}")
            :ok

          {:error, reason} ->
            {:error, "Failed to write #{token_file}: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Failed to encode tokens: #{reason}"}
    end
  end

  @doc """
  Checks if a token is expired or about to expire.

  Returns true if the token needs refresh, false otherwise.
  """
  @spec token_needs_refresh?(map()) :: boolean()
  def token_needs_refresh?(tokens) do
    case tokens do
      %{"expires_at" => expires_at} when is_binary(expires_at) ->
        case DateTime.from_iso8601(expires_at) do
          {:ok, expiry_time, _} ->
            # Refresh if expires within 5 minutes
            buffer_time = DateTime.add(DateTime.utc_now(), 5 * 60, :second)
            DateTime.compare(expiry_time, buffer_time) == :lt

          _ ->
            true
        end

      %{"expires_in" => expires_in} when is_integer(expires_in) ->
        # If we have expires_in but no expires_at, assume it needs refresh
        expires_in < 300

      _ ->
        # If we don't have expiry information, assume it needs refresh
        true
    end
  end

  @doc """
  Validates the token file structure.

  Returns true if the token structure is valid, false otherwise.
  """
  @spec valid_token_structure?(map()) :: boolean()
  def valid_token_structure?(tokens) do
    case tokens do
      %{"access_token" => access_token, "refresh_token" => refresh_token}
      when is_binary(access_token) and is_binary(refresh_token) ->
        true

      _ ->
        false
    end
  end

  @doc """
  Creates a backup of the token file before modification.

  Returns :ok if successful, or {:error, reason} otherwise.
  """
  @spec backup_tokens(String.t()) :: :ok | {:error, String.t()}
  def backup_tokens(token_file) do
    token_path = Path.join(File.cwd!(), token_file)
    backup_path = "#{token_path}.backup.#{System.system_time(:second)}"

    case File.copy(token_path, backup_path) do
      {:ok, _} ->
        Logger.debug("Created token backup: #{backup_path}")
        :ok

      {:error, reason} ->
        {:error, "Failed to backup tokens: #{reason}"}
    end
  end

  # Private helper functions

  defp check_token_expiry(tokens) do
    if token_needs_refresh?(tokens) do
      Logger.warning("⚠️  OAuth2 token is expired or about to expire")
    else
      Logger.debug("✓ OAuth2 token is valid")
    end
  end

  defp calculate_expiry(tokens) do
    case tokens do
      %{"expires_in" => expires_in} when is_integer(expires_in) ->
        DateTime.utc_now()
        |> DateTime.add(expires_in, :second)
        |> DateTime.to_iso8601()

      _ ->
        # Default to 1 hour if no expiry information
        DateTime.utc_now()
        |> DateTime.add(3600, :second)
        |> DateTime.to_iso8601()
    end
  end
end
