#!/usr/bin/env elixir

# Debug countTokens API issue

Mix.install([
  {:ex_llm, path: "."},
  {:jason, "~> 1.4"},
  {:req, "~> 0.5"}
])

alias ExLLM.Providers.Gemini

IO.puts("\n=== Testing countTokens API ===\n")

# Test with simple content
content = "Hello, world!"
model = "gemini-2.0-flash"

# First, let's see what the Gemini module is doing
IO.puts("Testing with Gemini.count_tokens/2:")
case Gemini.count_tokens(content, model: model) do
  {:ok, result} ->
    IO.puts("Success: #{inspect(result)}")
  {:error, error} ->
    IO.puts("Error:")
    IO.inspect(error, pretty: true, limit: :infinity)
end

# Now let's make a direct API call to see what the API expects
IO.puts("\n\nMaking direct API call:")

api_key = System.get_env("GEMINI_API_KEY")
url = "https://generativelanguage.googleapis.com/v1beta/models/#{model}:countTokens?key=#{api_key}"

# Try the format from Google's documentation
request_body = %{
  "contents" => [
    %{
      "parts" => [
        %{"text" => content}
      ]
    }
  ]
}

case Req.post(url, json: request_body) do
  {:ok, %{status: 200, body: body}} ->
    IO.puts("Direct API Success:")
    IO.inspect(body, pretty: true)
    
  {:ok, %{status: status, body: body}} ->
    IO.puts("Direct API Error (#{status}):")
    IO.inspect(body, pretty: true)
    
  {:error, error} ->
    IO.puts("Direct API Request Error:")
    IO.inspect(error, pretty: true)
end

# Let's also check what format the Gemini module is sending
IO.puts("\n\nDebugging Gemini module implementation...")

# Look at the source to understand the issue better