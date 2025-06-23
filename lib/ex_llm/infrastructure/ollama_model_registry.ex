defmodule ExLLM.Infrastructure.OllamaModelRegistry do
  @moduledoc """
  A GenServer that provides cached access to Ollama model details.

  This registry fetches model information from three sources in order:
  1. An in-memory cache with a configurable TTL.
  2. The static `ModelConfig` YAML files.
  3. The Ollama `/api/show` endpoint.

  This reduces redundant API calls and provides a consistent way to access
  model capabilities and context window sizes.
  """

  use GenServer

  alias ExLLM.Infrastructure.Config.ModelConfig
  alias ExLLM.Providers.Ollama

  # Cache TTL of 1 hour
  @ttl :timer.hours(1)

  # --- Client API ---

  @doc """
  Starts the OllamaModelRegistry GenServer.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Retrieves details for a specific Ollama model.

  The function follows a fallback mechanism:
  1. Checks the local cache.
  2. Checks the static `ModelConfig`.
  3. Queries the Ollama API.

  Returns `{:ok, details}` or `{:error, reason}`.
  The details map has the shape:
  `%{context_window: integer, capabilities: list(string())}`
  """
  def get_model_details(model_name) when is_binary(model_name) do
    GenServer.call(__MODULE__, {:get_model_details, model_name})
  end

  @doc """
  Clears the in-memory model cache. Useful for testing.
  """
  def clear_cache do
    GenServer.cast(__MODULE__, :clear_cache)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    # The state is a map of model_name -> {timestamp, details}
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get_model_details, model_name}, _from, state) do
    now = System.system_time(:millisecond)

    case Map.get(state, model_name) do
      {timestamp, details} when now - timestamp < @ttl ->
        # Cache hit and not expired
        {:reply, {:ok, details}, state}

      _ ->
        # Cache miss or expired, fetch details
        case fetch_and_cache_details(model_name, state) do
          {:ok, details, new_state} ->
            {:reply, {:ok, details}, new_state}

          {{:error, _reason} = error, new_state} ->
            {:reply, error, new_state}
        end
    end
  end

  @impl true
  def handle_cast(:clear_cache, _state) do
    {:noreply, %{}}
  end

  # --- Private Helper Functions ---

  defp fetch_and_cache_details(model_name, state) do
    case fetch_from_sources(model_name) do
      {:ok, details} ->
        new_state = Map.put(state, model_name, {System.system_time(:millisecond), details})
        {:ok, details, new_state}

      {:error, _reason} = error ->
        {error, state}
    end
  end

  defp fetch_from_sources(model_name) do
    # 1. Try ModelConfig first
    case get_from_model_config(model_name) do
      {:ok, details} ->
        {:ok, details}

      :not_found ->
        # 2. Fallback to Ollama API
        get_from_api(model_name)
    end
  end

  defp get_from_model_config(model_name) do
    case ModelConfig.get_model_config(:ollama, model_name) do
      nil ->
        :not_found

      config ->
        details = %{
          context_window: Map.get(config, :context_window),
          capabilities: Map.get(config, :capabilities, []) |> Enum.map(&to_string/1)
        }

        {:ok, details}
    end
  end

  defp get_from_api(model_name) do
    case Ollama.show_model(model_name) do
      {:ok, api_response} ->
        {:ok, parse_api_response(model_name, api_response)}

      {:error, reason} ->
        {:error, {:api_fetch_failed, reason}}
    end
  end

  defp parse_api_response(model_name, details) do
    capabilities = details["capabilities"] || []

    context_window =
      case details["model_info"] do
        nil -> 4096
        info -> get_context_from_model_info(info) || 4096
      end

    cap_list = ["streaming"]

    cap_list =
      if "tools" in capabilities || ("completion" in capabilities && "tools" in capabilities) do
        ["function_calling" | cap_list]
      else
        cap_list
      end

    cap_list =
      if "embedding" in capabilities do
        ["embeddings" | cap_list]
      else
        cap_list
      end

    cap_list =
      if is_vision_model?(model_name) do
        ["vision" | cap_list]
      else
        cap_list
      end

    %{
      context_window: context_window,
      capabilities: Enum.sort(cap_list)
      # max_output_tokens is not available from Ollama's API
    }
  end

  defp get_context_from_model_info(model_info) when is_map(model_info) do
    model_info["qwen3.context_length"] ||
      model_info["llama.context_length"] ||
      model_info["bert.context_length"] ||
      model_info["mistral.context_length"] ||
      model_info["gemma.context_length"] ||
      nil
  end

  defp get_context_from_model_info(_), do: nil

  defp is_vision_model?(model_name) do
    String.contains?(model_name, "vision") ||
      String.contains?(model_name, "llava") ||
      String.contains?(model_name, "bakllava")
  end
end
