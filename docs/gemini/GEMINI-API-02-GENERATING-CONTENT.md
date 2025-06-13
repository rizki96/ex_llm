# Gemini API: Generating Content

The Gemini API supports content generation with images, audio, code, tools, and more. For details on each of these features, read on and check out the task-focused sample code, or read the comprehensive guides.

## Method: models.generateContent

Generates a model response given an input `GenerateContentRequest`. Refer to the text generation guide for detailed usage information. Input capabilities differ between models, including tuned models. Refer to the model guide and tuning guide for details.

### Endpoint

`post https://generativelanguage.googleapis.com/v1beta/{model=models/*}:generateContent`

### Path parameters

  * **model** (string): Required. The name of the Model to use for generating the completion. Format: `models/{model}`.

### Request body

The request body contains data with the following structure:

  * **contents[]** (object (Content)): Required. The content of the current conversation with the model. For single-turn queries, this is a single instance. For multi-turn queries like chat, this is a repeated field that contains the conversation history and the latest request.
  * **tools[]** (object (Tool)): Optional. A list of Tools the Model may use to generate the next response. A Tool is a piece of code that enables the system to interact with external systems to perform an action, or set of actions, outside of knowledge and scope of the Model. Supported Tools are Function and codeExecution. Refer to the Function calling and the Code execution guides to learn more.
  * **toolConfig** (object (ToolConfig)): Optional. Tool configuration for any Tool specified in the request. Refer to the Function calling guide for a usage example.
  * **safetySettings[]** (object (SafetySetting)): Optional. A list of unique SafetySetting instances for blocking unsafe content. This will be enforced on the `GenerateContentRequest.contents` and `GenerateContentResponse.candidates`. There should not be more than one setting for each SafetyCategory type. The API will block any contents and responses that fail to meet the thresholds set by these settings. This list overrides the default settings for each SafetyCategory specified in the safetySettings. If there is no SafetySetting for a given SafetyCategory provided in the list, the API will use the default safety setting for that category. Harm categories `HARM_CATEGORY_HATE_SPEECH`, `HARM_CATEGORY_SEXUALLY_EXPLICIT`, `HARM_CATEGORY_DANGEROUS_CONTENT`, `HARM_CATEGORY_HARASSMENT`, `HARM_CATEGORY_CIVIC_INTEGRITY` are supported. Refer to the guide for detailed information on available safety settings. Also refer to the Safety guidance to learn how to incorporate safety considerations in your AI applications.
  * **systemInstruction** (object (Content)): Optional. Developer set system instruction(s). Currently, text only.
  * **generationConfig** (object (GenerationConfig)): Optional. Configuration options for model generation and outputs.
  * **cachedContent** (string): Optional. The name of the content cached to use as context to serve the prediction. Format: `cachedContents/{cachedContent}`

### Example request

```shell
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$GEMINI_API_KEY" \
    -H 'Content-Type: application/json' \
    -X POST \
    -d '{
      "contents": [{
        "parts":[{"text": "Write a story about a magic backpack."}]
        }]
       }'
```

### Response body

If successful, the response body contains an instance of `GenerateContentResponse`.

## Method: models.streamGenerateContent

Generates a streamed response from the model given an input `GenerateContentRequest`.

### Endpoint

`post https://generativelanguage.googleapis.com/v1beta/{model=models/*}:streamGenerateContent`

### Path parameters

  * **model** (string): Required. The name of the Model to use for generating the completion. Format: `models/{model}`.

### Request body

