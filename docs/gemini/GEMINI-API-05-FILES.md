# Using files

The Gemini API supports uploading media files separately from the prompt input, allowing your media to be reused across multiple requests and multiple prompts. For more details, check out the Prompting with media guide.

## Method: media.upload

Creates a File.

### Endpoint

  * **Upload URI**, for media upload requests: `post https://generativelanguage.googleapis.com/upload/v1beta/files`
  * **Metadata URI**, for metadata-only requests: `post https://generativelanguage.googleapis.com/v1beta/files`

### Request body

The request body contains data with the following structure:

  * **file** (object (File)): Optional. Metadata for the file to create.

### Example request

Here's an example using `curl` for image upload. Examples for other media types (Audio, Text, Video, PDF) follow a similar multi-step pattern.

```shell
MIME_TYPE=$(file -b --mime-type "${IMG_PATH_2}")
NUM_BYTES=$(wc -c < "${IMG_PATH_2}")
DISPLAY_NAME=TEXT
tmp_header_file=upload-header.tmp

# Initial resumable request defining metadata.
# The upload url is in the response headers dump them to a file.
curl "${BASE_URL}/upload/v1beta/files?key=${GEMINI_API_KEY}" \
  -D upload-header.tmp \
  -H "X-Goog-Upload-Protocol: resumable" \
  -H "X-Goog-Upload-Command: start" \
  -H "X-Goog-Upload-Header-Content-Length: ${NUM_BYTES}" \
  -H "X-Goog-Upload-Header-Content-Type: ${MIME_TYPE}" \
  -H "Content-Type: application/json" \
  -d "{'file': {'display_name': '${DISPLAY_NAME}'}}" 2> /dev/null

upload_url=$(grep -i "x-goog-upload-url: " "${tmp_header_file}" | cut -d" " -f2 | tr -d "\r")
rm "${tmp_header_file}"

# Upload the actual bytes.
curl "${upload_url}" \
  -H "Content-Length: ${NUM_BYTES}" \
  -H "X-Goog-Upload-Offset: 0" \
  -H "X-Goog-Upload-Command: upload, finalize" \
  --data-binary "@${IMG_PATH_2}" 2> /dev/null > file_info.json

file_uri=$(jq ".file.uri" file_info.json)
echo file_uri=$file_uri

# Now generate content using that file
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$GEMINI_API_KEY" \
    -H 'Content-Type: application/json' \
    -X POST \
    -d '{
      "contents": [{
        "parts":[
          {"text": "Can you tell me about the instruments in this photo?"},
          {"file_data":
            {"mime_type": "image/jpeg",
             "file_uri": '$file_uri'}
        }]
        }]
       }' 2> /dev/null > response.json

cat response.json
echo

jq ".candidates[].content.parts[].text" response.json
```

### Response body

Response for `media.upload`. If successful, the response body contains data with the following structure:

  * **file** (object (File)): Metadata for the created file.

<!-- end list -->

```json
{
  "file": {
    object (File)
  }
}
```

## Method: files.get

Gets the metadata for the given File.

### Endpoint

`get https://generativelanguage.googleapis.com/v1beta/{name=files/*}`

### Path parameters

  * **name** (string): Required. The name of the File to get. Example: `files/abc-123`. It takes the form `files/{file}`.

### Request body

The request body must be empty.

### Example request

```shell
name=$(jq ".file.name" file_info.json)
# Get the file of interest to check state
curl https://generativelanguage.googleapis.com/v1beta/files/$name > file_info.json

# Print some information about the file you got
name=$(jq ".file.name" file_info.json)
echo name=$name
file_uri=$(jq ".file.uri" file_info.json)
echo file_uri=$file_uri
```

### Response body

If successful, the response body contains an instance of `File`.

## Method: files.list

Lists the metadata for Files owned by the requesting project.

### Endpoint

`get https://generativelanguage.googleapis.com/v1beta/files`

### Query parameters

  * **pageSize** (integer): Optional. Maximum number of Files to return per page. If unspecified, defaults to 10. Maximum `pageSize` is 100.
  * **pageToken** (string): Optional. A page token from a previous `files.list` call.

### Request body

The request body must be empty.

### Example request

```shell
echo "My files: "

curl "https://generativelanguage.googleapis.com/v1beta/files?key=$GEMINI_API_KEY"
```

### Response body

Response for `files.list`. If successful, the response body contains data with the following structure:

  * **files[]** (object (File)): The list of Files.
  * **nextPageToken** (string): A token that can be sent as a `pageToken` into a subsequent `files.list` call.

