# Context caching

In a typical AI workflow, you might pass the same input tokens over and over to a model. The Gemini API offers two different caching mechanisms:

* Implicit caching (automatic, no cost saving guarantee)
* Explicit caching (manual, cost saving guarantee)

Implicit caching is enabled on Gemini 2.5 models by default. If a request contains content that is a cache hit, we automatically pass the cost savings back to you.

Explicit caching is useful in cases where you want to guarantee cost savings, but with some added developer work.

## Implicit caching

Implicit caching is enabled by default for all Gemini 2.5 models. We automatically pass on cost savings if your request hits caches. There is nothing you need to do in order to enable this. It is effective as of May 8th, 2025. The minimum input token count for context caching is 1,024 for 2.5 Flash and 2,048 for 2.5 Pro.

To increase the chance of an implicit cache hit:

* Try putting large and common contents at the beginning of your prompt
* Try to send requests with similar prefix in a short amount of time

You can see the number of tokens which were cache hits in the response object's `usage_metadata` field.

## Explicit caching

Using the Gemini API explicit caching feature, you can pass some content to the model once, cache the input tokens, and then refer to the cached tokens for subsequent requests. At certain volumes, using cached tokens is lower cost than passing in the same corpus of tokens repeatedly.

When you cache a set of tokens, you can choose how long you want the cache to exist before the tokens are automatically deleted. This caching duration is called the **time to live** (TTL). If not set, the TTL defaults to 1 hour. The cost for caching depends on the input token size and how long you want the tokens to persist.

This section assumes that you've installed a Gemini SDK (or have curl installed) and that you've configured an API key, as shown in the [quickstart].

### Generate content using a cache

The following example shows how to create a cache and then use it to generate content.

(Examples for Videos and PDFs are mentioned but not provided in text, omitting)

(Shell code example for creating cache and generating content is present in the original text and is omitted here for brevity as per instructions)

### List caches

It's not possible to retrieve or view cached content, but you can retrieve cache metadata (`name`, `model`, `displayName`, `usageMetadata`, `createTime`, `updateTime`, and `expireTime`).

(Shell code example for listing caches is present in the original text and is omitted here for brevity as per instructions)

### Update a cache

You can set a new `ttl` or `expireTime` for a cache. Changing anything else about the cache isn't supported.
The following example shows how to update the `ttl` of a cache.

(Shell code example for updating a cache is present in the original text and is omitted here for brevity as per instructions)

### Delete a cache

The caching service provides a delete operation for manually removing content from the cache. The following example shows how to delete a cache.

(Shell code example for deleting a cache is present in the original text and is omitted here for brevity as per instructions)

## When to use explicit caching

Context caching is particularly well suited to scenarios where a substantial initial context is referenced repeatedly by shorter requests. Consider using context caching for use cases such as:

* Chatbots with extensive [system instructions]
* Repetitive analysis of lengthy video files
* Recurring queries against large document sets
* Frequent code repository analysis or bug fixing

## How explicit caching reduces costs

Context caching is a paid feature designed to reduce overall operational costs. Billing is based on the following factors:

* **Cache token count:** The number of input tokens cached, billed at a reduced rate when included in subsequent prompts.
* **Storage duration:** The amount of time cached tokens are stored (TTL), billed based on the TTL duration of cached token count. There are no minimum or maximum bounds on the TTL.
* **Other factors:** Other charges apply, such as for non-cached input tokens and output tokens.

For up-to-date pricing details, refer to the Gemini API [pricing page]. To learn how to count tokens, see the [Token guide].

## Additional considerations

Keep the following considerations in mind when using context caching:

* The **minimum** input token count for context caching is 1,024 for 2.5 Flash and 2,048 for 2.5 Pro. The **maximum** is the same as the maximum for the given model. (For more on counting tokens, see the [Token guide]).
* The model doesn't make any distinction between cached tokens and regular input tokens. Cached content is a prefix to the prompt.
* There are no special rate or usage limits on context caching; the standard rate limits for `GenerateContent` apply, and token limits include cached tokens.
* The number of cached tokens is returned in the `usage_metadata` from the create, get, and list operations of the cache service, and also in `GenerateContent` when using the cache.
