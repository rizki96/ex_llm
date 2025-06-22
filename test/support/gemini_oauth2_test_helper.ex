defmodule ExLLM.Testing.GeminiOAuth2Helper do
  @moduledoc """
  Test helper for Gemini OAuth2 authentication.

  This module provides utilities for using OAuth2 tokens in tests,
  including automatic token refresh when needed.

  NOTE: This module now uses the new generalized OAuth2 infrastructure
  while maintaining backward compatibility with existing code.
  """

  require Logger

  alias ExLLM.Testing.OAuth2.Helper

  @token_file ".gemini_tokens"

  @doc """
  Gets a valid OAuth2 token for testing.

  This function:
  1. Checks for tokens in environment variables (CI/CD friendly)
  2. Falls back to loading from .gemini_tokens file
  3. Automatically refreshes if token is expired
  4. Returns nil if no tokens are available

  ## Usage in Tests

      setup do
        case ExLLM.Testing.GeminiOAuth2Helper.get_valid_token() do
          {:ok, token} ->
            {:ok, oauth_token: token}
          {:error, :no_token} ->
            :ok  # Skip OAuth tests
          {:error, reason} ->
            raise "OAuth2 setup error: \#{reason}"
        end
      end
      
      @tag :oauth_required
      test "list permissions", %{oauth_token: token} do
        {:ok, perms} = ExLLM.Gemini.Permissions.list_permissions(
          "tunedModels/test",
          oauth_token: token
        )
        # assertions...
      end
  """
  @spec get_valid_token() :: {:ok, String.t()} | {:error, :no_token | String.t()}
  def get_valid_token do
    # Use new generalized OAuth2 infrastructure
    Helper.get_valid_token(:google)
  end

  @doc """
  Checks if OAuth2 tokens are available for testing.
  """
  @spec oauth_available?() :: boolean()
  def oauth_available? do
    # Use new generalized OAuth2 infrastructure
    Helper.oauth_available?(:google)
  end

  @doc """
  Setup function that provides OAuth token if available.

  NOTE: ExUnit doesn't support skipping tests from setup callbacks.
  Tests should check for the presence of oauth_token in context.

  ## Usage

      setup :skip_without_oauth
      
      test "requires oauth", %{oauth_token: token} = context do
        # Check if we should skip
        if Map.get(context, :oauth_unavailable) do
          IO.puts("Skipping: OAuth tokens not available")
        else
          # Your test logic here
          assert is_binary(token)
        end
      end

  ## Alternative: Use @moduletag or @tag

      # Skip entire module if no OAuth
      if not ExLLM.Testing.GeminiOAuth2Helper.oauth_available?() do
        @moduletag :skip
      end

      # Or for individual tests
      @tag :requires_oauth
      test "requires oauth" do
        # test implementation
      end

      # Then in test_helper.exs:
      if not ExLLM.Testing.GeminiOAuth2Helper.oauth_available?() do
        ExUnit.configure(exclude: [:requires_oauth])
      end
  """
  def skip_without_oauth(context) do
    if oauth_available?() do
      case get_valid_token() do
        {:ok, token} ->
          Map.merge(context, %{oauth_token: token})

        _ ->
          Map.merge(context, %{oauth_token: nil, oauth_unavailable: true})
      end
    else
      IO.puts("\n⚠️  OAuth2 tokens not available for test")
      IO.puts("   Run: elixir scripts/setup_oauth2.exs")
      Map.merge(context, %{oauth_unavailable: true})
    end
  end

  @doc """
  Gets stored refresh token.
  """
  @spec get_refresh_token() :: {:ok, String.t()} | {:error, :no_token | String.t()}
  def get_refresh_token do
    case System.get_env("GEMINI_REFRESH_TOKEN") do
      nil ->
        case load_tokens() do
          {:ok, tokens} ->
            case tokens["refresh_token"] do
              nil -> {:error, :no_token}
              token -> {:ok, token}
            end

          error ->
            error
        end

      token ->
        {:ok, token}
    end
  end

  # Private functions

  defp load_tokens do
    token_path = Path.join(File.cwd!(), @token_file)

    case File.read(token_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, tokens} -> {:ok, tokens}
          {:error, _} -> {:error, "Invalid token file format"}
        end

      {:error, :enoent} ->
        {:error, :no_token}

      {:error, reason} ->
        {:error, "Failed to read tokens: #{reason}"}
    end
  end

  # This function is kept for backward compatibility but not currently used
  # defp refresh_token do
  #   refresh_script = Path.join(File.cwd!(), @token_refresh_script)

  #   if File.exists?(refresh_script) do
  #     case System.cmd("elixir", [refresh_script], stderr_to_stdout: true) do
  #       {output, 0} ->
  #         if String.contains?(output, "✅") do
  #           IO.puts("✅ Token refreshed successfully")
  #           :ok
  #         else
  #           {:error, "Token refresh failed"}
  #         end

  #       {output, _} ->
  #         {:error, "Token refresh failed: #{output}"}
  #     end
  #   else
  #     {:error, "Refresh script not found. Token expired."}
  #   end
  # end

  @doc """
  Creates a mock OAuth2 token for testing error scenarios.
  """
  def mock_token(type \\ :invalid) do
    case type do
      :invalid -> "invalid-token-123"
      :expired -> "ya29.expired-#{:rand.uniform(1000)}"
      :malformed -> "not-a-valid-jwt"
      _ -> "mock-token-#{type}"
    end
  end

  @doc """
  Test helper to assert OAuth2 authentication errors.
  """
  def assert_oauth_error({:error, %{status: 401} = error}) do
    if error.message =~ "API keys are not supported" or
         error.message =~ "authentication" or
         error.message =~ "unauthorized" do
      :ok
    else
      {:error, "Expected OAuth2 authentication message, got: #{error.message}"}
    end
  end

  def assert_oauth_error({:error, %{message: message, reason: :network_error}})
      when is_binary(message) do
    if String.contains?(message, "status: 401") or
         String.contains?(message, "UNAUTHENTICATED") or
         String.contains?(message, "API keys are not supported") or
         String.contains?(message, "authentication") or
         String.contains?(message, "unauthorized") do
      :ok
    else
      {:error, "Expected OAuth2 authentication message, got: #{message}"}
    end
  end

  def assert_oauth_error(other) do
    {:error, "Expected OAuth2 authentication error (401), got: #{inspect(other)}"}
  end

  @doc """
  Cleanup all test corpora to avoid hitting Gemini's quota limits.

  This function uses raw HTTP requests to bypass caching and lists all corpora,
  deleting any that match test naming patterns.
  Should be called periodically or in test teardown to prevent accumulation.
  """
  @spec cleanup_test_corpora(String.t()) :: :ok | {:error, String.t()}
  def cleanup_test_corpora(oauth_token) do
    case list_corpora_raw(oauth_token) do
      {:ok, corpora} ->
        test_corpora = Enum.filter(corpora, &is_test_corpus?/1)

        IO.puts("Found #{length(test_corpora)} test corpora to cleanup")

        results =
          Enum.map(test_corpora, fn corpus ->
            display_name = corpus["displayName"] || "Unknown"
            corpus_name = corpus["name"]
            IO.puts("Deleting corpus: #{display_name}")

            # First try to cleanup documents within the corpus (needed before deleting corpus)
            cleanup_corpus_contents(corpus_name, oauth_token)

            case delete_corpus_raw(corpus_name, oauth_token) do
              :ok ->
                :ok

              error ->
                IO.warn("Failed to delete corpus #{display_name}: #{inspect(error)}")
                error
            end
          end)

        # Return error only if all deletions failed
        if Enum.all?(results, &match?({:error, _}, &1)) and length(results) > 0 do
          {:error, "Failed to delete any test corpora"}
        else
          IO.puts("Cleanup completed successfully")
          :ok
        end

      {:error, reason} ->
        {:error, "Failed to list corpora: #{inspect(reason)}"}
    end
  end

  @doc """
  Cleanup test documents and chunks within a corpus.
  """
  @spec cleanup_test_documents(String.t(), String.t()) :: :ok | {:error, String.t()}
  def cleanup_test_documents(corpus_name, oauth_token) do
    case ExLLM.Providers.Gemini.Document.list_documents(corpus_name, oauth_token: oauth_token) do
      {:ok, response} ->
        test_documents = Enum.filter(response.documents || [], &is_test_document?/1)

        Enum.each(test_documents, fn document ->
          case ExLLM.Providers.Gemini.Document.delete_document(document.name,
                 oauth_token: oauth_token
               ) do
            :ok ->
              :ok

            # Already deleted
            {:error, %{status: 404}} ->
              :ok

            error ->
              IO.warn("Failed to delete document #{document.display_name}: #{inspect(error)}")
          end
        end)

        :ok

      {:error, reason} ->
        {:error, "Failed to list documents: #{inspect(reason)}"}
    end
  end

  @doc """
  Cleanup all contents (documents and chunks) within a corpus before deletion.
  """
  @spec cleanup_corpus_contents(String.t(), String.t()) :: :ok
  def cleanup_corpus_contents(corpus_name, oauth_token) do
    try do
      # Use raw HTTP to list and delete documents to bypass caching and avoid module dependencies
      case list_documents_raw(corpus_name, oauth_token) do
        {:ok, documents} ->
          Enum.each(documents, fn document ->
            document_name = document["name"]

            # First delete all chunks in this document (required before document deletion)
            case list_chunks_raw(document_name, oauth_token) do
              {:ok, chunks} ->
                Enum.each(chunks, fn chunk ->
                  chunk_name = chunk["name"]
                  delete_chunk_raw(chunk_name, oauth_token)
                end)

              {:error, _} ->
                # Document might have no chunks or be inaccessible
                :ok
            end

            # Now delete the document
            delete_document_raw(document_name, oauth_token)
          end)

        {:error, _} ->
          # Corpus might be empty or inaccessible
          :ok
      end
    rescue
      _ -> :ok
    end

    :ok
  end

  @doc """
  Global cleanup function that should be called before running OAuth2 tests
  to ensure we're under quota limits.
  """
  @spec global_cleanup() :: :ok | :skip
  def global_cleanup do
    # Use new generalized OAuth2 infrastructure
    Helper.global_cleanup(:google)

    # Keep existing cleanup logic for backward compatibility
    case get_valid_token() do
      {:ok, token} ->
        IO.puts("Performing global cleanup of test resources...")

        # First check quota and show all corpora
        case check_corpus_quota(token) do
          {:ok, count} when count >= 5 ->
            IO.warn("At quota limit (#{count}/5 corpora). Forcing cleanup of ALL corpora...")
            force_cleanup_all_corpora(token)
            # Wait for deletion to propagate
            Process.sleep(3000)
            check_corpus_quota(token)

          {:ok, count} when count > 0 ->
            IO.puts("Found #{count} existing corpora - cleaning up...")
            # Try test cleanup first
            cleanup_test_corpora(token)
            # Wait and check again
            Process.sleep(2000)

            case check_corpus_quota(token) do
              {:ok, remaining} when remaining >= 5 ->
                IO.warn("Still at limit after test cleanup. Forcing full cleanup...")
                force_cleanup_all_corpora(token)
                Process.sleep(3000)

              {:ok, remaining} ->
                IO.puts("After cleanup: #{remaining}/5 corpora remaining")

              _ ->
                :ok
            end

          {:ok, 0} ->
            IO.puts("No corpora found - quota is clear")

          {:error, reason} ->
            IO.warn("Could not check quota: #{inspect(reason)}")
        end

        :ok

      {:error, :no_token} ->
        IO.puts("No OAuth2 token available, skipping cleanup")
        :skip

      {:error, reason} ->
        IO.warn("OAuth2 cleanup failed: #{reason}")
        # Don't fail the test suite
        :ok
    end
  end

  @doc """
  Checks current corpus quota usage and lists all corpora using raw HTTP requests.
  """
  @spec check_corpus_quota(String.t()) :: {:ok, integer()} | {:error, String.t()}
  def check_corpus_quota(oauth_token) do
    case list_corpora_raw(oauth_token) do
      {:ok, corpora} ->
        count = length(corpora)

        # Debug: Show all corpora
        if count > 0 do
          IO.puts("Current corpora (#{count}/5):")

          Enum.each(corpora, fn corpus ->
            display_name = corpus["displayName"] || "Unknown"
            name = corpus["name"] || "Unknown"
            IO.puts("  - #{display_name} (#{name})")
          end)
        end

        {:ok, count}

      {:error, reason} ->
        {:error, "Failed to check quota: #{inspect(reason)}"}
    end
  end

  @doc """
  Forces cleanup of ALL corpora using raw HTTP requests - use with caution!
  This removes all corpora in the account, not just test ones.
  """
  @spec force_cleanup_all_corpora(String.t()) :: :ok | {:error, String.t()}
  def force_cleanup_all_corpora(oauth_token) do
    case list_corpora_raw(oauth_token) do
      {:ok, all_corpora} ->
        IO.puts("⚠️  FORCING cleanup of ALL #{length(all_corpora)} corpora...")

        results =
          Enum.map(all_corpora, fn corpus ->
            display_name = corpus["displayName"] || "Unknown"
            corpus_name = corpus["name"]
            IO.puts("Deleting corpus: #{display_name}")

            # First try to cleanup documents within the corpus (needed before deleting corpus)
            cleanup_corpus_contents(corpus_name, oauth_token)

            case delete_corpus_raw(corpus_name, oauth_token) do
              :ok ->
                :ok

              error ->
                IO.warn("Failed to delete corpus #{display_name}: #{inspect(error)}")
                error
            end
          end)

        # Return error only if all deletions failed
        if Enum.all?(results, &match?({:error, _}, &1)) and length(results) > 0 do
          {:error, "Failed to delete any corpora"}
        else
          IO.puts("Force cleanup completed successfully")
          :ok
        end

      {:error, reason} ->
        {:error, "Failed to list corpora for force cleanup: #{inspect(reason)}"}
    end
  end

  @doc """
  Quick cleanup function that can be called in test teardown.
  """
  @spec quick_cleanup() :: :ok
  def quick_cleanup do
    # Use new generalized OAuth2 infrastructure
    Helper.cleanup(:google)

    # Keep existing cleanup logic for backward compatibility
    case get_valid_token() do
      {:ok, token} ->
        cleanup_test_corpora(token)
        :ok

      _ ->
        :ok
    end
  end

  # Raw HTTP request functions to bypass caching

  @spec list_corpora_raw(String.t()) :: {:ok, [map()]} | {:error, String.t()}
  defp list_corpora_raw(oauth_token) do
    url = "https://generativelanguage.googleapis.com/v1beta/corpora"

    headers = [
      authorization: "Bearer #{oauth_token}",
      content_type: "application/json"
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        case body do
          %{"corpora" => corpora} when is_list(corpora) ->
            {:ok, corpora}

          _response ->
            # No corpora field means empty list
            {:ok, []}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  @spec delete_corpus_raw(String.t(), String.t()) :: :ok | {:error, integer() | String.t()}
  defp delete_corpus_raw(corpus_name, oauth_token) do
    url = "https://generativelanguage.googleapis.com/v1beta/#{corpus_name}"

    headers = [
      authorization: "Bearer #{oauth_token}",
      content_type: "application/json"
    ]

    case Req.delete(url, headers: headers) do
      {:ok, %{status: status}} when status in [200, 204, 404] ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, "Delete failed #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  # Private helpers

  defp is_test_corpus?(corpus) when is_map(corpus) do
    # Handle both struct format (from ExLLM API) and raw map format (from HTTP)
    name =
      case corpus do
        %{"displayName" => display_name} -> display_name || ""
        %{display_name: display_name} -> display_name || ""
        _ -> ""
      end

    String.contains?(name, "test") or
      String.contains?(name, "corpus") or
      String.starts_with?(name, "doc-test") or
      String.starts_with?(name, "chunk-test") or
      String.starts_with?(name, "qa-test")
  end

  defp is_test_document?(document) do
    # Handle both struct format (from ExLLM API) and raw map format (from HTTP)
    name =
      case document do
        %{"displayName" => display_name} -> display_name || ""
        %{display_name: display_name} -> display_name || ""
        _ -> ""
      end

    String.contains?(name, "test") or
      String.contains?(name, "sample") or
      String.starts_with?(name, "Test Document")
  end

  @spec list_documents_raw(String.t(), String.t()) :: {:ok, [map()]} | {:error, String.t()}
  defp list_documents_raw(corpus_name, oauth_token) do
    url = "https://generativelanguage.googleapis.com/v1beta/#{corpus_name}/documents"

    headers = [
      authorization: "Bearer #{oauth_token}",
      content_type: "application/json"
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        case body do
          %{"documents" => documents} when is_list(documents) ->
            {:ok, documents}

          _response ->
            # No documents field means empty list
            {:ok, []}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  @spec delete_document_raw(String.t(), String.t()) :: :ok | {:error, integer() | String.t()}
  defp delete_document_raw(document_name, oauth_token) do
    url = "https://generativelanguage.googleapis.com/v1beta/#{document_name}"

    headers = [
      authorization: "Bearer #{oauth_token}",
      content_type: "application/json"
    ]

    case Req.delete(url, headers: headers) do
      {:ok, %{status: status}} when status in [200, 204, 404] ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, "Delete failed #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  @spec list_chunks_raw(String.t(), String.t()) :: {:ok, [map()]} | {:error, String.t()}
  defp list_chunks_raw(document_name, oauth_token) do
    url = "https://generativelanguage.googleapis.com/v1beta/#{document_name}/chunks"

    headers = [
      authorization: "Bearer #{oauth_token}",
      content_type: "application/json"
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        case body do
          %{"chunks" => chunks} when is_list(chunks) ->
            {:ok, chunks}

          _response ->
            # No chunks field means empty list
            {:ok, []}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  @spec delete_chunk_raw(String.t(), String.t()) :: :ok | {:error, integer() | String.t()}
  defp delete_chunk_raw(chunk_name, oauth_token) do
    url = "https://generativelanguage.googleapis.com/v1beta/#{chunk_name}"

    headers = [
      authorization: "Bearer #{oauth_token}",
      content_type: "application/json"
    ]

    case Req.delete(url, headers: headers) do
      {:ok, %{status: status}} when status in [200, 204, 404] ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, "Delete failed #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end
end
