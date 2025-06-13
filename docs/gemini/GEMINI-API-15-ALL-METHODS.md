# All methods

## Generative Language API

The Gemini API allows developers to build generative AI applications using Gemini models. Gemini is our most capable model, built from the ground up to be multimodal. It can generalize and seamlessly understand, operate across, and combine different types of information including language, images, audio, video, and code. You can use the Gemini API for use cases like reasoning across text and images, content generation, dialogue agents, summarization and classification systems, and more.

## Service: generativelanguage.googleapis.com

To call this service, we recommend that you use the Google-provided client libraries. If your application needs to use your own libraries to call this service, use the following information when you make the API requests.

### Service endpoint

A service endpoint is a base URL that specifies the network address of an API service. One service might have multiple service endpoints. This service has the following service endpoint and all URIs below are relative to this service endpoint:

`https://generativelanguage.googleapis.com`

## REST Resource: v1beta.cachedContents

* **create**: `POST /v1beta/cachedContents` - Creates CachedContent resource.
* **delete**: `DELETE /v1beta/{name=cachedContents/*}` - Deletes CachedContent resource.
* **get**: `GET /v1beta/{name=cachedContents/*}` - Reads CachedContent resource.
* **list**: `GET /v1beta/cachedContents` - Lists CachedContents.
* **patch**: `PATCH /v1beta/{cachedContent.name=cachedContents/*}` - Updates CachedContent resource (only expiration is updatable).

## REST Resource: v1beta.corpora

* **create**: `POST /v1beta/corpora` - Creates an empty Corpus.
* **delete**: `DELETE /v1beta/{name=corpora/*}` - Deletes a Corpus.
* **get**: `GET /v1beta/{name=corpora/*}` - Gets information about a specific Corpus.
* **list**: `GET /v1beta/corpora` - Lists all Corpora owned by the user.
* **patch**: `PATCH /v1beta/{corpus.name=corpora/*}` - Updates a Corpus.
* **query**: `POST /v1beta/{name=corpora/*}:query` - Performs semantic search over a Corpus.

## REST Resource: v1beta.corpora.documents

* **create**: `POST /v1beta/{parent=corpora/*}/documents` - Creates an empty Document.
* **delete**: `DELETE /v1beta/{name=corpora/*/documents/*}` - Deletes a Document.
* **get**: `GET /v1beta/{name=corpora/*/documents/*}` - Gets information about a specific Document.
* **list**: `GET /v1beta/{parent=corpora/*}/documents` - Lists all Documents in a Corpus.
* **patch**: `PATCH /v1beta/{document.name=corpora/*/documents/*}` - Updates a Document.
* **query**: `POST /v1beta/{name=corpora/*/documents/*}:query` - Performs semantic search over a Document.

## REST Resource: v1beta.corpora.documents.chunks

* **batchCreate**: `POST /v1beta/{parent=corpora/*/documents/*}/chunks:batchCreate` - Batch create Chunks.
* **batchDelete**: `POST /v1beta/{parent=corpora/*/documents/*}/chunks:batchDelete` - Batch delete Chunks.
* **batchUpdate**: `POST /v1beta/{parent=corpora/*/documents/*}/chunks:batchUpdate` - Batch update Chunks.
* **create**: `POST /v1beta/{parent=corpora/*/documents/*}/chunks` - Creates a Chunk.
* **delete**: `DELETE /v1beta/{name=corpora/*/documents/*/chunks/*}` - Deletes a Chunk.
* **get**: `GET /v1beta/{name=corpora/*/documents/*/chunks/*}` - Gets information about a specific Chunk.
* **list**: `GET /v1beta/{parent=corpora/*/documents/*}/chunks` - Lists all Chunks in a Document.
* **patch**: `PATCH /v1beta/{chunk.name=corpora/*/documents/*/chunks/*}` - Updates a Chunk.

## REST Resource: v1beta.corpora.permissions

* **create**: `POST /v1beta/{parent=corpora/*}/permissions` - Create a permission to a specific resource.
* **delete**: `DELETE /v1beta/{name=corpora/*/permissions/*}` - Deletes the permission.
* **get**: `GET /v1beta/{name=corpora/*/permissions/*}` - Gets information about a specific Permission.
* **list**: `GET /v1beta/{parent=corpora/*}/permissions` - Lists permissions for the specific resource.
* **patch**: `PATCH /v1beta/{permission.name=corpora/*/permissions/*}` - Updates the permission.

