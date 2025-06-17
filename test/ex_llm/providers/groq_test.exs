defmodule ExLLM.Providers.GroqTest do
  use ExUnit.Case
  alias ExLLM.Providers.Groq
  alias ExLLM.Testing.ConfigProviderHelper

  describe "Groq adapter" do
    test "configured?/1 returns false when no API key" do
      provider = ConfigProviderHelper.setup_static_provider(%{groq: %{}})
      refute Groq.configured?(config_provider: provider)
    end

    test "configured?/1 returns true when API key is set" do
      config = %{groq: %{api_key: "test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)
      assert Groq.configured?(config_provider: provider)
    end

    test "transform_request/2 handles Groq-specific parameters" do
      request = %{
        "model" => "llama3-70b",
        "messages" => [%{"role" => "user", "content" => "test"}],
        "stop" => ["stop1", "stop2", "stop3", "stop4", "stop5"],
        "temperature" => 3.0
      }

      transformed = Groq.transform_request(request, [])

      # Should limit stop sequences to 4
      assert length(transformed["stop"]) == 4
      assert transformed["stop"] == ["stop1", "stop2", "stop3", "stop4"]

      # Should cap temperature at 2
      assert transformed["temperature"] == 2
    end

    test "filter_model/1 filters out whisper models" do
      assert Groq.filter_model(%{"id" => "llama3-70b"})
      assert Groq.filter_model(%{"id" => "mixtral-8x7b"})
      refute Groq.filter_model(%{"id" => "whisper-large-v3"})
      refute Groq.filter_model(%{"id" => "distil-whisper-large-v3-en"})
    end
  end

  describe "provider detection" do
    test "provider/model string works with mock adapter" do
      # Test with mock to avoid real API calls
      messages = [%{role: "user", content: "Hello"}]

      {:ok, response} =
        ExLLM.chat(:mock, messages,
          model: "groq/llama3-70b-8192",
          mock_response: "Test response"
        )

      # Either the mock response or default response is fine
      assert is_binary(response.content)
    end
  end
end
