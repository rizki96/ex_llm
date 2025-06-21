defmodule ExLLM.API.Delegator do
  @moduledoc """
  Central delegation engine for the unified API.

  This module handles the delegation of operation calls to appropriate
  provider modules, including argument transformation when needed.
  """

  alias ExLLM.API.{Capabilities, Transformers}

  @doc """
  Delegate an operation to the appropriate provider.

  ## Parameters
  - `operation` - The operation atom (e.g., :upload_file, :create_fine_tune)
  - `provider` - The provider atom (e.g., :openai, :gemini, :anthropic)  
  - `args` - List of arguments to pass to the provider function

  ## Returns
  - `{:ok, result}` on success
  - `{:error, reason}` on failure or unsupported operation

  ## Examples
      
      # Direct delegation (no transformation)
      {:ok, files} = ExLLM.API.Delegator.delegate(:list_files, :openai, [opts])
      
      # With argument transformation  
      {:ok, file} = ExLLM.API.Delegator.delegate(:upload_file, :openai, [file_path, opts])
      
      # Unsupported operation
      {:error, "upload_file not supported for provider: anthropic"} = 
        ExLLM.API.Delegator.delegate(:upload_file, :anthropic, [file_path, opts])
  """
  @spec delegate(atom(), atom(), [term()]) :: {:ok, term()} | {:error, String.t()}
  def delegate(operation, provider, args)
      when is_atom(operation) and is_atom(provider) and is_list(args) do
    case Capabilities.get_capability(operation, provider) do
      {module, function, :direct} ->
        # Direct delegation - no argument transformation
        apply_provider_function(module, function, args)

      {module, function, transformer} when is_atom(transformer) ->
        # Apply argument transformation before delegation
        case apply_transformer(transformer, args) do
          {:ok, transformed_args} ->
            apply_provider_function(module, function, transformed_args)

          {:error, _reason} = error ->
            error
        end

      nil ->
        {:error, "#{operation} not supported for provider: #{provider}"}
    end
  end

  def delegate(_operation, _provider, _args) do
    {:error, "Invalid arguments: operation and provider must be atoms, args must be a list"}
  end

  @doc """
  Check if a provider supports a specific operation.

  This is a convenience function that delegates to Capabilities.supports?/2.
  """
  @spec supports?(atom(), atom()) :: boolean()
  def supports?(operation, provider) do
    Capabilities.supports?(operation, provider)
  end

  @doc """
  Get all providers that support a specific operation.

  This is a convenience function that delegates to Capabilities.get_providers/1.
  """
  @spec get_supported_providers(atom()) :: [atom()]
  def get_supported_providers(operation) do
    Capabilities.get_providers(operation)
  end

  @doc """
  Get all operations supported by a specific provider.

  This is a convenience function that delegates to Capabilities.get_operations/1.
  """
  @spec get_supported_operations(atom()) :: [atom()]
  def get_supported_operations(provider) do
    Capabilities.get_operations(provider)
  end

  # Private functions

  defp apply_provider_function(module, function, args) do
    try do
      result = apply(module, function, args)
      {:ok, result}
    rescue
      error ->
        {:error,
         %{
           reason: :provider_function_error,
           message: "Error calling #{inspect(module)}.#{function}: #{inspect(error)}",
           module: module,
           function: function,
           args_count: length(args)
         }}
    catch
      :throw, value ->
        {:error,
         %{
           reason: :provider_function_throw,
           message: "Throw from #{inspect(module)}.#{function}: #{inspect(value)}",
           module: module,
           function: function
         }}

      :exit, reason ->
        {:error,
         %{
           reason: :provider_function_exit,
           message: "Exit from #{inspect(module)}.#{function}: #{inspect(reason)}",
           module: module,
           function: function
         }}
    end
  end

  defp apply_transformer(transformer, args) do
    try do
      transformed_args = apply(Transformers, transformer, [args])
      {:ok, transformed_args}
    rescue
      error ->
        {:error,
         %{
           reason: :transformer_error,
           message: "Error in transformer #{transformer}: #{inspect(error)}",
           transformer: transformer,
           original_args: args
         }}
    catch
      :throw, value ->
        {:error,
         %{
           reason: :transformer_throw,
           message: "Throw in transformer #{transformer}: #{inspect(value)}",
           transformer: transformer
         }}

      :exit, reason ->
        {:error,
         %{
           reason: :transformer_exit,
           message: "Exit in transformer #{transformer}: #{inspect(reason)}",
           transformer: transformer
         }}
    end
  end

  @doc """
  Get delegation statistics and health information.

  Useful for monitoring and debugging the delegation system.
  """
  @spec health_check() :: %{
          capabilities_loaded: boolean(),
          total_operations: non_neg_integer(),
          total_capabilities: non_neg_integer(),
          providers: [atom()],
          transformers_available: [atom()],
          delegation_ready: boolean()
        }
  def health_check do
    capabilities_stats = Capabilities.stats()

    # Check if transformer functions are available
    transformer_functions = [
      :transform_upload_args,
      :preprocess_gemini_tuning,
      :preprocess_openai_tuning
    ]

    transformers_available =
      Enum.filter(transformer_functions, fn func ->
        function_exported?(Transformers, func, 1)
      end)

    %{
      capabilities_loaded: capabilities_stats.total_operations > 0,
      total_operations: capabilities_stats.total_operations,
      total_capabilities: capabilities_stats.total_capabilities,
      providers: capabilities_stats.providers,
      transformers_available: transformers_available,
      delegation_ready: capabilities_stats.total_operations > 0
    }
  end
end
