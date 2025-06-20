defmodule ExLLM.BumblebeeTopLevelIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  describe "bumblebee adapter integration" do
    test "bumblebee adapter is registered" do
      providers = ExLLM.supported_providers()
      assert :bumblebee in providers
    end

    test "default model is available" do
      assert ExLLM.default_model(:bumblebee) == "HuggingFaceTB/SmolLM2-1.7B-Instruct"
    end

    test "configured? returns false without ModelLoader" do
      # Bumblebee is installed but ModelLoader isn't running, should return false
      # Note: configured? checks if ModelLoader is running, not just if Bumblebee is installed
      assert ExLLM.configured?(:bumblebee) == false
    end

    test "list_models returns error without ModelLoader" do
      # Without ModelLoader running, list_models should return an error
      assert {:error, message} = ExLLM.list_models(:bumblebee)
      assert is_binary(message)
    end

    test "chat returns error without ModelLoader" do
      messages = [%{role: "user", content: "Hello"}]
      # Should get an error because ModelLoader isn't running
      # The actual error is an EXIT from GenServer.call when the process isn't running
      assert catch_exit(ExLLM.chat(:bumblebee, messages))
    end

    @tag :streaming
    test "stream returns error without ModelLoader" do
      messages = [%{role: "user", content: "Hello"}]
      # Use the new streaming API with build/execute pattern
      builder = ExLLM.build(:bumblebee, messages)
      # Should get an EXIT because ModelLoader isn't running
      assert catch_exit(ExLLM.execute(builder))
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
          model: "HuggingFaceTB/SmolLM2-1.7B-Instruct",
          max_tokens: 1000
        )

      assert is_list(prepared)
      assert length(prepared) <= length(messages)
    end

    test "context_window_size returns correct size for bumblebee models" do
      assert ExLLM.context_window_size(:bumblebee, "HuggingFaceTB/SmolLM2-1.7B-Instruct") == 2048
      assert ExLLM.context_window_size(:bumblebee, "mistralai/Mistral-7B-v0.1") == 8192
    end
  end
end
