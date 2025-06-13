# Corpora

Corpora are a collection of Documents. A project can create up to 5 corpora.

## Method: corpora.create

Creates an empty Corpus.

### Endpoint

`post https://generativelanguage.googleapis.com/v1beta/corpora`

### Request body

The request body contains an instance of Corpus.

  * **name** (string): Immutable. Identifier. The Corpus resource name. The ID (name excluding the "corpora/" prefix) can contain up to 40 characters that are lowercase alphanumeric or dashes (-). The ID cannot start or end with a dash. If the name is empty on create, a unique name will be derived from `displayName` along with a 12 character random suffix. Example: `corpora/my-awesome-corpora-123a456b789c`.
  * **displayName** (string): Optional. The human-readable display name for the Corpus. The display name must be no more than 512 characters in length, including spaces. Example: "Docs on Semantic Retriever".

### Response body

If successful, the response body contains a newly created instance of Corpus.

## Method: corpora.query

Performs semantic search over a Corpus.

### Endpoint

`post https://generativelanguage.googleapis.com/v1beta/{name=corpora/*}:query`

### Path parameters

  * **name** (string): Required. The name of the Corpus to query. Example: `corpora/my-corpus-123`.

### Request body

The request body contains data with the following structure:

  * **query** (string): Required. Query string to perform semantic search.
  * **metadataFilters[]** (object (MetadataFilter)): Optional. Filter for Chunk and Document metadata. Each MetadataFilter object should correspond to a unique key. Multiple MetadataFilter objects are joined by logical "AND"s.
      * Example query at document level: `(year >= 2020 OR year < 2010) AND (genre = drama OR genre = action)`
        `metadataFilters = [ {key = "document.custom_metadata.year" conditions = [{int_value = 2020, operation = GREATER_EQUAL}, {int_value = 2010, operation = LESS}]}, {key = "document.custom_metadata.year" conditions = [{int_value = 2020, operation = GREATER_EQUAL}, {int_value = 2010, operation = LESS}]}, {key = "document.custom_metadata.genre" conditions = [{stringValue = "drama", operation = EQUAL}, {stringValue = "action", operation = EQUAL}]}]`
      * Example query at chunk level for a numeric range of values: `(year > 2015 AND year <= 2020)`
        `metadataFilters = [ {key = "chunk.custom_metadata.year" conditions = [{int_value = 2015, operation = GREATER}]}, {key = "chunk.custom_metadata.year" conditions = [{int_value = 2020, operation = LESS_EQUAL}]}]`
      * Note: "AND"s for the same key are only supported for numeric values. String values only support "OR"s for the same key.
  * **resultsCount** (integer): Optional. The maximum number of Chunks to return. The service may return fewer Chunks. If unspecified, at most 10 Chunks will be returned. The maximum specified result count is 100.

### Response body

Response from `corpora.query` containing a list of relevant chunks. If successful, the response body contains data with the following structure:

  * **relevantChunks[]** (object (RelevantChunk)): The relevant chunks.

<!-- end list -->

```json
{
  "relevantChunks": [
    {
      object (RelevantChunk)
    }
  ]
}
```

## Method: corpora.list

Lists all Corpora owned by the user.

### Endpoint

`get https://generativelanguage.googleapis.com/v1beta/corpora`

### Query parameters

  * **pageSize** (integer): Optional. The maximum number of Corpora to return (per page). The service may return fewer Corpora. If unspecified, at most 10 Corpora will be returned. The maximum size limit is 20 Corpora per page.
  * **pageToken** (string): Optional. A page token, received from a previous `corpora.list` call. Provide the `nextPageToken` returned in the response as an argument to the next request to retrieve the next page. When paginating, all other parameters provided to `corpora.list` must match the call that provided the page token.

### Request body

The request body must be empty.

### Response body

Response from `corpora.list` containing a paginated list of Corpora. The results are sorted by ascending `corpus.create_time`. If successful, the response body contains data with the following structure:

  * **corpora[]** (object (Corpus)): The returned corpora.
  * **nextPageToken** (string): A token, which can be sent as `pageToken` to retrieve the next page. If this field is omitted, there are no more pages.

<!-- end list -->

```json
{
  "corpora": [
    {
      object (Corpus)
    }
  ],
  "nextPageToken": string
}
```

## Method: corpora.get

Gets information about a specific Corpus.

### Endpoint

`get https://generativelanguage.googleapis.com/v1beta/{name=corpora/*}`

### Path parameters

  * **name** (string): Required. The name of the Corpus. Example: `corpora/my-corpus-123`.

### Request body

The request body must be empty.

### Response body

If successful, the response body contains an instance of Corpus.

## Method: corpora.patch

Updates a Corpus.

### Endpoint

`patch https://generativelanguage.googleapis.com/v1beta/{corpus.name=corpora/*}`

### Path parameters

  * **corpus.name** (string): Immutable. Identifier. The Corpus resource name. The ID (name excluding the "corpora/" prefix) can contain up to 40 characters that are lowercase alphanumeric or dashes (-). The ID cannot start or end with a dash. If the name is empty on create, a unique name will be derived from `displayName` along with a 12 character random suffix. Example: `corpora/my-awesome-corpora-123a456b789c`.