The request body contains data with the following structure:

  * **contents[]** (object (Content)): Required. The content of the current conversation with the model. For single-turn queries, this is a single instance. For multi-turn queries like chat, this is a repeated field that contains the conversation history and the latest request.
  * **tools[]** (object (Tool)): Optional. A list of Tools the Model may use to generate the next response. A Tool is a piece of code that enables the system to interact with external systems to perform an action, or set of actions, outside of knowledge and scope of the Model. Supported Tools are Function and codeExecution. Refer to the Function calling and the Code execution guides to learn more.
  * **toolConfig** (object (ToolConfig)): Optional. Tool configuration for any Tool specified in the request. Refer to the Function calling guide for a usage example.
  * **safetySettings[]** (object (SafetySetting)): Optional. A list of unique SafetySetting instances for blocking unsafe content. This will be enforced on the `GenerateContentRequest.contents` and `GenerateContentResponse.candidates`. There should not be more than one setting for each SafetyCategory type. The API will block any contents and responses that fail to meet the thresholds set by these settings. This list overrides the default settings for each SafetyCategory specified in the safetySettings. If there is no SafetySetting for a given SafetyCategory provided in the list, the API will use the default safety setting for that category. Harm categories `HARM_CATEGORY_HATE_SPEECH`, `HARM_CATEGORY_SEXUALLY_EXPLICIT`, `HARM_CATEGORY_DANGEROUS_CONTENT`, `HARM_CATEGORY_HARASSMENT`, `HARM_CATEGORY_CIVIC_INTEGRITY` are supported. Refer to the guide for detailed information on available safety settings. Also refer to the Safety guidance to learn how to incorporate safety considerations in your AI applications.
  * **systemInstruction** (object (Content)): Optional. Developer set system instruction(s). Currently, text only.
  * **generationConfig** (object (GenerationConfig)): Optional. Configuration options for model generation and outputs.
  * **cachedContent** (string): Optional. The name of the content cached to use as context to serve the prediction. Format: `cachedContents/{cachedContent}`

### Example request

```shell
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent?alt=sse&key=${GEMINI_API_KEY}" \
        -H 'Content-Type: application/json' \
        --no-buffer \
        -d '{ "contents":[{"parts":[{"text": "Write a story about a magic backpack."}]}]}'
```

### Response body

If successful, the response body contains a stream of `GenerateContentResponse` instances.

## GenerateContentResponse

Response from the model supporting multiple candidate responses.

Safety ratings and content filtering are reported for both prompt in `GenerateContentResponse.prompt_feedback` and for each candidate in `finishReason` and in `safetyRatings`. The API: - Returns either all requested candidates or none of them - Returns no candidates at all only if there was something wrong with the prompt (check `promptFeedback`) - Reports feedback on each candidate in `finishReason` and `safetyRatings`.

  * **candidates[]** (object (Candidate)): Output only. Candidate responses from the model.
  * **promptFeedback** (object (PromptFeedback)): Returns the prompt's feedback related to the content filters.
  * **usageMetadata** (object (UsageMetadata)): Output only. Metadata on the generation requests' token usage.
  * **modelVersion** (string): Output only. The model version used to generate the response.

<!-- end list -->

```json
{
  "candidates": [
    {
      object (Candidate)
    }
  ],
  "promptFeedback": {
    object (PromptFeedback)
  },
  "usageMetadata": {
    object (UsageMetadata)
  },
  "modelVersion": string
}
```

## PromptFeedback

A set of the feedback metadata the prompt specified in `GenerateContentRequest.content`.

  * **blockReason** (enum (BlockReason)): Optional. If set, the prompt was blocked and no candidates are returned. Rephrase the prompt.
  * **safetyRatings[]** (object (SafetyRating)): Ratings for safety of the prompt. There is at most one rating per category.

<!-- end list -->

```json
{
  "blockReason": enum (BlockReason),
  "safetyRatings": [
    {
      object (SafetyRating)
    }
  ]
}
```

## BlockReason

Specifies the reason why the prompt was blocked.

>   * **BLOCK\_REASON\_UNSPECIFIED**: Default value. This value is unused.
>   * **SAFETY**: Prompt was blocked due to safety reasons. Inspect `safetyRatings` to understand which safety category blocked it.
>   * **OTHER**: Prompt was blocked due to unknown reasons.
>   * **BLOCKLIST**: Prompt was blocked due to the terms which are included from the terminology blocklist.
>   * **PROHIBITED\_CONTENT**: Prompt was blocked due to prohibited content.
>   * **IMAGE\_SAFETY**: Candidates blocked due to unsafe image generation content.

## UsageMetadata

