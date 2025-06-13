defmodule ExLLM.Test.ConfigProviderHelper do
  @moduledoc """
  Helper for setting up static config providers in tests.

  This helper ensures that the Static config provider is properly started
  and returns the PID for use in tests.
  """

  @doc """
  Starts a Static config provider with the given config and returns the PID.

  ## Examples

      config = %{openai: %{api_key: "test-key"}}
      provider = ConfigProviderHelper.setup_static_provider(config)
      # provider is a PID that can be used with config_provider option
  """
  def setup_static_provider(config) do
    {:ok, pid} = ExLLM.ConfigProvider.Static.start_link(config)
    pid
  end
end
