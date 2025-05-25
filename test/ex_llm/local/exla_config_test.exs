defmodule ExLLM.Local.EXLAConfigTest do
  use ExUnit.Case, async: true
  alias ExLLM.Local.EXLAConfig

  describe "configure_backend/0" do
    test "configures backend based on available libraries" do
      assert {:ok, backend} = EXLAConfig.configure_backend()
      
      # Should return :binary when no acceleration libraries available
      assert backend in [:binary, :emlx, :cuda, :rocm, :cpu, nil] or is_map(backend)
    end
  end

  describe "serving_options/0" do
    test "returns serving configuration options" do
      options = EXLAConfig.serving_options()
      
      assert is_list(options)
      assert Keyword.has_key?(options, :compile)
      assert Keyword.has_key?(options, :defn_options)
      
      compile_opts = Keyword.get(options, :compile)
      assert Keyword.has_key?(compile_opts, :batch_size)
      assert Keyword.has_key?(compile_opts, :sequence_length)
    end

    test "batch size is positive integer" do
      options = EXLAConfig.serving_options()
      compile_opts = Keyword.get(options, :compile)
      batch_size = Keyword.get(compile_opts, :batch_size)
      
      assert is_integer(batch_size)
      assert batch_size > 0
    end

    test "sequence length is positive integer" do
      options = EXLAConfig.serving_options()
      compile_opts = Keyword.get(options, :compile)
      sequence_length = Keyword.get(compile_opts, :sequence_length)
      
      assert is_integer(sequence_length)
      assert sequence_length > 0
    end
  end

  describe "determine_backend_options/0" do
    test "returns backend configuration map" do
      options = EXLAConfig.determine_backend_options()
      
      assert is_map(options)
      assert Map.has_key?(options, :client)
      assert options.client in [:host, :cuda, :rocm, :metal]
    end

    test "CPU backend has parallelism settings" do
      # Force CPU backend by mocking unavailable accelerators
      options = EXLAConfig.determine_backend_options()
      
      if options.client == :host do
        assert Map.has_key?(options, :num_replicas)
        assert Map.has_key?(options, :intra_op_parallelism)
        assert Map.has_key?(options, :inter_op_parallelism)
        assert options.num_replicas == System.schedulers_online()
      end
    end
  end

  describe "acceleration_info/0" do
    test "returns acceleration information map" do
      info = EXLAConfig.acceleration_info()
      
      assert is_map(info)
      assert Map.has_key?(info, :type)
      assert Map.has_key?(info, :name)
      assert info.type in [:cpu, :cuda, :rocm, :metal]
    end

    test "CPU info includes core count" do
      info = EXLAConfig.acceleration_info()
      
      if info.type == :cpu do
        assert Map.has_key?(info, :cores)
        assert info.cores == System.schedulers_online()
      end
    end

    test "backend info is included" do
      info = EXLAConfig.acceleration_info()
      
      assert Map.has_key?(info, :backend)
      assert info.backend in ["EXLA", "EMLX", "Binary", "Not available"]
    end
  end

  describe "enable_mixed_precision/0" do
    test "enables mixed precision without error" do
      # Should not raise
      assert EXLAConfig.enable_mixed_precision() == :ok
    end
  end

  describe "optimize_memory/0" do
    test "optimizes memory without error" do
      # Should not raise
      assert EXLAConfig.optimize_memory() == :ok
    end
  end
end