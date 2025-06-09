defmodule ExLLM.BumblebeeTopLevelIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  describe "bumblebee adapter integration" do
    test "bumblebee adapter is registered" do
      providers = ExLLM.supported_providers()
      assert :bumblebee in providers
    end

    test "default model is available" do
      assert ExLLM.default_model(:bumblebee) == "microsoft/phi-4"
    end

    test "configured? returns false without Bumblebee" do
      # Without Bumblebee installed, should return false
      assert ExLLM.configured?(:bumblebee) == false
    end

    test "list_models returns empty list without Bumblebee" do
      assert {:ok, []} = ExLLM.list_models(:bumblebee)
    end

    test "chat returns error without Bumblebee" do
      messages = [%{role: "user", content: "Hello"}]
      assert {:error, message} = ExLLM.chat(:bumblebee, messages)
      assert message =~ "Bumblebee"
    end

    test "stream_chat returns error without Bumblebee" do
      messages = [%{role: "user", content: "Hello"}]
      assert {:error, message} = ExLLM.stream_chat(:bumblebee, messages)
      assert message =~ "Bumblebee"
    end
  end

  describe "context management with bumblebee models" do
    test "prepare_messages works with bumblebee provider" do
      messages = [
        %{role: "system", content: "You are a helpful assistant"},
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"},
        %{role: "user", content: "How are you?"}
      ]

      prepared =
        ExLLM.prepare_messages(messages,
          provider: "bumblebee",
          model: "microsoft/phi-4",
          max_tokens: 1000
        )

      assert is_list(prepared)
      assert length(prepared) <= length(messages)
    end

    test "context_window_size returns correct size for bumblebee models" do
      assert ExLLM.context_window_size(:bumblebee, "microsoft/phi-2") == 2048
      assert ExLLM.context_window_size(:bumblebee, "mistralai/Mistral-7B-v0.1") == 8192
    end
  end
end
