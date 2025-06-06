defmodule ExLLM.Local.EXLAConfig do
  @moduledoc """
  Configuration module for EXLA/EMLX backend optimization.

  Provides optimal settings for CPU and GPU inference, including Apple Silicon support.
  This module automatically detects available hardware acceleration and configures
  the appropriate backend for best performance.

  ## Supported Backends

  - **EMLX** - Apple Silicon (Metal) acceleration
  - **CUDA** - NVIDIA GPU acceleration
  - **ROCm** - AMD GPU acceleration  
  - **CPU** - Optimized CPU inference

  ## Features

  - Automatic hardware detection
  - Mixed precision support
  - Memory optimization
  - Dynamic batch sizing
  - Parallel execution configuration
  """

  alias ExLLM.Logger

  @doc """
  Configure EXLA/EMLX backend with optimal settings based on available hardware.

  Returns `{:ok, backend}` where backend is `:emlx`, `:cuda`, `:rocm`, `:cpu`, or `:binary`.
  """
  def configure_backend() do
    cond do
      # Prefer EMLX for Apple Silicon
      metal_available?() and Code.ensure_loaded?(EMLX) ->
        Logger.info("EMLX backend configured for Apple Silicon")
        Application.put_env(:nx, :default_backend, EMLX.Backend)
        {:ok, :emlx}

      Code.ensure_loaded?(EXLA) ->
        backend_opts = determine_backend_options()

        Application.put_env(:nx, :default_backend, {EXLA.Backend, backend_opts})

        Application.put_env(:nx, :default_defn_options,
          compiler: EXLA,
          client: backend_opts[:client]
        )

        Logger.info("EXLA backend configured: #{inspect(backend_opts)}")
        {:ok, backend_opts}

      true ->
        Logger.warn("EXLA/EMLX not available, falling back to binary backend")
        {:ok, :binary}
    end
  end

  @doc """
  Get optimal compiler options for model serving.

  Returns keyword list of options for Bumblebee serving configuration.
  """
  def serving_options() do
    cond do
      # EMLX for Apple Silicon
      metal_available?() and Code.ensure_loaded?(EMLX) ->
        [
          compile: [
            batch_size: get_optimal_batch_size(),
            sequence_length: get_optimal_sequence_length()
          ],
          defn_options: [
            compiler: EMLX
          ],
          # Enable memory optimization
          preallocate_params: true
        ]

      Code.ensure_loaded?(EXLA) ->
        backend_opts = determine_backend_options()

        [
          compile: [
            batch_size: get_optimal_batch_size(),
            sequence_length: get_optimal_sequence_length()
          ],
          defn_options: [
            compiler: EXLA,
            client: backend_opts[:client]
          ],
          # Enable memory optimization
          preallocate_params: true
        ]

      true ->
        [
          compile: [
            batch_size: 1,
            sequence_length: 512
          ],
          defn_options: [
            compiler: Nx.BinaryBackend
          ]
        ]
    end
  end

  @doc """
  Determine optimal backend options based on available hardware.

  Returns a map of backend configuration options.
  """
  def determine_backend_options() do
    cond do
      cuda_available?() ->
        %{
          client: :cuda,
          device_id: 0,
          memory_fraction: 0.9,
          preallocate: true
        }

      rocm_available?() ->
        %{
          client: :rocm,
          device_id: 0,
          memory_fraction: 0.9
        }

      metal_available?() ->
        %{
          client: :metal,
          device_id: 0
        }

      true ->
        # CPU optimization
        %{
          client: :host,
          num_replicas: System.schedulers_online(),
          intra_op_parallelism: System.schedulers_online(),
          inter_op_parallelism: 2
        }
    end
  end

  @doc """
  Get information about available acceleration.

  Returns a map with acceleration details including type, name, and capabilities.
  """
  def acceleration_info() do
    cond do
      cuda_available?() ->
        %{
          type: :cuda,
          name: "NVIDIA CUDA",
          device_count: cuda_device_count(),
          memory: cuda_memory_info(),
          backend: if(Code.ensure_loaded?(EXLA), do: "EXLA", else: "Not available")
        }

      rocm_available?() ->
        %{
          type: :rocm,
          name: "AMD ROCm",
          device_count: 1,
          backend: if(Code.ensure_loaded?(EXLA), do: "EXLA", else: "Not available")
        }

      metal_available?() ->
        backend =
          cond do
            Code.ensure_loaded?(EMLX) -> "EMLX"
            Code.ensure_loaded?(EXLA) -> "EXLA"
            true -> "Not available"
          end

        %{
          type: :metal,
          name: "Apple Metal",
          device_count: 1,
          backend: backend,
          memory: metal_memory_info()
        }

      true ->
        %{
          type: :cpu,
          name: "CPU",
          cores: System.schedulers_online(),
          backend: if(Code.ensure_loaded?(EXLA), do: "EXLA", else: "Binary")
        }
    end
  end

  @doc """
  Enable mixed precision training/inference for better performance.
  """
  def enable_mixed_precision() do
    cond do
      Code.ensure_loaded?(EMLX) ->
        # EMLX automatically handles mixed precision on Apple Silicon
        Logger.info("EMLX handles mixed precision automatically on Apple Silicon")

      Code.ensure_loaded?(EXLA) ->
        # Enable automatic mixed precision
        Application.put_env(:exla, :mixed_precision, true)
        Application.put_env(:exla, :preferred_dtype, {:f, 16})
        Logger.info("Mixed precision enabled for better performance")

      true ->
        :ok
    end
  end

  @doc """
  Optimize memory usage for large models.
  """
  def optimize_memory() do
    cond do
      Code.ensure_loaded?(EMLX) ->
        # EMLX uses unified memory efficiently on Apple Silicon
        Logger.info("EMLX optimizes unified memory usage on Apple Silicon")

      Code.ensure_loaded?(EXLA) ->
        # Enable gradient checkpointing and memory optimizations
        Application.put_env(:exla, :allocator, :best_fit)
        Application.put_env(:exla, :memory_fraction, 0.9)
        Logger.info("Memory optimizations enabled")

      true ->
        :ok
    end
  end

  # Private functions

  defp cuda_available? do
    Code.ensure_loaded?(EXLA) and
      System.get_env("CUDA_VISIBLE_DEVICES") != "-1" and
      check_cuda_runtime()
  end

  defp check_cuda_runtime() do
    try do
      {output, 0} =
        System.cmd("nvidia-smi", ["--query-gpu=name", "--format=csv,noheader"],
          stderr_to_stdout: true
        )

      String.trim(output) != ""
    rescue
      _ -> false
    end
  end

  defp cuda_device_count() do
    try do
      {output, 0} =
        System.cmd("nvidia-smi", ["--query-gpu=count", "--format=csv,noheader"],
          stderr_to_stdout: true
        )

      String.to_integer(String.trim(output))
    rescue
      _ -> 0
    end
  end

  defp cuda_memory_info() do
    try do
      {output, 0} =
        System.cmd("nvidia-smi", ["--query-gpu=memory.total", "--format=csv,noheader,nounits"],
          stderr_to_stdout: true
        )

      memory_mb = String.to_integer(String.trim(output))
      %{total_mb: memory_mb, total_gb: Float.round(memory_mb / 1_024, 2)}
    rescue
      _ -> %{total_mb: 0, total_gb: 0}
    end
  end

  defp rocm_available? do
    Code.ensure_loaded?(EXLA) and
      System.get_env("ROCM_PATH") != nil and
      File.exists?("/opt/rocm/bin/rocminfo")
  end

  defp metal_available? do
    :os.type() == {:unix, :darwin} and
      System.get_env("DISABLE_METAL") != "1"
  end

  defp metal_memory_info() do
    # Try to get unified memory info on macOS
    try do
      {output, 0} = System.cmd("sysctl", ["hw.memsize"], stderr_to_stdout: true)

      total_bytes =
        output
        |> String.trim()
        |> String.split(": ")
        |> List.last()
        |> String.to_integer()

      total_mb = div(total_bytes, 1_048_576)
      %{total_mb: total_mb, total_gb: Float.round(total_mb / 1_024, 2)}
    rescue
      _ -> %{total_mb: 0, total_gb: 0}
    end
  end

  defp get_optimal_batch_size() do
    # Adjust based on available memory
    case acceleration_info().type do
      :cuda ->
        memory_gb = cuda_memory_info().total_gb

        cond do
          memory_gb >= 24 -> 8
          memory_gb >= 16 -> 4
          memory_gb >= 8 -> 2
          true -> 1
        end

      :metal ->
        # Apple Silicon unified memory allows for good batch sizes
        memory_gb = metal_memory_info().total_gb

        cond do
          memory_gb >= 64 -> 8
          memory_gb >= 32 -> 4
          memory_gb >= 16 -> 2
          true -> 1
        end

      _ ->
        1
    end
  end

  defp get_optimal_sequence_length() do
    # Adjust based on model and memory
    case acceleration_info().type do
      :cuda ->
        memory_gb = cuda_memory_info().total_gb

        cond do
          memory_gb >= 24 -> 2048
          memory_gb >= 16 -> 1_536
          memory_gb >= 8 -> 1_024
          true -> 512
        end

      :metal ->
        # Apple Silicon can handle good sequence lengths
        memory_gb = metal_memory_info().total_gb

        cond do
          memory_gb >= 64 -> 4_096
          memory_gb >= 32 -> 2_048
          memory_gb >= 16 -> 1_536
          true -> 1_024
        end

      _ ->
        512
    end
  end
end
