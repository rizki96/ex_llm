# Get a Gemini API key

To use the Gemini API, you need an API key. You can create a key with a few clicks in Google AI Studio.

[Get a Gemini API key in Google AI Studio]

## Set up your API key

For initial testing, you can hard code an API key, but this should only be temporary since it is not secure. The rest of this section goes through how to set up your API key locally as an environment variable with different operating systems.

### Linux/macOS - Bash

Bash is a common Linux and macOS terminal configuration. You can check if you have a configuration file for it by running the following command:

```bash
~/.bashrc
```

If the response is "No such file or directory", you will need to create this file and open it by running the following commands, or use `zsh`:

```bash
touch ~/.bashrc
open ~/.bashrc
```

Next, you need to set your API key by adding the following export command:

```bash
export GEMINI_API_KEY=<YOUR_API_KEY_HERE>
```

After saving the file, apply the changes by running:

```bash
source ~/.bashrc
```

### macOS - Zsh

(Instructions for Zsh are typically similar to Bash, often using `~/.zshrc`. The provided text implies using `zsh` as an alternative but doesn't give explicit `zsh` steps distinct from Bash in this snippet, so the Bash steps are generally applicable for environment variables).

### Windows

(The provided text mentions Windows but does not include the specific commands for setting environment variables on Windows. Common methods involve the Command Prompt `set` command or PowerShell `$env:` prefix, often added to user or system environment variables through the system properties GUI for persistence.)

## Send your first Gemini API request

You can use a curl command to verify your setup:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '{
    "contents": [
      {
        "parts": [
          {
            "text": "Write a story about a magic backpack."
          }
        ]
      }
    ]
  }'
```

## Keep your API key secure

It's important to keep your Gemini API key secure. Here are a few things to keep in mind when using your Gemini API key:

  * The Google AI Gemini API uses API keys for authorization. If others get access to your Gemini API key, they can make calls using your project's quota, which could result in lost quota or additional charges for billed projects, in addition to accessing tuned models and files.
  * Adding [API key restrictions] can help limit the surface area usable through each API key.
  * You're responsible for keeping your Gemini API key secure.
  * Do NOT check Gemini API keys into source control.
  * Client-side applications (Android, Swift, web, and Dart/Flutter) risk exposing API keys. We don't recommend using the Google AI client SDKs in production apps to call the Google AI Gemini API directly from your mobile and web apps.
  * For some general best practices, you can also review this [support article].

