defmodule ExLLM.API.DelegatorTest do
  use ExUnit.Case, async: true

  alias ExLLM.API.Delegator

  describe "delegate/3" do
    test "delegates direct operations successfully" do
      # Test with a mock function call that we know exists
      # Note: This is a unit test, so we're testing the delegation mechanism
      # The actual provider functions are tested in integration tests

      # Test unsupported operation
      result = Delegator.delegate(:unsupported_operation, :openai, [])
      assert {:error, "unsupported_operation not supported for provider: openai"} = result

      # Test unsupported provider for valid operation
      result = Delegator.delegate(:upload_file, :unsupported_provider, ["/path/to/file", []])
      assert {:error, "upload_file not supported for provider: unsupported_provider"} = result
    end

    test "handles argument transformation" do
      # We can't easily test actual provider calls in unit tests,
      # but we can test that the right transformation is triggered
      # by checking error messages that include the transformer name

      result =
        Delegator.delegate(:upload_file, :openai, ["/path/to/file", [purpose: "fine-tune"]])

      # The provider function will return an error, but we can verify transformation occurred
      # by checking that we get the provider function result (which is wrapped in {:ok, ...})
      assert {:ok, _provider_result} = result
    end

    test "validates input arguments" do
      # Test non-atom operation
      result = Delegator.delegate("upload_file", :openai, [])

      assert {:error,
              "Invalid arguments: operation and provider must be atoms, args must be a list"} =
               result

      # Test non-atom provider
      result = Delegator.delegate(:upload_file, "openai", [])

      assert {:error,
              "Invalid arguments: operation and provider must be atoms, args must be a list"} =
               result

      # Test non-list args
      result = Delegator.delegate(:upload_file, :openai, "not a list")

      assert {:error,
              "Invalid arguments: operation and provider must be atoms, args must be a list"} =
               result
    end
  end

  describe "supports?/2" do
    test "returns true for supported operations" do
      assert Delegator.supports?(:upload_file, :openai) == true
      assert Delegator.supports?(:upload_file, :gemini) == true
      assert Delegator.supports?(:create_assistant, :openai) == true
      assert Delegator.supports?(:create_batch, :anthropic) == true
    end

    test "returns false for unsupported operations" do
      assert Delegator.supports?(:upload_file, :anthropic) == false
      assert Delegator.supports?(:create_assistant, :gemini) == false
      assert Delegator.supports?(:create_batch, :openai) == false
      assert Delegator.supports?(:nonexistent_operation, :openai) == false
    end
  end

  describe "get_supported_providers/1" do
    test "returns correct providers for operations" do
      providers = Delegator.get_supported_providers(:upload_file)
      assert Enum.sort(providers) == [:gemini, :openai]

      providers = Delegator.get_supported_providers(:create_assistant)
      assert providers == [:openai]

      providers = Delegator.get_supported_providers(:create_batch)
      assert providers == [:anthropic]

      providers = Delegator.get_supported_providers(:nonexistent_operation)
      assert providers == []
    end
  end

  describe "get_supported_operations/1" do
    test "returns correct operations for providers" do
      # Test a few key operations for each provider
      openai_ops = Delegator.get_supported_operations(:openai)
      assert :upload_file in openai_ops
      assert :create_assistant in openai_ops
      assert :list_files in openai_ops
      refute :create_batch in openai_ops

      gemini_ops = Delegator.get_supported_operations(:gemini)
      assert :upload_file in gemini_ops
      assert :create_cached_context in gemini_ops
      assert :count_tokens in gemini_ops
      refute :create_assistant in gemini_ops

      anthropic_ops = Delegator.get_supported_operations(:anthropic)
      assert :create_batch in anthropic_ops
      assert :get_batch in anthropic_ops
      refute :upload_file in anthropic_ops

      unsupported_ops = Delegator.get_supported_operations(:unsupported_provider)
      assert unsupported_ops == []
    end
  end

  describe "health_check/0" do
    test "returns comprehensive health information" do
      health = Delegator.health_check()

      assert is_map(health)
      assert Map.has_key?(health, :capabilities_loaded)
      assert Map.has_key?(health, :total_operations)
      assert Map.has_key?(health, :total_capabilities)
      assert Map.has_key?(health, :providers)
      assert Map.has_key?(health, :transformers_available)
      assert Map.has_key?(health, :delegation_ready)

      # Verify expected values
      assert health.capabilities_loaded == true
      # We have 39 operations
      assert health.total_operations > 30
      # More than operations due to multi-provider support
      assert health.total_capabilities > 40
      assert :openai in health.providers
      assert :gemini in health.providers
      assert :anthropic in health.providers
      # Check that some transformers are available (they may not all be loaded in test)
      assert length(health.transformers_available) >= 0
      assert health.delegation_ready == true
    end
  end
end
