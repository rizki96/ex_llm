defmodule ExLLM.Plugs.ValidateMessagesTest do
  use ExUnit.Case, async: true

  alias ExLLM.Pipeline.Request
  alias ExLLM.Plugs.ValidateMessages
  alias ExLLM.Providers.Shared.MessageFormatter

  test "call/2 with valid messages passes the request through" do
    messages = [%{role: "user", content: "Hello"}]
    request = Request.new(:openai, messages)

    # This test relies on the real MessageFormatter implementation.
    # We assert its behavior here to make the test's assumption explicit.
    assert MessageFormatter.validate_messages(messages) == :ok

    result = ValidateMessages.call(request, [])

    assert result == request
    assert result.halted == false
  end

  test "call/2 with empty messages halts the pipeline" do
    request = Request.new(:openai, [])

    result = ValidateMessages.call(request, [])

    assert result.halted == true
    assert result.state == :error
    assert length(result.errors) == 1

    error = hd(result.errors)
    assert error.plug == ValidateMessages
    assert error.error == :invalid_messages
    assert error.message == "Validation error on field `messages`: cannot be empty"
    assert error.details == %{field: :messages, reason: "cannot be empty"}
  end

  test "call/2 with malformed messages halts the pipeline" do
    # A list containing a non-map element is a common malformation.
    messages = [%{role: "user", content: "Hi"}, "not a map"]
    request = Request.new(:openai, messages)

    result = ValidateMessages.call(request, [])

    assert result.halted == true
    assert result.state == :error
    assert length(result.errors) == 1

    error = hd(result.errors)
    assert error.plug == ValidateMessages
    assert error.error == :invalid_messages
    # Individual message validation fails
    assert error.details.field == :message
    # The reason is implementation-dependent, so just check it's a string.
    assert is_binary(error.details.reason)
    assert error.message == "Validation error on field `message`: #{error.details.reason}"
  end

  test "call/2 with a message missing a required key halts the pipeline" do
    # A message missing the :content key.
    messages = [%{role: "user"}]
    request = Request.new(:openai, messages)

    result = ValidateMessages.call(request, [])

    assert result.halted == true
    assert result.state == :error
    assert length(result.errors) == 1

    error = hd(result.errors)
    assert error.plug == ValidateMessages
    assert error.error == :invalid_messages
    # Individual message validation fails
    assert error.details.field == :message
    assert is_binary(error.details.reason)
  end
end
