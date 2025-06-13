# Permissions

## Method: tunedModels.permissions.create

Create a permission to a specific resource.

### Endpoint

`post https://generativelanguage.googleapis.com/v1beta/{parent=tunedModels/*}/permissions`

### Path parameters

  * **parent** (string): Required. The parent resource of the Permission. Formats: `tunedModels/{tunedModel}`, `corpora/{corpus}`.

### Request body

The request body contains an instance of Permission.

  * **granteeType** (enum (GranteeType)): Optional. Immutable. The type of the grantee.
  * **emailAddress** (string): Optional. Immutable. The email address of the user of group which this permission refers. Field is not set when permission's grantee type is EVERYONE.
  * **role** (enum (Role)): Required. The role granted by this permission.

### Example request

Note: The provided documentation references examples using a new SDK. Refer to the Gemini 2 SDK migration guide for details.

### Response body

If successful, the response body contains a newly created instance of Permission.

## Method: tunedModels.permissions.get

Gets information about a specific Permission.

### Endpoint

`get https://generativelanguage.googleapis.com/v1beta/{name=tunedModels/*/permissions/*}`

### Path parameters

  * **name** (string): Required. The resource name of the permission. Formats: `tunedModels/{tunedModel}/permissions/{permission}`, `corpora/{corpus}/permissions/{permission}`.

### Request body

The request body must be empty.

### Example request

Note: The provided documentation references examples using a new SDK. Refer to the Gemini 2 SDK migration guide for details.

### Response body

If successful, the response body contains an instance of Permission.

## Method: tunedModels.permissions.list

Lists permissions for the specific resource.

### Endpoint

`get https://generativelanguage.googleapis.com/v1beta/{parent=tunedModels/*}/permissions`

### Path parameters

  * **parent** (string): Required. The parent resource of the permissions. Formats: `tunedModels/{tunedModel}`, `corpora/{corpus}`.

### Query parameters

  * **pageSize** (integer): Optional. The maximum number of Permissions to return (per page). The service may return fewer permissions. If unspecified, at most 10 permissions will be returned. This method returns at most 1000 permissions per page, even if you pass larger pageSize.
  * **pageToken** (string): Optional. A page token, received from a previous `permissions.list` call. Provide the `pageToken` returned by one request as an argument to the next request to retrieve the next page. When paginating, all other parameters provided to `permissions.list` must match the call that provided the page token.

### Request body

The request body must be empty.

### Example request

Note: The provided documentation references examples using a new SDK. Refer to the Gemini 2 SDK migration guide for details.

### Response body

If successful, the response body contains an instance of ListPermissionsResponse.

## Method: tunedModels.permissions.patch

Updates the permission.

### Endpoint

`patch https://generativelanguage.googleapis.com/v1beta/{permission.name=tunedModels/*/permissions/*}`

### Path parameters

  * **permission.name** (string): Output only. Identifier. The permission name. A unique name will be generated on create. Examples: `tunedModels/{tunedModel}/permissions/{permission}`, `corpora/{corpus}/permissions/{permission}`.

### Query parameters

  * **updateMask** (string (FieldMask format)): Required. The list of fields to update. Accepted ones: - role (`Permission.role` field). This is a comma-separated list of fully qualified names of fields. Example: `"user.displayName,photo"`.

### Request body

The request body contains an instance of Permission.

  * **role** (enum (Role)): Required. The role granted by this permission.

### Example request

Note: The provided documentation references examples using a new SDK. Refer to the Gemini 2 SDK migration guide for details.

### Response body

If successful, the response body contains an instance of Permission.

## Method: tunedModels.permissions.delete

Deletes the permission.

### Endpoint

`delete https://generativelanguage.googleapis.com/v1beta/{name=tunedModels/*/permissions/*}`

### Path parameters

  * **name** (string): Required. The resource name of the permission. Formats: `tunedModels/{tunedModel}/permissions/{permission}`, `corpora/{corpus}/permissions/{permission}`.

### Request body

The request body must be empty.

### Example request

Note: The provided documentation references examples using a new SDK. Refer to the Gemini 2 SDK migration guide for details.

### Response body

If successful, the response body is an empty JSON object.

## Method: tunedModels.transferOwnership

Transfers ownership of the tuned model. This is the only way to change ownership of the tuned model. The current owner will be downgraded to writer role.

### Endpoint

`post https://generativelanguage.googleapis.com/v1beta/{name=tunedModels/*}:transferOwnership`

### Path parameters

  * **name** (string): Required. The resource name of the tuned model to transfer ownership. Format: `tunedModels/my-model-id`.

### Request body

The request body contains data with the following structure:

  * **emailAddress** (string): Required. The email address of the user to whom the tuned model is being transferred to.

### Response body

If successful, the response body is empty.

## REST Resource: tunedModels.permissions

### Resource: Permission

Permission resource grants user, group or the rest of the world access to the PaLM API resource (e.g. a tuned model, corpus). A role is a collection of permitted operations that allows users to perform specific actions on PaLM API resources. To make them available to users, groups, or service accounts, you assign roles. When you assign a role, you grant permissions that the role contains. There are three concentric roles. Each role is a superset of the previous role's permitted operations:

  * **reader**: can use the resource (e.g. tuned model, corpus) for inference

  * **writer**: has reader's permissions and additionally can edit and share

  * **owner**: has writer's permissions and additionally can delete

  * **name** (string): Output only. Identifier. The permission name. A unique name will be generated on create. Examples: `tunedModels/{tunedModel}/permissions/{permission}`, `corpora/{corpus}/permissions/{permission}`.

  * **granteeType** (enum (GranteeType)): Optional. Immutable. The type of the grantee.

  * **emailAddress** (string): Optional. Immutable. The email address of the user of group which this permission refers. Field is not set when permission's grantee type is EVERYONE.

  * **role** (enum (Role)): Required. The role granted by this permission.

<!-- end list -->

```json
{
  "name": string,
  "granteeType": enum (GranteeType),
  "emailAddress": string,
  "role": enum (Role)
}
```

### ListPermissionsResponse

Response from `ListPermissions` containing a paginated list of permissions.

  * **permissions[]** (object (Permission)): Returned permissions.
  * **nextPageToken** (string): A token, which can be sent as `pageToken` to retrieve the next page. If this field is omitted, there are no more pages.

<!-- end list -->

```json
{
  "permissions": [
    {
      object (Permission)
    }
  ],
  "nextPageToken": string
}
```
