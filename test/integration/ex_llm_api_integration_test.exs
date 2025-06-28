defmodule ExLLM.APIIntegrationTest do
  use ExUnit.Case
  doctest ExLLM

  @moduletag :integration

  test "supported_providers includes anthropic" do
    assert :anthropic in ExLLM.supported_providers()
  end

  test "supported_providers includes xai" do
    assert :xai in ExLLM.supported_providers()
  end

  test "can get default model for anthropic" do
    model = ExLLM.default_model(:anthropic)
    assert is_binary(model)
  end

  test "configured? returns boolean for anthropic" do
    result = ExLLM.configured?(:anthropic)
    assert is_boolean(result)
  end

  test "list_models returns ok tuple for anthropic" do
    assert {:ok, models} = ExLLM.list_models(:anthropic)
    assert is_list(models)
  end

  test "can get default model for xai" do
    model = ExLLM.default_model(:xai)
    assert is_binary(model)
    assert model == "grok-3"
  end

  test "configured? returns boolean for xai" do
    result = ExLLM.configured?(:xai)
    assert is_boolean(result)
  end

  test "list_models returns ok tuple for xai" do
    assert {:ok, models} = ExLLM.list_models(:xai)
    assert is_list(models)
    assert length(models) > 0
  end
end