Metadata on the generation request's token usage.

  * **promptTokenCount** (integer): Number of tokens in the prompt. When `cachedContent` is set, this is still the total effective prompt size meaning this includes the number of tokens in the cached content.
  * **cachedContentTokenCount** (integer): Number of tokens in the cached part of the prompt (the cached content).
  * **candidatesTokenCount** (integer): Total number of tokens across all the generated response candidates.
  * **toolUsePromptTokenCount** (integer): Output only. Number of tokens present in tool-use prompt(s).
  * **thoughtsTokenCount** (integer): Output only. Number of tokens of thoughts for thinking models.
  * **totalTokenCount** (integer): Total token count for the generation request (prompt + response candidates).
  * **promptTokensDetails[]** (object (ModalityTokenCount)): Output only. List of modalities that were processed in the request input.
  * **cacheTokensDetails[]** (object (ModalityTokenCount)): Output only. List of modalities of the cached content in the request input.
  * **candidatesTokensDetails[]** (object (ModalityTokenCount)): Output only. List of modalities that were returned in the response.
  * **toolUsePromptTokensDetails[]** (object (ModalityTokenCount)): Output only. List of modalities that were processed for tool-use request inputs.

<!-- end list -->

```json
{
  "promptTokenCount": integer,
  "cachedContentTokenCount": integer,
  "candidatesTokenCount": integer,
  "toolUsePromptTokenCount": integer,
  "thoughtsTokenCount": integer,
  "totalTokenCount": integer,
  "promptTokensDetails": [
    {
      object (ModalityTokenCount)
    }
  ],
  "cacheTokensDetails": [
    {
      object (ModalityTokenCount)
    }
  ],
  "candidatesTokensDetails": [
    {
      object (ModalityTokenCount)
    }
  ],
  "toolUsePromptTokensDetails": [
    {
      object (ModalityTokenCount)
    }
  ]
}
```

## Candidate

A response candidate generated from the model.

  * **content** (object (Content)): Output only. Generated content returned from the model.
  * **finishReason** (enum (FinishReason)): Optional. Output only. The reason why the model stopped generating tokens. If empty, the model has not stopped generating tokens.
  * **safetyRatings[]** (object (SafetyRating)): List of ratings for the safety of a response candidate. There is at most one rating per category.
  * **citationMetadata** (object (CitationMetadata)): Output only. Citation information for model-generated candidate. This field may be populated with recitation information for any text included in the content. These are passages that are "recited" from copyrighted material in the foundational LLM's training data.
  * **tokenCount** (integer): Output only. Token count for this candidate.
  * **groundingAttributions[]** (object (GroundingAttribution)): Output only. Attribution information for sources that contributed to a grounded answer. This field is populated for `GenerateAnswer` calls.
  * **groundingMetadata** (object (GroundingMetadata)): Output only. Grounding metadata for the candidate. This field is populated for `GenerateContent` calls.
  * **avgLogprobs** (number): Output only. Average log probability score of the candidate.
  * **logprobsResult** (object (LogprobsResult)): Output only. Log-likelihood scores for the response tokens and top tokens.
  * **urlRetrievalMetadata** (object (UrlRetrievalMetadata)): Output only. Metadata related to url context retrieval tool.
  * **index** (integer): Output only. Index of the candidate in the list of response candidates.

<!-- end list -->

```json
{
  "content": {
    object (Content)
  },
  "finishReason": enum (FinishReason),
  "safetyRatings": [
    {
      object (SafetyRating)
    }
  ],
  "citationMetadata": {
    object (CitationMetadata)
  },
  "tokenCount": integer,
  "groundingAttributions": [
    {
      object (GroundingAttribution)
    }
  ],
  "groundingMetadata": {
    object (GroundingMetadata)
  },
  "avgLogprobs": number,
  "logprobsResult": {
    object (LogprobsResult)
  },
  "urlRetrievalMetadata": {
    object (UrlRetrievalMetadata)
  },
  "index": integer
}
```

## FinishReason

Defines the reason why the model stopped generating tokens.

>   * **FINISH\_REASON\_UNSPECIFIED**: Default value. This value is unused.
>   * **STOP**: Natural stop point of the model or provided stop sequence.
>   * **MAX\_TOKENS**: The maximum number of tokens as specified in the request was reached.
>   * **SAFETY**: The response candidate content was flagged for safety reasons.
>   * **RECITATION**: The response candidate content was flagged for recitation reasons.
>   * **LANGUAGE**: The response candidate content was flagged for using an unsupported language.
>   * **OTHER**: Unknown reason.
>   * **BLOCKLIST**: Token generation stopped because the content contains forbidden terms.
>   * **PROHIBITED\_CONTENT**: Token generation stopped for potentially containing prohibited content.
>   * **SPII**: Token generation stopped because the content potentially contains Sensitive Personally Identifiable Information (SPII).
>   * **MALFORMED\_FUNCTION\_CALL**: The function call generated by the model is invalid.
>   * **IMAGE\_SAFETY**: Token generation stopped because generated images contain safety violations.

