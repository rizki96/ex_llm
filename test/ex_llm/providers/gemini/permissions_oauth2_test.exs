defmodule ExLLM.Providers.Gemini.PermissionsOAuth2Test do
  use ExUnit.Case, async: false

  alias ExLLM.Providers.Gemini.Permissions
  alias ExLLM.Testing.GeminiOAuth2Helper

  # Import test cache helpers
  import ExLLM.Testing.TestCacheHelpers

  # Skip entire module if OAuth2 is not available
  if not GeminiOAuth2Helper.oauth_available?() do
    @moduletag :skip
  else
    @moduletag :integration
    @moduletag :external
    @moduletag :oauth2
    @moduletag :requires_oauth
    @moduletag provider: :gemini
  end

  setup context do
    # Setup test caching context
    setup_test_cache(context)

    # Clear context on test exit
    on_exit(fn ->
      ExLLM.Testing.TestCacheDetector.clear_test_context()
    end)

    # Refresh OAuth tokens and get the token
    context = ExLLM.Testing.EnvHelper.setup_oauth(context)

    # Double-check we have a token (should be set by setup_oauth if available)
    if Map.has_key?(context, :oauth_token) do
      context
    else
      # Fallback to the original method if setup_oauth didn't work
      case GeminiOAuth2Helper.get_valid_token() do
        {:ok, token} ->
          Map.put(context, :oauth_token, token)

        _ ->
          # This shouldn't happen if module is tagged to skip
          Map.put(context, :oauth_token, nil)
      end
    end
  end

  describe "with valid OAuth2 token" do
    @describetag :oauth2
    @describetag :oauth_required

    test "lists permissions for a tuned model", %{oauth_token: token} do
      # This will likely return 404 unless you have actual tuned models
      model_name = "tunedModels/test-model-#{System.unique_integer([:positive])}"

      result = Permissions.list_permissions(model_name, oauth_token: token)

      case result do
        {:ok, response} ->
          # If the model exists, verify the response structure
          assert %Permissions.ListPermissionsResponse{} = response
          assert is_list(response.permissions)

        {:error, %{status: 404}} ->
          # Expected for non-existent models - this is fine
          assert true

        {:error, %{message: message, reason: :network_error}} when is_binary(message) ->
          # Handle wrapped API errors - extract the actual error from the message
          if String.contains?(message, "status: 404") or String.contains?(message, "NOT_FOUND") do
            # Expected 404 for non-existent model
            assert true
          else
            flunk("Unexpected network error: #{message}")
          end

        {:error, error} ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end

    test "handles non-existent model gracefully", %{oauth_token: token} do
      result =
        Permissions.get_permission(
          "tunedModels/non-existent/permissions/fake",
          oauth_token: token
        )

      case result do
        {:error, %{status: status}} when status in [403, 404] ->
          assert true

        {:error, %{message: message, reason: :network_error}} when is_binary(message) ->
          # Handle wrapped API errors - check for 403/404 in the message
          if String.contains?(message, "status: 404") or String.contains?(message, "status: 403") or
               String.contains?(message, "NOT_FOUND") or
               String.contains?(message, "PERMISSION_DENIED") do
            assert true
          else
            flunk("Expected 403/404 error, got: #{message}")
          end

        other ->
          flunk("Expected 403/404 error, got: #{inspect(other)}")
      end
    end

    @tag :manual_only
    test "creates and manages permissions", %{oauth_token: _token} do
      # This test requires an actual tuned model that you own
      # Uncomment and update model_name to test with a real model

      # model_name = "tunedModels/your-actual-model"
      # 
      # # Create permission
      # {:ok, permission} = Permissions.create_permission(
      #   model_name,
      #   %{
      #     grantee_type: :USER,
      #     email_address: "test@example.com",
      #     role: :READER
      #   },
      #   oauth_token: token
      # )
      # 
      # assert permission.role == :READER
      # 
      # # Update permission
      # {:ok, updated} = Permissions.update_permission(
      #   permission.name,
      #   %{role: :WRITER},
      #   oauth_token: token,
      #   update_mask: "role"
      # )
      # 
      # assert updated.role == :WRITER
      # 
      # # Delete permission
      # assert {:ok, _} = Permissions.delete_permission(
      #   permission.name,
      #   oauth_token: token
      # )
    end
  end

  describe "OAuth2 error handling" do
    @describetag :integration

    test "returns proper error with invalid token" do
      invalid_token = GeminiOAuth2Helper.mock_token(:invalid)

      result =
        Permissions.list_permissions(
          "tunedModels/test",
          oauth_token: invalid_token
        )

      case GeminiOAuth2Helper.assert_oauth_error(result) do
        :ok -> :ok
        {:error, message} -> flunk(message)
      end
    end

    test "returns error when using API key instead of OAuth2" do
      # The Permissions API specifically requires OAuth2
      result =
        Permissions.list_permissions(
          "tunedModels/test",
          api_key: "some-api-key"
        )

      case result do
        {:error, %{status: 401}} ->
          assert true

        {:error, %{message: message, reason: :network_error}} when is_binary(message) ->
          # Handle wrapped API errors - check for OAuth requirement message
          if String.contains?(message, "status: 401") or
               String.contains?(message, "UNAUTHENTICATED") or
               String.contains?(message, "API keys are not supported") do
            assert true
          else
            flunk("Expected OAuth2 authentication error, got: #{message}")
          end

        other ->
          flunk("Expected OAuth2 authentication error, got: #{inspect(other)}")
      end
    end
  end

  describe "token validation" do
    test "validates token format" do
      # Test various token formats
      tokens = [
        {"valid format", "ya29.a0AfH6SMBx..."},
        {"another valid", "ya29.c0AfH6SMBx..."},
        {"clearly invalid", "not-a-token"},
        {"empty", ""},
        {"nil", nil}
      ]

      for {description, token} <- tokens do
        if token && String.starts_with?(token, "ya29.") do
          assert {:ok, _} = validate_token_format(token),
                 "Token '#{description}' should be valid"
        else
          assert {:error, _} = validate_token_format(token),
                 "Token '#{description}' should be invalid"
        end
      end
    end
  end

  # Helper function
  defp validate_token_format(nil), do: {:error, "Token is nil"}
  defp validate_token_format(""), do: {:error, "Token is empty"}

  defp validate_token_format(token) when is_binary(token) do
    if String.starts_with?(token, "ya29.") do
      {:ok, token}
    else
      {:error, "Invalid token format"}
    end
  end

  defp validate_token_format(_), do: {:error, "Token must be a string"}
end
