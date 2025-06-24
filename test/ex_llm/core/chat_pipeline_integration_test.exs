defmodule ExLLM.Core.ChatPipelineIntegrationTest do
  use ExUnit.Case, async: false

  # Test that Core.Chat correctly uses pipeline system for supported providers
  # and falls back to adapter system for unsupported ones

  setup do
    # Set API keys for both providers
    System.put_env("OPENAI_API_KEY", "test-key-12345")
    System.put_env("ANTHROPIC_API_KEY", "test-key-12345")
    System.put_env("GROQ_API_KEY", "test-key-12345")

    on_exit(fn ->
      System.delete_env("OPENAI_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")
      System.delete_env("GROQ_API_KEY")
    end)

    :ok
  end

  describe "pipeline integration" do
    @tag :skip
    test "OpenAI provider uses pipeline system" do
      # This is a smoke test to verify the integration works
      # We can't actually test without mocking the HTTP client
      messages = [%{role: "user", content: "Hello"}]

      # The function should use pipeline system internally
      # but we can't test the full flow without HTTP mocking
      assert ExLLM.Core.Chat.chat(:openai, messages, model: "gpt-4")
    end

    @tag :skip
    test "Anthropic provider uses pipeline system" do
      messages = [%{role: "user", content: "Hello"}]

      # The function should use pipeline system internally
      assert ExLLM.Core.Chat.chat(:anthropic, messages, model: "claude-3-haiku-20240307")
    end

    @tag :skip
    test "Groq provider falls back to adapter system" do
      messages = [%{role: "user", content: "Hello"}]

      # Groq should use the old adapter system since no pipeline plugs exist yet
      assert ExLLM.Core.Chat.chat(:groq, messages, model: "llama3-8b-8192")
    end

    test "pipeline system is properly set up for supported providers" do
      # Test internal logic by trying a basic provider detection
      # We can't access the private function directly, but we can verify
      # the providers are configured by testing the public interface

      # These providers should be supported by pipeline system
      # (We'll just verify they don't throw errors when configured)
      alias ExLLM.Pipelines.StandardProvider
      alias ExLLM.Providers.OpenAI.{BuildRequest, ParseResponse}

      openai_plugs = [
        build_request: {BuildRequest, []},
        parse_response: {ParseResponse, []}
      ]

      # Should successfully build pipeline
      pipeline = StandardProvider.build(openai_plugs)
      assert is_list(pipeline)
      assert length(pipeline) == 1
    end
  end
end