## GroundingAttribution

Attribution for a source that contributed to an answer.

  * **sourceId** (object (AttributionSourceId)): Output only. Identifier for the source contributing to this attribution.
  * **content** (object (Content)): Grounding source content that makes up this attribution.

<!-- end list -->

```json
{
  "sourceId": {
    object (AttributionSourceId)
  },
  "content": {
    object (Content)
  }
}
```

## AttributionSourceId

Identifier for the source contributing to this attribution.

> **source** (Union type): `source` can be only one of the following:
>
>   * **groundingPassage** (object (GroundingPassageId)): Identifier for an inline passage.
>   * **semanticRetrieverChunk** (object (SemanticRetrieverChunk)): Identifier for a Chunk fetched via Semantic Retriever.

```json
{
  // source
  "groundingPassage": {
    object (GroundingPassageId)
  },
  "semanticRetrieverChunk": {
    object (SemanticRetrieverChunk)
  }
  // Union type
}
```

## GroundingPassageId

Identifier for a part within a `GroundingPassage`.

  * **passageId** (string): Output only. ID of the passage matching the `GenerateAnswerRequest's` `GroundingPassage.id`.
  * **partIndex** (integer): Output only. Index of the part within the `GenerateAnswerRequest's` `GroundingPassage.content`.

<!-- end list -->

```json
{
  "passageId": string,
  "partIndex": integer
}
```

## SemanticRetrieverChunk

Identifier for a Chunk retrieved via Semantic Retriever specified in the `GenerateAnswerRequest` using `SemanticRetrieverConfig`.

  * **source** (string): Output only. Name of the source matching the request's `SemanticRetrieverConfig.source`. Example: `corpora/123` or `corpora/123/documents/abc`.
  * **chunk** (string): Output only. Name of the Chunk containing the attributed text. Example: `corpora/123/documents/abc/chunks/xyz`.

<!-- end list -->

```json
{
  "source": string,
  "chunk": string
}
```

## GroundingMetadata

Metadata returned to client when grounding is enabled.

  * **groundingChunks[]** (object (GroundingChunk)): List of supporting references retrieved from specified grounding source.
  * **groundingSupports[]** (object (GroundingSupport)): List of grounding support.
  * **webSearchQueries[]** (string): Web search queries for the following-up web search.
  * **searchEntryPoint** (object (SearchEntryPoint)): Optional. Google search entry for the following-up web searches.
  * **retrievalMetadata** (object (RetrievalMetadata)): Metadata related to retrieval in the grounding flow.

<!-- end list -->

```json
{
  "groundingChunks": [
    {
      object (GroundingChunk)
    }
  ],
  "groundingSupports": [
    {
      object (GroundingSupport)
    }
  ],
  "webSearchQueries": [
    string
  ],
  "searchEntryPoint": {
    object (SearchEntryPoint)
  },
  "retrievalMetadata": {
    object (RetrievalMetadata)
  }
}
```

## SearchEntryPoint

Google search entry point.

  * **renderedContent** (string): Optional. Web content snippet that can be embedded in a web page or an app webview.
  * **sdkBlob** (string (bytes format)): Optional. Base64 encoded JSON representing array of \<search term, search url\> tuple. A base64-encoded string.

<!-- end list -->

```json
{
  "renderedContent": string,
  "sdkBlob": string
}
```

## GroundingChunk

Grounding chunk.

> **chunk\_type** (Union type): Chunk type. `chunk_type` can be only one of the following:
>
>   * **web** (object (Web)): Grounding chunk from the web.

```json
{
  // chunk_type
  "web": {
    object (Web)
  }
  // Union type
}
```

## Web

Chunk from the web.

  * **uri** (string): URI reference of the chunk.
  * **title** (string): Title of the chunk.

<!-- end list -->