<!-- end list -->

```json
{
  "files": [
    {
      object (File)
    }
  ],
  "nextPageToken": string
}
```

## Method: files.delete

Deletes the File.

### Endpoint

`delete https://generativelanguage.googleapis.com/v1beta/{name=files/*}`

### Path parameters

  * **name** (string): Required. The name of the File to delete. Example: `files/abc-123`. It takes the form `files/{file}`.

### Request body

The request body must be empty.

### Example request

```shell
curl --request "DELETE" https://generativelanguage.googleapis.com/v1beta/files/$name?key=$GEMINI_API_KEY
```

### Response body

If successful, the response body is an empty JSON object.

## REST Resource: files

### Resource: File

A file uploaded to the API. Next ID: 15

  * **name** (string): Immutable. Identifier. The File resource name. The ID (name excluding the "files/" prefix) can contain up to 40 characters that are lowercase alphanumeric or dashes (-). The ID cannot start or end with a dash. If the name is empty on create, a unique name will be generated. Example: `files/123-456`
  * **displayName** (string): Optional. The human-readable display name for the File. The display name must be no more than 512 characters in length, including spaces. Example: "Welcome Image"
  * **mimeType** (string): Output only. MIME type of the file.
  * **sizeBytes** (string (int64 format)): Output only. Size of the file in bytes.
  * **createTime** (string (Timestamp format)): Output only. The timestamp of when the File was created. Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.
  * **updateTime** (string (Timestamp format)): Output only. The timestamp of when the File was last updated. Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.
  * **expirationTime** (string (Timestamp format)): Output only. The timestamp of when the File will be deleted. Only set if the File is scheduled to expire. Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.
  * **sha256Hash** (string (bytes format)): Output only. SHA-256 hash of the uploaded bytes. A base64-encoded string.
  * **uri** (string): Output only. The uri of the File.
  * **downloadUri** (string): Output only. The download uri of the File.
  * **state** (enum (State)): Output only. Processing state of the File.
  * **source** (enum (Source)): Source of the File.
  * **error** (object (Status)): Output only. Error status if File processing failed.

> **metadata** (Union type): Metadata for the File. `metadata` can be only one of the following:
>
>   * **videoMetadata** (object (VideoFileMetadata)): Output only. Metadata for a video.

```json
{
  "name": string,
  "displayName": string,
  "mimeType": string,
  "sizeBytes": string,
  "createTime": string,
  "updateTime": string,
  "expirationTime": string,
  "sha256Hash": string,
  "uri": string,
  "downloadUri": string,
  "state": enum (State),
  "source": enum (Source),
  "error": {
    object (Status)
  },

  // metadata
  "videoMetadata": {
    object (VideoFileMetadata)
  }
  // Union type
}
```

### VideoFileMetadata

Metadata for a video File.

  * **videoDuration** (string (Duration format)): Duration of the video. A duration in seconds with up to nine fractional digits, ending with 's'. Example: `"3.5s"`.

<!-- end list -->

```json
{
  "videoDuration": string
}
```

### State

States for the lifecycle of a File.

>   * **STATE\_UNSPECIFIED**: The default value. This value is used if the state is omitted.
>   * **PROCESSING**: File is being processed and cannot be used for inference yet.
>   * **ACTIVE**: File is processed and available for inference.
>   * **FAILED**: File failed processing.

### Source

>   * **SOURCE\_UNSPECIFIED**: Used if source is not specified.
>   * **UPLOADED**: Indicates the file is uploaded by the user.
>   * **GENERATED**: Indicates the file is generated by Google.

### Status

The Status type defines a logical error model that is suitable for different programming environments, including REST APIs and RPC APIs. It is used by gRPC. Each Status message contains three pieces of data: error code, error message, and error details. You can find out more about this error model and how to work with it in the API Design Guide.

  * **code** (integer): The status code, which should be an enum value of `google.rpc.Code`.
  * **message** (string): A developer-facing error message, which should be in English. Any user-facing error message should be localized and sent in the `google.rpc.Status.details` field, or localized by the client.
  * **details[]** (object): A list of messages that carry the error details. There is a common set of message types for APIs to use. An object containing fields of an arbitrary type. An additional field `"@type"` contains a URI identifying the type. Example: `{ "id": 1234, "@type": "types.example.com/standard/id" }`.

<!-- end list -->

```json
{
  "code": integer,
  "message": string,
  "details": [
    {
      "@type": string,
      field1: ...,
      ...
    }
  ]
}
```
