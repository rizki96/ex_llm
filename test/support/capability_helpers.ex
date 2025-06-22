defmodule ExLLM.Testing.CapabilityHelpers do
  @moduledoc """
  Test helpers for capability-based testing.

  Provides functions to conditionally run tests based on provider capabilities,
  preventing false confidence from tests that accept errors for unsupported features.

  ## Usage

  The recommended approach is to use setup callbacks to check capabilities:

      defmodule MyProviderTest do
        use ExUnit.Case
        import ExLLM.Testing.CapabilityHelpers
        
        setup do
          skip_unless_supports(:my_provider, :chat)
          :ok
        end
        
        test "basic chat functionality" do
          # This test will be skipped if provider doesn't support chat
        end
      end
  """

  @doc """
  Skip test if provider doesn't support the required capability.

  Returns `{:skip, reason}` if the provider lacks the capability, otherwise `:ok`.
  """
  def skip_unless_supports(provider, capability) do
    if ExLLM.Capabilities.supports?(provider, capability) do
      :ok
    else
      {:skip, "Provider #{provider} does not support #{capability}"}
    end
  end

  @doc """
  Skip test if provider is not configured or doesn't support capability.

  Returns `{:skip, reason}` if the provider is not configured or lacks the
  capability, otherwise `:ok`.
  """
  def skip_unless_configured_and_supports(provider, capability) do
    cond do
      !ExLLM.Capabilities.supports?(provider, capability) ->
        {:skip, "Provider #{provider} does not support #{capability}"}

      !ExLLM.configured?(provider) ->
        {:skip, "Provider #{provider} is not configured"}

      true ->
        :ok
    end
  end

  @doc """
  Get a list of providers that support a capability for parameterized tests.

  ## Examples

      for provider <- providers_supporting(:vision) do
        # Test vision functionality with this provider
      end
  """
  def providers_supporting(capability) do
    ExLLM.Capabilities.providers_with_capability(capability)
  end

  @doc """
  Check if we should expect a feature to work based on capability and configuration.
  """
  def should_work?(provider, capability) do
    ExLLM.configured?(provider) and ExLLM.Capabilities.supports?(provider, capability)
  end

  @doc """
  Macro to conditionally define tests based on provider capabilities.

  ## Examples

      if_provider_supports :openai, :vision do
        test "vision functionality works" do
          # This test only exists if OpenAI supports vision
        end
      end
  """
  defmacro if_provider_supports(provider, capability, do: block) do
    if ExLLM.Capabilities.supports?(provider, capability) do
      block
    else
      # Return empty AST - test won't be defined
      quote do: nil
    end
  end
end
