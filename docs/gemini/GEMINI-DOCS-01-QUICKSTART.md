# Gemini API quickstart

This quickstart shows you how to install your SDK of choice from the new Google Gen AI SDK, and then make your first Gemini API request.

**Note:** We've recently updated our code snippets to use the new Google GenAI SDK, which is the recommended library for accessing Gemini API. You can find out more about the new SDK and legacy ones on the Libraries page.

Python | JavaScript | Go | Apps Script | REST

## Make your first request

Get a Gemini API key in Google AI Studio.

Use the `generateContent` method to send a request to the Gemini API.

```shell
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$YOUR_API_KEY" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "contents": [
      {
        "parts": [
          {
            "text": "Explain how AI works in a few words"
          }
        ]
      }
    ]
  }'
```

## What's next

Now that you made your first API request, you might want to explore the following guides that show Gemini in action:

  * Text generation
  * Vision
  * Long context