```json
{
  "uri": string,
  "title": string
}
```

## GroundingSupport

Grounding support.

  * **groundingChunkIndices[]** (integer): A list of indices (into 'grounding\_chunk') specifying the citations associated with the claim. For instance [1,3,4] means that grounding\_chunk[1], grounding\_chunk[3], grounding\_chunk[4] are the retrieved content attributed to the claim.
  * **confidenceScores[]** (number): Confidence score of the support references. Ranges from 0 to 1. 1 is the most confident. This list must have the same size as the groundingChunkIndices.
  * **segment** (object (Segment)): Segment of the content this support belongs to.

<!-- end list -->

```json
{
  "groundingChunkIndices": [
    integer
  ],
  "confidenceScores": [
    number
  ],
  "segment": {
    object (Segment)
  }
}
```

## Segment

Segment of the content.

  * **partIndex** (integer): Output only. The index of a Part object within its parent Content object.
  * **startIndex** (integer): Output only. Start index in the given Part, measured in bytes. Offset from the start of the Part, inclusive, starting at zero.
  * **endIndex** (integer): Output only. End index in the given Part, measured in bytes. Offset from the start of the Part, exclusive, starting at zero.
  * **text** (string): Output only. The text corresponding to the segment from the response.

<!-- end list -->

```json
{
  "partIndex": integer,
  "startIndex": integer,
  "endIndex": integer,
  "text": string
}
```

## RetrievalMetadata

Metadata related to retrieval in the grounding flow.

  * **googleSearchDynamicRetrievalScore** (number): Optional. Score indicating how likely information from google search could help answer the prompt. The score is in the range [0, 1], where 0 is the least likely and 1 is the most likely. This score is only populated when google search grounding and dynamic retrieval is enabled. It will be compared to the threshold to determine whether to trigger google search.

<!-- end list -->

```json
{
  "googleSearchDynamicRetrievalScore": number
}
```

## LogprobsResult

Logprobs Result

  * **topCandidates[]** (object (TopCandidates)): Length = total number of decoding steps.
  * **chosenCandidates[]** (object (Candidate)): Length = total number of decoding steps. The chosen candidates may or may not be in topCandidates.

<!-- end list -->

```json
{
  "topCandidates": [
    {
      object (TopCandidates)
    }
  ],
  "chosenCandidates": [
    {
      object (Candidate)
    }
  ]
}
```

## TopCandidates

Candidates with top log probabilities at each decoding step.

  * **candidates[]** (object (Candidate)): Sorted by log probability in descending order.

<!-- end list -->

```json
{
  "candidates": [
    {
      object (Candidate)
    }
  ]
}
```

## Candidate (for Logprobs)

Candidate for the logprobs token and score. (Note: This appears to be a nested object definition within `LogprobsResult` and `TopCandidates`).

  * **token** (string): The candidate’s token string value.
  * **tokenId** (integer): The candidate’s token id value.
  * **logProbability** (number): The candidate's log probability.

<!-- end list -->

```json
{
  "token": string,
  "tokenId": integer,
  "logProbability": number
}
```

## UrlRetrievalMetadata

Metadata related to url context retrieval tool.

  * **urlRetrievalContexts[]** (object (UrlRetrievalContext)): List of url retrieval contexts.

<!-- end list -->

```json
{
  "urlRetrievalContexts": [
    {
      object (UrlRetrievalContext)
    }
  ]
}
```

## UrlRetrievalContext

Context of the a single url retrieval.

  * **retrievedUrl** (string): Retrieved url by the tool.

<!-- end list -->

```json
{
  "retrievedUrl": string
}
```

## CitationMetadata

A collection of source attributions for a piece of content.

  * **citationSources[]** (object (CitationSource)): Citations to sources for a specific response.

<!-- end list -->

```json
{
  "citationSources": [
    {
      object (CitationSource)
    }
  ]
}
```

## CitationSource

A citation to a source for a portion of a specific response.

  * **startIndex** (integer): Optional. Start of segment of the response that is attributed to this source. Index indicates the start of the segment, measured in bytes.
  * **endIndex** (integer): Optional. End of the attributed segment, exclusive.
  * **uri** (string): Optional. URI that is attributed as a source for a portion of the text.
  * **license** (string): Optional. License for the GitHub project that is attributed as a source for segment. License info is required for code citations.

