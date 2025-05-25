defmodule ExLLM.LocalIntegrationTest do
  use ExUnit.Case, async: false

  describe "local adapter integration" do
    test "local adapter is registered" do
      providers = ExLLM.supported_providers()
      assert :local in providers
    end

    test "default model is available" do
      assert ExLLM.default_model(:local) == "microsoft/phi-2"
    end

    test "configured? returns false without Bumblebee" do
      # Without Bumblebee installed, should return false
      assert ExLLM.configured?(:local) == false
    end

    test "list_models returns empty list without Bumblebee" do
      assert {:ok, []} = ExLLM.list_models(:local)
    end

    test "chat returns error without Bumblebee" do
      messages = [%{role: "user", content: "Hello"}]
      assert {:error, message} = ExLLM.chat(:local, messages)
      assert message =~ "Bumblebee"
    end

    test "stream_chat returns error without Bumblebee" do
      messages = [%{role: "user", content: "Hello"}]
      assert {:error, message} = ExLLM.stream_chat(:local, messages)
      assert message =~ "Bumblebee"
    end
  end

  describe "context management with local models" do
    test "prepare_messages works with local provider" do
      messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"},
        %{role: "user", content: "How are you?"}
      ]

      prepared =
        ExLLM.prepare_messages(messages,
          provider: "local",
          model: "microsoft/phi-2",
          max_tokens: 1000
        )

      assert is_list(prepared)
      assert length(prepared) <= length(messages)
    end

    test "context_window_size returns correct size for local models" do
      assert ExLLM.context_window_size(:local, "microsoft/phi-2") == 2048
      assert ExLLM.context_window_size(:local, "mistralai/Mistral-7B-v0.1") == 8192
    end
  end
end
