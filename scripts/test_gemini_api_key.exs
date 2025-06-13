#!/usr/bin/env elixir

# Comprehensive Gemini API Testing with API Key Authentication
# Tests all APIs that support API key authentication

Mix.install([
  {:req, "~> 0.5.0"},
  {:jason, "~> 1.4"}
])

defmodule GeminiAPIKeyTester do
  @moduledoc """
  Comprehensive testing of Gemini APIs using API key authentication.
  Based on September 2024 authentication policy changes.
  """

  @base_url "https://generativelanguage.googleapis.com/v1beta"

  def run do
    IO.puts("\n🔑 Gemini API Key Testing Suite")
    IO.puts("=" <> String.duplicate("=", 40))
    IO.puts("Testing APIs that support API key authentication (September 2024+)")

    case get_api_key() do
      {:ok, api_key} ->
        run_tests(api_key)
      {:error, reason} ->
        IO.puts("\n❌ #{reason}")
        show_setup_instructions()
        System.halt(1)
    end
  end

  defp get_api_key do
    case System.get_env("GEMINI_API_KEY") do
      nil ->
        {:error, "GEMINI_API_KEY environment variable not set"}
      "" ->
        {:error, "GEMINI_API_KEY is empty"}
      api_key ->
        {:ok, api_key}
    end
  end

  defp run_tests(api_key) do
    IO.puts("\n🔑 Using API key: #{String.slice(api_key, 0..20)}...")
    
    tests = [
      {"Models API - List Models", fn -> test_models_list(api_key) end},
      {"Models API - Get Model", fn -> test_models_get(api_key) end},
      {"Content Generation - Simple", fn -> test_content_simple(api_key) end},
      {"Content Generation - With Config", fn -> test_content_with_config(api_key) end},
      {"Token Counting", fn -> test_token_counting(api_key) end},
      {"Files API - List Files", fn -> test_files_list(api_key) end},
      {"Context Caching - List", fn -> test_caching_list(api_key) end},
      {"Embeddings API", fn -> test_embeddings(api_key) end},
      {"Fine-tuning - List Models", fn -> test_tuning_list(api_key) end},
      {"Question Answering - Inline", fn -> test_qa_inline(api_key) end}
    ]
    
    IO.puts("\n" <> String.duplicate("-", 50))
    
    results = Enum.map(tests, fn {name, test_fn} ->
      IO.puts("\n🧪 Testing: #{name}")
      try do
        case test_fn.() do
          :ok -> 
            IO.puts("   ✅ PASSED")
            {name, :passed}
          {:error, reason} -> 
            IO.puts("   ❌ FAILED: #{reason}")
            {name, :failed, reason}
          {:skip, reason} ->
            IO.puts("   ⏭️  SKIPPED: #{reason}")
            {name, :skipped, reason}
        end
      rescue
        error ->
          IO.puts("   💥 ERROR: #{inspect(error)}")
          {name, :error, error}
      end
    end)
    
    print_summary(results)
  end

  # Test Functions

  defp test_models_list(api_key) do
    case api_request("GET", "models", api_key) do
      {:ok, %{"models" => models}} when is_list(models) ->
        IO.puts("   📋 Found #{length(models)} models")
        :ok
      {:ok, response} ->
        {:error, "Unexpected response format: #{inspect(response)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_models_get(api_key) do
    # First get list of models to pick one
    case api_request("GET", "models", api_key) do
      {:ok, %{"models" => [first_model | _]}} ->
        model_name = first_model["name"]
        case api_request("GET", model_name, api_key) do
          {:ok, model} ->
            IO.puts("   📖 Retrieved model: #{model["displayName"] || model["name"]}")
            :ok
          {:error, reason} ->
            {:error, "Failed to get model details: #{reason}"}
        end
      {:ok, %{"models" => []}} ->
        {:skip, "No models available to test"}
      {:error, reason} ->
        {:error, "Could not list models: #{reason}"}
    end
  end

  defp test_content_simple(api_key) do
    body = %{
      "contents" => [
        %{
          "parts" => [%{"text" => "Write a one-sentence summary of artificial intelligence."}]
        }
      ]
    }
    
    case api_request("POST", "models/gemini-1.5-flash:generateContent", api_key, body) do
      {:ok, %{"candidates" => [candidate | _]}} ->
        content = get_in(candidate, ["content", "parts", Access.at(0), "text"])
        if content do
          IO.puts("   💬 Generated #{String.length(content)} characters")
          :ok
        else
          {:error, "No text content in response"}
        end
      {:ok, response} ->
        {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_content_with_config(api_key) do
    body = %{
      "contents" => [
        %{
          "parts" => [%{"text" => "List 3 colors"}]
        }
      ],
      "generationConfig" => %{
        "temperature" => 0.1,
        "topP" => 0.8,
        "maxOutputTokens" => 100
      },
      "safetySettings" => [
        %{
          "category" => "HARM_CATEGORY_HARASSMENT",
          "threshold" => "BLOCK_MEDIUM_AND_ABOVE"
        }
      ]
    }
    
    case api_request("POST", "models/gemini-1.5-flash:generateContent", api_key, body) do
      {:ok, %{"candidates" => [_candidate | _]}} ->
        IO.puts("   ⚙️  Generated with config")
        :ok
      {:ok, response} ->
        {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_token_counting(api_key) do
    body = %{
      "contents" => [
        %{
          "parts" => [%{"text" => "Count the tokens in this message please."}]
        }
      ]
    }
    
    case api_request("POST", "models/gemini-1.5-flash:countTokens", api_key, body) do
      {:ok, %{"totalTokens" => token_count}} when is_integer(token_count) ->
        IO.puts("   🔢 Counted #{token_count} tokens")
        :ok
      {:ok, response} ->
        {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_files_list(api_key) do
    case api_request("GET", "files", api_key) do
      {:ok, %{"files" => files}} when is_list(files) ->
        IO.puts("   📁 Found #{length(files)} files")
        :ok
      {:ok, %{}} ->
        # Empty response is normal when no files exist
        IO.puts("   📁 No files found (empty list)")
        :ok
      {:ok, response} ->
        {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_caching_list(api_key) do
    case api_request("GET", "cachedContents", api_key) do
      {:ok, %{"cachedContents" => contents}} when is_list(contents) ->
        IO.puts("   💾 Found #{length(contents)} cached contents")
        :ok
      {:ok, %{}} ->
        # Empty response is normal when no cached content exists
        IO.puts("   💾 No cached content found")
        :ok
      {:ok, response} ->
        {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_embeddings(api_key) do
    body = %{
      "model" => "models/text-embedding-004",
      "content" => %{
        "parts" => [%{"text" => "Embed this text for semantic search"}]
      }
    }
    
    case api_request("POST", "models/text-embedding-004:embedContent", api_key, body) do
      {:ok, %{"embedding" => %{"values" => values}}} when is_list(values) ->
        IO.puts("   🔗 Generated embedding with #{length(values)} dimensions")
        :ok
      {:ok, response} ->
        {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_tuning_list(api_key) do
    case api_request("GET", "tunedModels", api_key) do
      {:ok, %{"tunedModels" => models}} when is_list(models) ->
        IO.puts("   🎯 Found #{length(models)} tuned models")
        :ok
      {:ok, %{}} ->
        # Empty response is normal when no tuned models exist
        IO.puts("   🎯 No tuned models found")
        :ok
      {:ok, response} ->
        {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp test_qa_inline(api_key) do
    body = %{
      "contents" => [
        %{
          "parts" => [%{"text" => "What is the capital of France based on the passage?"}],
          "role" => "user"
        }
      ],
      "answerStyle" => "ABSTRACTIVE",
      "inlinePassages" => %{
        "passages" => [
          %{
            "id" => "passage1",  # Use simple alphanumeric format for ID
            "content" => %{
              "parts" => [%{"text" => "France is a country in Europe. Paris is the capital city of France and its largest city."}]
            }
          }
        ]
      }
    }
    
    case api_request("POST", "models/aqa:generateAnswer", api_key, body) do
      {:ok, %{"answer" => answer}} when is_map(answer) ->
        IO.puts("   💡 Generated grounded answer")
        :ok
      {:ok, response} ->
        {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Helper functions

  defp api_request(method, endpoint, api_key, body \\ nil) do
    url = "#{@base_url}/#{endpoint}"
    
    # Add API key as query parameter
    url_with_key = if String.contains?(url, "?") do
      "#{url}&key=#{api_key}"
    else
      "#{url}?key=#{api_key}"
    end
    
    headers = [{"Content-Type", "application/json"}]
    req_opts = [headers: headers]
    req_opts = if body, do: [{:json, body} | req_opts], else: req_opts
    
    case apply(Req, String.downcase(method) |> String.to_atom(), [url_with_key, req_opts]) do
      {:ok, %{status: status, body: response}} when status in 200..299 ->
        {:ok, response}
      {:ok, %{status: status, body: body}} ->
        error_msg = extract_error_message(body)
        {:error, "HTTP #{status}: #{error_msg}"}
      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp extract_error_message(%{"error" => %{"message" => message}}), do: message
  defp extract_error_message(%{"error" => error}) when is_binary(error), do: error
  defp extract_error_message(body), do: inspect(body)

  defp print_summary(results) do
    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("📊 Gemini API Key Test Results:")
    IO.puts(String.duplicate("=", 50))
    
    passed = Enum.count(results, fn 
      {_, :passed} -> true
      {_, :passed, _} -> true
      _ -> false
    end)
    failed = Enum.count(results, fn 
      {_, :failed} -> true
      {_, :failed, _} -> true
      _ -> false
    end)
    skipped = Enum.count(results, fn 
      {_, :skipped} -> true
      {_, :skipped, _} -> true
      _ -> false
    end)
    errors = Enum.count(results, fn 
      {_, :error} -> true
      {_, :error, _} -> true
      _ -> false
    end)
    total = length(results)
    
    Enum.each(results, fn
      {name, :passed} -> IO.puts("✅ #{name}")
      {name, :failed, reason} -> IO.puts("❌ #{name} - #{reason}")
      {name, :skipped, reason} -> IO.puts("⏭️  #{name} - #{reason}")
      {name, :error, error} -> IO.puts("💥 #{name} - #{inspect(error)}")
    end)
    
    IO.puts("\n📈 Results:")
    IO.puts("   ✅ Passed: #{passed}/#{total}")
    IO.puts("   ❌ Failed: #{failed}/#{total}")
    IO.puts("   ⏭️  Skipped: #{skipped}/#{total}")
    IO.puts("   💥 Errors: #{errors}/#{total}")
    
    success_rate = if total > 0, do: Float.round(passed / total * 100, 1), else: 0.0
    IO.puts("   📊 Success Rate: #{success_rate}%")
    
    if passed == total do
      IO.puts("\n🎉 All API key authentication tests passed!")
      IO.puts("✅ Gemini API integration is working correctly with API keys!")
    else
      IO.puts("\n📝 Summary:")
      IO.puts("   • API key authentication is the primary method as of September 2024")
      IO.puts("   • OAuth2 is only needed for permission management APIs")
      IO.puts("   • Most Gemini APIs now work seamlessly with API keys")
    end
  end

  defp show_setup_instructions do
    IO.puts("\n💡 Gemini API Key Setup Instructions:")
    IO.puts("=" <> String.duplicate("=", 40))
    IO.puts("1. Visit: https://aistudio.google.com/app/apikey")
    IO.puts("2. Create an API key for your project")
    IO.puts("3. Set environment variable:")
    IO.puts("   export GEMINI_API_KEY=\"your-api-key-here\"")
    IO.puts("4. Or add to ~/.env file:")
    IO.puts("   echo 'GEMINI_API_KEY=\"your-key\"' >> ~/.env")
    IO.puts("5. Run this test again!")
  end
end

# Run the tests
GeminiAPIKeyTester.run()