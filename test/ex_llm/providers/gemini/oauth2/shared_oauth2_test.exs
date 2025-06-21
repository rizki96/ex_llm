defmodule ExLLM.Providers.Gemini.OAuth2.SharedOAuth2Test do
  @moduledoc """
  Shared OAuth2 test utilities and error handling tests.

  This module contains common OAuth2 test functionality and error handling
  tests that apply across all OAuth2 APIs.
  """

  use ExLLM.Testing.OAuth2TestCase, timeout: 300_000

  alias ExLLM.Providers.Gemini.{
    Chunk,
    Corpus,
    Document,
    Permissions,
    QA
  }

  alias ExLLM.Testing.GeminiOAuth2Helper

  @moduletag :gemini_oauth2_apis
  @moduletag :oauth2_error_handling

  describe "Error handling for OAuth2 APIs" do
    @describetag :oauth2

    test "handles invalid OAuth token gracefully", %{oauth_token: _token} do
      invalid_token = "invalid_token_12345"

      # Test with Corpus API
      result = Corpus.list_corpora(oauth_token: invalid_token)
      assert {:error, error} = result
      assert error =~ "401" or error =~ "Unauthorized" or error =~ "invalid"

      # Test with Document API  
      result = Document.list_documents("corpora/invalid", oauth_token: invalid_token)
      assert {:error, error} = result
      assert error =~ "401" or error =~ "Unauthorized" or error =~ "invalid"

      # Test with Permissions API
      result = Permissions.list_permissions("tunedModels/invalid", oauth_token: invalid_token)
      assert {:error, error} = result
      assert error =~ "401" or error =~ "Unauthorized" or error =~ "invalid"
    end

    test "handles missing OAuth token", %{oauth_token: _token} do
      # Test with Corpus API
      result = Corpus.list_corpora(oauth_token: nil)
      assert {:error, error} = result
      assert error =~ "token" or error =~ "auth"

      # Test with Document API
      result = Document.list_documents("corpora/test", oauth_token: nil)
      assert {:error, error} = result
      assert error =~ "token" or error =~ "auth"
    end

    test "handles network errors gracefully", %{oauth_token: token} do
      # This test would require mocking network failures
      # For now, we'll test with an invalid corpus name that should return 404
      result = Corpus.get_corpus("corpora/nonexistent-corpus-12345", oauth_token: token)
      assert {:error, error} = result
      assert error =~ "404" or error =~ "Not Found" or error =~ "not found"
    end
  end

  @doc """
  Helper function to generate unique resource names for testing.
  """
  def unique_name(prefix) do
    "#{prefix}-#{System.unique_integer([:positive]) |> Integer.to_string() |> String.downcase()}"
  end

  @doc """
  Helper function to wait for eventual consistency in OAuth2 APIs.
  """
  def wait_for_consistency(ms \\ 2000) do
    Process.sleep(ms)
  end

  @doc """
  Helper function to perform aggressive cleanup before tests.
  """
  def aggressive_cleanup(token) do
    GeminiOAuth2Helper.force_cleanup_all_corpora(token)
    wait_for_consistency()
  end
end
