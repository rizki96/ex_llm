defmodule ExLLM.Providers.Gemini.Permissions do
  @moduledoc """
  Google Gemini Permissions API implementation.

  This module provides functionality for managing permissions on tuned models
  and corpora in the Gemini API. Permissions control access levels (reader, writer, owner)
  for users, groups, or everyone.
  """

  alias ExLLM.Infrastructure.Config
  alias ExLLM.Providers.Gemini.Base

  # Type definitions

  @type grantee_type :: :GRANTEE_TYPE_UNSPECIFIED | :USER | :GROUP | :EVERYONE
  @type role :: :ROLE_UNSPECIFIED | :READER | :WRITER | :OWNER

  # Request/Response structs

  defmodule Permission do
    @moduledoc """
    Permission resource that grants access to a tuned model or corpus.
    """
    defstruct [:name, :grantee_type, :email_address, :role]

    @type t :: %__MODULE__{
            name: String.t() | nil,
            grantee_type: ExLLM.Providers.Gemini.Permissions.grantee_type() | nil,
            email_address: String.t() | nil,
            role: ExLLM.Providers.Gemini.Permissions.role()
          }

    def to_json(%__MODULE__{} = permission) do
      json = %{}

      json =
        if permission.grantee_type do
          Map.put(json, "granteeType", to_string(permission.grantee_type))
        else
          json
        end

      json =
        if permission.email_address do
          Map.put(json, "emailAddress", permission.email_address)
        else
          json
        end

      Map.put(json, "role", to_string(permission.role))
    end

    def from_json(json) do
      %__MODULE__{
        name: json["name"],
        grantee_type: ExLLM.Providers.Gemini.Permissions.parse_grantee_type(json["granteeType"]),
        email_address: json["emailAddress"],
        role: ExLLM.Providers.Gemini.Permissions.parse_role(json["role"])
      }
    end
  end

  defmodule ListPermissionsResponse do
    @moduledoc """
    Response from listing permissions.
    """
    defstruct [:permissions, :next_page_token]

    @type t :: %__MODULE__{
            permissions: [Permission.t()],
            next_page_token: String.t() | nil
          }

    def from_json(json) do
      %__MODULE__{
        permissions: Enum.map(json["permissions"] || [], &Permission.from_json/1),
        next_page_token: json["nextPageToken"]
      }
    end
  end

  defmodule TransferOwnershipRequest do
    @moduledoc """
    Request to transfer ownership of a tuned model.
    """
    defstruct [:email_address]

    @type t :: %__MODULE__{
            email_address: String.t()
          }

    def to_json(%__MODULE__{} = request) do
      %{
        "emailAddress" => request.email_address
      }
    end
  end

  # API Functions

  @type options :: [
          {:api_key, String.t()}
          | {:oauth_token, String.t()}
          | {:config_provider, module()}
          | {:page_size, integer()}
          | {:page_token, String.t()}
          | {:update_mask, String.t()}
        ]

  @doc """
  Creates a permission for a tuned model or corpus.

  ## Parameters

  * `parent` - The parent resource (e.g., "tunedModels/my-model" or "corpora/my-corpus")
  * `permission` - The permission to create containing:
    * `:grantee_type` - Type of grantee (USER, GROUP, or EVERYONE)
    * `:email_address` - Email for USER or GROUP types
    * `:role` - Permission level (READER, WRITER, or OWNER)
  * `opts` - Options including `:api_key`

  ## Returns

  * `{:ok, permission}` - The created permission
  * `{:error, reason}` - Error details
  """
  @spec create_permission(String.t(), map(), options()) ::
          {:ok, Permission.t()} | {:error, term()}
  def create_permission(parent, permission, opts \\ []) do
    with :ok <- validate_parent(parent),
         :ok <- validate_create_permission(permission),
         body <- Permission.to_json(struct(Permission, permission)) do
      auth_opts = get_auth_opts(opts)

      case Base.request(
             [{:method, :post}, {:url, "/#{parent}/permissions"}, {:body, body}] ++
               auth_opts ++ [{:opts, opts}]
           ) do
        {:ok, json} -> {:ok, Permission.from_json(json)}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Lists permissions for a tuned model or corpus.

  ## Parameters

  * `parent` - The parent resource
  * `opts` - Options including:
    * `:api_key` - Google API key
    * `:page_size` - Maximum number of permissions to return
    * `:page_token` - Token for pagination

  ## Returns

  * `{:ok, response}` - List of permissions
  * `{:error, reason}` - Error details
  """
  @spec list_permissions(String.t(), options()) ::
          {:ok, ListPermissionsResponse.t()} | {:error, term()}
  def list_permissions(parent, opts \\ []) do
    with :ok <- validate_parent(parent),
         query_params <- build_list_query_params(opts) do
      auth_opts = get_auth_opts(opts)

      case Base.request(
             [{:method, :get}, {:url, "/#{parent}/permissions"}, {:query, query_params}] ++
               auth_opts ++ [{:opts, opts}]
           ) do
        {:ok, json} -> {:ok, ListPermissionsResponse.from_json(json)}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Gets information about a specific permission.

  ## Parameters

  * `name` - The resource name (e.g., "tunedModels/my-model/permissions/perm-123")
  * `opts` - Options including `:api_key`

  ## Returns

  * `{:ok, permission}` - The permission details
  * `{:error, reason}` - Error details
  """
  @spec get_permission(String.t(), options()) :: {:ok, Permission.t()} | {:error, term()}
  def get_permission(name, opts \\ []) do
    auth_opts = get_auth_opts(opts)

    case Base.request([{:method, :get}, {:url, "/#{name}"}] ++ auth_opts ++ [{:opts, opts}]) do
      {:ok, json} -> {:ok, Permission.from_json(json)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Updates a permission's role.

  ## Parameters

  * `name` - The resource name of the permission
  * `update` - Map containing `:role` to update
  * `opts` - Options including:
    * `:api_key` - Google API key
    * `:update_mask` - Required field mask (should be "role")

  ## Returns

  * `{:ok, permission}` - The updated permission
  * `{:error, reason}` - Error details
  """
  @spec update_permission(String.t(), map(), options()) ::
          {:ok, Permission.t()} | {:error, term()}
  def update_permission(name, update, opts \\ []) do
    with :ok <- validate_update_permission(update),
         :ok <- validate_update_mask(opts[:update_mask]),
         body <- %{"role" => to_string(update[:role])},
         query_params <- %{"updateMask" => opts[:update_mask]} do
      auth_opts = get_auth_opts(opts)

      case Base.request(
             [{:method, :patch}, {:url, "/#{name}"}, {:body, body}, {:query, query_params}] ++
               auth_opts ++ [{:opts, opts}]
           ) do
        {:ok, json} -> {:ok, Permission.from_json(json)}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Deletes a permission.

  ## Parameters

  * `name` - The resource name of the permission
  * `opts` - Options including `:api_key`

  ## Returns

  * `{:ok, %{}}` - Empty response on success
  * `{:error, reason}` - Error details
  """
  @spec delete_permission(String.t(), options()) :: {:ok, map()} | {:error, term()}
  def delete_permission(name, opts \\ []) do
    auth_opts = get_auth_opts(opts)

    Base.request([{:method, :delete}, {:url, "/#{name}"}] ++ auth_opts ++ [{:opts, opts}])
  end

  @doc """
  Transfers ownership of a tuned model.

  The current owner will be downgraded to writer role.

  ## Parameters

  * `name` - The resource name of the tuned model
  * `request` - Map containing `:email_address` of new owner
  * `opts` - Options including `:api_key`

  ## Returns

  * `{:ok, %{}}` - Empty response on success
  * `{:error, reason}` - Error details
  """
  @spec transfer_ownership(String.t(), map(), options()) :: {:ok, map()} | {:error, term()}
  def transfer_ownership(name, request, opts \\ []) do
    with :ok <- validate_transfer_ownership(request),
         body <- TransferOwnershipRequest.to_json(struct(TransferOwnershipRequest, request)) do
      auth_opts = get_auth_opts(opts)

      Base.request(
        [{:method, :post}, {:url, "/#{name}:transferOwnership"}, {:body, body}] ++
          auth_opts ++ [{:opts, opts}]
      )
    end
  end

  # Validation functions

  @doc false
  def validate_parent(""), do: {:error, "parent resource is required"}
  def validate_parent(_), do: :ok

  @doc false
  def validate_create_permission(permission) do
    cond do
      !permission[:role] ->
        {:error, "role is required"}

      permission[:role] not in [:READER, :WRITER, :OWNER] ->
        {:error, "role must be one of: READER, WRITER, OWNER"}

      !permission[:grantee_type] ->
        # Default to USER if not specified
        :ok

      permission[:grantee_type] not in [:USER, :GROUP, :EVERYONE] ->
        {:error, "grantee_type must be one of: USER, GROUP, EVERYONE"}

      permission[:grantee_type] in [:USER, :GROUP] and !permission[:email_address] ->
        {:error, "email_address is required for #{permission[:grantee_type]} grantee type"}

      true ->
        :ok
    end
  end

  @doc false
  def validate_update_permission(update) do
    cond do
      !update[:role] ->
        {:error, "role is required for update"}

      update[:role] not in [:READER, :WRITER, :OWNER] ->
        {:error, "role must be one of: READER, WRITER, OWNER"}

      true ->
        :ok
    end
  end

  @doc false
  def validate_update_mask(nil), do: {:error, "update_mask is required"}
  def validate_update_mask(_), do: :ok

  @doc false
  def validate_transfer_ownership(request) do
    cond do
      !request[:email_address] ->
        {:error, "email_address is required"}

      !String.contains?(request[:email_address], "@") ->
        {:error, "email_address must be a valid email"}

      true ->
        :ok
    end
  end

  # Helper functions

  @doc false
  def parse_grantee_type(nil), do: :GRANTEE_TYPE_UNSPECIFIED
  def parse_grantee_type("USER"), do: :USER
  def parse_grantee_type("GROUP"), do: :GROUP
  def parse_grantee_type("EVERYONE"), do: :EVERYONE
  def parse_grantee_type("GRANTEE_TYPE_UNSPECIFIED"), do: :GRANTEE_TYPE_UNSPECIFIED
  def parse_grantee_type(_), do: :GRANTEE_TYPE_UNSPECIFIED

  @doc false
  def parse_role(nil), do: :ROLE_UNSPECIFIED
  def parse_role("READER"), do: :READER
  def parse_role("WRITER"), do: :WRITER
  def parse_role("OWNER"), do: :OWNER
  def parse_role("ROLE_UNSPECIFIED"), do: :ROLE_UNSPECIFIED
  def parse_role(_), do: :ROLE_UNSPECIFIED

  defp get_api_key(opts) do
    config_provider = opts[:config_provider] || Config.DefaultProvider
    opts[:api_key] || config_provider.get_config(:gemini)[:api_key]
  end

  defp get_auth_opts(opts) do
    if oauth_token = opts[:oauth_token] do
      [{:oauth_token, oauth_token}]
    else
      api_key = get_api_key(opts)
      [{:api_key, api_key}]
    end
  end

  defp build_list_query_params(opts) do
    params = %{}

    params =
      if opts[:page_size] do
        Map.put(params, "pageSize", opts[:page_size])
      else
        params
      end

    if opts[:page_token] do
      Map.put(params, "pageToken", opts[:page_token])
    else
      params
    end
  end
end
