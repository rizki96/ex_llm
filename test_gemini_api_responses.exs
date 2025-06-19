#!/usr/bin/env elixir

# Test script to check actual Gemini API responses for thinking config and countTokens

Mix.install([
  {:req, "~> 0.5"},
  {:jason, "~> 1.4"}
])

api_key = System.get_env("GEMINI_API_KEY")

IO.puts("\n=== Testing Thinking Config API Response ===\n")

# Test 1: Try the thinking model with direct API call
thinking_payload = %{
  contents: [
    %{
      role: "user",
      parts: [%{text: "Step by step, calculate: What is 25 * 37?"}]
    }
  ],
  generationConfig: %{
    thinkingConfig: %{
      "thoughtsRole" => "model",
      "includeThoughts" => true
    }
  }
}

url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-thinking-exp:generateContent?key=#{api_key}"

case Req.post(url, json: thinking_payload) do
  {:ok, %{status: 200, body: body}} ->
    IO.puts("Success! Response structure:")
    IO.puts(Jason.encode!(body, pretty: true))
    
    # Check if thinking content is returned
    if candidates = body["candidates"] do
      case candidates do
        [%{"content" => %{"parts" => parts}} | _] ->
          IO.puts("\nParts in response:")
          for part <- parts do
            IO.inspect(part, pretty: true)
          end
        _ ->
          IO.puts("\nNo content parts found")
      end
    end
    
  {:ok, %{status: status, body: body}} ->
    IO.puts("Error #{status}:")
    IO.inspect(body, pretty: true)
    
  {:error, error} ->
    IO.puts("Request error:")
    IO.inspect(error)
end

IO.puts("\n\n=== Testing CountTokens API Response ===\n")

# Test 2: CountTokens with simple content
count_payload = %{
  contents: [
    %{
      role: "user",
      parts: [%{text: "Hello, world!"}]
    }
  ]
}

count_url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:countTokens?key=#{api_key}"

case Req.post(count_url, json: count_payload) do
  {:ok, %{status: 200, body: body}} ->
    IO.puts("CountTokens response:")
    IO.puts(Jason.encode!(body, pretty: true))
    
  {:ok, %{status: status, body: body}} ->
    IO.puts("Error #{status}:")
    IO.inspect(body, pretty: true)
    
  {:error, error} ->
    IO.puts("Request error:")
    IO.inspect(error)
end

IO.puts("\n\n=== Testing CountTokens with GenerateContentRequest ===\n")

# Test 3: CountTokens with generateContentRequest
count_with_request_payload = %{
  generateContentRequest: %{
    model: "models/gemini-1.5-flash",
    contents: [
      %{
        role: "user",
        parts: [%{text: "Hello, world!"}]
      }
    ],
    generationConfig: %{
      temperature: 0.9,
      maxOutputTokens: 100
    }
  }
}

case Req.post(count_url, json: count_with_request_payload) do
  {:ok, %{status: 200, body: body}} ->
    IO.puts("CountTokens with generateContentRequest response:")
    IO.puts(Jason.encode!(body, pretty: true))
    
  {:ok, %{status: status, body: body}} ->
    IO.puts("Error #{status}:")
    IO.inspect(body, pretty: true)
    
  {:error, error} ->
    IO.puts("Request error:")
    IO.inspect(error)
end