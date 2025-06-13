# Tuning

On this page:

  * [Method: tunedModels.create](https://www.google.com/search?q=%23method-tunedmodelscreate)
  * [Endpoint](https://www.google.com/search?q=%23endpoint)
  * [Query parameters](https://www.google.com/search?q=%23query-parameters)
  * [Request body](https://www.google.com/search?q=%23request-body)
  * [Example request](https://www.google.com/search?q=%23example-request)
  * [Response body](https://www.google.com/search?q=%23response-body-1)
  * [Method: tunedModels.generateContent](https://www.google.com/search?q=%23method-tunedmodelsgeneratecontent)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-1)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters)
  * [Request body](https://www.google.com/search?q=%23request-body-2)
  * [Example request](https://www.google.com/search?q=%23example-request-2)
  * [Response body](https://www.google.com/search?q=%23response-body-3)
  * [Method: tunedModels.streamGenerateContent](https://www.google.com/search?q=%23method-tunedmodelsstreamgeneratecontent)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-2)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-1)
  * [Request body](https://www.google.com/search?q=%23request-body-4)
  * [Example request](https://www.google.com/search?q=%23example-request-3)
  * [Response body](https://www.google.com/search?q=%23response-body-5)
  * [Method: tunedModels.get](https://www.google.com/search?q=%23method-tunedmodelsget)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-3)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-2)
  * [Request body](https://www.google.com/search?q=%23request-body-6)
  * [Example request](https://www.google.com/search?q=%23example-request-4)
  * [Response body](https://www.google.com/search?q=%23response-body-7)
  * [Method: tunedModels.list](https://www.google.com/search?q=%23method-tunedmodelslist)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-4)
  * [Query parameters](https://www.google.com/search?q=%23query-parameters-1)
  * [Request body](https://www.google.com/search?q=%23request-body-8)
  * [Example request](https://www.google.com/search?q=%23example-request-5)
  * [Response body](https://www.google.com/search?q=%23response-body-9)
  * [Method: tunedModels.patch](https://www.google.com/search?q=%23method-tunedmodelspatch)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-5)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-3)
  * [Query parameters](https://www.google.com/search?q=%23query-parameters-2)
  * [Request body](https://www.google.com/search?q=%23request-body-10)
  * [Response body](https://www.google.com/search?q=%23response-body-11)
  * [Method: tunedModels.delete](https://www.google.com/search?q=%23method-tunedmodelsdelete)
  * [Endpoint](https://www.google.com/search?q=%23endpoint-6)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters-4)
  * [Request body](https://www.google.com/search?q=%23request-body-12)
  * [Response body](https://www.google.com/search?q=%23response-body-13)
  * [REST Resource: tunedModels](https://www.google.com/search?q=%23rest-resource-tunedmodels)
  * [Resource: TunedModel](https://www.google.com/search?q=%23resource-tunedmodel)
  * [TunedModelSource](https://www.google.com/search?q=%23tunedmodelsource)
  * [State](https://www.google.com/search?q=%23state)
  * [TuningTask](https://www.google.com/search?q=%23tuningtask)
  * [TuningSnapshot](https://www.google.com/search?q=%23tuningsnapshot)
  * [Dataset](https://www.google.com/search?q=%23dataset)
  * [TuningExamples](https://www.google.com/search?q=%23tuningexamples)
  * [TuningExample](https://www.google.com/search?q=%23tuningexample)
  * [Hyperparameters](https://www.google.com/search?q=%23hyperparameters)

The Gemini API’s fine tuning support provides a mechanism for curating output when you have a small dataset of input/output examples. For more details, check out the [Model tuning guide] and [tutorial].

## Method: tunedModels.create

Creates a tuned model. Check intermediate tuning progress (if any) through the `google.longrunning.Operations` service.
Access status and results through the Operations service. Example: GET /v1/tunedModels/az2mb0bpw6i/operations/000-111-222

### Endpoint

`post`
`https://generativelanguage.googleapis.com/v1beta/tunedModels`

### Query parameters

  * `tunedModelId`

    `string`

    Optional. The unique id for the tuned model if specified. This value should be up to 40 characters, the first character must be a letter, the last could be a letter or a number. The id must match the regular expression: `[a-z]([a-z0-9-]{0,38}[a-z0-9])?`.

### Request body

The request body contains an instance of `TunedModel`.

#### Fields

  * `displayName`

    `string`

    Optional. The name to display for this model in user interfaces. The display name must be up to 40 characters including spaces.

  * `description`

    `string`

    Optional. A short description of this model.

  * `tuningTask`

    `object (TuningTask)`

    Required. The tuning task that creates the tuned model.

  * `readerProjectNumbers[]`

    `string (int64 format)`

    Optional. List of project numbers that have read access to the tuned model.

  * `source_model`

    `Union type`

    The model used as the starting point for tuning. `source_model` can be only one of the following:

      * `tunedModelSource`

        `object (TunedModelSource)`

        Optional. TunedModel to use as the starting point for training the new model.

      * `baseModel`

        `string`

        Immutable. The name of the `Model` to tune. Example: `models/gemini-1.5-flash-001`

  * `temperature`

    `number`

    Optional. Controls the randomness of the output.
    Values can range over `[0.0,1.0]`, inclusive. A value closer to `1.0` will produce responses that are more varied, while a value closer to `0.0` will typically result in less surprising responses from the model.
    This value specifies default to be the one used by the base model while creating the model.

  * `topP`

    `number`

    Optional. For Nucleus sampling.
    Nucleus sampling considers the smallest set of tokens whose probability sum is at least `topP`.
    This value specifies default to be the one used by the base model while creating the model.

  * `topK`

    `integer`

    Optional. For Top-k sampling.
    Top-k sampling considers the set of `topK` most probable tokens. This value specifies default to be used by the backend while making the call to the model.
    This value specifies default to be the one used by the base model while creating the model.

### Example request

(Language-specific code examples are omitted as per instructions)

### Response body

If successful, the response body contains a newly created instance of `Operation`.

## Method: tunedModels.generateContent

Generates a model response given an input `GenerateContentRequest`. Refer to the [text generation guide] for detailed usage information. Input capabilities differ between models, including tuned models. Refer to the [model guide] and [tuning guide] for details.

### Endpoint

`post`
`https://generativelanguage.googleapis.com/v1beta/{model=tunedModels/*}:generateContent`

### Path parameters

  * `model`

    `string`

    Required. The name of the `Model` to use for generating the completion.
    Format: `models/{model}`. It takes the form `tunedModels/{tunedmodel}`.

### Request body

The request body contains data with the following structure:

#### Fields

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

### Example request

(Language-specific code examples are omitted as per instructions)

### Response body

If successful, the response body contains an instance of `GenerateContentResponse`.

## Method: tunedModels.streamGenerateContent

Generates a [streamed response] from the model given an input `GenerateContentRequest`.

### Endpoint

`post`
`https://generativelanguage.googleapis.com/v1beta/{model=tunedModels/*}:streamGenerateContent`

### Path parameters

  * `model`

    `string`

    Required. The name of the `Model` to use for generating the completion.
    Format: `models/{model}`. It takes the form `tunedModels/{tunedmodel}`.

### Request body

The request body contains data with the following structure:

#### Fields

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

### Example request

(Language-specific code examples are omitted as per instructions)

### Response body

If successful, the response body contains a stream of `GenerateContentResponse` instances.

## Method: tunedModels.get

Gets information about a specific TunedModel.

### Endpoint

`get`
`https://generativelanguage.googleapis.com/v1beta/{name=tunedModels/*}`

### Path parameters

  * `name`

    `string`

    Required. The resource name of the model.
    Format: `tunedModels/my-model-id` It takes the form `tunedModels/{tunedmodel}`.

### Request body

The request body must be empty.

### Example request

(Language-specific code examples are omitted as per instructions)

### Response body

If successful, the response body contains an instance of `TunedModel`.

## Method: tunedModels.list

Lists created tuned models.

### Endpoint

`get`
`https://generativelanguage.googleapis.com/v1beta/tunedModels`

### Query parameters

  * `pageSize`

    `integer`

    Optional. The maximum number of `TunedModels` to return (per page). The service may return fewer tuned models.
    If unspecified, at most 10 tuned models will be returned. This method returns at most 1000 models per page, even if you pass a larger pageSize.

  * `pageToken`

    `string`

    Optional. A page token, received from a previous `tunedModels.list` call.
    Provide the `pageToken` returned by one request as an argument to the next request to retrieve the next page.
    When paginating, all other parameters provided to `tunedModels.list` must match the call that provided the page token.

  * `filter`

    `string`

    Optional. A filter is a full text search over the tuned model's description and display name. By default, results will not include tuned models shared with everyone.
    Additional operators: - owner:me - writers:me - readers:me - readers:everyone
    Examples: "owner:me" returns all tuned models to which caller has owner role "readers:me" returns all tuned models to which caller has reader role "readers:everyone" returns all tuned models that are shared with everyone

### Request body

The request body must be empty.

### Example request

(Language-specific code examples are omitted as per instructions)

### Response body

Response from `tunedModels.list` containing a paginated list of Models.
If successful, the response body contains data with the following structure:

#### Fields

  * `tunedModels[]`

    `object (TunedModel)`

    The returned Models.

  * `nextPageToken`

    `string`

    A token, which can be sent as `pageToken` to retrieve the next page.
    If this field is omitted, there are no more pages.

#### JSON representation

```json
{
  "tunedModels": [
    {
      object (TunedModel)
    }
  ],
  "nextPageToken": string
}
```

## Method: tunedModels.patch

Updates a tuned model.

### Endpoint

`patch`
`https://generativelanguage.googleapis.com/v1beta/{tunedModel.name=tunedModels/*}`

`PATCH https://generativelanguage.googleapis.com/v1beta/{tunedModel.name=tunedModels/*}`

### Path parameters

  * `tunedModel.name`

    `string`

    Output only. The tuned model name. A unique name will be generated on create. Example: `tunedModels/az2mb0bpw6i` If displayName is set on create, the id portion of the name will be set by concatenating the words of the displayName with hyphens and adding a random portion for uniqueness.
    Example:

    `displayName = Sentence Translator`
    `name = tunedModels/sentence-translator-u3b7m` It takes the form `tunedModels/{tunedmodel}`.

### Query parameters

  * `updateMask`

    `string (FieldMask format)`

    Optional. The list of fields to update.
    This is a comma-separated list of fully qualified names of fields. Example: `"user.displayName,photo"`.

### Request body

The request body contains an instance of `TunedModel`.

#### Fields

  * `displayName`

    `string`

    Optional. The name to display for this model in user interfaces. The display name must be up to 40 characters including spaces.

  * `description`

    `string`

    Optional. A short description of this model.

  * `tuningTask`

    `object (TuningTask)`

    Required. The tuning task that creates the tuned model.

  * `readerProjectNumbers[]`

    `string (int64 format)`

    Optional. List of project numbers that have read access to the tuned model.

  * `source_model`

    `Union type`

    The model used as the starting point for tuning. `source_model` can be only one of the following:

      * `tunedModelSource`

        `object (TunedModelSource)`

        Optional. TunedModel to use as the starting point for training the new model.

      * `baseModel`

        `string`

        Immutable. The name of the `Model` to tune. Example: `models/gemini-1.5-flash-001`

  * `temperature`

    `number`

    Optional. Controls the randomness of the output.
    Values can range over `[0.0,1.0]`, inclusive. A value closer to `1.0` will produce responses that are more varied, while a value closer to `0.0` will typically result in less surprising responses from the model.
    This value specifies default to be the one used by the base model while creating the model.

  * `topP`

    `number`

    Optional. For Nucleus sampling.
    Nucleus sampling considers the smallest set of tokens whose probability sum is at least `topP`.
    This value specifies default to be the one used by the base model while creating the model.

  * `topK`

    `integer`

    Optional. For Top-k sampling.
    Top-k sampling considers the set of `topK` most probable tokens. This value specifies default to be used by the backend while making the call to the model.
    This value specifies default to be the one used by the base model while creating the model.

### Response body

If successful, the response body contains an instance of `TunedModel`.

## Method: tunedModels.delete

Deletes a tuned model.

### Endpoint

`delete`
`https://generativelanguage.googleapis.com/v1beta/{name=tunedModels/*}`

### Path parameters

  * `name`

    `string`

    Required. The resource name of the model. Format: `tunedModels/my-model-id` It takes the form `tunedModels/{tunedmodel}`.

### Request body

The request body must be empty.

### Response body

If successful, the response body is an empty JSON object.

## REST Resource: tunedModels

## Resource: TunedModel

A fine-tuned model created using ModelService.CreateTunedModel.

### Fields

  * `name`

    `string`

    Output only. The tuned model name. A unique name will be generated on create. Example: `tunedModels/az2mb0bpw6i` If displayName is set on create, the id portion of the name will be set by concatenating the words of the displayName with hyphens and adding a random portion for uniqueness.
    Example:

    `displayName = Sentence Translator`
    `name = tunedModels/sentence-translator-u3b7m`

  * `displayName`

    `string`

    Optional. The name to display for this model in user interfaces. The display name must be up to 40 characters including spaces.

  * `description`

    `string`

    Optional. A short description of this model.

  * `state`

    `enum (State)`

    Output only. The state of the tuned model.

  * `createTime`

    `string (Timestamp format)`

    Output only. The timestamp when this model was created.
    Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.

  * `updateTime`

    `string (Timestamp format)`

    Output only. The timestamp when this model was updated.
    Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.

  * `tuningTask`

    `object (TuningTask)`

    Required. The tuning task that creates the tuned model.

  * `readerProjectNumbers[]`

    `string (int64 format)`

    Optional. List of project numbers that have read access to the tuned model.

  * `source_model`

    `Union type`

    The model used as the starting point for tuning. `source_model` can be only one of the following:

      * `tunedModelSource`

        `object (TunedModelSource)`

        Optional. TunedModel to use as the starting point for training the new model.

      * `baseModel`

        `string`

        Immutable. The name of the `Model` to tune. Example: `models/gemini-1.5-flash-001`

  * `temperature`

    `number`

    Optional. Controls the randomness of the output.
    Values can range over `[0.0,1.0]`, inclusive. A value closer to `1.0` will produce responses that are more varied, while a value closer to `0.0` will typically result in less surprising responses from the model.
    This value specifies default to be the one used by the base model while creating the model.

  * `topP`

    `number`

    Optional. For Nucleus sampling.
    Nucleus sampling considers the smallest set of tokens whose probability sum is at least `topP`.
    This value specifies default to be the one used by the base model while creating the model.

  * `topK`

    `integer`

    Optional. For Top-k sampling.
    Top-k sampling considers the set of `topK` most probable tokens. This value specifies default to be used by the backend while making the call to the model.
    This value specifies default to be the one used by the base model while creating the model.

### JSON representation

```json
{
  "name": string,
  "displayName": string,
  "description": string,
  "state": enum (State),
  "createTime": string,
  "updateTime": string,
  "tuningTask": {
    object (TuningTask)
  },
  "readerProjectNumbers": [
    string
  ],

  // source_model
  "tunedModelSource": {
    object (TunedModelSource)
  },
  "baseModel": string
  // Union type
  "temperature": number,
  "topP": number,
  "topK": integer
}
```

## TunedModelSource

Tuned model as a source for training a new model.

### Fields

  * `tunedModel`

    `string`

    Immutable. The name of the `TunedModel` to use as the starting point for training the new model. Example: `tunedModels/my-tuned-model`

  * `baseModel`

    `string`

    Output only. The name of the base `Model` this `TunedModel` was tuned from. Example: `models/gemini-1.5-flash-001`

### JSON representation

```json
{
  "tunedModel": string,
  "baseModel": string
}
```

## State

The state of the tuned model.

### Enums

  * `STATE_UNSPECIFIED`
    The default value. This value is unused.
  * `CREATING`
    The model is being created.
  * `ACTIVE`
    The model is ready to be used.
  * `FAILED`
    The model failed to be created.

## TuningTask

Tuning tasks that create tuned models.

### Fields

  * `startTime`

    `string (Timestamp format)`

    Output only. The timestamp when tuning this model started.
    Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.

  * `completeTime`

    `string (Timestamp format)`

    Output only. The timestamp when tuning this model completed.
    Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.

  * `snapshots[]`

    `object (TuningSnapshot)`

    Output only. Metrics collected during tuning.

  * `trainingData`

    `object (Dataset)`

    Required. Input only. Immutable. The model training data.

  * `hyperparameters`

    `object (Hyperparameters)`

    Immutable. Hyperparameters controlling the tuning process. If not provided, default values will be used.

### JSON representation

```json
{
  "startTime": string,
  "completeTime": string,
  "snapshots": [
    {
      object (TuningSnapshot)
    }
  ],
  "trainingData": {
    object (Dataset)
  },
  "hyperparameters": {
    object (Hyperparameters)
  }
}
```

## TuningSnapshot

Record for a single tuning step.

### Fields

  * `step`

    `integer`

    Output only. The tuning step.

  * `epoch`

    `integer`

    Output only. The epoch this step was part of.

  * `meanLoss`

    `number`

    Output only. The mean loss of the training examples for this step.

  * `computeTime`

    `string (Timestamp format)`

    Output only. The timestamp when this metric was computed.
    Uses RFC 3339, where generated output will always be Z-normalized and uses 0, 3, 6 or 9 fractional digits. Offsets other than "Z" are also accepted. Examples: `"2014-10-02T15:01:23Z"`, `"2014-10-02T15:01:23.045123456Z"` or `"2014-10-02T15:01:23+05:30"`.

### JSON representation

```json
{
  "step": integer,
  "epoch": integer,
  "meanLoss": number,
  "computeTime": string
}
```

## Dataset

Dataset for training or validation.

### Fields

  * `dataset`

    `Union type`

    Inline data or a reference to the data. `dataset` can be only one of the following:

      * `examples`

        `object (TuningExamples)`

        Optional. Inline examples with simple input/output text.

### JSON representation

```json
{

  // dataset
  "examples": {
    object (TuningExamples)
  }
  // Union type
}
```

## TuningExamples

A set of tuning examples. Can be training or validation data.

### Fields

  * `examples[]`

    `object (TuningExample)`

    The examples. Example input can be for text or discuss, but all examples in a set must be of the same type.

### JSON representation

```json
{
  "examples": [
    {
      object (TuningExample)
    }
  ]
}
```

## TuningExample

A single example for tuning.

### Fields

  * `output`

    `string`

    Required. The expected model output.

  * `model_input`

    `Union type`

    The input to the model for this example. `model_input` can be only one of the following:

      * `textInput`

        `string`

        Optional. Text model input.

### JSON representation

```json
{
  "output": string,

  // model_input
  "textInput": string
  // Union type
}
```

## Hyperparameters

Hyperparameters controlling the tuning process. Read more at [https://ai.google.dev/docs/model\_tuning\_guidance](https://ai.google.dev/docs/model_tuning_guidance)

### Fields

  * `learning_rate_option`

    `Union type`

    Options for specifying learning rate during tuning. `learning_rate_option` can be only one of the following:

      * `learningRate`

        `number`

        Optional. Immutable. The learning rate hyperparameter for tuning. If not set, a default of 0.001 or 0.0002 will be calculated based on the number of training examples.

      * `learningRateMultiplier`

        `number`

        Optional. Immutable. The learning rate multiplier is used to calculate a final learningRate based on the default (recommended) value. Actual learning rate := learningRateMultiplier \* default learning rate Default learning rate is dependent on base model and dataset size. If not set, a default of 1.0 will be used.

  * `epochCount`

    `integer`

    Immutable. The number of training epochs. An epoch is one pass through the training data. If not set, a default of 5 will be used.

  * `batchSize`

    `integer`

    Immutable. The batch size hyperparameter for tuning. If not set, a default of 4 or 16 will be used based on the number of training examples.
