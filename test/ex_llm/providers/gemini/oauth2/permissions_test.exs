defmodule ExLLM.Providers.Gemini.OAuth2.PermissionsTest do
  @moduledoc """
  Tests for Gemini Permissions API via OAuth2.

  This module tests permission management for tuned models including
  creating, updating, and deleting permissions.
  """

  use ExLLM.Testing.OAuth2TestCase, timeout: 300_000

  alias ExLLM.Providers.Gemini.Permissions

  @moduletag :gemini_oauth2_apis
  @moduletag :permissions_management

  describe "Permissions API for Tuned Models" do
    @describetag :oauth2
    @describetag :requires_tuned_model

    # Note: These tests require an actual tuned model to work properly
    # They will be skipped unless you have created a tuned model

    test "manage permissions on tuned model", %{oauth_token: token} do
      # This test requires you to have a tuned model
      # Replace with your actual tuned model name
      model_name = System.get_env("TEST_TUNED_MODEL") || "tunedModels/test-model"

      # Try to list permissions (will fail if model doesn't exist)
      case Permissions.list_permissions(model_name, oauth_token: token, skip_cache: true) do
        {:ok, response} ->
          # If we have a real model, test permission management
          assert is_list(response.permissions)

          # Add a permission
          {:ok, permission} =
            Permissions.create_permission(
              model_name,
              %{
                grantee_type: :USER,
                email_address: "test@example.com",
                role: :READER
              },
              oauth_token: token
            )

          assert permission.grantee_type == :USER
          assert permission.role == :READER

          # Update permission role
          updated_permission = %{permission | role: :WRITER}

          {:ok, updated} =
            Permissions.update_permission(
              permission.name,
              updated_permission,
              oauth_token: token
            )

          assert updated.role == :WRITER

          # Delete permission
          :ok =
            Permissions.delete_permission(permission.name, oauth_token: token, skip_cache: true)

        {:error, error} ->
          # Handle wrapped error format from Gemini API
          message = Map.get(error, :message, "")

          if error[:reason] == :network_error and
               (message =~ "403" or message =~ "404" or message =~ "PERMISSION_DENIED") do
            # Model doesn't exist - skip this test
            IO.puts("\nℹ️  Skipping permission management test - no tuned model available")
            IO.puts("   Set TEST_TUNED_MODEL environment variable to test with a real model\n")
            assert true
          else
            # Fail on unexpected errors
            flunk("Unexpected error when listing permissions: #{inspect(error)}")
          end
      end
    end
  end
end
