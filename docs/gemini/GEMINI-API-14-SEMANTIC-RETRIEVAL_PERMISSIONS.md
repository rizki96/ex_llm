# Corpus Permissions

On this page:

  * [Method: corpora.permissions.create](https://www.google.com/search?q=%23method-corporapermissionscreate)
  * [Endpoint](https://www.google.com/search?q=%23endpoint)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters)
  * [Request body](https://www.google.com/search?q=%23request-body)
  * [Example request](https://www.google.com/search?q=%23example-request)
  * [Response body](https://www.google.com/search?q=%23response-body-1)
  * [Method: corpora.permissions.list](https://www.google.com/search?q=%23method-corporapermissionslist)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-1)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-1)
  * [Query parameters](https://www.google.com/search?q=%23query-parameters)
  * [Request body](https://www.google.com/search?q=%23request-body-2)
  * [Response body](https://www.google.com/search?q=%23response-body-3)
  * [Method: corpora.permissions.get](https://www.google.com/search?q=%23method-corporapermissionsget)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-2)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-2)
  * [Request body](https://www.google.com/search?q=%23request-body-4)
  * [Example request](https://www.google.com/search?q=%23example-request-2)
  * [Response body](https://www.google.com/search?q=%23response-body-5)
  * [Method: corpora.permissions.patch](https://www.google.com/search?q=%23method-corporapermissionspatch)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-3)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-3)
  * [Query parameters](https://www.google.com/search?q=%23query-parameters-1)
  * [Request body](https://www.google.com/search?q=%23request-body-6)
  * [Example request](https://www.google.com/search?q=%23example-request-3)
  * [Response body](https://www.google.com/search?q=%23response-body-7)
  * [Method: corpora.permissions.delete](https://www.google.com/search?q=%23method-corporapermissionsdelete)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-4)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-4)
  * [Request body](https://www.google.com/search?q=%23request-body-8)
  * [Example request](https://www.google.com/search?q=%23example-request-4)
  * [Response body](https://www.google.com/search?q=%23response-body-9)
  * [REST Resource: corpora.permissions](https://www.google.com/search?q=%23rest-resource-corporapermissions)
  * [Resource: Permission](https://www.google.com/search?q=%23resource-permission)
  * [GranteeType](https://www.google.com/search?q=%23granteetype)
  * [Role](https://www.google.com/search?q=%23role)
  * [ListPermissionsResponse](https://www.google.com/search?q=%23listpermissionsresponse)

## Method: corpora.permissions.create

Create a permission to a specific resource.

### Endpoint

`post`
`https://generativelanguage.googleapis.com/v1beta/{parent=corpora/*}/permissions`

### Path parameters

  * `parent`

    `string`

    Required. The parent resource of the `Permission`. Formats: `tunedModels/{tunedModel}` `corpora/{corpus}` It takes the form `corpora/{corpora}`.

### Request body

The request body contains an instance of `Permission`.

#### Fields

  * `granteeType`

    `enum (GranteeType)`

    Optional. Immutable. The type of the grantee.

  * `emailAddress`

    `string`

    Optional. Immutable. The email address of the user of group which this permission refers. Field is not set when permission's grantee type is EVERYONE.

  * `role`

    `enum (Role)`

    Required. The role granted by this permission.

### Example request

(Language-specific code examples are omitted as per instructions)

### Response body

If successful, the response body contains a newly created instance of `Permission`.

## Method: corpora.permissions.list

Lists permissions for the specific resource.

### Endpoint

`get`
`https://generativelanguage.googleapis.com/v1beta/{parent=corpora/*}/permissions`

### Path parameters

  * `parent`

    `string`

    Required. The parent resource of the permissions. Formats: `tunedModels/{tunedModel}` `corpora/{corpus}` It takes the form `corpora/{corpora}`.

### Query parameters

  * `pageSize`

    `integer`

    Optional. The maximum number of `Permissions` to return (per page). The service may return fewer permissions.
    If unspecified, at most 10 permissions will be returned. This method returns at most 1000 permissions per page, even if you pass larger pageSize.

  * `pageToken`

    `string`

    Optional. A page token, received from a previous `permissions.list` call.
    Provide the `pageToken` returned by one request as an argument to the next request to retrieve the next page.
    When paginating, all other parameters provided to `permissions.list` must match the call that provided the page token.

### Request body

The request body must be empty.

### Example request

(Language-specific code examples are omitted as per instructions)

### Response body

If successful, the response body contains an instance of `ListPermissionsResponse`.

## Method: corpora.permissions.get

Gets information about a specific Permission.

### Endpoint

`get`
`https://generativelanguage.googleapis.com/v1beta/{name=corpora/*/permissions/*}`

### Path parameters

  * `name`

    `string`

    Required. The resource name of the permission.
    Formats: `tunedModels/{tunedModel}/permissions/{permission}` `corpora/{corpus}/permissions/{permission}` It takes the form `corpora/{corpora}/permissions/{permission}`.

### Request body

The request body must be empty.

### Example request

(Language-specific code examples are omitted as per instructions)

### Response body

If successful, the response body contains an instance of `Permission`.

## Method: corpora.permissions.patch

Updates the permission.

### Endpoint

`patch`
`https://generativelanguage.googleapis.com/v1beta/{permission.name=corpora/*/permissions/*}`

`PATCH https://generativelanguage.googleapis.com/v1beta/{permission.name=corpora/*/permissions/*}`

### Path parameters

  * `permission.name`

    `string`

    Output only. Identifier. The permission name. A unique name will be generated on create. Examples: tunedModels/{tunedModel}/permissions/{permission} corpora/{corpus}/permissions/{permission} Output only. It takes the form `corpora/{corpora}/permissions/{permission}`.

### Query parameters

  * `updateMask`

    `string (FieldMask format)`

    Required. The list of fields to update. Accepted ones: - role (Permission.role field)
    This is a comma-separated list of fully qualified names of fields. Example: `"user.displayName,photo"`.

### Request body

The request body contains an instance of `Permission`.

#### Fields

  * `role`

    `enum (Role)`

    Required. The role granted by this permission.

### Example request

(Language-specific code examples are omitted as per instructions)

### Response body

If successful, the response body contains an instance of `Permission`.

## Method: corpora.permissions.delete

Deletes the permission.

### Endpoint

`delete`
`https://generativelanguage.googleapis.com/v1beta/{name=corpora/*/permissions/*}`

### Path parameters

  * `name`

    `string`

    Required. The resource name of the permission. Formats: `tunedModels/{tunedModel}/permissions/{permission}` `corpora/{corpus}/permissions/{permission}` It takes the form `corpora/{corpora}/permissions/{permission}`.

### Request body

The request body must be empty.

### Example request

(Language-specific code examples are omitted as per instructions)

### Response body

If successful, the response body is an empty JSON object.

## REST Resource: corpora.permissions

## Resource: Permission

Permission resource grants user, group or the rest of the world access to the PaLM API resource (e.g. a tuned model, corpus).
A role is a collection of permitted operations that allows users to perform specific actions on PaLM API resources. To make them available to users, groups, or service accounts, you assign roles. When you assign a role, you grant permissions that the role contains.
There are three concentric roles. Each role is a superset of the previous role's permitted operations:
reader can use the resource (e.g. tuned model, corpus) for inference
writer has reader's permissions and additionally can edit and share
owner has writer's permissions and additionally can delete

### Fields

  * `name`

    `string`

    Output only. Identifier. The permission name. A unique name will be generated on create. Examples: tunedModels/{tunedModel}/permissions/{permission} corpora/{corpus}/permissions/{permission} Output only.

  * `granteeType`

    `enum (GranteeType)`

    Optional. Immutable. The type of the grantee.

  * `emailAddress`

    `string`

    Optional. Immutable. The email address of the user of group which this permission refers. Field is not set when permission's grantee type is EVERYONE.

  * `role`

    `enum (Role)`

    Required. The role granted by this permission.

### JSON representation

```json
{
  "name": string,
  "granteeType": enum (GranteeType),
  "emailAddress": string,
  "role": enum (Role)
}
```

## GranteeType

Defines types of the grantee of this permission.

### Enums

  * `GRANTEE_TYPE_UNSPECIFIED`
    The default value. This value is unused.
  * `USER`
    Represents a user. When set, you must provide emailAddress for the user.
  * `GROUP`
    Represents a group. When set, you must provide emailAddress for the group.
  * `EVERYONE`
    Represents access to everyone. No extra information is required.

## Role

Defines the role granted by this permission.

### Enums

  * `ROLE_UNSPECIFIED`
    The default value. This value is unused.
  * `OWNER`
    Owner can use, update, share and delete the resource.
  * `WRITER`
    Writer can use, update and share the resource.
  * `READER`
    Reader can use the resource.

## ListPermissionsResponse

Response from `ListPermissions` containing a paginated list of permissions.

### Fields

  * `permissions[]`

    `object (Permission)`

    Returned permissions.

  * `nextPageToken`

    `string`

    A token, which can be sent as `pageToken` to retrieve the next page.
    If this field is omitted, there are no more pages.

### JSON representation

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