<!-- end list -->

```json
{
  "startIndex": integer,
  "endIndex": integer,
  "uri": string,
  "license": string
}
```

## GenerationConfig

Configuration options for model generation and outputs. Not all parameters are configurable for every model.

  * **stopSequences[]** (string): Optional. The set of character sequences (up to 5) that will stop output generation. If specified, the API will stop at the first appearance of a stop\_sequence. The stop sequence will not be included as part of the response.
  * **responseMimeType** (string): Optional. MIME type of the generated candidate text. Supported MIME types are: `text/plain`: (default) Text output. `application/json`: JSON response in the response candidates. `text/x.enum`: ENUM as a string response in the response candidates. Refer to the docs for a list of all supported text MIME types.
  * **responseSchema** (object (Schema)): Optional. Output schema of the generated candidate text. Schemas must be a subset of the OpenAPI schema and can be objects, primitives or arrays. If set, a compatible responseMimeType must also be set. Compatible MIME types: `application/json`: Schema for JSON response. Refer to the JSON text generation guide for more details.
  * **responseModalities[]** (enum (Modality)): Optional. The requested modalities of the response. Represents the set of modalities that the model can return, and should be expected in the response. This is an exact match to the modalities of the response. A model may have multiple combinations of supported modalities. If the requested modalities do not match any of the supported combinations, an error will be returned. An empty list is equivalent to requesting only text.
  * **candidateCount** (integer): Optional. Number of generated responses to return. If unset, this will default to 1. Please note that this doesn't work for previous generation models (Gemini 1.0 family).
  * **maxOutputTokens** (integer): Optional. The maximum number of tokens to include in a response candidate. Note: The default value varies by model, see the `Model.output_token_limit` attribute of the Model returned from the `getModel` function.
  * **temperature** (number): Optional. Controls the randomness of the output. Note: The default value varies by model, see the `Model.temperature` attribute of the Model returned from the `getModel` function. Values can range from [0.0, 2.0].
  * **topP** (number): Optional. The maximum cumulative probability of tokens to consider when sampling. The model uses combined Top-k and Top-p (nucleus) sampling. Tokens are sorted based on their assigned probabilities so that only the most likely tokens are considered. Top-k sampling directly limits the maximum number of tokens to consider, while Nucleus sampling limits the number of tokens based on the cumulative probability. Note: The default value varies by Model and is specified by the `Model.top_p` attribute returned from the `getModel` function. An empty `topK` attribute indicates that the model doesn't apply top-k sampling and doesn't allow setting `topK` on requests.
  * **topK** (integer): Optional. The maximum number of tokens to consider when sampling. Gemini models use Top-p (nucleus) sampling or a combination of Top-k and nucleus sampling. Top-k sampling considers the set of topK most probable tokens. Models running with nucleus sampling don't allow topK setting. Note: The default value varies by Model and is specified by the `Model.top_p` attribute returned from the `getModel` function. An empty `topK` attribute indicates that the model doesn't apply top-k sampling and doesn't allow setting `topK` on requests.
  * **seed** (integer): Optional. Seed used in decoding. If not set, the request uses a randomly generated seed.
  * **presencePenalty** (number): Optional. Presence penalty applied to the next token's logprobs if the token has already been seen in the response. This penalty is binary on/off and not dependant on the number of times the token is used (after the first). Use `frequencyPenalty` for a penalty that increases with each use. A positive penalty will discourage the use of tokens that have already been used in the response, increasing the vocabulary. A negative penalty will encourage the use of tokens that have already been used in the response, decreasing the vocabulary.
  * **frequencyPenalty** (number): Optional. Frequency penalty applied to the next token's logprobs, multiplied by the number of times each token has been seen in the response so far. A positive penalty will discourage the use of tokens that have already been used, proportional to the number of times the token has been used: The more a token is used, the more difficult it is for the model to use that token again increasing the vocabulary of responses. Caution: A negative penalty will encourage the model to reuse tokens proportional to the number of times the token has been used. Small negative values will reduce the vocabulary of a response. Larger negative values will cause the model to start repeating a common token until it hits the `maxOutputTokens` limit.
  * **responseLogprobs** (boolean): Optional. If true, export the logprobs results in response.
  * **logprobs** (integer): Optional. Only valid if `responseLogprobs=True`. This sets the number of top logprobs to return at each decoding step in the `Candidate.logprobs_result`.
  * **enableEnhancedCivicAnswers** (boolean): Optional. Enables enhanced civic answers. It may not be available for all models.
  * **speechConfig** (object (SpeechConfig)): Optional. The speech generation config.
  * **thinkingConfig** (object (ThinkingConfig)): Optional. Config for thinking features. An error will be returned if this field is set for models that don't support thinking.
  * **mediaResolution** (enum (MediaResolution)): Optional. If specified, the media resolution specified will be used.

