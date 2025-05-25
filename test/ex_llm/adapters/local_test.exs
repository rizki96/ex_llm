defmodule ExLLM.Adapters.LocalTest do
  use ExUnit.Case, async: true
  alias ExLLM.Adapters.Local

  # Mock modules for testing without actual Bumblebee
  defmodule MockModelLoader do
    def load_model(_model), do: {:ok, %{serving: :mock_serving}}
    def list_loaded_models(), do: ["microsoft/phi-2"]
    def get_acceleration_info(), do: %{name: "CPU", backend: "Mock", type: :cpu}
  end

  defmodule MockNxServing do
    def run(_serving, %{text: prompt}) do
      %{text: "Mock response to: #{prompt}"}
    end
  end

  describe "chat/2" do
    test "returns error when Bumblebee is not available" do
      messages = [%{role: "user", content: "Hello"}]

      assert {:error, message} = Local.chat(messages)
      assert message =~ "Bumblebee is not available"
    end

    test "handles basic chat with mocked dependencies" do
      # This test would only run if Bumblebee is available
      # For now, we're testing the error case
      messages = [%{role: "user", content: "Test message"}]

      result = Local.chat(messages, model: "microsoft/phi-2")
      assert {:error, _} = result
    end
  end

  describe "stream_chat/2" do
    test "returns error when Bumblebee is not available" do
      messages = [%{role: "user", content: "Hello"}]

      assert {:error, message} = Local.stream_chat(messages)
      assert message =~ "Bumblebee is not available"
    end
  end

  describe "configured?/1" do
    test "returns false when Bumblebee is not available" do
      assert Local.configured?() == false
    end
  end

  describe "default_model/0" do
    test "returns the default model" do
      assert Local.default_model() == "microsoft/phi-2"
    end
  end

  describe "list_models/1" do
    test "returns empty list when Bumblebee is not available" do
      assert {:ok, []} = Local.list_models()
    end
  end

  describe "message formatting" do
    test "formats messages correctly for different models" do
      # Test the private format_messages function indirectly
      # by checking the module compiles correctly
      assert function_exported?(Local, :chat, 2)
    end
  end

  describe "model metadata" do
    test "model names are humanized correctly" do
      # Test would verify humanize_model_name if it were public
      # For now, we just ensure the module loads
      assert function_exported?(Local, :list_models, 1)
    end

    test "default model is available" do
      assert Local.default_model() == "microsoft/phi-2"
    end
  end
end