## REST Resource: v1beta.files

* **delete**: `DELETE /v1beta/{name=files/*}` - Deletes the File.
* **get**: `GET /v1beta/{name=files/*}` - Gets the metadata for the given File.
* **list**: `GET /v1beta/files` - Lists the metadata for Files owned by the requesting project.

## REST Resource: v1beta.media

* **upload**: `POST /v1beta/files` | `POST /upload/v1beta/files` - Creates a File.

## REST Resource: v1beta.models

* **batchEmbedContents**: `POST /v1beta/{model=models/*}:batchEmbedContents` - Generates multiple embedding vectors from the input Content which consists of a batch of strings represented as EmbedContentRequest objects.
* **batchEmbedText**: `POST /v1beta/{model=models/*}:batchEmbedText` - Generates multiple embeddings from the model given input text in a synchronous call.
* **countMessageTokens**: `POST /v1beta/{model=models/*}:countMessageTokens` - Runs a model's tokenizer on a string and returns the token count.
* **countTextTokens**: `POST /v1beta/{model=models/*}:countTextTokens` - Runs a model's tokenizer on a text and returns the token count.
* **countTokens**: `POST /v1beta/{model=models/*}:countTokens` - Runs a model's tokenizer on input Content and returns the token count.
* **embedContent**: `POST /v1beta/{model=models/*}:embedContent` - Generates a text embedding vector from the input Content using the specified Gemini Embedding model.
* **embedText**: `POST /v1beta/{model=models/*}:embedText` - Generates an embedding from the model given an input message.
* **generateAnswer**: `POST /v1beta/{model=models/*}:generateAnswer` - Generates a grounded answer from the model given an input GenerateAnswerRequest.
* **generateContent**: `POST /v1beta/{model=models/*}:generateContent` - Generates a model response given an input GenerateContentRequest.
* **generateMessage**: `POST /v1beta/{model=models/*}:generateMessage` - Generates a response from the model given an input MessagePrompt.
* **generateText**: `POST /v1beta/{model=models/*}:generateText` - Generates a response from the model given an input message.
* **get**: `GET /v1beta/{name=models/*}` - Gets information about a specific Model such as its version number, token limits, parameters and other metadata.
* **list**: `GET /v1beta/models` - Lists the Models available through the Gemini API.
* **streamGenerateContent**: `POST /v1beta/{model=models/*}:streamGenerateContent` - Generates a streamed response from the model given an input GenerateContentRequest.

## REST Resource: v1beta.tunedModels

* **create**: `POST /v1beta/tunedModels` - Creates a tuned model.
* **delete**: `DELETE /v1beta/{name=tunedModels/*}` - Deletes a tuned model.
* **generateContent**: `POST /v1beta/{model=tunedModels/*}:generateContent` - Generates a model response given an input GenerateContentRequest.
* **generateText**: `POST /v1beta/{model=tunedModels/*}:generateText` - Generates a response from the model given an input message.
* **get**: `GET /v1beta/{name=tunedModels/*}` - Gets information about a specific TunedModel.
* **list**: `GET /v1beta/tunedModels` - Lists created tuned models.
* **patch**: `PATCH /v1beta/{tunedModel.name=tunedModels/*}` - Updates a tuned model.
* **streamGenerateContent**: `POST /v1beta/{model=tunedModels/*}:streamGenerateContent` - Generates a streamed response from the model given an input GenerateContentRequest.
* **transferOwnership**: `POST /v1beta/{name=tunedModels/*}:transferOwnership` - Transfers ownership of the tuned model.

## REST Resource: v1beta.tunedModels.permissions

* **create**: `POST /v1beta/{parent=tunedModels/*}/permissions` - Create a permission to a specific resource.
* **delete**: `DELETE /v1beta/{name=tunedModels/*/permissions/*}` - Deletes the permission.
* **get**: `GET /v1beta/{name=tunedModels/*/permissions/*}` - Gets information about a specific Permission.
* **list**: `GET /v1beta/{parent=tunedModels/*}/permissions` - Lists permissions for the specific resource.
* **patch**: `PATCH /v1beta/{permission.name=tunedModels/*/permissions/*}` - Updates the permission.
