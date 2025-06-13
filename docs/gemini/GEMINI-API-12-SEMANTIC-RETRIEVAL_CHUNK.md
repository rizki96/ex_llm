# Chunks

On this page:

  * [Method: corpora.documents.chunks.create](https://www.google.com/search?q=%23method-corporadocumentschunkscreate)
  * [Endpoint](https://www.google.com/search?q=%23endpoint)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters)
  * [Request body](https://www.google.com/search?q=%23request-body)
  * [Response body](https://www.google.com/search?q=%23response-body)
  * [Method: corpora.documents.chunks.list](https://www.google.com/search?q=%23method-corporadocumentschunkslist)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-1)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-1)
  * [Query parameters](https://www.google.com/search?q=%23query-parameters)
  * [Request body](https://www.google.com/search?q=%23request-body-2)
  * [Response body](https://www.google.com/search?q=%23response-body-3)
  * [Method: corpora.documents.chunks.get](https://www.google.com/search?q=%23method-corporadocumentschunksget)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-2)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-2)
  * [Request body](https://www.google.com/search?q=%23request-body-4)
  * [Response body](https://www.google.com/search?q=%23response-body-5)
  * [Method: corpora.documents.chunks.patch](https://www.google.com/search?q=%23method-corporadocumentschunkspatch)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-3)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-3)
  * [Query parameters](https://www.google.com/search?q=%23query-parameters-1)
  * [Request body](https://www.google.com/search?q=%23request-body-6)
  * [Response body](https://www.google.com/search?q=%23response-body-7)
  * [Method: corpora.documents.chunks.delete](https://www.google.com/search?q=%23method-corporadocumentschunksdelete)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-4)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-4)
  * [Request body](https://www.google.com/search?q=%23request-body-8)
  * [Response body](https://www.google.com/search?q=%23response-body-9)
  * [Method: corpora.documents.chunks.batchCreate](https://www.google.com/search?q=%23method-corporadocumentschunksbatchcreate)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-5)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-5)
  * [Request body](https://www.google.com/search?q=%23request-body-10)
  * [Response body](https://www.google.com/search?q=%23response-body-11)
  * [CreateChunkRequest](https://www.google.com/search?q=%23createchunkrequest)
  * [Method: corpora.documents.chunks.batchUpdate](https://www.google.com/search?q=%23method-corporadocumentschunksbatchupdate)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-6)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-6)
  * [Request body](https://www.google.com/search?q=%23request-body-12)
  * [Response body](https://www.google.com/search?q=%23response-body-13)
  * [UpdateChunkRequest](https://www.google.com/search?q=%23updatechunkrequest)
  * [Method: corpora.documents.chunks.batchDelete](https://www.google.com/search?q=%23method-corporadocumentschunksbatchdelete)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-7)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-7)
  * [Request body](https://www.google.com/search?q=%23request-body-14)
  * [Response body](https://www.google.com/search?q=%23response-body-15)
  * [DeleteChunkRequest](https://www.google.com/search?q=%23deletechunkrequest)
  * [REST Resource: corpora.documents.chunks](https://www.google.com/search?q=%23rest-resource-corporadocumentschunks)
  * [Resource: Chunk](https://www.google.com/search?q=%23resource-chunk)
  * [ChunkData](https://www.google.com/search?q=%23chunkdata)
  * [State](https://www.google.com/search?q=%23state)

## Method: corpora.documents.chunks.create

Creates a `Chunk`.

### Endpoint

`post`
`https://generativelanguage.googleapis.com/v1beta/{parent=corpora/*/documents/*}/chunks`

### Path parameters

  * `parent`

    `string`

    Required. The name of the `Document` where this `Chunk` will be created. Example: `corpora/my-corpus-123/documents/the-doc-abc` It takes the form `corpora/{corpora}/documents/{document}`.

### Request body

The request body contains an instance of `Chunk`.

#### Fields

  * `name`

    `string`

    Immutable. Identifier. The `Chunk` resource name. The ID (name excluding the "corpora/*/documents/*/chunks/" prefix) can contain up to 40 characters that are lowercase alphanumeric or dashes (-). The ID cannot start or end with a dash. If the name is empty on create, a random 12-character unique ID will be generated. Example: `corpora/{corpus_id}/documents/{document_id}/chunks/123a456b789c`

  * `data`

    `object (ChunkData)`

    Required. The content for the `Chunk`, such as the text string. The maximum number of tokens per chunk is 2043.

  * `customMetadata[]`

    `object (CustomMetadata)`

    Optional. User provided custom metadata stored as key-value pairs. The maximum number of `CustomMetadata` per chunk is 20.

### Response body

If successful, the response body contains a newly created instance of `Chunk`.

## Method: corpora.documents.chunks.list

Lists all `Chunks` in a `Document`.

### Endpoint

`get`
`https://generativelanguage.googleapis.com/v1beta/{parent=corpora/*/documents/*}/chunks`

### Path parameters

  * `parent`

    `string`

    Required. The name of the `Document` containing `Chunks`. Example: `corpora/my-corpus-123/documents/the-doc-abc` It takes the form `corpora/{corpora}/documents/{document}`.

### Query parameters

  * `pageSize`

    `integer`

    Optional. The maximum number of `Chunks` to return (per page). The service may return fewer `Chunks`.
    If unspecified, at most 10 `Chunks` will be returned. The maximum size limit is 100 `Chunks` per page.

  * `pageToken`

    `string`

    Optional. A page token, received from a previous `chunks.list` call.
    Provide the `nextPageToken` returned in the response as an argument to the next request to retrieve the next page.
    When paginating, all other parameters provided to `chunks.list` must match the call that provided the page token.

### Request body

The request body must be empty.

### Response body

Response from `chunks.list` containing a paginated list of `Chunks`. The `Chunks` are sorted by ascending `chunk.create_time`.
If successful, the response body contains data with the following structure:

#### Fields

  * `chunks[]`

    `object (Chunk)`

    The returned `Chunks`.

  * `nextPageToken`

    `string`

    A token, which can be sent as `pageToken` to retrieve the next page. If this field is omitted, there are no more pages.

#### JSON representation

```json
{
  "chunks": [
    {
      object (Chunk)
    }
  ],
  "nextPageToken": string
}
```

## Method: corpora.documents.chunks.get

Gets information about a specific `Chunk`.

### Endpoint

`get`
`https://generativelanguage.googleapis.com/v1beta/{name=corpora/*/documents/*/chunks/*}`

### Path parameters

  * `name`

    `string`

    Required. The name of the `Chunk` to retrieve. Example: `corpora/my-corpus-123/documents/the-doc-abc/chunks/some-chunk` It takes the form `corpora/{corpora}/documents/{document}/chunks/{chunk}`.

### Request body

The request body must be empty.

### Response body

If successful, the response body contains an instance of `Chunk`.

## Method: corpora.documents.chunks.patch

Updates a `Chunk`.

### Endpoint

`patch`
`https://generativelanguage.googleapis.com/v1beta/{chunk.name=corpora/*/documents/*/chunks/*}`

`PATCH https://generativelanguage.googleapis.com/v1beta/{chunk.name=corpora/*/documents/*/chunks/*}`

### Path parameters

  * `chunk.name`

    `string`

    Immutable. Identifier. The `Chunk` resource name. The ID (name excluding the "corpora/*/documents/*/chunks/" prefix) can contain up to 40 characters that are lowercase alphanumeric or dashes (-). The ID cannot start or end with a dash. If the name is empty on create, a random 12-character unique ID will be generated. Example: `corpora/{corpus_id}/documents/{document_id}/chunks/123a456b789c` It takes the form `corpora/{corpora}/documents/{document}/chunks/{chunk}`.

### Query parameters

  * `updateMask`

    `string (FieldMask format)`

    Required. The list of fields to update. Currently, this only supports updating `customMetadata` and `data`.
    This is a comma-separated list of fully qualified names of fields. Example: `"user.displayName,photo"`.

### Request body

The request body contains an instance of `Chunk`.

#### Fields

  * `data`

    `object (ChunkData)`

    Required. The content for the `Chunk`, such as the text string. The maximum number of tokens per chunk is 2043.

  * `customMetadata[]`

    `object (CustomMetadata)`

    Optional. User provided custom metadata stored as key-value pairs. The maximum number of `CustomMetadata` per chunk is 20.

### Response body

If successful, the response body contains an instance of `Chunk`.

## Method: corpora.documents.chunks.delete

Deletes a `Chunk`.

### Endpoint

`delete`
`https://generativelanguage.googleapis.com/v1beta/{name=corpora/*/documents/*/chunks/*}`

### Path parameters

  * `name`

    `string`

    Required. The resource name of the `Chunk` to delete. Example: `corpora/my-corpus-123/documents/the-doc-abc/chunks/some-chunk` It takes the form `corpora/{corpora}/documents/{document}/chunks/{chunk}`.

### Request body

The request body must be empty.

### Response body

If successful, the response body is an empty JSON object.

## Method: corpora.documents.chunks.batchCreate

Batch create `Chunks`.

### Endpoint

`post`
`https://generativelanguage.googleapis.com/v1beta/{parent=corpora/*/documents/*}/chunks:batchCreate`

### Path parameters

  * `parent`

    `string`

    Optional. The name of the `Document` where this batch of `Chunks` will be created. The parent field in every `CreateChunkRequest` must match this value. Example: `corpora/my-corpus-123/documents/the-doc-abc` It takes the form `corpora/{corpora}/documents/{document}`.

### Request body

The request body contains data with the following structure:

#### Fields

  * `requests[]`

    `object (CreateChunkRequest)`

    Required. The request messages specifying the `Chunks` to create. A maximum of 100 `Chunks` can be created in a batch.

### Response body

Response from `chunks.batchCreate` containing a list of created `Chunks`.
If successful, the response body contains data with the following structure:

#### Fields

  * `chunks[]`

    `object (Chunk)`

    Chunks created.

#### JSON representation

```json
{
  "chunks": [
    {
      object (Chunk)
    }
  ]
}
```

## CreateChunkRequest

Request to create a `Chunk`.

### Fields

  * `parent`

    `string`

    Required. The name of the `Document` where this `Chunk` will be created. Example: `corpora/my-corpus-123/documents/the-doc-abc`

  * `chunk`

    `object (Chunk)`

    Required. The `Chunk` to create.

### JSON representation

```json
{
  "parent": string,
  "chunk": {
    object (Chunk)
  }
}
```

## Method: corpora.documents.chunks.batchUpdate

Batch update `Chunks`.

### Endpoint

`post`
`https://generativelanguage.googleapis.com/v1beta/{parent=corpora/*/documents/*}/chunks:batchUpdate`

### Path parameters

  * `parent`

    `string`

    Optional. The name of the `Document` containing the `Chunks` to update. The parent field in every `UpdateChunkRequest` must match this value. Example: `corpora/my-corpus-123/documents/the-doc-abc` It takes the form `corpora/{corpora}/documents/{document}`.

### Request body

The request body contains data with the following structure:

#### Fields

  * `requests[]`

    `object (UpdateChunkRequest)`

    Required. The request messages specifying the `Chunks` to update. A maximum of 100 `Chunks` can be updated in a batch.

### Response body

Response from `chunks.batchUpdate` containing a list of updated `Chunks`.
If successful, the response body contains data with the following structure:

#### Fields

  * `chunks[]`

    `object (Chunk)`

    Chunks updated.

#### JSON representation

```json
{
  "chunks": [
    {
      object (Chunk)
    }
  ]
}
```

## UpdateChunkRequest

Request to update a `Chunk`.

### Fields

  * `chunk`

    `object (Chunk)`

    Required. The `Chunk` to update.

  * `updateMask`

    `string (FieldMask format)`

    Required. The list of fields to update. Currently, this only supports updating `customMetadata` and `data`.
    This is a comma-separated list of fully qualified names of fields. Example: `"user.displayName,photo"`.

### JSON representation

```json
{
  "chunk": {
    object (Chunk)
  },
  "updateMask": string
}
```

## Method: corpora.documents.chunks.batchDelete

Batch delete `Chunks`.

### Endpoint

`post`
`https://generativelanguage.googleapis.com/v1beta/{parent=corpora/*/documents/*}/chunks:batchDelete`

### Path parameters

  * `parent`

    `string`

    Optional. The name of the `Document` containing the `Chunks` to delete. The parent field in every `DeleteChunkRequest` must match this value. Example: `corpora/my-corpus-123/documents/the-doc-abc` It takes the form `corpora/{corpora}/documents/{document}`.

### Request body

The request body contains data with the following structure:

#### Fields

  * `requests[]`

    `object (DeleteChunkRequest)`

    Required. The request messages specifying the `Chunks` to delete.

### Response body

If successful, the response body is an empty JSON object.

## DeleteChunkRequest

Request to delete a `Chunk`.

### Fields

  * `name`

    `string`

    Required. The resource name of the `Chunk` to delete. Example: `corpora/my-corpus-123/documents/the-doc-abc/chunks/some-chunk`

### JSON representation

```json
{
  "name": string
}
```

## REST Resource: corpora.documents.chunks

## Resource: Chunk

A `Chunk` is a subpart of a `Document` that is treated as an independent unit for the purposes of vector representation and storage. A `Corpus` can have a maximum of 1 million `Chunks`.

### Fields

  * `name`

    `string`

    Immutable. Identifier. The `Chunk` resource name. The ID (name excluding the "corpora/*/documents/*/chunks/" prefix) can contain up to 40 characters that are lowercase alphanumeric or dashes (-). The ID cannot start or end with a dash. If the name is empty on create, a random 12-character unique ID will be generated. Example: `corpora/{corpus_id}/documents/{document_id}/chunks/123a456b789c`

  * `data`

    `object (ChunkData)`

    Required. The content for the `Chunk`, such as the text string. The maximum number of tokens per chunk is 2043.

  * `customMetadata[]`

    `object (CustomMetadata)`

    Optional. User provided custom metadata stored as key-value pairs. The maximum number of `CustomMetadata` per chunk is 20.

  * `createTime`

    `string (Timestamp format)`

    Output only. The Timestamp of when the `Chunk` was created.
    Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.

  * `updateTime`

    `string (Timestamp format)`

    Output only. The Timestamp of when the `Chunk` was last updated.
    Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.

  * `state`

    `enum (State)`

    Output only. Current state of the `Chunk`.

### JSON representation

```json
{
  "name": string,
  "data": {
    object (ChunkData)
  },
  "customMetadata": [
    {
      object (CustomMetadata)
    }
  ],
  "createTime": string,
  "updateTime": string,
  "state": enum (State)
}
```

## ChunkData

Extracted data that represents the `Chunk` content.

### Fields

  * `data`

    `Union type`

    `data` can be only one of the following:

      * `stringValue`

        `string`

        The `Chunk` content as a string. The maximum number of tokens per chunk is 2043.

### JSON representation

```json
{

  // data
  "stringValue": string
  // Union type
}
```

## State

States for the lifecycle of a `Chunk`.

### Enums

  * `STATE_UNSPECIFIED`
    The default value. This value is used if the state is omitted.
  * `STATE_PENDING_PROCESSING`
    `Chunk` is being processed (embedding and vector storage).
  * `STATE_ACTIVE`
    `Chunk` is processed and available for querying.
  * `STATE_FAILED`
    `Chunk` failed processing.