<!-- end list -->

```json
{
  "stopSequences": [
    string
  ],
  "responseMimeType": string,
  "responseSchema": {
    object (Schema)
  },
  "responseModalities": [
    enum (Modality)
  ],
  "candidateCount": integer,
  "maxOutputTokens": integer,
  "temperature": number,
  "topP": number,
  "topK": integer,
  "seed": integer,
  "presencePenalty": number,
  "frequencyPenalty": number,
  "responseLogprobs": boolean,
  "logprobs": integer,
  "enableEnhancedCivicAnswers": boolean,
  "speechConfig": {
    object (SpeechConfig)
  },
  "thinkingConfig": {
    object (ThinkingConfig)
  },
  "mediaResolution": enum (MediaResolution)
}
```

## Modality (for GenerationConfig)

Supported modalities of the response.

>   * **MODALITY\_UNSPECIFIED**: Default value.
>   * **TEXT**: Indicates the model should return text.
>   * **IMAGE**: Indicates the model should return images.
>   * **AUDIO**: Indicates the model should return audio.

## SpeechConfig

The speech generation config.

  * **voiceConfig** (object (VoiceConfig)): The configuration in case of single-voice output.
  * **languageCode** (string): Optional. Language code (in BCP 47 format, e.g. "en-US") for speech synthesis. Valid values are: de-DE, en-AU, en-GB, en-IN, en-US, es-US, fr-FR, hi-IN, pt-BR, ar-XA, es-ES, fr-CA, id-ID, it-IT, ja-JP, tr-TR, vi-VN, bn-IN, gu-IN, kn-IN, ml-IN, mr-IN, ta-IN, te-IN, nl-NL, ko-KR, cmn-CN, pl-PL, ru-RU, and th-TH.

<!-- end list -->

```json
{
  "voiceConfig": {
    object (VoiceConfig)
  },
  "languageCode": string
}
```

## VoiceConfig

The configuration for the voice to use.

> **voice\_config** (Union type): The configuration for the speaker to use. `voice_config` can be only one of the following:
>
>   * **prebuiltVoiceConfig** (object (PrebuiltVoiceConfig)): The configuration for the prebuilt voice to use.

```json
{
  // voice_config
  "prebuiltVoiceConfig": {
    object (PrebuiltVoiceConfig)
  }
  // Union type
}
```

## PrebuiltVoiceConfig

The configuration for the prebuilt speaker to use.

  * **voiceName** (string): The name of the preset voice to use.

<!-- end list -->

```json
{
  "voiceName": string
}
```

## ThinkingConfig

Config for thinking features.

  * **includeThoughts** (boolean): Indicates whether to include thoughts in the response. If true, thoughts are returned only when available.
  * **thinkingBudget** (integer): The number of thoughts tokens that the model should generate.

<!-- end list -->

```json
{
  "includeThoughts": boolean,
  "thinkingBudget": integer
}
```

## MediaResolution

Media resolution for the input media.

>   * **MEDIA\_RESOLUTION\_UNSPECIFIED**: Media resolution has not been set.
>   * **MEDIA\_RESOLUTION\_LOW**: Media resolution set to low (64 tokens).
>   * **MEDIA\_RESOLUTION\_MEDIUM**: Media resolution set to medium (256 tokens).
>   * **MEDIA\_RESOLUTION\_HIGH**: Media resolution set to high (zoomed reframing with 256 tokens).

## HarmCategory

The category of a rating. These categories cover various kinds of harms that developers may wish to adjust.

