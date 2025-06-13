# Question answering

On this page:

  * [Method: models.generateAnswer](https://www.google.com/search?q=%23method-modelsgenerateanswer)
  * [Endpoint](https://www.google.com/search?q=%23endpoint)
  * [Path parameters](https://www.google.com/search?q=%23path-parameters)
  * [Request body](https://www.google.com/search?q=%23request-body)
  * [Response body](https://www.google.com/search?q=%23response-body)
  * [GroundingPassages](https://www.google.com/search?q=%23groundingpassages)
  * [GroundingPassage](https://www.google.com/search?q=%23groundingpassage)
  * [SemanticRetrieverConfig](https://www.google.com/search?q=%23semanticretrieverconfig)
  * [AnswerStyle](https://www.google.com/search?q=%23answerstyle)
  * [InputFeedback](https://www.google.com/search?q=%23inputfeedback)
  * [BlockReason](https://www.google.com/search?q=%23blockreason)

The Semantic Retrieval API provides a hosted question answering service for building Retrieval Augmented Generation (RAG) systems using Google's infrastructure.

## Method: models.generateAnswer

Generates a grounded answer from the model given an input `GenerateAnswerRequest`.

### Endpoint

`post`
`https://generativelanguage.googleapis.com/v1beta/{model=models/*}:generateAnswer`

### Path parameters

  * `model`

    `string`

    Required. The name of the `Model` to use for generating the grounded response.
    Format: `model=models/{model}`. It takes the form `models/{model}`.

### Request body

The request body contains data with the following structure:

#### Fields

  * `contents[]`

    `object (Content)`

    Required. The content of the current conversation with the `Model`. For single-turn queries, this is a single question to answer. For multi-turn queries, this is a repeated field that contains conversation history and the last `Content` in the list containing the question.
    Note: `models.generateAnswer` only supports queries in English.

  * `answerStyle`

    `enum (AnswerStyle)`

    Required. Style in which answers should be returned.

  * `safetySettings[]`

    `object (SafetySetting)`

    Optional. A list of unique `SafetySetting` instances for blocking unsafe content.
    This will be enforced on the `GenerateAnswerRequest.contents` and `GenerateAnswerResponse.candidate`. There should not be more than one setting for each `SafetyCategory` type. The API will block any contents and responses that fail to meet the thresholds set by these settings. This list overrides the default settings for each `SafetyCategory` specified in the safetySettings. If there is no `SafetySetting` for a given `SafetyCategory` provided in the list, the API will use the default safety setting for that category. Harm categories HARM\_CATEGORY\_HATE\_SPEECH, HARM\_CATEGORY\_SEXUALLY\_EXPLICIT, HARM\_CATEGORY\_DANGEROUS\_CONTENT, HARM\_CATEGORY\_HARASSMENT are supported. Refer to the [guide] for detailed information on available safety settings. Also refer to the [Safety guidance] to learn how to incorporate safety considerations in your AI applications.

  * `grounding_source`

    `Union type`

    The sources in which to ground the answer. `grounding_source` can be only one of the following:

      * `inlinePassages`

        `object (GroundingPassages)`

        Passages provided inline with the request.

      * `semanticRetriever`

        `object (SemanticRetrieverConfig)`

        Content retrieved from resources created via the Semantic Retriever API.

  * `temperature`

    `number`

    Optional. Controls the randomness of the output.
    Values can range from [0.0,1.0], inclusive. A value closer to 1.0 will produce responses that are more varied and creative, while a value closer to 0.0 will typically result in more straightforward responses from the model. A low temperature (\~0.2) is usually recommended for Attributed-Question-Answering use cases.

### Response body

Response from the model for a grounded answer.
If successful, the response body contains data with the following structure:

#### Fields

  * `answer`

    `object (Candidate)`

    Candidate answer from the model.
    Note: The model `always` attempts to provide a grounded answer, even when the answer is unlikely to be answerable from the given passages. In that case, a low-quality or ungrounded answer may be provided, along with a low `answerableProbability`.

  * `answerableProbability`

    `number`

    Output only. The model's estimate of the probability that its answer is correct and grounded in the input passages.
    A low `answerableProbability` indicates that the answer might not be grounded in the sources.
    When `answerableProbability` is low, you may want to:

      * Display a message to the effect of "We couldn’t answer that question" to the user.
      * Fall back to a general-purpose LLM that answers the question from world knowledge. The threshold and nature of such fallbacks will depend on individual use cases. `0.5` is a good starting threshold.

  * `inputFeedback`

    `object (InputFeedback)`

    Output only. Feedback related to the input data used to answer the question, as opposed to the model-generated response to the question.
    The input data can be one or more of the following:

      * Question specified by the last entry in `GenerateAnswerRequest.content`
      * Conversation history specified by the other entries in `GenerateAnswerRequest.content`
      * Grounding sources (`GenerateAnswerRequest.semantic_retriever` or `GenerateAnswerRequest.inline_passages`)

#### JSON representation

```json
{
  "answer": {
    object (Candidate)
  },
  "answerableProbability": number,
  "inputFeedback": {
    object (InputFeedback)
  }
}
```

## GroundingPassages

A repeated list of passages.

### Fields

  * `passages[]`

    `object (GroundingPassage)`

    List of passages.

### JSON representation

```json
{
  "passages": [
    {
      object (GroundingPassage)
    }
  ]
}
```

## GroundingPassage

Passage included inline with a grounding configuration.

### Fields

  * `id`

    `string`

    Identifier for the passage for attributing this passage in grounded answers.

  * `content`

    `object (Content)`

    Content of the passage.

### JSON representation

```json
{
  "id": string,
  "content": {
    object (Content)
  }
}
```

## SemanticRetrieverConfig

Configuration for retrieving grounding content from a `Corpus` or `Document` created using the Semantic Retriever API.

### Fields

  * `source`

    `string`

    Required. Name of the resource for retrieval. Example: `corpora/123` or `corpora/123/documents/abc`.

  * `query`

    `object (Content)`

    Required. Query to use for matching `Chunks` in the given resource by similarity.

  * `metadataFilters[]`

    `object (MetadataFilter)`

    Optional. Filters for selecting `Documents` and/or `Chunks` from the resource.

  * `maxChunksCount`

    `integer`

    Optional. Maximum number of relevant `Chunks` to retrieve.

  * `minimumRelevanceScore`

    `number`

    Optional. Minimum relevance score for retrieved relevant `Chunks`.

### JSON representation

```json
{
  "source": string,
  "query": {
    object (Content)
  },
  "metadataFilters": [
    {
      object (MetadataFilter)
    }
  ],
  "maxChunksCount": integer,
  "minimumRelevanceScore": number
}
```

## AnswerStyle

Style for grounded answers.

### Enums

  * `ANSWER_STYLE_UNSPECIFIED`
    Unspecified answer style.
  * `ABSTRACTIVE`
    Succinct but abstract style.
  * `EXTRACTIVE`
    Very brief and extractive style.
  * `VERBOSE`
    Verbose style including extra details. The response may be formatted as a sentence, paragraph, multiple paragraphs, or bullet points, etc.

## InputFeedback

Feedback related to the input data used to answer the question, as opposed to the model-generated response to the question.

### Fields

  * `safetyRatings[]`

    `object (SafetyRating)`

    Ratings for safety of the input. There is at most one rating per category.

  * `blockReason`

    `enum (BlockReason)`

    Optional. If set, the input was blocked and no candidates are returned. Rephrase the input.

### JSON representation

```json
{
  "safetyRatings": [
    {
      object (SafetyRating)
    }
  ],
  "blockReason": enum (BlockReason)
}
```

## BlockReason

Specifies what was the reason why input was blocked.

### Enums

  * `BLOCK_REASON_UNSPECIFIED`
    Default value. This value is unused.
  * `SAFETY`
    Input was blocked due to safety reasons. Inspect `safetyRatings` to understand which safety category blocked it.
  * `OTHER`
    Input was blocked due to other reasons.
