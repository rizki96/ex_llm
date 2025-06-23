defmodule ExLLM.BatchProcessing do
  @moduledoc """
  Batch processing functionality for ExLLM.

  This module provides functions for creating and managing message batches for
  asynchronous processing. Message batches allow you to process multiple chat
  requests at a significant discount (typically 50%) but with longer processing
  times (within 24 hours).

  ## Supported Providers

  - **Anthropic**: Message batches for Claude models with up to 50% cost savings

  ## Benefits of Batch Processing

  - **Cost Savings**: Up to 50% discount on token costs
  - **Scale**: Process thousands of requests efficiently
  - **Asynchronous**: Submit requests and retrieve results later
  - **Reliability**: Built-in error handling and status tracking

  ## Examples

      # Create a batch of requests
      requests = [
        %{
          custom_id: "req-1",
          params: %{
            model: "claude-3-opus-20240229",
            messages: [%{role: "user", content: "Hello"}],
            max_tokens: 1000
          }
        },
        %{
          custom_id: "req-2",
          params: %{
            model: "claude-3-opus-20240229",
            messages: [%{role: "user", content: "How are you?"}],
            max_tokens: 1000
          }
        }
      ]
      
      # Submit the batch
      {:ok, batch} = ExLLM.BatchProcessing.create_batch(:anthropic, requests)
      
      # Monitor progress
      {:ok, updated_batch} = ExLLM.BatchProcessing.get_batch(:anthropic, batch.id)
      
      # Cancel if needed
      {:ok, cancelled_batch} = ExLLM.BatchProcessing.cancel_batch(:anthropic, batch.id)
  """

  alias ExLLM.API.Delegator

  @doc """
  Creates a message batch for processing multiple requests.

  Message batches allow you to process multiple chat requests asynchronously
  at a 50% discount. Batches are processed within 24 hours.

  ## Parameters
    * `provider` - The LLM provider (currently only `:anthropic` supported)
    * `messages_list` - List of message request objects
    * `opts` - Batch options

  ## Request Format

  Each request in `messages_list` should be a map with:
    * `:custom_id` - Unique identifier for tracking (required)
    * `:params` - The message parameters:
      * `:model` - Model to use (e.g., "claude-3-opus-20240229")
      * `:messages` - List of message objects
      * `:max_tokens` - Maximum tokens in response
      * Other standard chat parameters

  ## Options
    * `:config_provider` - Configuration provider

  ## Examples

      requests = [
        %{
          custom_id: "req-1",
          params: %{
            model: "claude-3-opus-20240229",
            messages: [%{role: "user", content: "Hello"}],
            max_tokens: 1000
          }
        },
        %{
          custom_id: "req-2",
          params: %{
            model: "claude-3-opus-20240229",
            messages: [%{role: "user", content: "How are you?"}],
            max_tokens: 1000
          }
        }
      ]
      
      {:ok, batch} = ExLLM.BatchProcessing.create_batch(:anthropic, requests)
      IO.puts("Batch ID: \#{batch.id}")

  ## Return Value

  Returns `{:ok, batch}` with batch details including ID and status, or `{:error, reason}`.
  """
  @spec create_batch(atom(), list(map()), keyword()) :: {:ok, term()} | {:error, term()}
  def create_batch(provider, messages_list, opts \\ []) do
    case Delegator.delegate(:create_batch, provider, [messages_list, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Retrieves the status and details of a message batch.

  ## Parameters
    * `provider` - The LLM provider (currently only `:anthropic` supported)
    * `batch_id` - The batch identifier
    * `opts` - Request options

  ## Examples

      {:ok, batch} = ExLLM.BatchProcessing.get_batch(:anthropic, "batch_abc123")
      
      case batch.processing_status do
        "in_progress" -> IO.puts("Still processing...")
        "ended" -> IO.puts("Batch complete!")
      end

  ## Return Value

  Returns `{:ok, batch}` with current batch status and metadata, or `{:error, reason}`.

  The batch object includes:
    * `:id` - Batch identifier
    * `:processing_status` - "in_progress" or "ended"
    * `:request_counts` - Map with succeeded/errored/processing/canceled counts
    * `:ended_at` - Completion timestamp (if ended)
    * `:expires_at` - Expiration timestamp
  """
  @spec get_batch(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def get_batch(provider, batch_id, opts \\ []) do
    case Delegator.delegate(:get_batch, provider, [batch_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cancels a message batch that is still processing.

  Canceling a batch will stop processing of any requests that haven't started yet.
  Requests that are already being processed will complete.

  ## Parameters
    * `provider` - The LLM provider (currently only `:anthropic` supported)
    * `batch_id` - The batch identifier to cancel
    * `opts` - Request options

  ## Examples

      {:ok, batch} = ExLLM.BatchProcessing.cancel_batch(:anthropic, "batch_abc123")
      IO.puts("Batch canceled. Status: \#{batch.processing_status}")

  ## Return Value

  Returns `{:ok, batch}` with updated batch details, or `{:error, reason}`.
  """
  @spec cancel_batch(atom(), String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def cancel_batch(provider, batch_id, opts \\ []) do
    case Delegator.delegate(:cancel_batch, provider, [batch_id, opts]) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
