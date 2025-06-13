# Gemini API Libraries

This page provides information on downloading and installing the latest libraries for the Gemini API. If you're new to the Gemini API, get started with the API quickstart.

**Important note about our new libraries**

We've recently launched a new set of libraries that provide a more consistent and streamlined experience for accessing Google's generative AI models across different Google services.

## Key Library Updates

| Language             | Old library                | New library (Recommended)   |
| :------------------- | :------------------------- | :-------------------------- |
| Python               | `google-generativeai`      | `google-genai`              |
| JavaScript and TypeScript | `@google/generative-ai` | `@google/genai`\<br/\>Currently in Preview |
| Go                   | `google.golang.org/generative-ai` | `google.golang.org/genai`   |

We strongly encourage all users of the previous libraries to migrate to the new libraries. Despite the JavaScript/TypeScript library being in Preview, we still recommend that you start migrating, as long as you are comfortable with the caveats listed in the JavaScript/TypeScript section.

## Python

You can install our Python library by running:

```bash
pip install google-genai
```

## JavaScript and TypeScript

You can install our JavaScript and TypeScript library by running:

```bash
npm install @google/genai
```

The new JavaScript/TypeScript library is currently in **preview**, which means it may not be feature complete and that we may need to introduce breaking changes.

However, we **highly recommend** you start using the **new SDK** over the **previous, deprecated version**, as long as you are comfortable with these caveats. We are actively working towards a GA (General Availability) release for this library.

### API keys in client-side applications

**WARNING:** No matter which library you're using, it is **unsafe** to insert your API key into client-side JavaScript or TypeScript code. Use server-side deployments for accessing Gemini API in production.

## Go

You can install our Go library by running:

```bash
go get google.golang.org/genai
```

## Previous libraries and SDKs

The following is a set of our previous SDK's which are no longer being actively developed, you can switch to the updated Google Gen AI SDK by using our migration guide:

  * Previous Python library
  * Previous Node.js library
  * Previous Go library
  * Previous Dart and Flutter library
  * Previous Swift library
  * Previous Android library