### Query parameters

  * **updateMask** (string (FieldMask format)): Required. The list of fields to update. Currently, this only supports updating `displayName`. This is a comma-separated list of fully qualified names of fields. Example: `"user.displayName,photo"`.

### Request body

The request body contains an instance of Corpus.

  * **displayName** (string): Optional. The human-readable display name for the Corpus. The display name must be no more than 512 characters in length, including spaces. Example: "Docs on Semantic Retriever".

### Response body

If successful, the response body contains an instance of Corpus.

## Method: corpora.delete

Deletes a Corpus.

### Endpoint

`delete https://generativelanguage.googleapis.com/v1beta/{name=corpora/*}`

### Path parameters

  * **name** (string): Required. The resource name of the Corpus. Example: `corpora/my-corpus-123`.

### Query parameters

  * **force** (boolean): Optional. If set to true, any Documents and objects related to this Corpus will also be deleted. If false (the default), a FAILED\_PRECONDITION error will be returned if Corpus contains any Documents.

### Request body

The request body must be empty.

### Response body

If successful, the response body is an empty JSON object.

## REST Resource: corpora.permissions

(Note: Permission, GranteeType, and Role definitions were also included in the tunedModels.permissions section)

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

### GranteeType

Defines types of the grantee of this permission.

>   * **GRANTEE\_TYPE\_UNSPECIFIED**: The default value. This value is unused.
>   * **USER**: Represents a user. When set, you must provide emailAddress for the user.
>   * **GROUP**: Represents a group. When set, you must provide emailAddress for the group.
>   * **EVERYONE**: Represents access to everyone. No extra information is required.

### Role

Defines the role granted by this permission.

>   * **ROLE\_UNSPECIFIED**: The default value. This value is unused.
>   * **OWNER**: Owner can use, update, share and delete the resource.
>   * **WRITER**: Writer can use, update and share the resource.
>   * **READER**: Reader can use the resource.

## REST Resource: corpora

### Resource: Corpus

A Corpus is a collection of Documents. A project can create up to 5 corpora.

  * **name** (string): Immutable. Identifier. The Corpus resource name. The ID (name excluding the "corpora/" prefix) can contain up to 40 characters that are lowercase alphanumeric or dashes (-). The ID cannot start or end with a dash. If the name is empty on create, a unique name will be derived from `displayName` along with a 12 character random suffix. Example: `corpora/my-awesome-corpora-123a456b789c`.
  * **displayName** (string): Optional. The human-readable display name for the Corpus. The display name must be no more than 512 characters in length, including spaces. Example: "Docs on Semantic Retriever".
  * **createTime** (string (Timestamp format)): Output only. The Timestamp of when the Corpus was created. Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.
  * **updateTime** (string (Timestamp format)): Output only. The Timestamp of when the Corpus was last updated. Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.

<!-- end list -->

```json
{
  "name": string,
  "displayName": string,
  "createTime": string,
  "updateTime": string
}
```

## MetadataFilter

User provided filter to limit retrieval based on Chunk or Document level metadata values. Example `(genre = drama OR genre = action)`: `key = "document.custom_metadata.genre"` conditions = `[{stringValue = "drama", operation = EQUAL}, {stringValue = "action", operation = EQUAL}]`.

  * **key** (string): Required. The key of the metadata to filter on.
  * **conditions[]** (object (Condition)): Required. The Conditions for the given key that will trigger this filter. Multiple Conditions are joined by logical ORs.

<!-- end list -->

```json
{
  "key": string,
  "conditions": [
    {
      object (Condition)
    }
  ]
}
```

## Condition

Filter condition applicable to a single key.

  * **operation** (enum (Operator)): Required. Operator applied to the given key-value pair to trigger the condition.

> **value** (Union type): The value type must be consistent with the value type defined in the field for the corresponding key. If the value types are not consistent, the result will be an empty set. When the CustomMetadata has a StringList value type, the filtering condition should use `string_value` paired with an INCLUDES/EXCLUDES operation, otherwise the result will also be an empty set. `value` can be only one of the following:
>
>   * **stringValue** (string): The string value to filter the metadata on.
>   * **numericValue** (number): The numeric value to filter the metadata on.

```json
{
  "operation": enum (Operator),

  // value
  "stringValue": string,
  "numericValue": number
  // Union type
}
```

## Operator

Defines the valid operators that can be applied to a key-value pair.

>   * **OPERATOR\_UNSPECIFIED**: The default value. This value is unused.
>   * **LESS**: Supported by numeric.
>   * **LESS\_EQUAL**: Supported by numeric.
>   * **EQUAL**: Supported by numeric & string.
>   * **GREATER\_EQUAL**: Supported by numeric.
>   * **GREATER**: Supported by numeric.
>   * **NOT\_EQUAL**: Supported by numeric & string.
>   * **INCLUDES**: Supported by string only when CustomMetadata value type for the given key has a `stringListValue`.
>   * **EXCLUDES**: Supported by string only when CustomMetadata value type for the given key has a `stringListValue`.

## RelevantChunk

The information for a chunk relevant to a query.

  * **chunkRelevanceScore** (number): Chunk relevance to the query.
  * **chunk** (object (Chunk)): Chunk associated with the query.

<!-- end list -->

```json
{
  "chunkRelevanceScore": number,
  "chunk": {
    object (Chunk)
  }
}
```
