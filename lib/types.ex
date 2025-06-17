defmodule ExLLM.Types do
  @moduledoc """
  Shared type definitions used across ExLLM modules.

  This module contains struct definitions and types that are used by multiple
  modules, helping to avoid circular dependencies.
  """

  # Type definitions must come first
  @type message :: %{
          required(:role) => String.t(),
          required(:content) => String.t() | list(content_part()),
          optional(:timestamp) => DateTime.t(),
          optional(atom()) => any()
        }

  @type content_part :: text_content() | image_content()

  @type text_content :: %{
          type: :text,
          text: String.t()
        }

  @type image_content :: %{
          type: :image_url | :image,
          image_url: image_url() | nil,
          image: image_data() | nil
        }

  @type image_url :: %{
          url: String.t(),
          detail: :auto | :low | :high | nil
        }

  @type image_data :: %{
          # Base64 encoded image
          data: String.t(),
          # e.g., "image/jpeg", "image/png"
          media_type: String.t()
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

  @type provider_options :: keyword()

  @type stream :: Enumerable.t()

  @type cost_result :: %{
          provider: String.t(),
          model: String.t(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          total_tokens: non_neg_integer(),
          input_cost: float(),
          output_cost: float(),
          total_cost: float(),
          currency: String.t(),
          pricing: %{input: float(), output: float()}
        }

  defmodule LLMResponse do
    @moduledoc """
    Standard response format from LLM providers with integrated cost calculation.
    """
    defstruct [
      :content,
      :model,
      :usage,
      :finish_reason,
      :id,
      :cost,
      :function_call,
      :tool_calls,
      :refusal,
      :logprobs,
      :metadata
    ]

    @type t :: %__MODULE__{
            content: String.t() | nil,
            model: String.t() | nil,
            usage: ExLLM.Types.token_usage() | nil,
            finish_reason: String.t() | nil,
            id: String.t() | nil,
            cost: ExLLM.Types.cost_result() | nil,
            function_call: map() | nil,
            tool_calls: list(map()) | nil,
            refusal: String.t() | nil,
            logprobs: map() | nil,
            metadata: map() | nil
          }
  end

  defmodule StreamChunk do
    @moduledoc """
    Represents a chunk from a streaming LLM response.
    """
    defstruct [:content, :finish_reason, :model, :id, :metadata]

    @type t :: %__MODULE__{
            content: String.t() | nil,
            finish_reason: String.t() | nil,
            model: String.t() | nil,
            id: String.t() | nil,
            metadata: map() | nil
          }
  end

  defmodule Model do
    @moduledoc """
    Represents an available LLM model.
    """
    defstruct [
      :id,
      :name,
      :description,
      :context_window,
      :pricing,
      :capabilities,
      :max_output_tokens
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t() | nil,
            description: String.t() | nil,
            context_window: non_neg_integer() | nil,
            pricing: ExLLM.Types.pricing() | nil,
            capabilities: map() | nil,
            max_output_tokens: non_neg_integer() | nil
          }
  end

  defmodule EmbeddingResponse do
    @moduledoc """
    Represents an embedding response from an LLM provider.
    """
    defstruct [:embeddings, :model, :usage, :cost, :metadata]

    @type t :: %__MODULE__{
            embeddings: list(list(float())),
            model: String.t(),
            usage: ExLLM.Types.token_usage() | nil,
            cost: ExLLM.Types.cost_result() | nil,
            metadata: map() | nil
          }
  end

  defmodule EmbeddingModel do
    @moduledoc """
    Represents an available embedding model.
    """
    defstruct [:name, :dimensions, :max_inputs, :provider, :description, :pricing]

    @type t :: %__MODULE__{
            name: String.t(),
            dimensions: non_neg_integer(),
            max_inputs: non_neg_integer() | nil,
            provider: atom(),
            description: String.t() | nil,
            pricing: ExLLM.Types.pricing() | nil
          }
  end

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
            messages: [ExLLM.Types.message()],
            context: %{optional(atom()) => any()},
            created_at: DateTime.t(),
            updated_at: DateTime.t(),
            token_usage: ExLLM.Types.token_usage() | nil,
            name: String.t() | nil
          }
  end
end