>   * **HARM\_CATEGORY\_UNSPECIFIED**: Category is unspecified.
>   * **HARM\_CATEGORY\_DEROGATORY**: PaLM - Negative or harmful comments targeting identity and/or protected attribute.
>   * **HARM\_CATEGORY\_TOXICITY**: PaLM - Content that is rude, disrespectful, or profane.
>   * **HARM\_CATEGORY\_VIOLENCE**: PaLM - Describes scenarios depicting violence against an individual or group, or general descriptions of gore.
>   * **HARM\_CATEGORY\_SEXUAL**: PaLM - Contains references to sexual acts or other lewd content.
>   * **HARM\_CATEGORY\_MEDICAL**: PaLM - Promotes unchecked medical advice.
>   * **HARM\_CATEGORY\_DANGEROUS**: PaLM - Dangerous content that promotes, facilitates, or encourages harmful acts.
>   * **HARM\_CATEGORY\_HARASSMENT**: Gemini - Harassment content.
>   * **HARM\_CATEGORY\_HATE\_SPEECH**: Gemini - Hate speech and content.
>   * **HARM\_CATEGORY\_SEXUALLY\_EXPLICIT**: Gemini - Sexually explicit content.
>   * **HARM\_CATEGORY\_DANGEROUS\_CONTENT**: Gemini - Dangerous content.
>   * **HARM\_CATEGORY\_CIVIC\_INTEGRITY**: Gemini - Content that may be used to harm civic integrity.

## ModalityTokenCount

Represents token counting info for a single modality.

  * **modality** (enum (Modality)): The modality associated with this token count.
  * **tokenCount** (integer): Number of tokens.

<!-- end list -->

```json
{
  "modality": enum (Modality),
  "tokenCount": integer
}
```

## Modality (for Content Part)

Content Part modality

>   * **MODALITY\_UNSPECIFIED**: Unspecified modality.
>   * **TEXT**: Plain text.
>   * **IMAGE**: Image.
>   * **VIDEO**: Video.
>   * **AUDIO**: Audio.
>   * **DOCUMENT**: Document, e.g. PDF.

## SafetyRating

Safety rating for a piece of content. The safety rating contains the category of harm and the harm probability level in that category for a piece of content. Content is classified for safety across a number of harm categories and the probability of the harm classification is included here.

  * **category** (enum (HarmCategory)): Required. The category for this rating.
  * **probability** (enum (HarmProbability)): Required. The probability of harm for this content.
  * **blocked** (boolean): Was this content blocked because of this rating?

<!-- end list -->

```json
{
  "category": enum (HarmCategory),
  "probability": enum (HarmProbability),
  "blocked": boolean
}
```

## HarmProbability

The probability that a piece of content is harmful. The classification system gives the probability of the content being unsafe. This does not indicate the severity of harm for a piece of content.

>   * **HARM\_PROBABILITY\_UNSPECIFIED**: Probability is unspecified.
>   * **NEGLIGIBLE**: Content has a negligible chance of being unsafe.
>   * **LOW**: Content has a low chance of being unsafe.
>   * **MEDIUM**: Content has a medium chance of being unsafe.
>   * **HIGH**: Content has a high chance of being unsafe.

## SafetySetting

Safety setting, affecting the safety-blocking behavior. Passing a safety setting for a category changes the allowed probability that content is blocked.

  * **category** (enum (HarmCategory)): Required. The category for this setting.
  * **threshold** (enum (HarmBlockThreshold)): Required. Controls the probability threshold at which harm is blocked.

<!-- end list -->

```json
{
  "category": enum (HarmCategory),
  "threshold": enum (HarmBlockThreshold)
}
```

## HarmBlockThreshold

Block at and beyond a specified harm probability.

>   * **HARM\_BLOCK\_THRESHOLD\_UNSPECIFIED**: Threshold is unspecified.
>   * **BLOCK\_LOW\_AND\_ABOVE**: Content with NEGLIGIBLE will be allowed.
>   * **BLOCK\_MEDIUM\_AND\_ABOVE**: Content with NEGLIGIBLE and LOW will be allowed.
>   * **BLOCK\_ONLY\_HIGH**: Content with NEGLIGIBLE, LOW, and MEDIUM will be allowed.
>   * **BLOCK\_NONE**: All content will be allowed.
>   * **OFF**: Turn off the safety filter.
