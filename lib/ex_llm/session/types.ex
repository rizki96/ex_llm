defmodule ExLLM.Session.Types do
  @moduledoc """
  Type definitions for ExLLM.Session.
  """

  @type message :: %{
          required(:role) => String.t(),
          required(:content) => String.t(),
          optional(:timestamp) => DateTime.t(),
          optional(atom()) => any()
        }

  @type token_usage :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer()
        }

  @type context :: %{optional(atom()) => any()}

  defmodule Session do
    @moduledoc """
    Represents a conversation session with message history and metadata.
    """

    @enforce_keys [:id, :created_at, :updated_at]
    defstruct [
      :id,
      :llm_backend,
      :messages,
      :context,
      :created_at,
      :updated_at,
      :token_usage,
      :name
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            llm_backend: String.t() | nil,
            messages: [ExLLM.Session.Types.message()],
            context: ExLLM.Session.Types.context(),
            created_at: DateTime.t(),
            updated_at: DateTime.t(),
            token_usage: ExLLM.Session.Types.token_usage() | nil,
            name: String.t() | nil
          }
  end
end