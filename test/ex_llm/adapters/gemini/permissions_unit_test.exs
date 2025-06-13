defmodule ExLLM.Adapters.Gemini.PermissionsUnitTest do
  use ExUnit.Case

  alias ExLLM.Gemini.Permissions

  alias ExLLM.Gemini.Permissions.{
    Permission,
    ListPermissionsResponse,
    TransferOwnershipRequest
  }

  describe "structs" do
    test "Permission struct" do
      permission = %Permission{
        name: "tunedModels/test-123/permissions/perm-456",
        grantee_type: :USER,
        email_address: "user@example.com",
        role: :READER
      }

      assert permission.name == "tunedModels/test-123/permissions/perm-456"
      assert permission.grantee_type == :USER
      assert permission.email_address == "user@example.com"
      assert permission.role == :READER
    end

    test "Permission struct for EVERYONE" do
      permission = %Permission{
        name: "tunedModels/test-123/permissions/perm-789",
        grantee_type: :EVERYONE,
        email_address: nil,
        role: :READER
      }

      assert permission.grantee_type == :EVERYONE
      assert is_nil(permission.email_address)
    end

    test "ListPermissionsResponse struct" do
      response = %ListPermissionsResponse{
        permissions: [
          %Permission{
            name: "tunedModels/test/permissions/1",
            grantee_type: :USER,
            email_address: "user1@example.com",
            role: :OWNER
          },
          %Permission{
            name: "tunedModels/test/permissions/2",
            grantee_type: :GROUP,
            email_address: "group@example.com",
            role: :WRITER
          }
        ],
        next_page_token: "token123"
      }

      assert length(response.permissions) == 2
      assert response.next_page_token == "token123"
    end

    test "TransferOwnershipRequest struct" do
      request = %TransferOwnershipRequest{
        email_address: "newowner@example.com"
      }

      assert request.email_address == "newowner@example.com"
    end
  end

  describe "to_json/1 conversions" do
    test "Permission to_json" do
      permission = %Permission{
        grantee_type: :USER,
        email_address: "user@example.com",
        role: :READER
      }

      json = Permission.to_json(permission)

      assert json == %{
               "granteeType" => "USER",
               "emailAddress" => "user@example.com",
               "role" => "READER"
             }
    end

    test "Permission to_json for EVERYONE" do
      permission = %Permission{
        grantee_type: :EVERYONE,
        role: :READER
      }

      json = Permission.to_json(permission)

      assert json == %{
               "granteeType" => "EVERYONE",
               "role" => "READER"
             }

      refute Map.has_key?(json, "emailAddress")
    end

    test "TransferOwnershipRequest to_json" do
      request = %TransferOwnershipRequest{
        email_address: "newowner@example.com"
      }

      json = TransferOwnershipRequest.to_json(request)

      assert json == %{
               "emailAddress" => "newowner@example.com"
             }
    end
  end

  describe "from_json/1 conversions" do
    test "Permission from_json" do
      json = %{
        "name" => "tunedModels/test-123/permissions/perm-456",
        "granteeType" => "USER",
        "emailAddress" => "user@example.com",
        "role" => "WRITER"
      }

      permission = Permission.from_json(json)

      assert %Permission{} = permission
      assert permission.name == "tunedModels/test-123/permissions/perm-456"
      assert permission.grantee_type == :USER
      assert permission.email_address == "user@example.com"
      assert permission.role == :WRITER
    end

    test "Permission from_json for GROUP" do
      json = %{
        "name" => "tunedModels/test/permissions/group-123",
        "granteeType" => "GROUP",
        "emailAddress" => "group@example.com",
        "role" => "OWNER"
      }

      permission = Permission.from_json(json)

      assert permission.grantee_type == :GROUP
      assert permission.role == :OWNER
    end

    test "Permission from_json for EVERYONE" do
      json = %{
        "name" => "tunedModels/test/permissions/everyone",
        "granteeType" => "EVERYONE",
        "role" => "READER"
      }

      permission = Permission.from_json(json)

      assert permission.grantee_type == :EVERYONE
      assert is_nil(permission.email_address)
      assert permission.role == :READER
    end

    test "ListPermissionsResponse from_json" do
      json = %{
        "permissions" => [
          %{
            "name" => "tunedModels/test/permissions/1",
            "granteeType" => "USER",
            "emailAddress" => "user1@example.com",
            "role" => "READER"
          },
          %{
            "name" => "tunedModels/test/permissions/2",
            "granteeType" => "EVERYONE",
            "role" => "READER"
          }
        ],
        "nextPageToken" => "next-page"
      }

      response = ListPermissionsResponse.from_json(json)

      assert %ListPermissionsResponse{} = response
      assert length(response.permissions) == 2
      assert response.next_page_token == "next-page"

      [perm1, perm2] = response.permissions
      assert perm1.grantee_type == :USER
      assert perm2.grantee_type == :EVERYONE
    end

    test "ListPermissionsResponse from_json with empty list" do
      json = %{
        "permissions" => []
      }

      response = ListPermissionsResponse.from_json(json)

      assert response.permissions == []
      assert is_nil(response.next_page_token)
    end
  end

  describe "validate_create_permission/1" do
    test "validates valid permission with USER type" do
      permission = %{
        grantee_type: :USER,
        email_address: "user@example.com",
        role: :READER
      }

      assert :ok = Permissions.validate_create_permission(permission)
    end

    test "validates valid permission with GROUP type" do
      permission = %{
        grantee_type: :GROUP,
        email_address: "group@example.com",
        role: :WRITER
      }

      assert :ok = Permissions.validate_create_permission(permission)
    end

    test "validates valid permission with EVERYONE type" do
      permission = %{
        grantee_type: :EVERYONE,
        role: :READER
      }

      assert :ok = Permissions.validate_create_permission(permission)
    end

    test "returns error for missing role" do
      permission = %{
        grantee_type: :USER,
        email_address: "user@example.com"
      }

      assert {:error, "role is required"} = Permissions.validate_create_permission(permission)
    end

    test "returns error for invalid role" do
      permission = %{
        grantee_type: :USER,
        email_address: "user@example.com",
        role: :INVALID
      }

      assert {:error, "role must be one of: READER, WRITER, OWNER"} =
               Permissions.validate_create_permission(permission)
    end

    test "returns error for USER without email" do
      permission = %{
        grantee_type: :USER,
        role: :READER
      }

      assert {:error, "email_address is required for USER grantee type"} =
               Permissions.validate_create_permission(permission)
    end

    test "returns error for GROUP without email" do
      permission = %{
        grantee_type: :GROUP,
        role: :WRITER
      }

      assert {:error, "email_address is required for GROUP grantee type"} =
               Permissions.validate_create_permission(permission)
    end

    test "returns error for invalid grantee type" do
      permission = %{
        grantee_type: :INVALID,
        role: :READER
      }

      assert {:error, "grantee_type must be one of: USER, GROUP, EVERYONE"} =
               Permissions.validate_create_permission(permission)
    end
  end

  describe "validate_update_permission/1" do
    test "validates valid update" do
      update = %{
        role: :WRITER
      }

      assert :ok = Permissions.validate_update_permission(update)
    end

    test "validates all valid roles" do
      for role <- [:READER, :WRITER, :OWNER] do
        assert :ok = Permissions.validate_update_permission(%{role: role})
      end
    end

    test "returns error for invalid role" do
      update = %{
        role: :INVALID
      }

      assert {:error, "role must be one of: READER, WRITER, OWNER"} =
               Permissions.validate_update_permission(update)
    end

    test "returns error for empty update" do
      assert {:error, "role is required for update"} =
               Permissions.validate_update_permission(%{})
    end
  end

  describe "validate_transfer_ownership/1" do
    test "validates valid request" do
      request = %{
        email_address: "newowner@example.com"
      }

      assert :ok = Permissions.validate_transfer_ownership(request)
    end

    test "returns error for missing email" do
      assert {:error, "email_address is required"} =
               Permissions.validate_transfer_ownership(%{})
    end

    test "returns error for invalid email format" do
      request = %{
        email_address: "not-an-email"
      }

      assert {:error, "email_address must be a valid email"} =
               Permissions.validate_transfer_ownership(request)
    end
  end

  describe "parse_grantee_type/1" do
    test "parses all valid grantee types" do
      assert Permissions.parse_grantee_type("USER") == :USER
      assert Permissions.parse_grantee_type("GROUP") == :GROUP
      assert Permissions.parse_grantee_type("EVERYONE") == :EVERYONE

      assert Permissions.parse_grantee_type("GRANTEE_TYPE_UNSPECIFIED") ==
               :GRANTEE_TYPE_UNSPECIFIED
    end

    test "returns GRANTEE_TYPE_UNSPECIFIED for unknown types" do
      assert Permissions.parse_grantee_type("UNKNOWN") == :GRANTEE_TYPE_UNSPECIFIED
      assert Permissions.parse_grantee_type(nil) == :GRANTEE_TYPE_UNSPECIFIED
    end
  end

  describe "parse_role/1" do
    test "parses all valid roles" do
      assert Permissions.parse_role("READER") == :READER
      assert Permissions.parse_role("WRITER") == :WRITER
      assert Permissions.parse_role("OWNER") == :OWNER
      assert Permissions.parse_role("ROLE_UNSPECIFIED") == :ROLE_UNSPECIFIED
    end

    test "returns ROLE_UNSPECIFIED for unknown roles" do
      assert Permissions.parse_role("UNKNOWN") == :ROLE_UNSPECIFIED
      assert Permissions.parse_role(nil) == :ROLE_UNSPECIFIED
    end
  end
end
