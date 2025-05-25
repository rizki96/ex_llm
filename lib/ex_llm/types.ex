defmodule ExLLM.Types do
  @moduledoc """
  Shared type definitions used across ExLLM modules.

  This module contains struct definitions and types that are used by multiple
  modules, helping to avoid circular dependencies.
  """

  # Type definitions must come first
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

  @type pricing :: %{
          input_cost_per_token: float() | nil,
          output_cost_per_token: float() | nil,
          currency: String.t()
        }

  @type adapter_options :: keyword()

  @type stream :: Enumerable.t()

  defmodule LLMResponse do
    @moduledoc """
    Standard response format from LLM adapters.
    """
    defstruct [:content, :model, :usage, :finish_reason, :id]

    @type t :: %__MODULE__{
            content: String.t(),
            model: String.t() | nil,
            usage: ExLLM.Types.token_usage() | nil,
            finish_reason: String.t() | nil,
            id: String.t() | nil
          }
  end

  defmodule StreamChunk do
    @moduledoc """
    Represents a chunk from a streaming LLM response.
    """
    defstruct [:content, :finish_reason, :model, :id]

    @type t :: %__MODULE__{
            content: String.t() | nil,
            finish_reason: String.t() | nil,
            model: String.t() | nil,
            id: String.t() | nil
          }
  end

  defmodule Model do
    @moduledoc """
    Represents an available LLM model.
    """
    defstruct [:id, :name, :description, :context_window, :pricing]

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t() | nil,
            description: String.t() | nil,
            context_window: non_neg_integer() | nil,
            pricing: ExLLM.Types.pricing() | nil
          }
  end
end
