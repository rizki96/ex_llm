#!/usr/bin/env elixir

# Test different thinking config formats to find the correct one

Mix.install([
  {:req, "~> 0.5"},
  {:jason, "~> 1.4"}
])

api_key = System.get_env("GEMINI_API_KEY")
base_url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-thinking-exp:generateContent?key=#{api_key}"

# Test different thinking config formats
test_configs = [
  %{
    name: "Empty thinking config",
    config: %{}
  },
  %{
    name: "Just includeThoughts", 
    config: %{
      "includeThoughts" => true
    }
  },
  %{
    name: "With thoughtsCategory",
    config: %{
      "thoughtsCategory" => "verbose",
      "includeThoughts" => true
    }
  },
  %{
    name: "With role field",
    config: %{
      "role" => "model",
      "includeThoughts" => true
    }
  }
]

for %{name: name, config: thinking_config} <- test_configs do
  IO.puts("\n=== Testing: #{name} ===")
  
  payload = %{
    contents: [
      %{
        role: "user",
        parts: [%{text: "Step by step, what is 15 + 27?"}]
      }
    ],
    generationConfig: %{
      thinkingConfig: thinking_config,
      maxOutputTokens: 100
    }
  }
  
  case Req.post(base_url, json: payload) do
    {:ok, %{status: 200, body: body}} ->
      IO.puts("SUCCESS! Config worked: #{inspect(thinking_config)}")
      
      # Check response structure
      if body["candidates"] do
        [candidate | _] = body["candidates"]
        
        # Check if thinking content is in the response
        if usage = body["usageMetadata"] do
          IO.puts("Usage metadata: #{inspect(usage)}")
        end
        
        if content = candidate["content"] do
          if parts = content["parts"] do
            IO.puts("Response has #{length(parts)} parts")
            for {part, idx} <- Enum.with_index(parts) do
              if part["text"] do
                preview = String.slice(part["text"], 0, 100)
                IO.puts("Part #{idx}: #{preview}...")
              end
            end
          end
        end
      end
      
    {:ok, %{status: status, body: body}} ->
      error_msg = get_in(body, ["error", "message"]) || "Unknown error"
      IO.puts("Failed (#{status}): #{error_msg}")
      
    {:error, error} ->
      IO.puts("Request error: #{inspect(error)}")
  end
end

# Also test without thinking config to see normal response
IO.puts("\n=== Testing without thinking config (control) ===")

normal_payload = %{
  contents: [
    %{
      role: "user",
      parts: [%{text: "What is 15 + 27?"}]
    }
  ],
  generationConfig: %{
    maxOutputTokens: 100
  }
}

case Req.post(base_url, json: normal_payload) do
  {:ok, %{status: 200, body: body}} ->
    IO.puts("Normal response received")
    if usage = body["usageMetadata"] do
      IO.puts("Usage metadata: #{inspect(usage)}")
    end
    
  {:ok, %{status: status, body: body}} ->
    IO.puts("Error #{status}: #{inspect(body)}")
    
  {:error, error} ->
    IO.puts("Request error: #{inspect(error)}")
end