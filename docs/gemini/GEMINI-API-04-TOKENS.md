# Counting tokens

On this page:

  * [Method: models.countTokens](https://www.google.com/search?q=%23method-models.counttokens)
  * [Endpoint](https://www.google.com/search?q=%23endpoint)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters)
  * [Request body](https://www.google.com/search?q=%23request-body)
  * [Example request](https://www.google.com/search?q=%23example-request)
  * [Response body](https://www.google.com/search?q=%23response-body)
  * [GenerateContentRequest](https://www.google.com/search?q=%23generatecontentrequest)

For a detailed guide on counting tokens using the Gemini API, including how images, audio and video are counted, see the [Token counting guide] and accompanying [Cookbook recipe].

## Method: models.countTokens

Runs a model's tokenizer on input `Content` and returns the token count. Refer to the [tokens guide] to learn more about tokens.

## Endpoint

`post`
`https://generativelanguage.googleapis.com/v1beta/{model=models/*}:countTokens`

## Path parameters

### `model`

`string`

Required. The model's resource name. This serves as an ID for the Model to use.
This name should match a model name returned by the `models.list` method.
Format: `models/{model}` It takes the form `models/{model}`.

## Request body

The request body contains data with the following structure:

### Fields

  * `contents[]`

    `object (Content)`

    Optional. The input given to the model as a prompt. This field is ignored when `generateContentRequest` is set.

  * `generateContentRequest`

    `object (GenerateContentRequest)`

    Optional. The overall input given to the `Model`. This includes the prompt as well as other model steering information like `system instructions`, and/or function declarations for `function calling`. `Models/Contents` and `generateContentRequests` are mutually exclusive. You can either send `Model` + `Contents` or a `generateContentRequest`, but never both.

## Example request

```bash
curl https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:countTokens?key=$GEMINI_API_KEY \
    -H 'Content-Type: application/json' \
    -X POST \
    -d '{
      "contents": [{
        "parts":[{
          "text": "The quick brown fox jumps over the lazy dog."
          }],
        }],
      }'
```

## Response body

A response from `models.countTokens`.
It returns the model's `tokenCount` for the `prompt`.
If successful, the response body contains data with the following structure:

### Fields

  * `totalTokens`

    `integer`

    The number of tokens that the `Model` tokenizes the `prompt` into. Always non-negative.

  * `cachedContentTokenCount`

    `integer`

    Number of tokens in the cached part of the prompt (the cached content).

  * `promptTokensDetails[]`

    `object (ModalityTokenCount)`

    Output only. List of modalities that were processed in the request input.

  * `cacheTokensDetails[]`

    `object (ModalityTokenCount)`

    Output only. List of modalities that were processed in the cached content.

### JSON representation

```json
{
  "totalTokens": integer,
  "cachedContentTokenCount": integer,
  "promptTokensDetails": [
    {
      object (ModalityTokenCount)
    }
  ],
  "cacheTokensDetails": [
    {
      object (ModalityTokenCount)
    }
  ]
}
```

## GenerateContentRequest

Request to generate a completion from the model.

### Fields

  * `model`

    `string`

    Required. The name of the `Model` to use for generating the completion.
    Format: `models/{model}`.

  * `contents[]`

    `object (Content)`

    Required. The content of the current conversation with the model.
    For single-turn queries, this is a single instance. For multi-turn queries like `chat`, this is a repeated field that contains the conversation history and the latest request.

  * `tools[]`

    `object (Tool)`

    Optional. A list of `Tools` the `Model` may use to generate the next response.
    A `Tool` is a piece of code that enables the system to interact with external systems to perform an action, or set of actions, outside of knowledge and scope of the `Model`. Supported `Tools` are `Function` and `codeExecution`. Refer to the [Function calling] and the [Code execution] guides to learn more.

  * `toolConfig`

    `object (ToolConfig)`

    Optional. Tool configuration for any `Tool` specified in the request. Refer to the [Function calling guide] for a usage example.

  * `safetySettings[]`

    `object (SafetySetting)`

    Optional. A list of unique `SafetySetting` instances for blocking unsafe content.
    This will be enforced on the `GenerateContentRequest.contents` and `GenerateContentResponse.candidates`. There should not be more than one setting for each `SafetyCategory` type. The API will block any contents and responses that fail to meet the thresholds set by these settings. This list overrides the default settings for each `SafetyCategory` specified in the safetySettings. If there is no `SafetySetting` for a given `SafetyCategory` provided in the list, the API will use the default safety setting for that category. Harm categories HARM\_CATEGORY\_HATE\_SPEECH, HARM\_CATEGORY\_SEXUALLY\_EXPLICIT, HARM\_CATEGORY\_DANGEROUS\_CONTENT, HARM\_CATEGORY\_HARASSMENT, HARM\_CATEGORY\_CIVIC\_INTEGRITY are supported. Refer to the [guide] for detailed information on available safety settings. Also refer to the [Safety guidance] to learn how to incorporate safety considerations in your AI applications.

  * `systemInstruction`

    `object (Content)`

    Optional. Developer set `system instruction`(s). Currently, text only.

  * `generationConfig`

    `object (GenerationConfig)`

    Optional. Configuration options for model generation and outputs.

  * `cachedContent`

    `string`

    Optional. The name of the content `cached` to use as context to serve the prediction. Format: `cachedContents/{cachedContent}`

### JSON representation

```json
{
  "model": string,
  "contents": [
    {
      object (Content)
    }
  ],
  "tools": [
    {
      object (Tool)
    }
  ],
  "toolConfig": {
    object (ToolConfig)
  },
  "safetySettings": [
    {
      object (SafetySetting)
    }
  ],
  "systemInstruction": {
    object (Content)
  },
  "generationConfig": {
    object (GenerationConfig)
  },
  "cachedContent": string
}
```
