defmodule ExLLMTest do
  use ExUnit.Case
  doctest ExLLM

  test "supported_providers includes anthropic" do
    assert :anthropic in ExLLM.supported_providers()
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
end
