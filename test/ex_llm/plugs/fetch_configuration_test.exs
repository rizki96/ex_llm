defmodule ExLLM.Plugs.FetchConfigurationTest do
  use ExUnit.Case, async: false

  import ExUnit.Callbacks

  alias ExLLM.Infrastructure.ConfigProvider.Static
  alias ExLLM.Pipeline.Request
  alias ExLLM.Plugs.FetchConfiguration

  setup do
    # Store original environment values for API keys we might modify
    original_openai = System.get_env("OPENAI_API_KEY")
    original_ollama_url = System.get_env("OLLAMA_BASE_URL")

    on_exit(fn ->
      # Restore original values or delete if they weren't set
      if original_openai do
        System.put_env("OPENAI_API_KEY", original_openai)
      else
        System.delete_env("OPENAI_API_KEY")
      end

      if original_ollama_url do
        System.put_env("OLLAMA_BASE_URL", original_ollama_url)
      else
        System.delete_env("OLLAMA_BASE_URL")
      end
    end)

    # Clear the env vars we'll be testing
    System.delete_env("OPENAI_API_KEY")
    System.delete_env("OLLAMA_BASE_URL")
    :ok
  end

  describe "call/2 with providers requiring API key" do
    test "fetches config and API key from environment" do
      System.put_env("OPENAI_API_KEY", "sk-env-key")
      request = Request.new(:openai, [])

      result = FetchConfiguration.call(request, [])

      assert result.halted == false
      assert result.assigns.api_key == "sk-env-key"
      assert is_map(result.assigns.config)
      assert result.assigns.config.api_key == "sk-env-key"
    end

    test "halts if API key is missing" do
      System.delete_env("OPENAI_API_KEY")
      request = Request.new(:openai, [])

      result = FetchConfiguration.call(request, [])

      assert result.halted == true
      assert result.state == :error
      assert result.errors |> hd() |> Map.get(:error) == :unauthorized
    end

    test "fetches config from a static provider" do
      config = %{openai: %{api_key: "sk-static-key", model: "gpt-4"}}
      {:ok, static_provider} = Static.start_link(config)

      request = Request.new(:openai, [], %{config_provider: static_provider})

      result = FetchConfiguration.call(request, [])

      assert result.halted == false
      assert result.assigns.api_key == "sk-static-key"
      assert result.assigns.config == %{api_key: "sk-static-key", model: "gpt-4"}
    end
  end

  describe "call/2 with providers not requiring API key" do
    test "fetches config and continues without an API key" do
      # Ollama does not use a standard API key
      request = Request.new(:ollama, [])

      result = FetchConfiguration.call(request, [])

      assert result.halted == false
      # No api_key assignment for providers that don't use API keys
      refute Map.has_key?(result.assigns, :api_key)
      # Config will be fetched, should contain base_url for ollama
      assert is_map(result.assigns.config)
    end

    test "fetches config with other env vars" do
      System.put_env("OLLAMA_MODEL", "llama3")
      System.put_env("OLLAMA_BASE_URL", "http://localhost:11434")

      request = Request.new(:ollama, [])

      result = FetchConfiguration.call(request, [])

      assert result.halted == false
      # No api_key assignment for providers that don't use API keys  
      refute Map.has_key?(result.assigns, :api_key)

      assert result.assigns.config == %{
               model: "llama3",
               base_url: "http://localhost:11434"
             }
    end
  end
end
