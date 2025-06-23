defmodule ExLLM.FineTuning do
  @moduledoc """
  Fine-tuning functionality for ExLLM.

  This module provides functions for creating, managing, and monitoring fine-tuning jobs
  across different providers like Gemini and OpenAI. Fine-tuning allows you to customize
  a model for your specific use case by training it on your own data.

  ## Supported Providers

  - **Gemini**: Create tuned models with custom datasets and hyperparameters
  - **OpenAI**: Create fine-tuning jobs for GPT models with JSONL training files

  ## Examples

      # Gemini fine-tuning
      dataset = %{
        examples: %{
          examples: [
            %{text_input: "What is AI?", output: "AI is artificial intelligence..."}
          ]
        }
      }
      {:ok, tuned_model} = ExLLM.FineTuning.create_fine_tune(:gemini, dataset, 
        base_model: "models/gemini-1.5-flash-001",
        display_name: "My Custom Model"
      )

      # OpenAI fine-tuning
      {:ok, job} = ExLLM.FineTuning.create_fine_tune(:openai, "file-abc123",
        model: "gpt-3.5-turbo",
        suffix: "my-model"
      )

      # List fine-tuning jobs
      {:ok, jobs} = ExLLM.FineTuning.list_fine_tunes(:openai)

      # Monitor a specific job
      {:ok, job_details} = ExLLM.FineTuning.get_fine_tune(:openai, "ftjob-abc123")

      # Cancel if needed
      {:ok, cancelled_job} = ExLLM.FineTuning.cancel_fine_tune(:openai, "ftjob-abc123")
  """

  alias ExLLM.API.Delegator

  @doc """
  Creates a fine-tuning job.

  Fine-tuning allows you to customize a model for your specific use case
  by training it on your own data.

  ## Parameters
    * `provider` - The LLM provider (`:gemini` or `:openai`)
    * `data` - Training data or file identifier (format varies by provider)
    * `opts` - Options for fine-tuning

  ## Options for Gemini
    * `:base_model` - Base model to tune (required)
    * `:display_name` - Human-readable name for the tuned model
    * `:description` - Description of the tuned model
    * `:temperature` - Temperature for tuning
    * `:top_p` - Top-p value for tuning
    * `:top_k` - Top-k value for tuning
    * `:candidate_count` - Number of candidates
    * `:max_output_tokens` - Maximum output tokens
    * `:stop_sequences` - Stop sequences
    * `:hyperparameters` - Training hyperparameters map
    * `:config_provider` - Configuration provider

  ## Options for OpenAI
    * `:model` - Base model to fine-tune (default: "gpt-3.5-turbo")
    * `:validation_file` - Validation file ID
    * `:hyperparameters` - Training hyperparameters
    * `:suffix` - Suffix for the fine-tuned model name
    * `:integrations` - Third-party integration settings
    * `:seed` - Random seed for training
    * `:config_provider` - Configuration provider

  ## Examples

      # Gemini fine-tuning
      dataset = %{
        examples: %{
          examples: [
            %{text_input: "What is AI?", output: "AI is artificial intelligence..."}
          ]
        }
      }
      {:ok, tuned_model} = ExLLM.FineTuning.create_fine_tune(:gemini, dataset, 
        base_model: "models/gemini-1.5-flash-001",
        display_name: "My Custom Model"
      )

      # OpenAI fine-tuning
      {:ok, job} = ExLLM.FineTuning.create_fine_tune(:openai, "file-abc123",
        model: "gpt-3.5-turbo",
        suffix: "my-model"
      )

  ## Return Value

  Returns `{:ok, result}` with the fine-tuning job or model details, or `{:error, reason}`.
  """
  @spec create_fine_tune(atom(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def create_fine_tune(provider, data, opts \\ []) do
    case Delegator.delegate(:create_fine_tune, provider, [data, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists fine-tuning jobs or tuned models.

  ## Parameters
    * `provider` - The LLM provider (`:gemini` or `:openai`)
    * `opts` - Options for listing

  ## Options for Gemini
    * `:page_size` - Number of results per page
    * `:page_token` - Token for pagination
    * `:config_provider` - Configuration provider

  ## Options for OpenAI
    * `:after` - Identifier for pagination
    * `:limit` - Number of results to return (max 100)
    * `:config_provider` - Configuration provider

  ## Examples

      # List Gemini tuned models
      {:ok, %{tuned_models: models}} = ExLLM.FineTuning.list_fine_tunes(:gemini)

      # List OpenAI fine-tuning jobs
      {:ok, %{data: jobs}} = ExLLM.FineTuning.list_fine_tunes(:openai, limit: 20)

  ## Return Value

  Returns `{:ok, response}` with the list of fine-tuning jobs or models, or `{:error, reason}`.
  """
  @spec list_fine_tunes(atom(), keyword()) :: {:ok, term()} | {:error, term()}
  def list_fine_tunes(provider, opts \\ []) do
    case Delegator.delegate(:list_fine_tunes, provider, [opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets details of a specific fine-tuning job or tuned model.

  ## Parameters
    * `provider` - The LLM provider (`:gemini` or `:openai`)
    * `id` - The fine-tuning job ID or tuned model name
    * `opts` - Options for retrieval

  ## Examples

      # Get Gemini tuned model
      {:ok, model} = ExLLM.FineTuning.get_fine_tune(:gemini, "tunedModels/my-model-abc123")

      # Get OpenAI fine-tuning job
      {:ok, job} = ExLLM.FineTuning.get_fine_tune(:openai, "ftjob-abc123")

  ## Return Value

  Returns `{:ok, details}` with the fine-tuning job or model details, or `{:error, reason}`.
  """
  @spec get_fine_tune(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_fine_tune(provider, id, opts \\ []) do
    case Delegator.delegate(:get_fine_tune, provider, [id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cancels or deletes a fine-tuning job or tuned model.

  For OpenAI, this cancels a running fine-tuning job.
  For Gemini, this deletes a tuned model.

  ## Parameters
    * `provider` - The LLM provider (`:gemini` or `:openai`)
    * `id` - The fine-tuning job ID or tuned model name
    * `opts` - Options for cancellation/deletion

  ## Examples

      # Delete Gemini tuned model
      :ok = ExLLM.FineTuning.cancel_fine_tune(:gemini, "tunedModels/my-model-abc123")

      # Cancel OpenAI fine-tuning job
      {:ok, job} = ExLLM.FineTuning.cancel_fine_tune(:openai, "ftjob-abc123")

  ## Return Value

  Returns `:ok` or `{:ok, details}` if successful, or `{:error, reason}` if failed.
  """
  @spec cancel_fine_tune(atom(), String.t(), keyword()) :: :ok | {:ok, term()} | {:error, term()}
  def cancel_fine_tune(provider, id, opts \\ []) do
    case Delegator.delegate(:cancel_fine_tune, provider, [id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
