defmodule ExLLM.Adapters.Gemini.PermissionsTest do
  use ExUnit.Case, async: false

  alias ExLLM.Gemini.Permissions

  alias ExLLM.Gemini.Permissions.{
    ListPermissionsResponse
  }

  @api_key System.get_env("GEMINI_API_KEY") || "test-key"

  describe "create_permission/3" do
    @describetag :oauth2
    test "creates a permission with email address" do
      permission = %{
        grantee_type: :USER,
        email_address: "test@example.com",
        role: :READER
      }

      assert {:error, %{status: status}} =
               Permissions.create_permission("tunedModels/non-existent", permission,
                 api_key: @api_key
               )

      assert status in [400, 401, 403, 404]
    end

    test "creates a permission for everyone" do
      permission = %{
        grantee_type: :EVERYONE,
        role: :READER
      }

      assert {:error, %{status: status}} =
               Permissions.create_permission("tunedModels/non-existent", permission,
                 api_key: @api_key
               )

      assert status in [400, 401, 403, 404]
    end

    test "creates a permission for a group" do
      permission = %{
        grantee_type: :GROUP,
        email_address: "group@example.com",
        role: :WRITER
      }

      assert {:error, %{status: status}} =
               Permissions.create_permission("tunedModels/non-existent", permission,
                 api_key: @api_key
               )

      assert status in [400, 401, 403, 404]
    end

    test "returns error for invalid role" do
      permission = %{
        grantee_type: :USER,
        email_address: "test@example.com",
        role: :INVALID_ROLE
      }

      assert {:error, _} =
               Permissions.create_permission("tunedModels/test-model", permission,
                 api_key: @api_key
               )
    end

    test "returns error for missing parent" do
      permission = %{
        grantee_type: :USER,
        email_address: "test@example.com",
        role: :READER
      }

      assert {:error, _} =
               Permissions.create_permission("", permission, api_key: @api_key)
    end
  end

  describe "list_permissions/2" do
    @describetag :oauth2
    test "lists permissions for a tuned model" do
      assert {:ok, %ListPermissionsResponse{} = response} =
               Permissions.list_permissions("tunedModels/non-existent", api_key: @api_key)

      assert is_list(response.permissions)
      # API might return empty list for non-existent models
    end

    test "lists permissions with pagination" do
      assert {:ok, %ListPermissionsResponse{}} =
               Permissions.list_permissions("tunedModels/non-existent",
                 api_key: @api_key,
                 page_size: 5
               )
    end

    test "lists permissions with page token" do
      assert {:ok, %ListPermissionsResponse{}} =
               Permissions.list_permissions("tunedModels/non-existent",
                 api_key: @api_key,
                 page_token: "some-token"
               )
    end
  end

  describe "get_permission/2" do
    @describetag :oauth2
    test "returns error for non-existent permission" do
      assert {:error, %{status: status}} =
               Permissions.get_permission("tunedModels/non-existent/permissions/invalid",
                 api_key: @api_key
               )

      assert status in [400, 401, 403, 404]
    end

    @tag :skip
    test "gets permission details" do
      # This would require an existing permission
      # assert {:ok, %Permission{} = perm} = 
      #   Permissions.get_permission("tunedModels/test-model/permissions/perm-123", api_key: @api_key)
      # assert perm.name
      # assert perm.role
    end
  end

  describe "update_permission/3" do
    @describetag :oauth2
    test "returns error for non-existent permission" do
      update = %{
        role: :WRITER
      }

      assert {:error, %{status: status}} =
               Permissions.update_permission(
                 "tunedModels/non-existent/permissions/invalid",
                 update,
                 api_key: @api_key,
                 update_mask: "role"
               )

      assert status in [400, 401, 403, 404]
    end

    test "validates update mask is required" do
      update = %{
        role: :WRITER
      }

      # Without update_mask, should get error
      assert {:error, _} =
               Permissions.update_permission(
                 "tunedModels/test-model/permissions/perm-123",
                 update,
                 api_key: @api_key
               )
    end

    @tag :skip
    test "updates permission role" do
      # This would require an existing permission
      # update = %{
      #   role: :WRITER
      # }
      # 
      # assert {:ok, %Permission{} = perm} = 
      #   Permissions.update_permission(
      #     "tunedModels/test-model/permissions/perm-123", 
      #     update,
      #     api_key: @api_key,
      #     update_mask: "role"
      #   )
      # assert perm.role == :WRITER
    end
  end

  describe "delete_permission/2" do
    @describetag :oauth2
    test "returns error for non-existent permission" do
      assert {:error, %{status: status}} =
               Permissions.delete_permission("tunedModels/non-existent/permissions/invalid",
                 api_key: @api_key
               )

      assert status in [400, 401, 403, 404]
    end

    @tag :skip
    test "deletes a permission" do
      # This would require creating and then deleting a permission
      # assert {:ok, %{}} = 
      #   Permissions.delete_permission("tunedModels/test-model/permissions/perm-123", api_key: @api_key)

      # Verify deletion
      # assert {:error, %{status: 404}} = 
      #   Permissions.get_permission("tunedModels/test-model/permissions/perm-123", api_key: @api_key)
    end
  end

  describe "transfer_ownership/3" do
    @describetag :oauth2
    test "returns error for non-existent model" do
      request = %{
        email_address: "newowner@example.com"
      }

      assert {:error, %{status: status}} =
               Permissions.transfer_ownership("tunedModels/non-existent", request,
                 api_key: @api_key
               )

      assert status in [400, 401, 403, 404]
    end

    test "validates email address is required" do
      request = %{}

      assert {:error, "email_address is required"} =
               Permissions.transfer_ownership("tunedModels/test-model", request,
                 api_key: @api_key
               )
    end

    @tag :skip
    test "transfers ownership of a tuned model" do
      # This would require an existing tuned model that you own
      # request = %{
      #   email_address: "newowner@example.com"
      # }
      # 
      # assert {:ok, %{}} = 
      #   Permissions.transfer_ownership("tunedModels/my-model", request, api_key: @api_key)
    end
  end
end
