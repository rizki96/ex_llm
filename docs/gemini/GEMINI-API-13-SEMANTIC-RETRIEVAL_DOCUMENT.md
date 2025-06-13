# Documents

A Document is a collection of Chunks. A Corpus can have a maximum of 10,000 Documents.

## Method: corpora.documents.create

Creates an empty Document.

### Endpoint

`post https://generativelanguage.googleapis.com/v1beta/{parent=corpora/*}/documents`

### Path parameters

  * **parent** (string): Required. The name of the Corpus where this Document will be created. Example: `corpora/my-corpus-123`.

### Request body

The request body contains an instance of Document.

  * **name** (string): Immutable. Identifier. The Document resource name. The ID (name excluding the "corpora/\*/documents/" prefix) can contain up to 40 characters that are lowercase alphanumeric or dashes (-). The ID cannot start or end with a dash. If the name is empty on create, a unique name will be derived from `displayName` along with a 12 character random suffix. Example: `corpora/{corpus_id}/documents/my-awesome-doc-123a456b789c`.
  * **displayName** (string): Optional. The human-readable display name for the Document. The display name must be no more than 512 characters in length, including spaces. Example: "Semantic Retriever Documentation".
  * **customMetadata[]** (object (CustomMetadata)): Optional. User provided custom metadata stored as key-value pairs used for querying. A Document can have a maximum of 20 CustomMetadata.

### Response body

If successful, the response body contains a newly created instance of Document.

## Method: corpora.documents.query

Performs semantic search over a Document.

### Endpoint

`post https://generativelanguage.googleapis.com/v1beta/{name=corpora/*/documents/*}:query`

### Path parameters

  * **name** (string): Required. The name of the Document to query. Example: `corpora/my-corpus-123/documents/the-doc-abc`.

### Request body

The request body contains data with the following structure:

  * **query** (string): Required. Query string to perform semantic search.
  * **resultsCount** (integer): Optional. The maximum number of Chunks to return. The service may return fewer Chunks. If unspecified, at most 10 Chunks will be returned. The maximum specified result count is 100.
  * **metadataFilters[]** (object (MetadataFilter)): Optional. Filter for Chunk metadata. Each MetadataFilter object should correspond to a unique key. Multiple MetadataFilter objects are joined by logical "AND"s. Note: Document-level filtering is not supported for this request because a Document name is already specified.
      * Example query: `(year >= 2020 OR year < 2010) AND (genre = drama OR genre = action)`
        `metadataFilters = [ {key = "chunk.custom_metadata.year" conditions = [{int_value = 2020, operation = GREATER_EQUAL}, {int_value = 2010, operation = LESS}}, {key = "chunk.custom_metadata.genre" conditions = [{stringValue = "drama", operation = EQUAL}, {stringValue = "action", operation = EQUAL}}]`
      * Example query for a numeric range of values: `(year > 2015 AND year <= 2020)`
        `metadataFilters = [ {key = "chunk.custom_metadata.year" conditions = [{int_value = 2015, operation = GREATER}]}, {key = "chunk.custom_metadata.year" conditions = [{int_value = 2020, operation = LESS_EQUAL}]}]`
      * Note: "AND"s for the same key are only supported for numeric values. String values only support "OR"s for the same key.

### Response body

Response from `documents.query` containing a list of relevant chunks. If successful, the response body contains data with the following structure:

  * **relevantChunks[]** (object (RelevantChunk)): The returned relevant chunks.

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

## Method: corpora.documents.list

Lists all Documents in a Corpus.

### Endpoint

`get https://generativelanguage.googleapis.com/v1beta/{parent=corpora/*}/documents`

### Path parameters

  * **parent** (string): Required. The name of the Corpus containing Documents. Example: `corpora/my-corpus-123`.

### Query parameters

  * **pageSize** (integer): Optional. The maximum number of Documents to return (per page). The service may return fewer Documents. If unspecified, at most 10 Documents will be returned. The maximum size limit is 20 Documents per page.
  * **pageToken** (string): Optional. A page token, received from a previous `documents.list` call. Provide the `nextPageToken` returned in the response as an argument to the next request to retrieve the next page. When paginating, all other parameters provided to `documents.list` must match the call that provided the page token.

### Request body

The request body must be empty.

### Response body

Response from `documents.list` containing a paginated list of Documents. The Documents are sorted by ascending `document.create_time`. If successful, the response body contains data with the following structure:

  * **documents[]** (object (Document)): The returned Documents.
  * **nextPageToken** (string): A token, which can be sent as `pageToken` to retrieve the next page. If this field is omitted, there are no more pages.

<!-- end list -->

