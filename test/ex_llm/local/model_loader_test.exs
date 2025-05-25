defmodule ExLLM.Local.ModelLoaderTest do
  use ExUnit.Case, async: false
  alias ExLLM.Local.ModelLoader

  describe "start_link/1" do
    test "starts the GenServer" do
      # Stop if already running
      if pid = Process.whereis(ModelLoader) do
        GenServer.stop(pid)
      end

      assert {:ok, pid} = ModelLoader.start_link()
      assert is_pid(pid)
      assert Process.whereis(ModelLoader) == pid
    end
  end

  describe "load_model/1" do
    setup do
      # Ensure ModelLoader is started
      if not is_pid(Process.whereis(ModelLoader)) do
        {:ok, _pid} = ModelLoader.start_link()
      end
      :ok
    end

    test "returns error when Bumblebee is not available" do
      # Without Bumblebee, loading should fail
      assert {:error, reason} = ModelLoader.load_model("microsoft/phi-2")
      assert reason =~ "Bumblebee" or is_atom(reason)
    end

    test "handles HuggingFace model identifiers" do
      # Test would load actual model if Bumblebee available
      result = ModelLoader.load_model("microsoft/phi-2")
      assert {:error, _} = result
    end

    test "handles shorthand model names" do
      # Test shorthand conversion
      result = ModelLoader.load_model("phi")
      assert {:error, _} = result
    end
  end

  describe "list_loaded_models/0" do
    setup do
      if not is_pid(Process.whereis(ModelLoader)) do
        {:ok, _pid} = ModelLoader.start_link()
      end
      :ok
    end

    test "returns empty list when no models loaded" do
      assert ModelLoader.list_loaded_models() == []
    end
  end

  describe "get_acceleration_info/0" do
    setup do
      if not is_pid(Process.whereis(ModelLoader)) do
        {:ok, _pid} = ModelLoader.start_link()
      end
      :ok
    end

    test "returns acceleration information" do
      info = ModelLoader.get_acceleration_info()
      
      assert is_map(info)
      assert Map.has_key?(info, :type)
      assert Map.has_key?(info, :name)
      assert info.type in [:cpu, :cuda, :metal, :rocm]
    end
  end

  describe "unload_model/1" do
    setup do
      if not is_pid(Process.whereis(ModelLoader)) do
        {:ok, _pid} = ModelLoader.start_link()
      end
      :ok
    end

    test "returns error for non-loaded model" do
      assert {:error, :not_loaded} = ModelLoader.unload_model("not-loaded-model")
    end
  end

  describe "get_model_info/1" do
    setup do
      if not is_pid(Process.whereis(ModelLoader)) do
        {:ok, _pid} = ModelLoader.start_link()
      end
      :ok
    end

    test "returns error for non-loaded model" do
      assert {:error, :not_loaded} = ModelLoader.get_model_info("not-loaded-model")
    end
  end
end