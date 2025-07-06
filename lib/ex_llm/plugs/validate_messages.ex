defmodule ExLLM.Plugs.ValidateMessages do
  @moduledoc """
  Validates the message list in the request.

  This plug ensures that the `messages` field in the `ExLLM.Pipeline.Request`
  struct is a valid list of message maps before it's passed to a provider.
  It checks for common errors like an empty list or malformed messages.

  This plug extracts the common validation pattern from providers into a
  reusable component in the pipeline.

  ## Examples

      # This plug is typically used without options in a pipeline
      plug ExLLM.Plugs.ValidateMessages
  """

  use ExLLM.Plug
  alias ExLLM.Pipeline.Request
  alias ExLLM.Providers.Shared.MessageFormatter

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Request{messages: messages} = request, _opts) do
    # First normalize message keys to atoms
    normalized_messages = MessageFormatter.normalize_message_keys(messages)
    
    # Then validate the normalized messages
    case MessageFormatter.validate_messages(normalized_messages) do
      :ok ->
        # Update the request with normalized messages
        %{request | messages: normalized_messages}

      {:error, {:validation, field, reason}} ->
        error = %{
          plug: __MODULE__,
          error: :invalid_messages,
          message: "Validation error on field `#{field}`: #{reason}",
          details: %{field: field, reason: reason}
        }

        Request.halt_with_error(request, error)
    end
  end
end