```json
{
  "documents": [
    {
      object (Document)
    }
  ],
  "nextPageToken": string
}
```

## Method: corpora.documents.get

Gets information about a specific Document.

### Endpoint

`get https://generativelanguage.googleapis.com/v1beta/{name=corpora/*/documents/*}`

### Path parameters

  * **name** (string): Required. The name of the Document to retrieve. Example: `corpora/my-corpus-123/documents/the-doc-abc`.

### Request body

The request body must be empty.

### Response body

If successful, the response body contains an instance of Document.

## Method: corpora.documents.patch

Updates a Document.

### Endpoint

`patch https://generativelanguage.googleapis.com/v1beta/{document.name=corpora/*/documents/*}`

### Path parameters

  * **document.name** (string): Immutable. Identifier. The Document resource name. The ID (name excluding the "corpora/\*/documents/" prefix) can contain up to 40 characters that are lowercase alphanumeric or dashes (-). The ID cannot start or end with a dash. If the name is empty on create, a unique name will be derived from `displayName` along with a 12 character random suffix. Example: `corpora/{corpus_id}/documents/my-awesome-doc-123a456b789c`.

### Query parameters

  * **updateMask** (string (FieldMask format)): Required. The list of fields to update. Currently, this only supports updating `displayName` and `customMetadata`. This is a comma-separated list of fully qualified names of fields. Example: `"user.displayName,photo"`.

### Request body

The request body contains an instance of Document.

  * **displayName** (string): Optional. The human-readable display name for the Document. The display name must be no more than 512 characters in length, including spaces. Example: "Semantic Retriever Documentation".
  * **customMetadata[]** (object (CustomMetadata)): Optional. User provided custom metadata stored as key-value pairs used for querying. A Document can have a maximum of 20 CustomMetadata.

### Response body

If successful, the response body contains an instance of Document.

## Method: corpora.documents.delete

Deletes a Document.

### Endpoint

`delete https://generativelanguage.googleapis.com/v1beta/{name=corpora/*/documents/*}`

### Path parameters

  * **name** (string): Required. The resource name of the Document to delete. Example: `corpora/my-corpus-123/documents/the-doc-abc`.

### Query parameters

  * **force** (boolean): Optional. If set to true, any Chunks and objects related to this Document will also be deleted. If false (the default), a FAILED\_PRECONDITION error will be returned if Document contains any Chunks.

### Request body

The request body must be empty.

### Response body

If successful, the response body is an empty JSON object.

## REST Resource: corpora.documents

### Resource: Document

A Document is a collection of Chunks. A Corpus can have a maximum of 10,000 Documents.

  * **name** (string): Immutable. Identifier. The Document resource name. The ID (name excluding the "corpora/\*/documents/" prefix) can contain up to 40 characters that are lowercase alphanumeric or dashes (-). The ID cannot start or end with a dash. If the name is empty on create, a unique name will be derived from `displayName` along with a 12 character random suffix. Example: `corpora/{corpus_id}/documents/my-awesome-doc-123a456b789c`.
  * **displayName** (string): Optional. The human-readable display name for the Document. The display name must be no more than 512 characters in length, including spaces. Example: "Semantic Retriever Documentation".
  * **customMetadata[]** (object (CustomMetadata)): Optional. User provided custom metadata stored as key-value pairs used for querying. A Document can have a maximum of 20 CustomMetadata.
  * **updateTime** (string (Timestamp format)): Output only. The Timestamp of when the Document was last updated. Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.
  * **createTime** (string (Timestamp format)): Output only. The Timestamp of when the Document was created. Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.

<!-- end list -->

```json
{
  "name": string,
  "displayName": string,
  "customMetadata": [
    {
      object (CustomMetadata)
    }
  ],
  "updateTime": string,
  "createTime": string
}
```

### CustomMetadata

User provided metadata stored as key-value pairs.

  * **key** (string): Required. The key of the metadata to store.

> **value** (Union type): `value` can be only one of the following:
>
>   * **stringValue** (string): The string value of the metadata to store.
>   * **stringListValue** (object (StringList)): The StringList value of the metadata to store.
>   * **numericValue** (number): The numeric value of the metadata to store.

```json
{
  "key": string,

  // value
  "stringValue": string,
  "stringListValue": {
    object (StringList)
  },
  "numericValue": number
  // Union type
}
```

### StringList

User provided string values assigned to a single metadata key.

  * **values[]** (string): The string values of the metadata to store.

<!-- end list -->

```json
{
  "values": [
    string
  ]
}
```

## MetadataFilter

User provided filter to limit retrieval based on Chunk or Document level metadata values.

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

> **value** (Union type): `value` can be only one of the following:
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
